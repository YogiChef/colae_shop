// ignore_for_file: use_build_context_synchronously, unnecessary_cast

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/customer_member_scanner_page.dart';
import 'package:colae_shop/pages/services/vendor_booking_detail_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
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

  // QR Walk-in: linked buyer member
  String? _linkedBuyerId;
  Map<String, dynamic>? _linkedBuyerData;

  List<Map<String, dynamic>> _providers = [];
  String? _selectedProviderId;
  String? _selectedProviderName;
  bool _loadingProviders = false;
  String? _actualAssigneeName;
  String _actualAssigneeLabel = '';
  bool _allProvidersBusy = false;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final buyerId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerMemberScannerPage()),
    );
    if (buyerId == null || !mounted) return;
    await _linkBuyer(buyerId);
  }

  Future<void> _enterMemberCode() async {
    final ctrl = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          title: Text(
            'กรอกรหัสสมาชิก',
            style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'กรอกรหัสสมาชิก (referral code) หรือ Member ID ของลูกค้า',
                style: styles(fontSize: 13.sp, color: context.subColor),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: ctrl,
                style: styles(fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'เช่น ABC12345',
                  hintStyle: styles(fontSize: 12.sp, color: Colors.grey[400]),
                  errorText: error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                ),
                onChanged: (_) {
                  if (error != null) setS(() => error = null);
                },
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
                backgroundColor: mainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              onPressed: () {
                final input = ctrl.text.trim();
                if (input.isEmpty) {
                  setS(() => error = 'กรุณากรอกรหัส');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(
                'ค้นหา',
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

    if (confirmed != true || !mounted) return;

    final input = ctrl.text.trim();
    EasyLoading.show(status: 'กำลังค้นหา...');
    try {
      final directSnap = await FirebaseFirestore.instance
          .collection('buyers')
          .doc(input)
          .get();

      if (directSnap.exists && mounted) {
        EasyLoading.dismiss();
        await _linkBuyer(
          directSnap.id,
          data: directSnap.data() as Map<String, dynamic>,
        );
        return;
      }

      final normalized = input.toUpperCase();
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(normalized)) {
        EasyLoading.dismiss();
        if (!mounted) return;
        Fluttertoast.showToast(
          msg: 'ไม่พบสมาชิกที่มีรหัสนี้',
          backgroundColor: Colors.red,
        );
        return;
      }

      final refSnap = await FirebaseFirestore.instance
          .collection('buyers')
          .where('referralCode', isEqualTo: normalized)
          .limit(1)
          .get();

      EasyLoading.dismiss();
      if (!mounted) return;

      if (refSnap.docs.isEmpty) {
        Fluttertoast.showToast(
          msg: 'ไม่พบสมาชิกที่มีรหัสนี้',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _linkBuyer(
        refSnap.docs.first.id,
        data: refSnap.docs.first.data() as Map<String, dynamic>,
      );
    } catch (e) {
      EasyLoading.dismiss();
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'เกิดข้อผิดพลาด: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _linkBuyer(String buyerId, {Map<String, dynamic>? data}) async {
    Map<String, dynamic> buyerData;
    if (data != null) {
      buyerData = data;
    } else {
      EasyLoading.show(status: 'กำลังโหลด...');
      try {
        final snap = await FirebaseFirestore.instance
            .collection('buyers')
            .doc(buyerId)
            .get();
        EasyLoading.dismiss();
        if (!snap.exists || !mounted) return;
        buyerData = snap.data() as Map<String, dynamic>;
      } catch (e) {
        EasyLoading.dismiss();
        Fluttertoast.showToast(
          msg: 'โหลดข้อมูลสมาชิกไม่ได้: $e',
          backgroundColor: Colors.red,
        );
        return;
      }
    }

    final name = (buyerData['fullName'] as String?) ?? '';
    final phone = (buyerData['custphone'] as String?) ?? '';

    setState(() {
      _linkedBuyerId = buyerId;
      _linkedBuyerData = buyerData;
      _customerNameController.text = name;
      _customerPhoneController.text = phone;
    });
  }

  void _unlinkBuyer() {
    setState(() {
      _linkedBuyerId = null;
      _linkedBuyerData = null;
      _customerNameController.clear();
      _customerPhoneController.clear();
    });
  }

  Future<void> _loadProviders(String typeId) async {
    if (mounted) {
      setState(() {
        _loadingProviders = true;
        _providers = [];
        _selectedProviderId = null;
        _selectedProviderName = null;
        _actualAssigneeName = null;
        _actualAssigneeLabel = '';
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

      final all =
          snap.docs.where((d) => (d.data()['active'] as bool?) != false).map((
              d,
            ) {
              final data = d.data();
              return <String, dynamic>{
                'id': d.id,
                'name': (data['name'] as String?) ?? '',
                'specialties': List<String>.from(
                  data['specialties'] as List? ?? [],
                ),
                'order': (data['order'] as num?)?.toInt() ?? 0,
              };
            }).toList()
            ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));

      final busySnap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: widget.shopId)
          .where('status', whereIn: ['pending', 'confirmed', 'in_service'])
          .get();
      final busyIds = busySnap.docs
          .where((d) {
            final endAt = (d.data()['bookingEndAt'] as Timestamp?)?.toDate();
            return endAt != null && endAt.isAfter(now);
          })
          .map((d) => d.data()['providerId'] as String?)
          .whereType<String>()
          .toSet();

      final eligible = all.where((p) {
        if (busyIds.contains(p['id'] as String)) return false;
        final specs = p['specialties'] as List<String>;
        return specs.isEmpty || typeId.isEmpty || specs.contains(typeId);
      }).toList();

      debugPrint(
        '[PROVIDER] shopId=${widget.shopId} typeId=$typeId eligible=${eligible.length} busy=${busyIds.length}',
      );

      String? pointerProviderId;
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

        if (queueSnap.exists) {
          pointerProviderId =
              queueSnap.data()?['lastAssignedProviderId'] as String?;
        }
      } catch (e) {
        debugPrint('[QUEUE] error: $e');
      }

      String? computedName;
      String computedLabel = '';
      if (all.isNotEmpty) {
        int pointerIdx;
        if (pointerProviderId != null) {
          pointerIdx = all.indexWhere((p) => p['id'] == pointerProviderId);
          if (pointerIdx == -1) pointerIdx = 0;
        } else {
          final nowBkk = now.toUtc().add(const Duration(hours: 7));
          pointerIdx = nowBkk.weekday % 7 % all.length;
        }

        int currentIdx = pointerIdx;
        for (int i = 0; i < all.length; i++) {
          final candidate = all[currentIdx];
          final specs = candidate['specialties'] as List<String>;
          final canDo =
              specs.isEmpty || typeId.isEmpty || specs.contains(typeId);

          if (!canDo) {
            currentIdx = (currentIdx + 1) % all.length;
            continue;
          }
          if (busyIds.contains(candidate['id'] as String)) {
            currentIdx = (currentIdx + 1) % all.length;
            continue;
          }
          computedName = candidate['name'] as String;
          computedLabel = (currentIdx == pointerIdx) ? 'ตามคิว' : 'แทนคิว';
          break;
        }
      }

      debugPrint(
        '[QUEUE] actual assignee preview: $computedName ($computedLabel)',
      );

      if (mounted) {
        setState(() {
          _providers = eligible;
          _allProvidersBusy = eligible.isEmpty && all.isNotEmpty;
          _actualAssigneeName = computedName;
          _actualAssigneeLabel = computedLabel;
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
        'buyerId': _linkedBuyerId,
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

        'providerId': _selectedProviderId,
        'providerName': _selectedProviderName,
        'assignedByQueue': _selectedProviderId == null,

        'mlmCalculated': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

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
                              borderRadius: BorderRadius.circular(7.r),
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

            SizedBox(height: 12.h),

            Text(
              'ข้อมูลลูกค้า',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 20.h),

            if (_linkedBuyerId != null) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(7.r),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green[700],
                          size: 18.r,
                        ),
                        SizedBox(width: 8.w),

                        Text(
                          'สมาชิก Colae',
                          style: styles(
                            fontSize: 12.sp,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Spacer(),
                        TextButton(
                          onPressed: _unlinkBuyer,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red[400],
                            padding: EdgeInsets.symmetric(horizontal: 6.w),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('ยกเลิก', style: styles(fontSize: 12.sp)),
                        ),
                      ],
                    ),
                    Text(
                      'ชื่อ: ${(_linkedBuyerData?['fullName'] as String?) ?? '-'}',
                      style: styles(fontSize: 13.sp, color: Colors.green[900]),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'เบอร์: ${(_linkedBuyerData?['custphone'] as String?)?.isNotEmpty == true ? (_linkedBuyerData!['custphone'] as String) : '-'}',
                      style: styles(fontSize: 13.sp, color: Colors.green[900]),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: _scanQr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            IconlyLight.scan,
                            size: 18.sp,
                            color: context.purpleColor,
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'สแกน QR',
                            style: styles(
                              fontSize: 13.sp,
                              color: context.purpleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: _enterMemberCode,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            IconlyLight.profile,
                            size: 18.sp,
                            color: context.purpleColor,
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'รหัสสมาชิก',
                            style: styles(
                              fontSize: 13.sp,
                              color: context.purpleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
            ],
            if (_linkedBuyerId == null) ...[
              Column(
                children: [
                  TextField(
                    controller: _customerNameController,
                    style: styles(fontSize: 14.sp),
                    decoration: InputDecoration(
                      labelText: 'ชื่อลูกค้า',
                      hintText: 'ลูกค้าเดินเข้าร้าน',
                      hintStyle: styles(
                        fontSize: 12.sp,
                        color: Colors.grey[400],
                      ),
                      labelStyle: styles(
                        fontSize: 13.sp,
                        color: context.subColor,
                      ),
                      prefixIcon: Icon(
                        Icons.person,
                        size: 20.sp,
                        color: Colors.grey[400],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.sp),
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
                      hintStyle: styles(
                        fontSize: 12.sp,
                        color: Colors.grey[400],
                      ),
                      labelStyle: styles(
                        fontSize: 13.sp,
                        color: context.subColor,
                      ),
                      prefixIcon: Icon(
                        Icons.phone,
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
            ],

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
                      'เวลา',
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
                      'พนักงาน',
                      _selectedProviderName != null
                          ? _selectedProviderName!
                          : _actualAssigneeName != null
                          ? '$_actualAssigneeName ($_actualAssigneeLabel)'
                          : 'ยังไม่ระบุ',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
            ],

            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: width * 0.8,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.play_arrow, color: Colors.white, size: 20.r),
                  label: Text(
                    'เริ่มบริการ',
                    style: styles(
                      fontSize: 15.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.center,
                    backgroundColor:
                        (_selectedServiceData != null &&
                            (_selectedProviderId != null ||
                                _actualAssigneeName != null))
                        ? Colors.blue[600]
                        : Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    elevation:
                        (_selectedServiceData != null &&
                            (_selectedProviderId != null ||
                                _actualAssigneeName != null))
                        ? 2
                        : 0,
                  ),
                  onPressed:
                      _selectedServiceData != null &&
                          !_isSubmitting &&
                          (_selectedProviderId != null ||
                              _actualAssigneeName != null)
                      ? _startService
                      : null,
                ),
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
            Icon(Icons.info, size: 16.r, color: Colors.grey.shade700),
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
        _actualAssigneeName != null
            ? '$_actualAssigneeName ($_actualAssigneeLabel)'
            : 'ไม่มีช่างว่าง',
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
      child: Icon(Icons.spa, size: 22.r, color: Colors.orange),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90.w,
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
