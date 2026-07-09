// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/utils/business_hours_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:thai_address_picker/thai_address_picker.dart';

class EditServiceShopPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> shopData;

  const EditServiceShopPage({super.key, required this.shopData});

  @override
  ConsumerState<EditServiceShopPage> createState() =>
      _EditServiceShopPageState();
}

class _EditServiceShopPageState extends ConsumerState<EditServiceShopPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _shopNameController;
  late final TextEditingController _descController;
  late final TextEditingController _phoneController;

  static const _dayDefs = [
    {'key': 'mon', 'label': 'จันทร์'},
    {'key': 'tue', 'label': 'อังคาร'},
    {'key': 'wed', 'label': 'พุธ'},
    {'key': 'thu', 'label': 'พฤหัส'},
    {'key': 'fri', 'label': 'ศุกร์'},
    {'key': 'sat', 'label': 'เสาร์'},
    {'key': 'sun', 'label': 'อาทิตย์'},
  ];
  late Map<String, Map<String, dynamic>> _businessHours;

  late final TextEditingController _addressController;
  String _province = '';
  String _district = '';
  String _subDistrict = '';
  String _postalCode = '';
  GoogleMapController? _mapController;
  LatLng _mapPosition = const LatLng(13.7563, 100.5018);
  Set<Marker> _markers = {};
  bool _mapReady = false;
  bool _locatingMap = false;
  double? _lat;
  Province? _initialProvince;
  District? _initialDistrict;
  SubDistrict? _initialSubDistrict;
  double? _lng;

  late String _serviceLocation;
  late final TextEditingController _radiusController;
  late final TextEditingController _feeController;

  @override
  void initState() {
    super.initState();

    _shopNameController = TextEditingController(
      text: widget.shopData['shopName'] as String? ?? '',
    );
    _descController = TextEditingController(
      text: widget.shopData['description'] as String? ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.shopData['phone'] as String? ?? '',
    );

    _businessHours = {
      for (final d in _dayDefs)
        d['key']!: {'open': '09:00', 'close': '21:00', 'closed': false},
    };
    final rawHours = widget.shopData['businessHours'];
    if (rawHours is Map) {
      for (final key in _businessHours.keys) {
        final entry = rawHours[key];
        if (entry is Map) {
          _businessHours[key] = {
            'open': (entry['open'] as String?) ?? '09:00',
            'close': (entry['close'] as String?) ?? '21:00',
            'closed': (entry['closed'] as bool?) ?? false,
          };
        }
      }
    }

    _addressController = TextEditingController(
      text: widget.shopData['address'] as String? ?? '',
    );
    _province = widget.shopData['province'] as String? ?? '';
    _district = widget.shopData['district'] as String? ?? '';
    _subDistrict = widget.shopData['subDistrict'] as String? ?? '';
    _postalCode = widget.shopData['postalCode'] as String? ?? '';

    final gp = widget.shopData['location'];
    if (gp is GeoPoint) {
      _lat = gp.latitude;
      _lng = gp.longitude;
      _mapPosition = LatLng(gp.latitude, gp.longitude);
      _markers = {
        Marker(
          markerId: const MarkerId('shop'),
          position: _mapPosition,
          draggable: true,
          infoWindow: const InfoWindow(
            title: 'ร้านของคุณ',
            snippet: 'ลากเพื่อย้ายตำแหน่ง',
          ),
          onDragEnd: (LatLng newPos) => setState(() {
            _mapPosition = newPos;
            _lat = newPos.latitude;
            _lng = newPos.longitude;
          }),
        ),
      };
    } else {
      _initMapLocation();
    }

    _loadAddressInitials();

    _serviceLocation = widget.shopData['serviceLocation'] as String? ?? 'shop';
    _radiusController = TextEditingController(
      text:
          (widget.shopData['homeServiceRadius'] as num?)?.toStringAsFixed(0) ??
          '10',
    );
    _feeController = TextEditingController(
      text:
          (widget.shopData['homeServiceFee'] as num?)?.toStringAsFixed(0) ??
          '0',
    );
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _descController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _radiusController.dispose();
    _feeController.dispose();
    _mapReady = false;
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _saveBasicInfo() async {
    if (!_formKey.currentState!.validate()) return;
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _db.collection('service_shops').doc(_uid).update({
        'shopName': _shopNameController.text.trim(),
        'description': _descController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'อัปเดตข้อมูลร้านแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _pickTime(String dayKey, bool isOpenTime) async {
    final current =
        _businessHours[dayKey]![isOpenTime ? 'open' : 'close'] as String;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      setState(() {
        _businessHours[dayKey]![isOpenTime ? 'open' : 'close'] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _saveBusinessHours() async {
    final hasOpen = _businessHours.values.any((h) => !(h['closed'] as bool));
    if (!hasOpen) {
      Fluttertoast.showToast(msg: 'กรุณาเปิดให้บริการอย่างน้อย 1 วัน');
      return;
    }
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _db.collection('service_shops').doc(_uid).update({
        'businessHours': _businessHours,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'อัปเดตเวลาทำการแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  // ─── Tab 3: Address + Location ────────────────────────────────────────────

  void _onMapTap(LatLng pos) {
    setState(() {
      _mapPosition = pos;
      _lat = pos.latitude;
      _lng = pos.longitude;
    });
    _updateMarker(pos);
  }

  void _updateMarker(LatLng pos) {
    if (!mounted) return;
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('shop'),
          position: pos,
          draggable: true,
          infoWindow: const InfoWindow(
            title: 'ร้านของคุณ',
            snippet: 'ลากเพื่อย้ายตำแหน่ง',
          ),
          onDragEnd: (LatLng newPos) {
            setState(() {
              _mapPosition = newPos;
              _lat = newPos.latitude;
              _lng = newPos.longitude;
            });
          },
        ),
      };
    });
  }

  Future<void> _getMyLocation() async {
    EasyLoading.show(status: 'กำลังหาตำแหน่ง...');
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          EasyLoading.showError('ไม่ได้รับสิทธิ์เข้าถึงตำแหน่ง');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        EasyLoading.showError('กรุณาเปิดสิทธิ์ตำแหน่งในการตั้งค่า');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _mapPosition = latLng;
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      _updateMarker(latLng);
      if (_mapReady && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16.0));
      }
      EasyLoading.showSuccess('ได้ตำแหน่งแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  // ─── Load Address Initials (lookup typed objects from repository) ─────────

  Future<void> _loadAddressInitials() async {
    if (_province.isEmpty) return;
    try {
      await ref.read(repositoryInitProvider.future);
      if (!mounted) return;
      final repo = ref.read(thaiAddressRepositoryProvider);

      // Find Province by nameTh
      final pList = repo.provinces.where((p) => p.nameTh == _province).toList();
      if (pList.isEmpty) return;
      final province = pList.first;

      // Find District by nameTh within Province
      final dList = repo
          .getDistrictsByProvince(province.id)
          .where((d) => d.nameTh == _district)
          .toList();
      final district = dList.isEmpty ? null : dList.first;

      // Find SubDistrict by nameTh within District
      SubDistrict? subDistrict;
      if (district != null) {
        final sList = repo
            .getSubDistrictsByDistrict(district.id)
            .where((s) => s.nameTh == _subDistrict)
            .toList();
        subDistrict = sList.isEmpty ? null : sList.first;
      }

      if (mounted) {
        setState(() {
          _initialProvince = province;
          _initialDistrict = district;
          _initialSubDistrict = subDistrict;
        });
      }
    } catch (_) {
      // silently fail — user can still select manually
    }
  }

  // ─── Init Map Location (GPS fallback when no saved location) ──────────────

  Future<void> _initMapLocation() async {
    if (mounted) setState(() => _locatingMap = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locatingMap = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _mapPosition = latLng;
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locatingMap = false;
      });
      _updateMarker(latLng);
      if (_mapReady && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16.0));
      }
    } catch (_) {
      if (mounted) setState(() => _locatingMap = false);
    }
  }

  Future<void> _saveAddress() async {
    if (_addressController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณากรอกที่อยู่');
      return;
    }
    if (_province.isEmpty || _district.isEmpty || _subDistrict.isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกจังหวัด/อำเภอ/ตำบล');
      return;
    }
    if (_lat == null || _lng == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกตำแหน่งบนแผนที่');
      return;
    }

    // Check active bookings before saving
    EasyLoading.show(status: 'กำลังตรวจสอบ...');
    int activeCount = 0;
    try {
      final snap = await _db
          .collection('service_bookings')
          .where('shopId', isEqualTo: _uid)
          .where('status', whereIn: ['pending', 'confirmed'])
          .where('bookingDate', isGreaterThanOrEqualTo: Timestamp.now())
          .get();
      activeCount = snap.docs.length;
    } catch (_) {
      // composite index might not exist yet — skip warning
    }
    EasyLoading.dismiss();

    if (activeCount > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          title: Text(
            'มีการจองที่กำลังจะมาถึง',
            style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'พบการจอง $activeCount รายการที่ลูกค้ารับทราบที่อยู่เดิมแล้ว\n'
            'การเปลี่ยนที่อยู่ตอนนี้อาจทำให้ลูกค้าสับสน\n'
            'ยืนยันการเปลี่ยน?',
            style: styles(fontSize: 13.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'ยกเลิก',
                style: styles(fontSize: 13.sp, color: Colors.grey[700]),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: mainColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'ยืนยัน (แจ้งลูกค้าด้วย)',
                style: styles(fontSize: 13.sp, color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _db.collection('service_shops').doc(_uid).update({
        'address': _addressController.text.trim(),
        'province': _province,
        'district': _district,
        'subDistrict': _subDistrict,
        'postalCode': _postalCode,
        'location': GeoPoint(_lat!, _lng!),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'อัปเดตที่ตั้งร้านแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  // ─── Tab 4: Service Settings ──────────────────────────────────────────────

  Future<void> _saveServiceSettings() async {
    if (_serviceLocation != 'shop') {
      final radius = double.tryParse(_radiusController.text.trim()) ?? 0;
      if (radius < 1) {
        Fluttertoast.showToast(msg: 'รัศมีให้บริการต้องอย่างน้อย 1 กม.');
        return;
      }
      final fee = double.tryParse(_feeController.text.trim());
      if (fee == null || fee < 0) {
        Fluttertoast.showToast(msg: 'ค่าเดินทางต้องไม่ติดลบ');
        return;
      }
    }

    // Warn if reducing home capability
    final oldLocation = widget.shopData['serviceLocation'] as String? ?? 'shop';
    final wasHome = oldLocation == 'home' || oldLocation == 'both';
    final isNowShopOnly = _serviceLocation == 'shop';

    if (wasHome && isNowShopOnly) {
      EasyLoading.show(status: 'กำลังตรวจสอบ...');
      int activeCount = 0;
      try {
        final snap = await _db
            .collection('service_bookings')
            .where('shopId', isEqualTo: _uid)
            .where('status', whereIn: ['pending', 'confirmed'])
            .where('bookingDate', isGreaterThanOrEqualTo: Timestamp.now())
            .where('serviceLocation', isEqualTo: 'home')
            .get();
        activeCount = snap.docs.length;
      } catch (_) {
        // composite index might not exist yet — skip warning
      }
      EasyLoading.dismiss();

      if (activeCount > 0) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            title: Text(
              'มีการจองถึงบ้านที่รอดำเนินการ',
              style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'พบการจอง $activeCount รายการที่ลูกค้าขอบริการที่บ้าน\n'
              'การเปลี่ยนรูปแบบบริการอาจทำให้การจองไม่ตรงรูปแบบใหม่\n'
              'ยืนยัน?',
              style: styles(fontSize: 13.sp),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'ยกเลิก',
                  style: styles(fontSize: 13.sp, color: Colors.grey[700]),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'ยืนยัน',
                  style: styles(fontSize: 13.sp, color: Colors.white),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    final radius = _serviceLocation == 'shop'
        ? 0.0
        : (double.tryParse(_radiusController.text.trim()) ?? 10.0);
    final fee = _serviceLocation == 'shop'
        ? 0.0
        : (double.tryParse(_feeController.text.trim()) ?? 0.0);

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _db.collection('service_shops').doc(_uid).update({
        'serviceLocation': _serviceLocation,
        'homeServiceRadius': radius,
        'homeServiceFee': fee,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'อัปเดตรูปแบบบริการแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'แก้ไขข้อมูลร้าน',
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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: styles(fontSize: 13.sp, fontWeight: FontWeight.w600),
            unselectedLabelStyle: styles(fontSize: 13.sp),
            tabs: const [
              Tab(text: 'ข้อมูลร้าน'),
              Tab(text: 'เวลาทำการ'),
              Tab(text: 'ที่ตั้งร้าน'),
              Tab(text: 'รูปแบบบริการ'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  _buildTab1(),
                  _buildTab2(),
                  _buildTab3(),
                  _buildTab4(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab1() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('ข้อมูลร้านค้า'),
            TextFormField(
              controller: _shopNameController,
              maxLength: 80,
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('ชื่อร้าน *'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'กรุณากรอกชื่อร้าน' : null,
            ),
            SizedBox(height: 8.h),
            TextFormField(
              controller: _descController,
              maxLines: 4,
              maxLength: 300,
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('รายละเอียดร้าน *'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'กรุณากรอกรายละเอียด' : null,
            ),
            SizedBox(height: 8.h),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('เบอร์โทรติดต่อ *'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'กรุณากรอกเบอร์โทร' : null,
            ),
            SizedBox(height: 32.h),
            _saveButton(_saveBasicInfo),
          ],
        ),
      ),
    );
  }

  // ─── Tab 2: Business Hours ────────────────────────────────────────────────

  Widget _buildTab2() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('เวลาเปิด-ปิดร้าน'),

          SizedBox(height: 16.h),
          ...(_dayDefs.map((d) => _buildDayRow(d['key']!, d['label']!))),
          SizedBox(height: 32.h),
          _saveButton(_saveBusinessHours),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _buildDayRow(String key, String label) {
    final hours = _businessHours[key]!;
    final isClosed = !parseBusinessDay(hours).isOpen;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isClosed ? Colors.grey[50] : mainColor.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          SizedBox(
            width: 90.w,
            child: Text(
              label,
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: isClosed ? Colors.grey[400] : Colors.black87,
              ),
            ),
          ),

          if (!isClosed) ...[
            SizedBox(width: 4.w),
            _timePill(key, true),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: Text(
                '–',
                style: styles(fontSize: 13.sp, color: Colors.grey[500]),
              ),
            ),
            _timePill(key, false),
          ] else ...[
            SizedBox(width: 8.w),
            Text(
              'หยุด',
              style: styles(fontSize: 13.sp, color: Colors.grey[400]),
            ),
          ],
          Transform.scale(
            scale: 0.85.r,
            child: Switch(
              value: !isClosed,
              activeThumbColor: mainColor,
              activeTrackColor: mainColor.withValues(alpha: 0.5),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) =>
                  setState(() => _businessHours[key]!['closed'] = !val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timePill(String dayKey, bool isOpen) {
    final timeStr =
        _businessHours[dayKey]![isOpen ? 'open' : 'close'] as String;
    return GestureDetector(
      onTap: () => _pickTime(dayKey, isOpen),
      child: Text(
        timeStr,
        style: styles(
          fontSize: 13.sp,
          color: mainColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── Tab 3: Address + Location ────────────────────────────────────────────

  Widget _buildTab3() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ที่อยู่ร้าน'),

          // Show current address as reference
          if (_province.isNotEmpty)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 12.h),
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ที่อยู่ปัจจุบัน',
                    style: styles(fontSize: 11.sp, color: Colors.grey[500]),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '$_subDistrict, $_district, จ.$_province $_postalCode',
                    style: styles(
                      fontSize: 12.sp,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          TextFormField(
            controller: _addressController,
            style: styles(fontSize: 13.sp),
            decoration: _inputDec('เลขที่ / หมู่บ้าน / ซอย / ถนน *'),
          ),
          SizedBox(height: 12.h),
          ThaiAddressForm(
            // ValueKey forces re-init of ThaiAddressForm state once initials are loaded
            key: ValueKey('addr_${_initialProvince?.id ?? 'none'}'),
            initialProvince: _initialProvince,
            initialDistrict: _initialDistrict,
            initialSubDistrict: _initialSubDistrict,
            textStyle: styles(
              fontSize: 13.sp,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
            provinceDecoration: _thaiInputDec(),
            districtDecoration: _thaiInputDec(),
            subDistrictDecoration: _thaiInputDec(),
            zipCodeDecoration: _thaiInputDec(),
            onChanged: (address) {
              if ((address.provinceTh ?? '').isEmpty) return;
              if ((address.districtTh ?? '').isEmpty) return;
              if ((address.subDistrictTh ?? '').isEmpty) return;
              setState(() {
                _province = address.provinceTh ?? '';
                _district = address.districtTh ?? '';
                _subDistrict = address.subDistrictTh ?? '';
                _postalCode = address.zipCode ?? '';
              });
            },
            useThai: true,
          ),
          SizedBox(height: 20.h),
          _sectionTitle('ตำแหน่งบนแผนที่'),
          Text(
            'แตะแผนที่หรือลากหมุดเพื่อปรับตำแหน่ง',
            style: styles(fontSize: 12.sp, color: Colors.grey[600]),
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: SizedBox(
              height: 260.h,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _mapPosition,
                      zoom: 14.0,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _mapReady = true;
                      if (_lat != null && _lng != null && !_locatingMap) {
                        _mapController!.animateCamera(
                          CameraUpdate.newLatLngZoom(_mapPosition, 16.0),
                        );
                      }
                    },
                    onTap: _onMapTap,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapType: MapType.normal,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                  if (_locatingMap)
                    Container(
                      color: Colors.black12,
                      child: Center(
                        child: CircularProgressIndicator(color: mainColor),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _lat == null
                    ? Text(
                        'ยังไม่ได้เลือกตำแหน่ง',
                        style: styles(
                          fontSize: 12.sp,
                          color: Colors.red.shade400,
                        ),
                      )
                    : Text(
                        '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                        style: styles(fontSize: 12.sp, color: Colors.grey[700]),
                      ),
              ),
              TextButton.icon(
                icon: Icon(Icons.my_location, size: 18.r, color: mainColor),
                label: Text(
                  'ตำแหน่งปัจจุบัน',
                  style: styles(
                    fontSize: 12.sp,
                    color: mainColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _getMyLocation,
              ),
            ],
          ),
          SizedBox(height: 32.h),
          _saveButton(_saveAddress),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  // ─── Tab 4: Service Settings ──────────────────────────────────────────────

  Widget _buildTab4() {
    final needsHome = _serviceLocation == 'home' || _serviceLocation == 'both';

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('รูปแบบการให้บริการ'),
          _serviceRadio(
            value: 'shop',
            label: 'ลูกค้ามาที่ร้าน',
            icon: Icons.storefront,
          ),
          _serviceRadio(
            value: 'home',
            label: 'ไปบริการที่บ้านลูกค้า',
            icon: Icons.home_repair_service,
          ),
          _serviceRadio(
            value: 'both',
            label: 'ทั้งสองแบบ',
            icon: Icons.swap_horiz,
          ),

          if (needsHome) ...[
            SizedBox(height: 20.h),
            _sectionTitle('รายละเอียดบริการถึงบ้าน'),
            TextField(
              controller: _radiusController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('รัศมีให้บริการ (กม.) *').copyWith(
                helperText: 'ระยะทางสูงสุดที่ยินดีเดินทางไปบริการ',
                helperStyle: styles(fontSize: 11.sp, color: Colors.grey[500]),
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: _feeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('ค่าเดินทางเพิ่ม (บาท)').copyWith(
                helperText: '0 = ไม่เก็บค่าเดินทาง',
                helperStyle: styles(fontSize: 11.sp, color: Colors.grey[500]),
              ),
            ),
          ],

          SizedBox(height: 32.h),
          _saveButton(_saveServiceSettings),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _serviceRadio({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _serviceLocation == value;
    return GestureDetector(
      onTap: () => setState(() => _serviceLocation = value),
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? mainColor.withValues(alpha: 0.07) : Colors.grey[50],
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected ? mainColor : Colors.grey[200]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20.r,
              height: 20.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? mainColor : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10.r,
                        height: 10.r,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: mainColor,
                        ),
                      ),
                    )
                  : null,
            ),
            Icon(
              icon,
              size: 20.r,
              color: selected ? mainColor : Colors.grey[500],
            ),
            SizedBox(width: 8.w),
            Text(
              label,
              style: styles(
                fontSize: 13.sp,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? mainColor : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared Helpers ───────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h, top: 4.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 18.h,
            decoration: BoxDecoration(
              color: mainColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            text,
            style: styles(
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: context.purpleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton(VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52.h,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: mainColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          'บันทึก',
          style: styles(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: styles(fontSize: 13.sp, color: Colors.grey[600]),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: mainColor, width: 2),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: context.isDark ? Colors.white70 : Colors.grey,
        ),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  InputDecoration _thaiInputDec() {
    return InputDecoration(
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: mainColor, width: 2),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: context.isDark ? Colors.white70 : Colors.grey,
        ),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}
