// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/vendor_booking_detail_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/utils/date_time_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';

class VendorServiceBookingsPage extends StatefulWidget {
  const VendorServiceBookingsPage({super.key});

  @override
  State<VendorServiceBookingsPage> createState() =>
      _VendorServiceBookingsPageState();
}

class _VendorServiceBookingsPageState
    extends State<VendorServiceBookingsPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'การจองบริการ',
            style: styles(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          backgroundColor: mainColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: styles(fontSize: 13.sp, fontWeight: FontWeight.w600),
            unselectedLabelStyle: styles(fontSize: 13.sp),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'รอยืนยัน'),
              Tab(text: 'ยืนยันแล้ว'),
              Tab(text: 'กำลังบริการ'),
              Tab(text: 'เสร็จแล้ว'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BookingTab(shopId: _uid, status: 'pending'),
            _BookingTab(shopId: _uid, status: 'confirmed'),
            _BookingTab(shopId: _uid, status: 'in_service'),
            _BookingTab(shopId: _uid, status: 'completed'),
          ],
        ),
      ),
    );
  }
}

class _BookingTab extends StatelessWidget {
  final String shopId;
  final String status;

  const _BookingTab({
    required this.shopId,
    required this.status,
  });


  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _markCustomerArrived(BuildContext context, String docId) async {
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
          .doc(docId)
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

  Future<void> _confirmBooking(BuildContext context, String docId) async {
    EasyLoading.show(status: 'กำลังยืนยัน...');
    try {
      await FirebaseFirestore.instance
          .collection('service_bookings')
          .doc(docId)
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

  Future<void> _rejectBooking(BuildContext context, String docId) async {
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
          .doc(docId)
          .update({
            'status': 'rejected',
            'cancelReason': reason.isNotEmpty ? reason : 'ร้านขอปฏิเสธการจอง',
            'rejectedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ปฏิเสธการจองแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _completeBooking(BuildContext context, String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ยืนยันเสร็จสิ้นบริการ?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'กดยืนยันเมื่อให้บริการเสร็จสิ้นแล้ว\nระบบจะคำนวณค่าคอมมิชชันอัตโนมัติ',
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
          .doc(docId)
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(
        msg: 'บันทึกเสร็จสิ้นแล้ว ⚡ ระบบคำนวณ MLM อัตโนมัติ',
      );
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: status)
          .orderBy('bookingDate')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: mainColor));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 56.r,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    status == 'pending'
                        ? 'ไม่มีการจองที่รอยืนยัน'
                        : status == 'confirmed'
                        ? 'ไม่มีการจองที่ยืนยันแล้ว'
                        : status == 'in_service'
                        ? 'ไม่มีบริการที่กำลังดำเนินการ'
                        : 'ยังไม่มีบริการที่เสร็จแล้ว',
                    style: styles(
                      fontSize: 14.sp,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final docId = doc.id;

            final customerName = data['customerName'] as String? ?? '';
            final customerPhone = data['customerPhone'] as String? ?? '';
            final serviceName = data['serviceName'] as String? ?? '';
            final duration = (data['duration'] as num?)?.toInt() ?? 0;
            final totalAmount = (data['totalAmount'] as num?)?.toInt() ?? 0;
            final serviceLoc = data['serviceLocation'] as String? ?? 'shop';
            final serviceAddress = data['serviceAddress'] as String? ?? '';
            final customerNote = data['customerNote'] as String? ?? '';
            final bd = (data['bookingDate'] as Timestamp?)?.toDate();
            final providerName = data['providerName'] as String?;


            final ratingData = status == 'completed'
                ? ((data['rating'] as Map<String, dynamic>?)?['fromCustomer']
                      as Map<String, dynamic>?)
                : null;
            final stars = (ratingData?['stars'] as num?)?.toInt() ?? 0;

            return Card(
              margin: EdgeInsets.only(bottom: 10.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
              elevation: 1,
              child: InkWell(
                borderRadius: BorderRadius.circular(14.r),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => VendorBookingDetailPage(bookingId: docId),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(14.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16.r,
                            color: context.subColor,
                          ),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              customerName,
                              style: styles(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: context.purpleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6.h),

                      // Service + duration
                      Text(
                        '$serviceName${duration > 0 ? '  ·  $duration นาที' : ''}',
                        style: styles(
                          fontSize: 13.sp,
                          color: context.textColor,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12.r,
                            color: providerName != null
                                ? mainColor
                                : Colors.orange[600],
                          ),
                          SizedBox(width: 3.w),
                          Text(
                            providerName ?? 'ยังไม่ระบุช่าง',
                            style: styles(
                              fontSize: 11.sp,
                              color: providerName != null
                                  ? context.subColor
                                  : Colors.orange[600],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),

                      // Date
                      if (bd != null)
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_outlined,
                              size: 13.r,
                              color: context.subColor,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              formatBookingTimeRange(
                                bd,
                                durationMinutes: duration,
                              ),
                              style: styles(
                                fontSize: 12.sp,
                                color: context.subColor,
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 4.h),

                      // Location
                      Row(
                        children: [
                          Icon(
                            serviceLoc == 'home'
                                ? Icons.home_outlined
                                : Icons.storefront_outlined,
                            size: 13.r,
                            color: serviceLoc == 'home'
                                ? Colors.blue
                                : mainColor,
                          ),
                          SizedBox(width: 4.w),
                          Expanded(
                            child: Text(
                              serviceLoc == 'home'
                                  ? 'นอกสถานที่: $serviceAddress'
                                  : 'ที่ร้าน',
                              style: styles(
                                fontSize: 12.sp,
                                color: context.subColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '฿$totalAmount',
                            style: styles(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),

                      if (customerNote.isNotEmpty) ...[
                        SizedBox(height: 6.h),
                        Container(
                          width: double.infinity,
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
                            children: [
                              Icon(
                                Icons.notes_outlined,
                                size: 14.r,
                                color: Colors.orange[700],
                              ),
                              SizedBox(width: 6.w),
                              Expanded(
                                child: Text(
                                  customerNote,
                                  style: styles(
                                    fontSize: 12.sp,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Rating (completed tab)
                      if (status == 'completed' && stars > 0) ...[
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < stars
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: Colors.amber,
                                size: 16.r,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              '$stars/5',
                              style: styles(
                                fontSize: 12.sp,
                                color: Colors.amber[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (customerPhone.isNotEmpty)
                        GestureDetector(
                          onTap: () => _callPhone(customerPhone),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.call_outlined,
                                size: 13.r,
                                color: Colors.blue[700],
                              ),
                              SizedBox(width: 6.w),
                              Text(
                                customerPhone,
                                style: styles(
                                  fontSize: 12.sp,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (status == 'completed' && stars == 0) ...[
                        SizedBox(height: 6.h),
                        Text(
                          'ลูกค้ายังไม่ได้ให้คะแนน',
                          style: styles(
                            fontSize: 12.sp,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],

                      // Action buttons
                      if (status == 'pending') ...[
                        SizedBox(height: 12.h),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                ),
                                onPressed: () => _rejectBooking(context, docId),
                                child: Text(
                                  'ปฏิเสธ',
                                  style: styles(
                                    fontSize: 13.sp,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                ),
                                onPressed: () =>
                                    _confirmBooking(context, docId),
                                child: Text(
                                  'ยืนยัน',
                                  style: styles(
                                    fontSize: 13.sp,
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
                        SizedBox(height: 12.h),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(
                              Icons.person_pin_circle_outlined,
                              color: Colors.white,
                              size: 16.r,
                            ),
                            label: Text(
                              'ลูกค้ามาถึงแล้ว',
                              style: styles(
                                fontSize: 13.sp,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                            ),
                            onPressed: () =>
                                _markCustomerArrived(context, docId),
                          ),
                        ),
                      ],

                      if (status == 'in_service') ...[
                        SizedBox(height: 12.h),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 16.r,
                            ),
                            label: Text(
                              'เสร็จสิ้นบริการ',
                              style: styles(
                                fontSize: 13.sp,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                            ),
                            onPressed: () => _completeBooking(context, docId),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
