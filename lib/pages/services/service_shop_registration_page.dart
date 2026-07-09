// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
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

class ServiceShopRegistrationPage extends StatefulWidget {
  const ServiceShopRegistrationPage({super.key});

  @override
  State<ServiceShopRegistrationPage> createState() =>
      _ServiceShopRegistrationPageState();
}

class _ServiceShopRegistrationPageState
    extends State<ServiceShopRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;

  final _shopNameController = TextEditingController();
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();

  int _currentStep = 0;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _allTypes = [];
  List<Map<String, dynamic>> _filteredTypes = [];
  String? _selectedCategoryId;
  String? _selectedTypeId;
  Map<String, dynamic>? _selectedTypeData;

  bool _loadingData = true;

  static const _dayDefs = [
    {'key': 'mon', 'label': 'จ.'},
    {'key': 'tue', 'label': 'อ.'},
    {'key': 'wed', 'label': 'พ.'},
    {'key': 'thu', 'label': 'พฤ.'},
    {'key': 'fri', 'label': 'ศ.'},
    {'key': 'sat', 'label': 'ส.'},
    {'key': 'sun', 'label': 'อา.'},
  ];
  late Map<String, Map<String, dynamic>> _businessHours;

  final _addressController = TextEditingController();
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
  double? _lng;

  String _serviceLocation = 'shop';
  final _radiusController = TextEditingController(text: '10');
  final _feeController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _businessHours = {
      for (final d in _dayDefs)
        d['key']!: {'open': '09:00', 'close': '21:00', 'closed': false},
    };
    _loadInitialData();
    _initMapLocation();
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

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _db
            .collection('service_categories')
            .where('active', isEqualTo: true)
            .orderBy('order')
            .get(),
        _db
            .collection('service_types')
            .where('active', isEqualTo: true)
            .orderBy('order')
            .get(),
        _db.collection('vendors').doc(_uid).get(),
      ]);

      final cats = (results[0] as QuerySnapshot).docs.map((d) {
        return {'id': d.id, ...d.data() as Map<String, dynamic>};
      }).toList();

      final allTypes = (results[1] as QuerySnapshot).docs.map((d) {
        return {'id': d.id, ...d.data() as Map<String, dynamic>};
      }).toList();

      final vendorSnap = results[2] as DocumentSnapshot;
      String phone = '';
      if (vendorSnap.exists) {
        final vData = vendorSnap.data() as Map<String, dynamic>?;
        phone = (vData?['phone'] as String?) ?? '';
      }

      if (mounted) {
        setState(() {
          _categories = cats;
          _allTypes = allTypes;
          _loadingData = false;
          if (phone.isNotEmpty) _phoneController.text = phone;
        });
      }
    } catch (e) {
      debugPrint('[Registration] load error: $e');
      if (mounted) setState(() => _loadingData = false);
    }
  }

  void _onCategoryChanged(String? catId) {
    setState(() {
      _selectedCategoryId = catId;
      _selectedTypeId = null;
      _selectedTypeData = null;
      _filteredTypes = _allTypes
          .where((t) => t['categoryId'] == catId)
          .toList();
    });
  }

  void _onTypeChanged(String? typeId) {
    final found = _allTypes.where((t) => t['id'] == typeId).toList();
    setState(() {
      _selectedTypeId = typeId;
      _selectedTypeData = found.isNotEmpty ? found.first : null;
    });
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

  Future<void> _initMapLocation() async {
    if (mounted) setState(() => _locatingMap = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        // fallback: keep default Bangkok coordinates, no marker
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

  bool _validateStep2() {
    if (_selectedCategoryId == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกหมวดบริการ');
      return false;
    }
    if (_selectedTypeId == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกประเภทบริการ');
      return false;
    }
    return true;
  }

  bool _validateStep3() {
    final hasOpen = _businessHours.values.any((h) => !(h['closed'] as bool));
    if (!hasOpen) {
      Fluttertoast.showToast(msg: 'กรุณาเปิดให้บริการอย่างน้อย 1 วัน');
      return false;
    }
    return true;
  }

  bool _validateStep4() {
    if (_addressController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณากรอกที่อยู่');
      return false;
    }
    if (_province.isEmpty || _district.isEmpty || _subDistrict.isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกจังหวัด/อำเภอ/ตำบล');
      return false;
    }
    if (_lat == null || _lng == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกตำแหน่งบนแผนที่');
      return false;
    }
    return true;
  }

  bool _validateStep5() {
    if (_serviceLocation != 'shop') {
      final radius = double.tryParse(_radiusController.text.trim()) ?? 0;
      if (radius < 1) {
        Fluttertoast.showToast(msg: 'รัศมีให้บริการต้องอย่างน้อย 1 กม.');
        return false;
      }
      final fee = double.tryParse(_feeController.text.trim());
      if (fee == null || fee < 0) {
        Fluttertoast.showToast(msg: 'ค่าเดินทางต้องไม่ติดลบ');
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validateStep5()) return;

    final radius = _serviceLocation == 'shop'
        ? 0.0
        : (double.tryParse(_radiusController.text.trim()) ?? 10.0);
    final fee = _serviceLocation == 'shop'
        ? 0.0
        : (double.tryParse(_feeController.text.trim()) ?? 0.0);

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _db.collection('service_shops').doc(_uid).set({
        'ownerId': _uid,
        'shopName': _shopNameController.text.trim(),
        'description': _descController.text.trim(),
        'phone': _phoneController.text.trim(),
        'categoryId': _selectedCategoryId,
        'typeId': _selectedTypeId,
        'businessHours': _businessHours,
        'address': _addressController.text.trim(),
        'province': _province,
        'district': _district,
        'subDistrict': _subDistrict,
        'postalCode': _postalCode,
        'location': GeoPoint(_lat!, _lng!),
        'serviceLocation': _serviceLocation,
        'homeServiceRadius': radius,
        'homeServiceFee': fee,
        'status': 'pending_approval',
        'rating': 0.0,
        'totalReviews': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ลงทะเบียนสำเร็จ — รอการอนุมัติ');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ลงทะเบียนร้านบริการ',
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
      body: _loadingData
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : Column(
              children: [
                _buildStepIndicator(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _buildCurrentStep(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return _buildStep5();
    }
  }

  Widget _buildStepIndicator() {
    const labels = ['ข้อมูล', 'หมวด', 'เวลา', 'ที่ตั้ง', 'บริการ'];
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < 5; i++) ...[
            _stepCircle(i + 1, labels[i], _currentStep >= i),
            if (i < 4) _stepLine(_currentStep > i),
          ],
        ],
      ),
    );
  }

  Widget _stepCircle(int step, String label, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28.r,
          height: 28.r,
          decoration: BoxDecoration(
            color: active ? mainColor : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: styles(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.grey[500],
              ),
            ),
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: styles(
            fontSize: 10.sp,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? mainColor : Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Widget _stepLine(bool active) {
    return Container(
      width: 32.w,
      height: 2.h,
      margin: EdgeInsets.only(bottom: 20.h),
      color: active ? mainColor : Colors.grey[300],
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      key: const ValueKey('step1'),
      padding: EdgeInsets.all(20.w),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('ข้อมูลร้านค้า'),
            TextFormField(
              controller: _shopNameController,
              style: styles(fontSize: 13.sp),
              decoration: _inputDec('ชื่อร้าน *'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'กรุณากรอกชื่อร้าน' : null,
            ),
            SizedBox(height: 16.h),
            TextFormField(
              controller: _descController,
              maxLines: 3,
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
            _nextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  setState(() => _currentStep = 1);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      key: const ValueKey('step2'),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('หมวดบริการ'),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategoryId,
            decoration: _inputDec('เลือกหมวดบริการ *'),
            hint: Text(
              'เลือกหมวด',
              style: styles(fontSize: 13.sp, color: Colors.grey),
            ),
            items: _categories.map((cat) {
              return DropdownMenuItem<String>(
                value: cat['id'] as String,
                child: Text(
                  cat['name'] as String? ?? '',
                  style: styles(fontSize: 13.sp),
                ),
              );
            }).toList(),
            onChanged: _onCategoryChanged,
          ),
          SizedBox(height: 20.h),
          _sectionTitle('ประเภทบริการ'),
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedCategoryId),
            initialValue: _selectedTypeId,
            decoration: _inputDec('เลือกประเภทบริการ *'),
            disabledHint: Text(
              _selectedCategoryId == null
                  ? 'เลือกหมวดก่อน'
                  : 'ไม่มีประเภทในหมวดนี้',
              style: styles(fontSize: 13.sp, color: Colors.grey),
            ),
            hint: Text(
              'เลือกประเภท',
              style: styles(fontSize: 13.sp, color: Colors.grey),
            ),
            items: _filteredTypes.map((t) {
              return DropdownMenuItem<String>(
                value: t['id'] as String,
                child: Text(
                  t['name'] as String? ?? '',
                  style: styles(fontSize: 13.sp),
                ),
              );
            }).toList(),
            onChanged: _filteredTypes.isEmpty ? null : _onTypeChanged,
          ),

          if (_selectedTypeData != null) ...[
            SizedBox(height: 16.h),
            _buildTypePreview(_selectedTypeData!),
          ],

          SizedBox(height: 32.h),
          _navRow(
            onBack: () => setState(() => _currentStep = 0),
            onNext: () {
              if (_validateStep2()) setState(() => _currentStep = 2);
            },
            nextLabel: 'ถัดไป',
          ),
        ],
      ),
    );
  }

  Widget _buildTypePreview(Map<String, dynamic> t) {
    final basePrice = t['basePrice'] as num?;
    final description = t['description'] as String?;
    final name = t['name'] as String?;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: mainColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: mainColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null)
            Text(
              name,
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: mainColor,
              ),
            ),
          if (description != null && description.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              description,
              style: styles(fontSize: 12.sp, color: Colors.grey[700]),
            ),
          ],
          if (basePrice != null) ...[
            SizedBox(height: 8.h),
            Text(
              'ราคาเริ่มต้น ฿${basePrice.toStringAsFixed(0)}',
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: Colors.green[700],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      key: const ValueKey('step3'),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('เวลาเปิด-ปิดร้าน'),
          Text(
            'ตั้งค่าวันและเวลาที่ให้บริการ',
            style: styles(fontSize: 12.sp, color: Colors.grey[600]),
          ),
          SizedBox(height: 16.h),
          ...(_dayDefs.map((d) => _buildDayRow(d['key']!, d['label']!))),
          SizedBox(height: 32.h),
          _navRow(
            onBack: () => setState(() => _currentStep = 1),
            onNext: () {
              if (_validateStep3()) setState(() => _currentStep = 3);
            },
            nextLabel: 'ถัดไป',
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow(String key, String label) {
    final hours = _businessHours[key]!;
    final isClosed = hours['closed'] as bool;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isClosed ? Colors.grey[50] : mainColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: isClosed
              ? Colors.grey[200]!
              : mainColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76.w,
            child: Text(
              label,
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: isClosed ? Colors.grey[400] : Colors.black87,
              ),
            ),
          ),
          Switch(
            value: !isClosed,
            activeThumbColor: mainColor,
            activeTrackColor: mainColor.withValues(alpha: 0.5),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (val) =>
                setState(() => _businessHours[key]!['closed'] = !val),
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
        ],
      ),
    );
  }

  Widget _timePill(String dayKey, bool isOpen) {
    final timeStr =
        _businessHours[dayKey]![isOpen ? 'open' : 'close'] as String;
    return GestureDetector(
      onTap: () => _pickTime(dayKey, isOpen),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: mainColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: mainColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          timeStr,
          style: styles(
            fontSize: 13.sp,
            color: mainColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─── Step 4: Address + Location ───────────────────────────────────────────

  Widget _buildStep4() {
    return SingleChildScrollView(
      key: const ValueKey('step4'),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ที่อยู่ร้าน'),
          TextFormField(
            controller: _addressController,
            style: styles(fontSize: 13.sp),
            decoration: _inputDec('เลขที่ / หมู่บ้าน / ซอย / ถนน *'),
          ),
          SizedBox(height: 12.h),
          ThaiAddressForm(
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
                      if (_locatingMap) return;
                      if (_lat != null && _lng != null) {
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
          _navRow(
            onBack: () => setState(() => _currentStep = 2),
            onNext: () {
              if (_validateStep4()) setState(() => _currentStep = 4);
            },
            nextLabel: 'ถัดไป',
          ),
        ],
      ),
    );
  }

  // ─── Step 5: Service Settings ─────────────────────────────────────────────

  Widget _buildStep5() {
    final needsHome = _serviceLocation == 'home' || _serviceLocation == 'both';

    return SingleChildScrollView(
      key: const ValueKey('step5'),
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
          _navRow(
            onBack: () => setState(() => _currentStep = 3),
            onNext: _save,
            nextLabel: 'บันทึก',
          ),
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

  // ─── Helpers ──────────────────────────────────────────────────────────────

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

  Widget _nextButton({required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50.h,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: mainColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          'ถัดไป',
          style: styles(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _navRow({
    required VoidCallback onBack,
    required VoidCallback onNext,
    required String nextLabel,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: mainColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              minimumSize: Size(0, 50.h),
            ),
            onPressed: onBack,
            child: Text(
              'ย้อนกลับ',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: mainColor,
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mainColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              minimumSize: Size(0, 50.h),
            ),
            onPressed: onNext,
            child: Text(
              nextLabel,
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
