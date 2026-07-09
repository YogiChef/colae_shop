// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';

class ProviderBookingDetailPage extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> data;

  const ProviderBookingDetailPage({
    super.key,
    required this.bookingId,
    required this.data,
  });

  @override
  State<ProviderBookingDetailPage> createState() =>
      _ProviderBookingDetailPageState();
}

class _ProviderBookingDetailPageState
    extends State<ProviderBookingDetailPage> {
  late Map<String, dynamic> _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
    _listenToBooking();
  }

  void _listenToBooking() {
    FirebaseFirestore.instance
        .collection('service_bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        setState(() => _data = snap.data()!);
      }
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    final actionLabel = newStatus == 'in_service' ? 'เริ่มบริการ' : 'เสร็จสิ้น';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          actionLabel,
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          newStatus == 'in_service'
              ? 'ยืนยันการเริ่มให้บริการลูกค้ารายนี้?'
              : 'ยืนยันว่าบริการเสร็จสิ้นแล้ว?',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              actionLabel,
              style: styles(
                color: newStatus == 'completed' ? Colors.green : mainColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    EasyLoading.show(status: 'กำลังอัปเดต...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(widget.bookingId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        if (newStatus == 'in_service') 'startedAt': FieldValue.serverTimestamp(),
        if (newStatus == 'completed') 'completedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.showSuccess('อัปเดตแล้ว');
      if (newStatus == 'completed' && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      EasyLoading.showError('เกิดข้อผิดพลาด');
      Fluttertoast.showToast(msg: e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'in_service':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'รอยืนยัน';
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'in_service':
        return 'กำลังบริการ';
      case 'completed':
        return 'เสร็จแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: styles(fontSize: 13.sp, color: context.subColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: valueColor ?? context.purpleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _data['status'] as String? ?? '';
    final customerName = _data['customerName'] as String? ?? 'ลูกค้า';
    final customerPhone = _data['customerPhone'] as String? ?? '';
    final serviceName = _data['serviceName'] as String? ?? '';
    final duration = (_data['durationMinutes'] as num?)?.toInt() ?? 0;
    final price = (_data['price'] as num?)?.toDouble() ?? 0.0;
    final note = _data['note'] as String? ?? '';
    final isWalkIn = _data['isWalkIn'] as bool? ?? false;
    final bookingDate = (_data['bookingDate'] as Timestamp?)?.toDate();
    final bookingEndAt = (_data['bookingEndAt'] as Timestamp?)?.toDate();

    final fmtDate = DateFormat('d MMM yyyy', 'th');
    final fmtTime = DateFormat('HH:mm');

    final canStart = status == 'confirmed' && !isWalkIn;
    final canComplete = status == 'in_service';

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'รายละเอียดการจอง',
          style: styles(
              fontSize: 17.sp, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status badge ────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: styles(
                      fontSize: 13.sp,
                      color: _statusColor(status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isWalkIn) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text(
                      'Walk-in',
                      style: styles(
                          fontSize: 12.sp, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ],
            ),

            SizedBox(height: 16.h),

            // ── Info card ────────────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
              elevation: 1,
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ข้อมูลลูกค้า',
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: context.purpleColor,
                      ),
                    ),
                    Divider(height: 16.h, color: Colors.grey[200]),
                    _infoRow('ชื่อ', customerName),
                    if (customerPhone.isNotEmpty)
                      _infoRow('เบอร์โทร', customerPhone),
                  ],
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // ── Service card ─────────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
              elevation: 1,
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รายละเอียดบริการ',
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: context.purpleColor,
                      ),
                    ),
                    Divider(height: 16.h, color: Colors.grey[200]),
                    _infoRow('บริการ', serviceName),
                    if (bookingDate != null)
                      _infoRow(
                        'วันที่',
                        fmtDate.format(bookingDate),
                      ),
                    if (bookingDate != null)
                      _infoRow(
                        'เวลา',
                        bookingEndAt != null
                            ? '${fmtTime.format(bookingDate)} – ${fmtTime.format(bookingEndAt)}'
                            : fmtTime.format(bookingDate),
                      ),
                    if (duration > 0)
                      _infoRow('ระยะเวลา', '$duration นาที'),
                    _infoRow(
                      'ราคา',
                      '฿${price.toStringAsFixed(0)}',
                      valueColor: mainColor,
                    ),
                    if (note.isNotEmpty) _infoRow('หมายเหตุ', note),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // ── Action buttons ───────────────────────────────────────────
            if (canStart)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.play_arrow_rounded,
                      size: 20.r, color: Colors.white),
                  label: Text(
                    'เริ่มบริการ',
                    style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  onPressed: _loading ? null : () => _updateStatus('in_service'),
                ),
              ),

            if (canComplete) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.check_circle_outline,
                      size: 20.r, color: Colors.white),
                  label: Text(
                    'บริการเสร็จสิ้น',
                    style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  onPressed: _loading ? null : () => _updateStatus('completed'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
