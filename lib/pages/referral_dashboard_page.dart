// ignore_for_file: use_build_context_synchronously, unnecessary_underscores

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:colae_shop/services/sevice.dart';

class ReferralDashboardPage extends StatefulWidget {
  const ReferralDashboardPage({super.key});

  @override
  State<ReferralDashboardPage> createState() => _ReferralDashboardPageState();
}

class _ReferralDashboardPageState extends State<ReferralDashboardPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isWithdrawing = false;

  Future<void> _requestWithdrawal(double amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการถอนเงิน'),
        content: Text('ถอนเงิน ฿${amount.toStringAsFixed(2)} ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isWithdrawing = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('withdrawal_requests').doc(),
        {
          'userId': _uid,
          'amount': amount,
          'status': 'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(
        FirebaseFirestore.instance.collection('referral_earnings').doc(_uid),
        {
          'pendingEarnings': 0,
          'withdrawnEarnings': FieldValue.increment(amount),
        },
      );
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำขอถอนเงินแล้ว รอการตรวจสอบ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  Future<List<int>> _getDownlineCounts() async {
    final db = FirebaseFirestore.instance;
    final List<int> counts = [];

    for (int i = 0; i < 5; i++) {
      int total = 0;
      for (final col in ['buyers', 'vendors', 'riders']) {
        final snap = await db
            .collection(col)
            .where('uplineIds', arrayContains: _uid)
            .get();
        total += snap.docs.where((doc) {
          final ids = List<String>.from(doc.data()['uplineIds'] ?? []);
          return ids.length > i && ids[i] == _uid;
        }).length;
      }
      counts.add(total);
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'แนะนำเพื่อน',
          style: styles(
            fontSize: 18.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vendors')
            .doc(_uid)
            .snapshots(),
        builder: (context, vendorSnap) {
          final vendorData =
              vendorSnap.data?.data() as Map<String, dynamic>? ?? {};
          final String code = vendorData['referralCode'] as String? ?? '';
          // auto-generate ถ้าไม่มี referralCode
          if (vendorSnap.hasData && code.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
                await functions.httpsCallable('generateReferralCodeForUser').call({
                  'userId': _uid,
                  'userType': 'vendor',
                });
              } catch (e) {
                debugPrint('[REFERRAL] generate code error: $e');
              }
            });
          }
          final int count =
              (vendorData['referralCount'] as num?)?.toInt() ?? 0;
          final bool qualified =
              vendorData['referralQualified'] as bool? ?? false;

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('referral_earnings')
                .doc(_uid)
                .snapshots(),
            builder: (context, earningsSnap) {
              if (vendorSnap.connectionState == ConnectionState.waiting &&
                  !vendorSnap.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: mainColor),
                );
              }
              final earningsData =
                  earningsSnap.data?.data() as Map<String, dynamic>? ?? {};
              final double pending =
                  (earningsData['pendingEarnings'] as num?)?.toDouble() ?? 0.0;
              final double total =
                  (earningsData['totalEarnings'] as num?)?.toDouble() ?? 0.0;
              final double withdrawn =
                  (earningsData['withdrawnEarnings'] as num?)?.toDouble() ??
                  0.0;

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _codeCard(code),
                      SizedBox(height: 12.h),
                      _qualCard(qualified, count),
                      SizedBox(height: 12.h),
                      _earningsCard(pending, total, withdrawn),
                      SizedBox(height: 12.h),
                      _downlineChart(),
                      SizedBox(height: 12.h),
                      _transactionList(),
                      SizedBox(height: 16.h),
                      _withdrawButton(pending),
                      SizedBox(height: 32.h),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _codeCard(String code) {
    final link = 'https://colae.app/join?ref=$code';
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รหัสแนะนำของคุณ',
              style: styles(
                fontSize: 14.sp,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 12.h,
                      horizontal: 16.w,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.orange, width: 1.5),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.orange),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอกลิงก์แล้ว')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.orange),
                  onPressed: () => Share.share(
                    'สมัครใช้งาน Colae ผ่านรหัสของฉัน: $code\n$link',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualCard(bool qualified, int count) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      color: qualified ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Icon(
              qualified ? Icons.check_circle : Icons.info_outline,
              color: qualified ? Colors.green : Colors.red,
              size: 40.sp,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    qualified ? 'ผ่านเงื่อนไขแล้ว!' : 'ยังไม่ผ่านเงื่อนไข',
                    style: styles(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: qualified ? Colors.green : Colors.red,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'แนะนำแล้ว $count / 12 คน',
                    style: styles(fontSize: 14.sp, color: Colors.grey[700]),
                  ),
                  SizedBox(height: 6.h),
                  LinearProgressIndicator(
                    value: (count / 12).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[200],
                    color: qualified ? Colors.green : Colors.orange,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _earningsCard(double pending, double total, double withdrawn) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ยอดรายได้ Referral',
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                _earningsItem('รอถอน', pending, Colors.orange),
                _earningsItem('ทั้งหมด', total, Colors.blue),
                _earningsItem('ถอนแล้ว', withdrawn, Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _earningsItem(String label, double amount, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '฿${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(label, style: styles(fontSize: 12.sp, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _downlineChart() {
    final levels = ['ชั้น 1', 'ชั้น 2', 'ชั้น 3', 'ชั้น 4', 'ชั้น 5'];
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'จำนวน Downline แต่ละชั้น',
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 12.h),
            FutureBuilder<List<int>>(
              future: _getDownlineCounts(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return SizedBox(
                    height: 180.h,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                final counts = snap.data ?? [0, 0, 0, 0, 0];
                final maxY =
                    counts.fold(0, (a, b) => a > b ? a : b).toDouble();

                return SizedBox(
                  height: 180.h,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY > 0 ? maxY + 5 : 10,
                      barGroups: List.generate(5, (i) {
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: counts[i].toDouble(),
                              color: Colors.orange,
                              width: 24.w,
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                          ],
                        );
                      }),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, _) {
                              final i = value.toInt();
                              if (i < 0 || i >= levels.length) {
                                return const Text('');
                              }
                              return Padding(
                                padding: EdgeInsets.only(top: 4.h),
                                child: Text(
                                  levels[i],
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                            '${rod.toY.toInt()} คน',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionList() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ประวัติรายได้',
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8.h),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('referral_transactions')
                  .where('toUserId', isEqualTo: _uid)
                  .orderBy('timestamp', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Text(
                      'ไม่สามารถโหลดประวัติได้',
                      style: styles(fontSize: 13.sp, color: Colors.grey),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: Center(
                      child: Text(
                        'ยังไม่มีรายการ',
                        style: styles(fontSize: 14.sp, color: Colors.grey),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final ts = d['timestamp'] as Timestamp?;
                    final date = ts != null
                        ? DateFormat('dd/MM/yy HH:mm').format(ts.toDate())
                        : '-';
                    final double amount =
                        (d['amount'] as num?)?.toDouble() ?? 0.0;
                    final int level = (d['level'] as num?)?.toInt() ?? 0;
                    final String orderId = d['orderId'] as String? ?? '';
                    final String shortId = orderId.length > 8
                        ? orderId.substring(0, 8)
                        : orderId;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 2.h,
                      ),
                      leading: CircleAvatar(
                        radius: 16.r,
                        backgroundColor: Colors.orange.shade100,
                        child: Text(
                          'L$level',
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        'ออร์เดอร์ $shortId...',
                        style: styles(fontSize: 13.sp, color: Colors.black87),
                      ),
                      subtitle: Text(
                        date,
                        style: styles(fontSize: 11.sp, color: Colors.grey),
                      ),
                      trailing: Text(
                        '+฿${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _withdrawButton(double pending) {
    final bool canWithdraw = pending >= 5000;
    return SizedBox(
      width: double.infinity,
      height: 52.h,
      child: ElevatedButton.icon(
        icon: _isWithdrawing
            ? SizedBox(
                width: 20.w,
                height: 20.h,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.account_balance_wallet),
        label: Text(
          canWithdraw
              ? 'ถอนเงิน ฿${pending.toStringAsFixed(0)}'
              : 'ยังถอนไม่ได้ (ขั้นต่ำ ฿5,000)',
          style: styles(
            fontSize: 15.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canWithdraw ? Colors.orange : Colors.grey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        onPressed: canWithdraw && !_isWithdrawing
            ? () => _requestWithdrawal(pending)
            : null,
      ),
    );
  }
}
