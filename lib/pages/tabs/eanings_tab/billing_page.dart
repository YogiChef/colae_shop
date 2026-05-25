// File: billing_page.dart
// ignore_for_file: unused_local_variable, unnecessary_null_comparison, curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:promptpay_qrcode_generate/promptpay_qrcode_generate.dart';
import 'package:screenshot/screenshot.dart';
import 'package:colae_shop/services/sevice.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String promptPayId = '0925403189';
  static const double vatRate = 0.07;

  bool _hasShownDialog = false;
  bool _hasCheckedBilling = false;
  late final Future<DocumentSnapshot> _vendorFuture;
  late final Stream<QuerySnapshot> _monthlySalesStream;

  Future<double> getVendorFee(
    double? totalSales, {
    double accumulatedCommission = 0.0,
  }) async {
    if (totalSales == null || totalSales <= 0) return 0.0;
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('calculateVendorFee');
      final result = await callable.call({
        'totalSales': totalSales,
        'accumulatedCommission': accumulatedCommission,
      });
      return (result.data['fee'] as num).toDouble();
    } catch (e) {
      // fallback คำนวณ local ถ้า Function ล้มเหลว
      double fee = 0;
      if (totalSales <= 5000) {
        fee = 0;
      } else if (totalSales <= 25000)
        fee = 159;
      else if (totalSales <= 55000)
        fee = 359;
      else if (totalSales <= 150000)
        fee = 759;
      else if (totalSales <= 250000)
        fee = 1259;
      else
        fee = 1259 + (totalSales - 250000) * 0.07;
      return double.parse((fee + accumulatedCommission).toStringAsFixed(2));
    }
  }

  Future<void> _loadPromptPayId() async {
    try {
      final vendorDoc = await firestore
          .collection('vendors')
          .doc(auth.currentUser!.uid)
          .get();
      if (vendorDoc.exists) {
        final data = vendorDoc.data()!;
        promptPayId = data['promptPayId']?.toString() ?? '0925403189';
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: "ไม่สามารถโหลด PromptPay ID ได้: $e",
        backgroundColor: Colors.red,
      );
    }
  }

  String _getDueDateInfo(Timestamp? nextDue) {
    if (nextDue == null) return 'กำลังคำนวณ...';
    final due = nextDue.toDate();
    final daysLeft = due.difference(DateTime.now()).inDays;
    final thaiMonths = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    final dueFormatted =
        '${due.day} ${thaiMonths[due.month]} ${due.year + 543}';

    if (daysLeft > 1)
      return 'เหลือ $daysLeft วัน ถึงกำหนดชำระ\n($dueFormatted)';
    if (daysLeft == 1) return 'เหลือ 1 วัน ถึงกำหนดชำระ\n($dueFormatted)';
    if (daysLeft == 0) return 'ครบกำหนดชำระวันนี้\n($dueFormatted)';
    return 'เลยกำหนดชำระ ${-daysLeft} วัน\n($dueFormatted)';
  }

  void _showPaymentAlert(double fee, double totalSales, Timestamp nextDue) {
    if (!mounted) return;

    final double vat = fee * vatRate;
    final double totalWithVat = fee + vat;
    final ScreenshotController screenshotController = ScreenshotController();

    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            insetPadding: EdgeInsets.only(left: 6.w, right: 6.w),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: 12.h),
                      Icon(
                        Icons.warning_rounded,
                        color: Colors.amber,
                        size: 54.r,
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        'แจ้งเตือนค่าบริการ',
                        textAlign: TextAlign.center,
                        style: styles(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 20.w, right: 20.w),
                        child: Text(
                          'โปรดชำระค่าบริการเพื่อการจัดการในระบบของท่าน!',
                          textAlign: TextAlign.center,
                          style: styles(
                            fontSize: 13.sp,
                            color: Colors.orange,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Screenshot(
                        controller: screenshotController,
                        child: RepaintBoundary(
                          child: Container(
                            padding: EdgeInsets.all(16.r),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: QRCodeGenerate(
                              amount: totalWithVat,
                              width: 270,
                              height: 270,
                              promptPayId: promptPayId,
                              isShowAccountDetail: false,
                              isShowAmountDetail: false,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'ยอดขายทั้งหมด: ฿${totalSales.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: styles(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'ค่าบริการ: ฿${fee.toStringAsFixed(2)}',
                        style: styles(fontSize: 12.sp, color: Colors.black87),
                      ),
                      Text(
                        'ภาษีมูลค่าเพิ่ม (VAT 7%): ฿${vat.toStringAsFixed(2)}',
                        style: styles(fontSize: 12.sp, color: Colors.black87),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        _getDueDateInfo(nextDue),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: styles(fontSize: 11.sp, color: Colors.orange),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'รวมชำระทั้งสิ้น: ฿${totalWithVat.toStringAsFixed(2)}',
                        style: styles(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepOrange.shade900,
                        ),
                      ),
                      SizedBox(height: 30.h),
                    ],
                  ),
                ),
                Positioned(
                  top: 24.h,
                  right: 20.w,
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget paymentButton({
    required IconData icon,
    required String text,
    required Color color,
    required Function() onPressed,
  }) {
    return SizedBox(
      height: 40.h,
      width: 0.35.sw,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Text(
          text,
          style: styles(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Future<void> _checkAndShowBillingAlert() async {
    if (!mounted || _hasShownDialog) return;
    if (_hasCheckedBilling) return;
    _hasCheckedBilling = true;

    try {
      final vendorRef = firestore
          .collection('vendors')
          .doc(auth.currentUser!.uid);
      final vendorDoc = await vendorRef.get();

      if (!vendorDoc.exists) {
        return;
      }

      final data = vendorDoc.data() as Map<String, dynamic>;

      double totalSales = (data['totalSales'] as num?)?.toDouble() ?? 0.0;
      double lastBilledSales =
          (data['lastBilledSales'] as num?)?.toDouble() ?? 0.0;
      double pendingFee = (data['pendingFee'] as num?)?.toDouble() ?? 0.0;
      Timestamp? nextDueDate = data['nextDueDate'] as Timestamp?;
      if (nextDueDate == null) {
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        nextDueDate = Timestamp.fromDate(
          createdAt.add(const Duration(days: 30)),
        );

        await vendorRef.update({
          'nextDueDate': nextDueDate,
          'lastBilledSales': 0,
          'pendingFee': 0,
        });
      }

      final double accumulatedCommission =
          (data['accumulatedCommission'] as num?)?.toDouble() ?? 0.0;

      final billable = totalSales - lastBilledSales;
      if (billable > 5000) {
        pendingFee = await getVendorFee(
          billable,
          accumulatedCommission: accumulatedCommission,
        );
        await vendorRef.update({'pendingFee': pendingFee});
      }
      if (pendingFee > 0 && nextDueDate != null && !_hasShownDialog) {
        final bool isDue = !DateTime.now().isBefore(nextDueDate.toDate());

        _hasShownDialog = true;
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _showPaymentAlert(pendingFee, totalSales, nextDueDate);
        }
      }
    } catch (e) {
      _hasCheckedBilling = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _vendorFuture = firestore
        .collection('vendors')
        .doc(auth.currentUser!.uid)
        .get();
    _monthlySalesStream = firestore
        .collection('vendors')
        .doc(auth.currentUser!.uid)
        .collection('monthly_sales')
        .orderBy('month', descending: true)
        .limit(12)
        .snapshots();
    _loadPromptPayId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAndShowBillingAlert();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'สรุปค่าบริการรายเดือน',
          style: styles(
            fontSize: 18.sp,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _vendorFuture,
        builder: (context, vendorSnapshot) {
          if (vendorSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          if (!vendorSnapshot.hasData || !vendorSnapshot.data!.exists) {
            return const Center(child: Text('ไม่พบข้อมูลผู้ขาย'));
          }

          final data = vendorSnapshot.data!.data() as Map<String, dynamic>;
          final double totalSales =
              (data['totalSales'] as num?)?.toDouble() ?? 0.0;
          final double pendingFee =
              (data['pendingFee'] as num?)?.toDouble() ?? 0.0;
          final Timestamp? nextDueDate = data['nextDueDate'] as Timestamp?;

          return StreamBuilder<QuerySnapshot>(
            stream: _monthlySalesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.green),
                );
              }

              final docs = snapshot.data!.docs;
              List<BarChartGroupData> barGroups = [];
              List<Map<String, dynamic>> monthlyData = [];

              for (var doc in docs) {
                final d = doc.data() as Map<String, dynamic>;
                final String month = d['month'] ?? doc.id;
                final double sales =
                    (d['total_sales'] as num?)?.toDouble() ?? 0.0;
                final bool paid = d['paid'] ?? false;

                monthlyData.add({'month': month, 'sales': sales, 'paid': paid});

                final int barIndex = docs.indexOf(doc);
                barGroups.add(
                  BarChartGroupData(
                    x: barIndex,
                    barRods: [
                      BarChartRodData(
                        toY: sales,
                        color: paid ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                );
              }

              final double maxY =
                  monthlyData
                      .map((e) => e['sales'] as double)
                      .fold(0.0, (a, b) => a > b ? a : b) *
                  1.1;

              return SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'กราฟรายได้รายเดือน',
                        style: styles(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      SizedBox(
                        height: 250.h,
                        child: BarChart(
                          BarChartData(
                            barGroups: barGroups,
                            backgroundColor: Colors.orange.shade50,
                            maxY: maxY > 0 ? maxY : 1000,
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final int index = value.toInt();
                                    if (index >= 0 &&
                                        index < monthlyData.length) {
                                      return Text(
                                        monthlyData[index]['month'],
                                        style: styles(fontSize: 10.sp),
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: styles(
                                        color: Colors.black54,
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    final double val = value.toDouble();
                                    String text;
                                    if (val >= 1000) {
                                      text =
                                          ' ${(val / 1000).toStringAsFixed(0)}k';
                                    } else {
                                      text = val.toInt().toString();
                                    }

                                    return Text(
                                      text,
                                      style: styles(
                                        color: Colors.black54,
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 12.h),
                      Text(
                        'ข้อมูลรายเดือน',
                        style: styles(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8.h),

                      if (docs.isNotEmpty)
                        Table(
                          border: TableBorder.all(color: Colors.grey),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                              ),
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(8.w),
                                  child: Text(
                                    'เดือน',
                                    style: styles(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(8.w),
                                  child: Text(
                                    'รายได้',
                                    style: styles(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(8.w),
                                  child: Text(
                                    'สถานะ',
                                    style: styles(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            ...monthlyData.map(
                              (data) => TableRow(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(8.w),
                                    child: Text(
                                      data['month'],
                                      textAlign: TextAlign.center,
                                      style: styles(
                                        fontSize: 12.sp,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(8.w),
                                    child: Text(
                                      '฿${data['sales'].toStringAsFixed(2)}',
                                      style: styles(
                                        fontSize: 12.sp,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(8.w),
                                    child: Text(
                                      data['paid'] ? 'จ่ายแล้ว' : 'ค้างจ่าย',
                                      textAlign: TextAlign.center,
                                      style: styles(
                                        fontSize: 12.sp,
                                        color: data['paid']
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        const Center(
                          child: Text('ยังไม่มีข้อมูลยอดขายรายเดือน'),
                        ),

                      SizedBox(height: 20.h),
                      if (pendingFee > 0)
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'ยอดขายทั้งหมด: ฿${totalSales.toStringAsFixed(2)}',
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'ค่าบริการ: ฿${pendingFee.toStringAsFixed(2)}',
                                style: styles(
                                  fontSize: 12.sp,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _getDueDateInfo(nextDueDate),
                                textAlign: TextAlign.center,
                                style: styles(
                                  fontSize: 11.sp,
                                  color: Colors.orange,
                                ),
                              ),
                              Text(
                                'รวมทั้งสิ้น (VAT 7%): ฿${(pendingFee * 1.07).toStringAsFixed(2)}',
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const Center(
                          child: Text(
                            'ยังไม่ถึงกำหนดชำระค่าบริการ',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
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

  @override
  void dispose() {
    super.dispose();
  }
}
