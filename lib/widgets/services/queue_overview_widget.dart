// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class QueueOverviewWidget extends StatefulWidget {
  final String shopId;
  const QueueOverviewWidget({super.key, required this.shopId});

  @override
  State<QueueOverviewWidget> createState() => _QueueOverviewWidgetState();
}

class _QueueOverviewWidgetState extends State<QueueOverviewWidget> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _providersFuture;

  @override
  void initState() {
    super.initState();
    _providersFuture = _loadProviders();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadProviders() {
    return FirebaseFirestore.instance
        .collection('service_shops')
        .doc(widget.shopId)
        .collection('providers')
        .where('active', isEqualTo: true)
        .orderBy('order')
        .get();
  }

  String _todayKey() {
    final bkk = DateTime.now().toUtc().add(const Duration(hours: 7));
    return '${bkk.year}-${bkk.month.toString().padLeft(2, '0')}-${bkk.day.toString().padLeft(2, '0')}';
  }

  Future<void> _resetQueue(BuildContext context) async {
    final todayKey = _todayKey();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        title: Text(
          'รีเซ็ตคิววันนี้?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'การ assign ถัดไปจะเริ่มจากช่างแรก',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('รีเซ็ต',
                style: styles(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    EasyLoading.show(status: 'กำลังรีเซ็ต...');
    try {
      await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('queue_state')
          .doc(todayKey)
          .delete();
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'รีเซ็ตคิวแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _showStats(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> providers,
  ) async {
    final bkk = DateTime.now().toUtc().add(const Duration(hours: 7));
    final startOfDayBkk = DateTime(bkk.year, bkk.month, bkk.day);
    // Convert Bangkok midnight to UTC for Firestore query
    final startOfDayUtc =
        startOfDayBkk.toUtc().subtract(const Duration(hours: 7));
    final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

    EasyLoading.show(status: 'กำลังโหลด...');
    QuerySnapshot? snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: widget.shopId)
          .where('bookingDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayUtc))
          .where('bookingDate', isLessThan: Timestamp.fromDate(endOfDayUtc))
          .get();
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
      return;
    }
    EasyLoading.dismiss();
    if (!context.mounted) return;

    final assigned = snap.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['assignedByQueue'] as bool? ?? false;
    }).toList();

    final distribution = <String, int>{};
    for (final doc in assigned) {
      final name = (doc.data() as Map<String, dynamic>)['providerName']
              as String? ??
          'ไม่ระบุ';
      distribution[name] = (distribution[name] ?? 0) + 1;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        title: Text(
          'สถิติคิววันนี้',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'จัดสรรรวม: ${assigned.length} ครั้ง',
              style: styles(fontSize: 13.sp, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10.h),
            if (distribution.isEmpty)
              Text(
                'ยังไม่มีการจัดสรรวันนี้',
                style: styles(fontSize: 12.sp, color: ctx.subColor),
              )
            else ...[
              Text('การกระจาย:',
                  style: styles(fontSize: 12.sp, color: ctx.subColor)),
              SizedBox(height: 6.h),
              ...distribution.entries.map(
                (e) => Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: styles(fontSize: 13.sp)),
                      Text(
                        '${e.value} ครั้ง',
                        style: styles(
                            fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ปิด', style: styles(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _todayKey();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('queue_state')
          .doc(todayKey)
          .snapshots(),
      builder: (context, queueSnap) {
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _providersFuture,
          builder: (context, providersSnap) {
            if (!providersSnap.hasData) return const SizedBox.shrink();
            final providers = providersSnap.data!.docs;
            if (providers.isEmpty) return const SizedBox.shrink();

            final queueData =
                queueSnap.data?.data() as Map<String, dynamic>?;
            final lastIdx =
                (queueData?['lastAssignedIndex'] as num?)?.toInt() ?? -1;
            final nextIdx = (lastIdx + 1) % providers.length;
            final nextName =
                providers[nextIdx].data()['name'] as String? ?? 'ช่าง';

            return Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.grey[850]
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.queue_outlined,
                      color: Colors.blue.shade600, size: 20.r),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'คิวถัดไป: $nextName',
                          style: styles(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        Text(
                          '${providers.length} ช่าง active',
                          style: styles(
                              fontSize: 11.sp, color: context.subColor),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 20.r, color: context.subColor),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'stats',
                        child: Row(children: [
                          Icon(Icons.bar_chart, size: 18.r),
                          SizedBox(width: 8.w),
                          Text('สถิติวันนี้',
                              style: styles(fontSize: 13.sp)),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'reset',
                        child: Row(children: [
                          Icon(Icons.restart_alt,
                              size: 18.r, color: Colors.red),
                          SizedBox(width: 8.w),
                          Text('รีเซ็ตคิววันนี้',
                              style: styles(
                                  fontSize: 13.sp, color: Colors.red)),
                        ]),
                      ),
                    ],
                    onSelected: (v) {
                      if (v == 'reset') _resetQueue(context);
                      if (v == 'stats') _showStats(context, providers);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
