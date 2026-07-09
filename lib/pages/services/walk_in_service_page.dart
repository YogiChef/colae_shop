// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/vendor_booking_detail_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class WalkInServicePage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;

  const WalkInServicePage({
    super.key,
    required this.shopId,
    required this.shopData,
  });

  @override
  State<WalkInServicePage> createState() => _WalkInServicePageState();
}

class _WalkInServicePageState extends State<WalkInServicePage> {
  String? _selectedServiceId;
  Map<String, dynamic>? _selectedServiceData;
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _providers = [];
  String? _selectedProviderId;
  String? _selectedProviderName;
  bool _loadingProviders = false;
  String? _nextInQueueName;
  bool _allProvidersBusy = false;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProviders(String typeId) async {
    if (mounted) {
      setState(() {
        _loadingProviders = true;
        _providers = [];
        _selectedProviderId = null;
        _selectedProviderName = null;
        _nextInQueueName = null;
        _allProvidersBusy = false;
      });
    }
    try {
      final now = DateTime.now();

      final snap = await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('providers')
          .get();

      final all = snap.docs
          .where((d) => (d.data()['active'] as bool?) != false)
          .map((d) {
            final data = d.data();
            return <String, dynamic>{
              'id': d.id,
              'name': (data['name'] as String?) ?? '',
              'specialties': List<String>.from(
                data['specialties'] as List? ?? [],
              ),
              'order': (data['order'] as num?)?.toInt() ?? 0,
            };
          })
          .toList();

      final busySnap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: widget.shopId)
          .where('status', whereIn: ['pending', 'confirmed', 'in_service'])
          .get();
      final busyProviderIds = busySnap.docs
          .where((d) {
            final endAt = (d.data()['bookingEndAt'] as Timestamp?)?.toDate();
            return endAt != null && endAt.isAfter(now);
          })
          .map((d) => d.data()['providerId'] as String?)
          .whereType<String>()
          .toSet();

      final eligible =
          all.where((p) {
              if (busyProviderIds.contains(p['id'] as String)) return false;
              final specs = p['specialties'] as List<String>;
              return specs.isEmpty || typeId.isEmpty || specs.contains(typeId);
            }).toList()
            ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));

      debugPrint(
        '[PROVIDER] shopId=${widget.shopId} typeId=$typeId eligible=${eligible.length} busy=${busyProviderIds.length}',
      );

      String? nextName;
      try {
        final nowBkk = now.toUtc().add(const Duration(hours: 7));
        final dateKey =
            '${nowBkk.year}-'
            '${nowBkk.month.toString().padLeft(2, '0')}-'
            '${nowBkk.day.toString().padLeft(2, '0')}';

        final queueSnap = await FirebaseFirestore.instance
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('queue_state')
            .doc(dateKey)
            .get();

        // If no booking today yet, seed from most recent previous day's queue_state
        Map<String, dynamic>? seedData;
        if (!queueSnap.exists) {
          final prevSnap = await FirebaseFirestore.instance
              .collection('service_shops')
              .doc(widget.shopId)
              .collection('queue_state')
              .orderBy('date', descending: true)
              .limit(1)
              .get();
          if (prevSnap.docs.isNotEmpty) {
            seedData = prevSnap.docs.first.data();
          }
        }

        final allSnap = await FirebaseFirestore.instance
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('providers')
            .where('active', isEqualTo: true)
            .get();

        final allProviders =
            allSnap.docs.map((d) {
              final data = d.data();
              return <String, dynamic>{
                'id': d.id,
                'name': (data['name'] as String?) ?? '',
                'specialties': List<String>.from(
                  data['specialties'] as List? ?? [],
                ),
                'order': (data['order'] as num?)?.toInt() ?? 0,
              };
            }).toList()..sort(
              (a, b) => (a['order'] as int).compareTo(b['order'] as int),
            );

        // Resolve lastIdx — prefer lastAssignedProviderId (ทนต่อ order ซ้ำ/reorder)
        // ใช้ pattern เดียวกันทั้ง today's doc และ seedData
        final Map<String, dynamic>? queueData = queueSnap.exists
            ? queueSnap.data()
            : seedData;

        debugPrint(
          '[QUEUE] dateKey=$dateKey exists=${queueSnap.exists} '
          'seedData=${seedData != null} '
          'lastAssignedIndex=${queueData?['lastAssignedIndex']} '
          'lastAssignedProviderId=${queueData?['lastAssignedProviderId']} '
          'allProviders=${allProviders.map((p) => '${p['name']}(order:${p['order']})').join(', ')}',
        );

        final int lastIdx;
        if (queueData != null) {
          // Prefer ID lookup → ทนต่อ sort instability เมื่อ order ซ้ำกัน
          final prevId = queueData['lastAssignedProviderId'] as String?;
          if (prevId != null) {
            final idx = allProviders.indexWhere((p) => p['id'] == prevId);
            lastIdx = idx != -1
                ? idx
                : ((queueData['lastAssignedIndex'] as num?)?.toInt() ?? -1);
            debugPrint(
              '[QUEUE] resolved by providerId "$prevId" → idx=$idx '
              '(fallback lastAssignedIndex=${queueData['lastAssignedIndex']})',
            );
          } else {
            lastIdx = (queueData['lastAssignedIndex'] as num?)?.toInt() ?? -1;
            debugPrint('[QUEUE] resolved by lastAssignedIndex=$lastIdx');
          }
        } else {
          lastIdx = -1;
          debugPrint('[QUEUE] no queue data → lastIdx=-1 (first booking ever)');
        }

        debugPrint(
          '[QUEUE] startIdx=${(lastIdx + 1) % allProviders.length} (lastIdx=$lastIdx length=${allProviders.length})',
        );

        for (int i = 0; i < allProviders.length; i++) {
          final idx = ((lastIdx + 1) + i) % allProviders.length;
          final p = allProviders[idx];
          if (busyProviderIds.contains(p['id'] as String)) continue;
          final specs = p['specialties'] as List<String>;
          if (specs.isEmpty || typeId.isEmpty || specs.contains(typeId)) {
            nextName = p['name'] as String;
            debugPrint('[QUEUE] → nextName=$nextName (idx=$idx)');
            break;
          }
        }
      } catch (e) {
        debugPrint('[QUEUE] error: $e');
      }

      debugPrint('[QUEUE] next in queue: $nextName');

      if (mounted) {
        setState(() {
          _providers = eligible;
          _allProvidersBusy = eligible.isEmpty && all.isNotEmpty;
          _nextInQueueName = nextName;
          // ไม่ auto-select _selectedProviderId — ให้ CF เป็น single source of truth
          // ผู้ใช้ต้องเลือกเองถ้าต้องการระบุช่าง หรือปล่อยว่างให้ CF จัดคิว
          _loadingProviders = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[PROVIDER] error: $e');
      debugPrint('[PROVIDER] $stack');
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  Future<void> _startService() async {
    if (_selectedServiceData == null) return;

    DateTime? providerFreeAt;
    if (_selectedProviderId != null) {
      try {
        final now = DateTime.now();
        final snap = await FirebaseFirestore.instance
            .collection('service_bookings')
            .where('shopId', isEqualTo: widget.shopId)
            .where('providerId', isEqualTo: _selectedProviderId)
            .where('status', whereIn: ['confirmed', 'in_service'])
            .get();

        final active =
            snap.docs.where((d) {
              final endAt = (d.data()['bookingEndAt'] as Timestamp?)?.toDate();
              return endAt != null && endAt.isAfter(now);
            }).toList()..sort((a, b) {
              final aEnd = (a.data()['bookingEndAt'] as Timestamp).toDate();
              final bEnd = (b.data()['bookingEndAt'] as Timestamp).toDate();
              return bEnd.compareTo(aEnd); // DESC — latest endAt first
            });

        if (active.isNotEmpty) {
          providerFreeAt = (active.first.data()['bookingEndAt'] as Timestamp)
              .toDate();
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final waitMinutes = providerFreeAt != null
        ? providerFreeAt.difference(now).inMinutes
        : 0;
    final freeTimeStr = providerFreeAt != null
        ? '${providerFreeAt.hour.toString().padLeft(2, "0")}:${providerFreeAt.minute.toString().padLeft(2, "0")}'
        : '';

    Widget dialogContent;
    if (providerFreeAt != null) {
      dialogContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16.r, color: Colors.orange[700]),
                    SizedBox(width: 6.w),
                    Text(
                      '$_selectedProviderName กำลังให้บริการอยู่',
                      style: styles(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  'จะว่างประมาณ $freeTimeStr (รออีก ~$waitMinutes นาที)',
                  style: styles(fontSize: 12.sp, color: Colors.orange[700]),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            'จะบันทึกเป็นคิวรอ — ลูกค้ารอในร้าน',
            style: styles(fontSize: 13.sp, color: context.subColor),
          ),
        ],
      );
    } else {
      final svcName = _selectedServiceData!['name'] as String? ?? '';
      dialogContent = Text(
        'เริ่มบริการ "$svcName" ทันที?',
        style: styles(fontSize: 13.sp, color: context.subColor),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
        title: Text(
          providerFreeAt != null ? 'จองคิวรอ' : 'ยืนยันเริ่มบริการ',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: dialogContent,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              providerFreeAt != null ? 'จองคิว' : 'เริ่มเลย',
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

    setState(() => _isSubmitting = true);
    EasyLoading.show(status: 'กำลังบันทึก...');

    try {
      final duration =
          (_selectedServiceData!['duration'] as num?)?.toInt() ?? 30;
      final servicePrice =
          (_selectedServiceData!['price'] as num?)?.toInt() ?? 0;

      final bookingDate = providerFreeAt ?? now;
      final endDt = bookingDate.add(Duration(minutes: duration));
      final status = providerFreeAt != null ? 'confirmed' : 'in_service';

      final customerName = _customerNameController.text.trim().isEmpty
          ? 'ลูกค้าเดินเข้าร้าน'
          : _customerNameController.text.trim();

      final location = widget.shopData['location'] as GeoPoint?;

      final docData = <String, dynamic>{
        'isWalkIn': true,

        'shopId': widget.shopId,
        'shopName': widget.shopData['shopName'] as String? ?? '',
        'vendorId': widget.shopId,

        'customerId': null,
        'customerName': customerName,
        'customerPhone': _customerPhoneController.text.trim(),

        'serviceId': _selectedServiceId,
        'serviceName': _selectedServiceData!['name'] as String? ?? '',
        'typeId': _selectedServiceData!['typeId'] as String?,
        'duration': duration,

        'bookingDate': Timestamp.fromDate(bookingDate),
        'bookingEndAt': Timestamp.fromDate(endDt),

        'serviceLocation': 'shop',
        'serviceAddress': widget.shopData['address'] as String? ?? '',
        'serviceLat': location?.latitude,
        'serviceLng': location?.longitude,

        'servicePrice': servicePrice,
        'travelFee': 0,
        'totalAmount': servicePrice,

        'paymentMethod': 'cash',
        'paymentStatus': 'pending',

        'status': status,
        'customerNote': '',

        'providerId': _selectedProviderId, // null → CF จัดคิวอัตโนมัติ
        'providerName': _selectedProviderName,
        'assignedByQueue': _selectedProviderId == null, // true = CF assign

        'mlmCalculated': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Only set customerArrivedAt if starting immediately (not waiting)
      if (providerFreeAt == null) {
        docData['customerArrivedAt'] = FieldValue.serverTimestamp();
      }

      final docRef = await FirebaseFirestore.instance
          .collection('service_bookings')
          .add(docData);

      EasyLoading.dismiss();
      Fluttertoast.showToast(
        msg: providerFreeAt != null ? 'บันทึกคิวรอแล้ว' : 'เริ่มบริการแล้ว',
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VendorBookingDetailPage(bookingId: docRef.id),
          ),
        );
      }
    } catch (e) {
      EasyLoading.dismiss();
      Fluttertoast.showToast(
        msg: 'เกิดข้อผิดพลาด: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'รับลูกค้าเดินเข้าร้าน',
          style: styles(
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'เลือกบริการ',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 10.h),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('service_shops')
                  .doc(uid)
                  .collection('services')
                  .where('available', isEqualTo: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.h),
                      child: CircularProgressIndicator(color: mainColor),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(24.r),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7.r),
                    ),
                    child: Center(
                      child: Text(
                        'ยังไม่มีบริการที่เปิดใช้งาน',
                        style: styles(fontSize: 13.sp, color: Colors.grey[500]),
                      ),
                    ),
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final name = data['name'] as String? ?? '';
                    final duration = (data['duration'] as num?)?.toInt() ?? 0;
                    final price = (data['price'] as num?)?.toInt() ?? 0;
                    final images = List<String>.from(
                      data['images'] as List? ?? [],
                    );
                    final isSelected = _selectedServiceId == docId;

                    return GestureDetector(
                      onTap: () {
                        final typeId = data['typeId'] as String? ?? '';
                        setState(() {
                          _selectedServiceId = docId;
                          _selectedServiceData = data;
                        });
                        _loadProviders(typeId);
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 8.h),
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.orange.shade50
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(7.r),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: SizedBox(
                                width: 44.r,
                                height: 44.r,
                                child: images.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: images.first,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) =>
                                            _placeholder(),
                                      )
                                    : _placeholder(),
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: styles(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w500,
                                      color: context.purpleColor,
                                    ),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    '$duration นาที · ฿$price',
                                    style: styles(
                                      fontSize: 12.sp,
                                      color: context.subColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 24.r,
                              height: 24.r,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? mainColor
                                    : Colors.grey.shade300,
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      size: 14.r,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (_selectedServiceData != null) ...[
              SizedBox(height: 20.h),
              Text(
                'เลือกผู้ให้บริการ',
                style: styles(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: context.purpleColor,
                ),
              ),
              SizedBox(height: 10.h),
              _buildProviderSection(),
              if (_allProvidersBusy && !_loadingProviders) ...[
                SizedBox(height: 8.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            size: 16.r,
                            color: Colors.red[700],
                          ),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              'ผู้ให้บริการทุกคนไม่ว่างในขณะนี้',
                              style: styles(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.red[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'กรุณารอสักครู่แล้วตรวจสอบใหม่ หรือนัดลูกค้าในช่วงเวลาถัดไป',
                        style: styles(fontSize: 12.sp, color: Colors.red[600]),
                      ),
                      SizedBox(height: 8.h),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(
                            Icons.refresh,
                            size: 16.r,
                            color: Colors.red[700],
                          ),
                          label: Text(
                            'ตรวจสอบคิวใหม่',
                            style: styles(
                              fontSize: 13.sp,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[700],
                            side: BorderSide(color: Colors.red.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                          ),
                          onPressed: () {
                            final typeId =
                                _selectedServiceData!['typeId'] as String? ??
                                '';
                            _loadProviders(typeId);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            SizedBox(height: 20.h),

            Text(
              'ข้อมูลลูกค้า',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 10.h),

            Column(
              children: [
                TextField(
                  controller: _customerNameController,
                  style: styles(fontSize: 14.sp),
                  decoration: InputDecoration(
                    labelText: 'ชื่อลูกค้า',
                    hintText: 'ลูกค้าเดินเข้าร้าน',
                    hintStyle: styles(fontSize: 12.sp, color: Colors.grey[400]),
                    labelStyle: styles(
                      fontSize: 13.sp,
                      color: context.subColor,
                    ),
                    prefixIcon: Icon(
                      Icons.person_outline,
                      size: 20.r,
                      color: Colors.grey[400],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 12.h,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: styles(fontSize: 14.sp),
                  decoration: InputDecoration(
                    labelText: 'เบอร์โทร',
                    hintText: 'ไม่บังคับ',
                    hintStyle: styles(fontSize: 12.sp, color: Colors.grey[400]),
                    labelStyle: styles(
                      fontSize: 13.sp,
                      color: context.subColor,
                    ),
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      size: 20.r,
                      color: Colors.grey[400],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 12.h,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 20.h),

            if (_selectedServiceData != null) ...[
              Text(
                'สรุปบริการ',
                style: styles(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: context.purpleColor,
                ),
              ),
              SizedBox(height: 10.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14.r),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(7.r),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryRow(
                      context,
                      'บริการ',
                      _selectedServiceData!['name'] as String? ?? '',
                    ),
                    SizedBox(height: 6.h),
                    _summaryRow(
                      context,
                      'ระยะเวลา',
                      '${(_selectedServiceData!['duration'] as num?)?.toInt() ?? 0} นาที',
                    ),
                    SizedBox(height: 6.h),
                    _summaryRow(
                      context,
                      'ราคา',
                      '฿${(_selectedServiceData!['price'] as num?)?.toInt() ?? 0}',
                    ),
                    SizedBox(height: 6.h),
                    _summaryRow(
                      context,
                      'ลูกค้า',
                      _customerNameController.text.trim().isEmpty
                          ? 'ลูกค้าเดินเข้าร้าน'
                          : _customerNameController.text.trim(),
                    ),
                    SizedBox(height: 6.h),
                    _summaryRow(
                      context,
                      'ผู้ให้บริการ',
                      _selectedProviderName ?? '$_nextInQueueName (ตามคิว)',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
            ],

            SizedBox(
              width: width * 0.8,
              child: ElevatedButton.icon(
                icon: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 20.r,
                ),
                label: Text(
                  'เริ่มบริการ',
                  style: styles(
                    fontSize: 15.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedServiceData != null
                      ? Colors.blue[600]
                      : Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  elevation: _selectedServiceData != null ? 2 : 0,
                ),
                onPressed: _selectedServiceData != null && !_isSubmitting
                    ? _startService
                    : null,
              ),
            ),
            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderSection() {
    if (_loadingProviders) {
      return Container(
        padding: EdgeInsets.all(20.w),
        alignment: Alignment.center,
        child: SizedBox(
          width: 24.r,
          height: 24.r,
          child: CircularProgressIndicator(strokeWidth: 2, color: mainColor),
        ),
      );
    }

    if (_providers.isEmpty) {
      if (_allProvidersBusy) return const SizedBox.shrink();
      return Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16.r, color: Colors.grey.shade700),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'ยังไม่มีช่างที่ลงทะเบียนไว้ กรุณาเพิ่มช่างก่อนรับลูกค้า',
                style: styles(fontSize: 13.sp, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: _selectedProviderId,
      isExpanded: true,
      hint: Text(
        '$_nextInQueueName (ตามคิว)',

        overflow: TextOverflow.ellipsis,
        style: styles(fontSize: 13.sp),
      ),
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: mainColor, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      ),
      items: _providers.map<DropdownMenuItem<String>>((p) {
        return DropdownMenuItem<String>(
          value: p['id'] as String,
          child: Text(
            p['name'] as String,
            overflow: TextOverflow.ellipsis,
            style: styles(fontSize: 13.sp, color: context.textColor),
          ),
        );
      }).toList(),
      onChanged: (String? value) {
        setState(() {
          _selectedProviderId = value;
          _selectedProviderName = value == null
              ? null
              : (_providers.firstWhere(
                      (p) => p['id'] == value,
                      orElse: () => <String, dynamic>{},
                    )['name']
                    as String?);
        });
      },
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.orange.withValues(alpha: 0.12),
      child: Icon(Icons.spa_rounded, size: 22.r, color: Colors.orange),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70.w,
          child: Text(
            '$label:',
            style: styles(
              fontSize: 13.sp,
              color: Colors.blue[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: styles(
              fontSize: 13.sp,
              color: Colors.blue[900],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
