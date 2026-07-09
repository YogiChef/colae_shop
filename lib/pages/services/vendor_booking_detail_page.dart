// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';

class VendorBookingDetailPage extends StatelessWidget {
  final String bookingId;

  const VendorBookingDetailPage({super.key, required this.bookingId});

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'in_service':
        return 'กำลังบริการ';
      case 'completed':
        return 'เสร็จแล้ว';
      case 'rejected':
        return 'ถูกปฏิเสธ';
      default:
        return 'รอยืนยัน';
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed':
        return Colors.blue;
      case 'in_service':
        return Colors.teal;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.deepOrange;
      default:
        return Colors.orange;
    }
  }

  String _paymentLabel(String m) {
    switch (m) {
      case 'bank_transfer':
        return 'โอนเงิน';
      case 'promptpay':
        return 'PromptPay QR';
      default:
        return 'เงินสด';
    }
  }

  Future<void> _showProviderPickerDialog(
    BuildContext context,
    Map<String, dynamic> bk,
  ) async {
    final shopId = bk['shopId'] as String? ?? '';
    final typeId = bk['typeId'] as String? ?? '';

    EasyLoading.show(status: 'กำลังโหลด...');
    List<QueryDocumentSnapshot<Map<String, dynamic>>> providers = [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(shopId)
          .collection('providers')
          .where('active', isEqualTo: true)
          .orderBy('order')
          .get();

      providers = snap.docs.where((doc) {
        final specialties = List<String>.from(
          doc.data()['specialties'] as List? ?? [],
        );
        return specialties.isEmpty || specialties.contains(typeId);
      }).toList();
    } catch (_) {}
    EasyLoading.dismiss();

    if (!context.mounted) return;

    String? selectedId = bk['providerId'] as String?;
    String? selectedName = bk['providerName'] as String?;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          title: Text(
            'เลือกผู้ให้บริการ',
            style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                   
                  ),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16.r,
                        color: Colors.blue.shade700,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'การเลือกผู้ให้บริการเองจะไม่กระทบคิวหมุนอัตโนมัติ',
                          style: styles(
                            fontSize: 11.sp,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey[100]),
                RadioListTile<String?>(
                  value: null,
                  groupValue: selectedId,
                  onChanged: (_) => setDialogState(() {
                    selectedId = null;
                    selectedName = null;
                  }),
                  title: Text(
                    'ไม่ระบุ (จัดสรรอัตโนมัติ)',
                    style: styles(fontSize: 13.sp, color: context.textColor),
                  ),
                  activeColor: mainColor,
                ),
                if (providers.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(16.r),
                    child: Text(
                      'ไม่มีพนักงานในระบบ',
                      style: styles(fontSize: 13.sp, color: Colors.grey[400]),
                    ),
                  )
                else ...[
                  Divider(height: 1, color: Colors.grey[100]),
                  ...providers.map((doc) {
                    final data = doc.data();
                    final name = data['name'] as String? ?? '';
                    final photo = data['photo'] as String?;
                    return RadioListTile<String?>(
                      value: doc.id,
                      groupValue: selectedId,
                      onChanged: (_) => setDialogState(() {
                        selectedId = doc.id;
                        selectedName = name;
                      }),
                      secondary: CircleAvatar(
                        radius: 14.r,
                        backgroundColor: mainColor.withValues(alpha: 0.12),
                        backgroundImage: photo != null
                            ? NetworkImage(photo)
                            : null,
                        child: photo == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: styles(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w700,
                                  color: mainColor,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        name,
                        style: styles(
                          fontSize: 13.sp,
                          color: context.textColor,
                        ),
                      ),
                      activeColor: mainColor,
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('ยกเลิก', style: styles(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'บันทึก',
                style: styles(
                  fontSize: 14.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(bookingId)
          .update({
            'providerId': selectedId,
            'providerName': selectedName,
            'assignedByQueue': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'บันทึกช่างเรียบร้อย');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final buddhistYear = (dt.year + 543).toString().substring(2);
    return '${dt.day} ${months[dt.month - 1]} $buddhistYear';
  }

  String _fmtTimeRange(DateTime? start, DateTime? end) {
    if (start == null) return '-';
    if (end == null) return '${_fmtDate(start)},${_fmtTime(start)}';
    return '${_fmtDate(start)},${_fmtTime(start)} - ${_fmtTime(end)}';
  }

  Future<void> _markCustomerArrived(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ยืนยันลูกค้ามาถึงแล้ว?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ระบบจะบันทึกเวลาที่ลูกค้ามาถึง',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ยืนยัน',
              style: styles(
                fontSize: 14.sp,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(bookingId)
          .update({
            'status': 'in_service',
            'customerArrivedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'บันทึกลูกค้ามาถึงแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _confirmBooking(BuildContext context) async {
    EasyLoading.show(status: 'กำลังยืนยัน...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(bookingId)
          .update({
            'status': 'confirmed',
            'confirmedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ยืนยันการจองแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _rejectBooking(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
        title: Text(
          'ปฏิเสธการจอง',
          style: styles(fontSize: 16.sp, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ระบุเหตุผล (ไม่บังคับ)',
              style: styles(fontSize: 13.sp, color: context.subColor),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              maxLength: 150,
              style: styles(fontSize: 13.sp),
              decoration: InputDecoration(
                hintText: 'เช่น ร้านเต็ม วันนั้นปิด...',
                hintStyle: styles(fontSize: 12.sp, color: context.subColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                contentPadding: EdgeInsets.all(10.r),
              ),
            ),
          ],
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
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ปฏิเสธ',
              style: styles(
                fontSize: 14.sp,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true) return;

    EasyLoading.show(status: 'กำลังปฏิเสธ...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(bookingId)
          .update({
            'status': 'rejected',
            'cancelReason': reason.isNotEmpty ? reason : 'ร้านขอปฏิเสธการจอง',
            'rejectedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ปฏิเสธการจองแล้ว');
      Navigator.pop(context);
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _completeBooking(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ยืนยันเสร็จสิ้นบริการ?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ระบบจะคำนวณค่าคอมมิชชันอัตโนมัติ\nหลังจากนี้ไม่สามารถแก้ไขได้',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ยืนยันเสร็จสิ้น',
              style: styles(
                fontSize: 14.sp,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(bookingId)
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'บันทึกเสร็จสิ้น ⚡ ระบบคำนวณ MLM อัตโนมัติ');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'รายละเอียดการจอง',
          style: styles(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('service_bookings')
            .doc(bookingId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: mainColor));
          }
          if (!snapshot.data!.exists) {
            return Center(
              child: Text(
                'ไม่พบการจอง',
                style: styles(fontSize: 14.sp, color: context.subColor),
              ),
            );
          }

          final bk = snapshot.data!.data() as Map<String, dynamic>;
          final status = bk['status'] as String? ?? 'pending';
          final isWalkIn = bk['isWalkIn'] as bool? ?? false;
          final bd = (bk['bookingDate'] as Timestamp?)?.toDate();
          final endAt = (bk['bookingEndAt'] as Timestamp?)?.toDate();
          final serviceLoc = bk['serviceLocation'] as String? ?? 'shop';
          final phone = bk['customerPhone'] as String? ?? '';
          final arrivedAt = (bk['customerArrivedAt'] as Timestamp?)?.toDate();
          final completedAt = (bk['completedAt'] as Timestamp?)?.toDate();

          final ratingData =
              ((bk['rating'] as Map<String, dynamic>?)?['fromCustomer'])
                  as Map<String, dynamic>?;
          final stars = (ratingData?['stars'] as num?)?.toInt() ?? 0;
          final review = ratingData?['review'] as String? ?? '';

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusBanner(context, status),
                if (isWalkIn) ...[
                  SizedBox(height: 8.h),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add_alt_1,
                          size: 14.r,
                          color: Colors.orange[700],
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          'ลูกค้าเดินเข้าร้าน',
                          style: styles(
                            fontSize: 12.sp,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildAssignmentErrorBanner(context, bk),
                SizedBox(height: 16.h),
                if (status != 'rejected') _buildTimeline(context, status),
                SizedBox(height: 16.h),

                _section(
                  context,
                  title: 'ข้อมูลลูกค้า',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child:
                                isWalkIn &&
                                    (bk['customerName'] as String? ?? '') ==
                                        'ลูกค้าเดินเข้าร้าน'
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 65.w,
                                        child: Text(
                                          'ชื่อ',
                                          style: styles(
                                            fontSize: 12.sp,
                                            color: context.textColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'ลูกค้าเดินเข้าร้าน',
                                          style:
                                              styles(
                                                fontSize: 13.sp,
                                                color: context.subColor,
                                                fontWeight: FontWeight.w400,
                                              ).copyWith(
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                      ),
                                    ],
                                  )
                                : _row(
                                    context,
                                    Icons.person_outline,
                                    'ชื่อ',
                                    bk['customerName'] as String? ?? '',
                                  ),
                          ),
                        ],
                      ),
                      if (serviceLoc == 'home' &&
                          (bk['serviceAddress'] as String? ?? '')
                              .isNotEmpty) ...[
                        SizedBox(height: 8.h),
                        _row(
                          context,
                          Icons.home_outlined,
                          'ที่อยู่',
                          bk['serviceAddress'] as String? ?? '',
                        ),
                      ],
                      if (phone.isNotEmpty)
                        GestureDetector(
                          onTap: () => _callPhone(phone),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 6.h,
                            ),

                            child: Row(
                              children: [
                                Icon(
                                  Icons.call_outlined,
                                  size: 14.r,
                                  color: Colors.blue[700],
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  phone,
                                  style: styles(
                                    fontSize: 12.sp,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),

                // Booking details
                _section(
                  context,
                  title: 'รายละเอียดการจอง',
                  child: Column(
                    children: [
                      Text(
                        bk['serviceName'] as String? ?? '',
                        style: styles(
                          fontSize: 14.sp,
                          color: context.textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      if (bd != null) ...[
                        _timeRow(context, 'เวลานัด', _fmtTimeRange(bd, endAt)),
                        SizedBox(height: 8.h),
                      ],
                      if (arrivedAt != null) ...[
                        _timeRow(
                          context,

                          'บริการ',
                          _fmtTimeRange(arrivedAt, completedAt),
                        ),
                        SizedBox(height: 8.h),
                      ],
                      _row(
                        context,
                        serviceLoc == 'home'
                            ? Icons.home_outlined
                            : Icons.storefront_outlined,
                        '',
                        serviceLoc == 'home'
                            ? 'บริการที่บ้าน'
                            : 'บริการที่ร้าน',
                      ),
                      SizedBox(height: 8.h),
                      _row(
                        context,
                        Icons.person_outline,
                        'ช่าง',
                        (bk['providerName'] as String? ?? '').isNotEmpty
                            ? bk['providerName'] as String
                            : 'ยังไม่ระบุ',
                      ),
                      if ((bk['customerNote'] as String? ?? '').isNotEmpty) ...[
                        SizedBox(height: 8.h),
                        _row(
                          context,
                          Icons.notes_outlined,
                          'หมายเหตุ',
                          bk['customerNote'] as String? ?? '',
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 8.h),
                if (status != 'completed' && status != 'rejected')
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.swap_horiz, size: 18.r),
                      label: Text(
                        'เปลี่ยนช่าง',
                        style: styles(
                          fontSize: 13.sp,
                          color: mainColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mainColor,
                        side: BorderSide(color: mainColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                      ),
                      onPressed: () => _showProviderPickerDialog(context, bk),
                    ),
                  ),
                SizedBox(height: 12.h),

                _section(
                  context,
                  title: 'การชำระเงิน',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isWalkIn) ...[
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 8.h,
                          ),
                          margin: EdgeInsets.only(bottom: 10.h),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.payments_outlined,
                                size: 16.r,
                                color: Colors.amber[800],
                              ),
                              SizedBox(width: 6.w),
                              Text(
                                'รอรับเงินสดจากลูกค้า',
                                style: styles(
                                  fontSize: 13.sp,
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _priceRow(
                        context,
                        'วิธีชำระ',
                        _paymentLabel(bk['paymentMethod'] as String? ?? ''),
                      ),
                      SizedBox(height: 6.h),
                      _priceRow(
                        context,
                        'ค่าบริการ',
                        '฿${(bk['servicePrice'] as num?)?.toInt() ?? 0}',
                      ),
                      if (((bk['travelFee'] as num?)?.toInt() ?? 0) > 0) ...[
                        SizedBox(height: 6.h),
                        _priceRow(
                          context,
                          'ค่าเดินทาง',
                          '+฿${(bk['travelFee'] as num?)?.toInt() ?? 0}',
                        ),
                      ],
                      Divider(height: 20.h, color: Colors.grey[200]),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'รวม',
                            style: styles(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: context.textColor,
                            ),
                          ),
                          Text(
                            '฿${(bk['totalAmount'] as num?)?.toInt() ?? 0}',
                            style: styles(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                              color: mainColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (status == 'completed') ...[
                  SizedBox(height: 12.h),
                  _section(
                    context,
                    title: 'คะแนนจากลูกค้า',
                    child: stars > 0
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Icon(
                                      i < stars
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: Colors.amber,
                                      size: 24.r,
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  Text(
                                    '$stars/5',
                                    style: styles(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.amber[700],
                                    ),
                                  ),
                                ],
                              ),
                              if (review.isNotEmpty) ...[
                                SizedBox(height: 8.h),
                                Text(
                                  review,
                                  style: styles(
                                    fontSize: 13.sp,
                                    color: context.textColor,
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Text(
                            'ลูกค้ายังไม่ได้ให้คะแนน',
                            style: styles(
                              fontSize: 13.sp,
                              color: Colors.grey[400],
                            ),
                          ),
                  ),
                ],

                SizedBox(height: 20.h),

                if (status == 'pending') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                          ),
                          onPressed: () => _rejectBooking(context),
                          child: Text(
                            'ปฏิเสธ',
                            style: styles(
                              fontSize: 15.sp,
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                          ),
                          onPressed: () => _confirmBooking(context),
                          child: Text(
                            'ยืนยัน',
                            style: styles(
                              fontSize: 15.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (status == 'confirmed') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        Icons.person_pin_circle_outlined,
                        color: Colors.white,
                        size: 20.r,
                      ),
                      label: Text(
                        'ลูกค้ามาถึงแล้ว',
                        style: styles(
                          fontSize: 15.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      onPressed: () => _markCustomerArrived(context),
                    ),
                  ),
                ],

                if (status == 'in_service') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 20.r,
                      ),
                      label: Text(
                        'เสร็จสิ้นบริการ',
                        style: styles(
                          fontSize: 15.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      onPressed: () => _completeBooking(context),
                    ),
                  ),
                ],

                SizedBox(height: 32.h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusBanner(BuildContext context, String status) {
    final color = _statusColor(status);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10.r),
          SizedBox(width: 10.w),
          Text(
            _statusLabel(status),
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, String status) {
    const steps = ['pending', 'confirmed', 'in_service', 'completed'];
    const labels = ['รอยืนยัน', 'ยืนยัน', 'บริการ', 'เสร็จสิ้น'];
    final activeIdx = steps.indexOf(status).clamp(0, 3);

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: activeIdx >= i ? mainColor : Colors.grey[300],
              ),
            ),
          Column(
            children: [
              Container(
                width: 28.r,
                height: 28.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeIdx >= i ? mainColor : Colors.grey[300],
                ),
                child: activeIdx > i
                    ? Icon(Icons.check, color: Colors.white, size: 14.r)
                    : activeIdx == i
                    ? Center(
                        child: Container(
                          width: 10.r,
                          height: 10.r,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(height: 4.h),
              Text(
                labels[i],
                style: styles(
                  fontSize: 10.sp,
                  color: activeIdx >= i ? mainColor : Colors.grey[400],
                  fontWeight: activeIdx == i
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4.w,
                height: 14.h,
                decoration: BoxDecoration(
                  color: mainColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                title,
                style: styles(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: context.textColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }

  Widget _timeRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          flex: 1,
          child: Text(
            '$label:',
            style: styles(
              fontSize: 12.sp,
              color: context.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: styles(
              fontSize: 12.sp,
              color: context.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 65.w,
          child: Text(
            label,
            style: styles(
              fontSize: 12.sp,
              color: context.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: styles(
              fontSize: 13.sp,
              color: context.textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssignmentErrorBanner(
    BuildContext context,
    Map<String, dynamic> bk,
  ) {
    final err = bk['assignmentError'] as String?;
    if (err == null) return const SizedBox.shrink();

    final isNoProv = err == 'no_eligible_provider';
    final color = isNoProv ? Colors.orange : Colors.red;
    final msg = isNoProv
        ? '⚠️ ไม่มีช่างที่ทำบริการนี้ได้ — กรุณา assign ช่างด้วยตนเอง'
        : '⚠️ ช่างทุกคนไม่ว่างในช่วงเวลานี้ — กรุณาติดต่อลูกค้า';

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18.r, color: color),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              msg,
              style: styles(fontSize: 13.sp, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        Text(
          value,
          style: styles(fontSize: 13.sp, color: context.textColor),
        ),
      ],
    );
  }
}
