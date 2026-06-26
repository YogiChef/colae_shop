// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_address_picker/thai_address_picker.dart';

class HotelInfoTab extends StatefulWidget {
  const HotelInfoTab({super.key});

  @override
  State<HotelInfoTab> createState() => _HotelInfoTabState();
}

class _HotelInfoTabState extends State<HotelInfoTab> {
  final _formKey = GlobalKey<FormState>();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  // Controllers
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _provinceController = TextEditingController();
  final _districtController = TextEditingController();
  final _addressController = TextEditingController();
  final _subDistrictController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _customAmenityController = TextEditingController();
  final _customServiceController = TextEditingController();

  // State
  String? _mainType;
  List<String> _mainTypeOptions = [];
  List<String> _amenitiesOptions = [];
  List<String> _servicesOptions = [];

  final Set<String> _selectedAmenities = {};
  final Set<String> _selectedServices = {};
  final List<String> _customAmenities = [];
  final List<String> _customServices = [];

  GeoPoint? _location;
  final List<String> _existingImages = [];
  final List<File> _newImages = [];
  bool _loading = true;
  bool _saving = false;
  ThaiAddress? _selectedAddress;
  Province? _initialProvince;
  District? _initialDistrict;
  SubDistrict? _initialSubDistrict;

  @override
  void initState() {
    super.initState();
    _loadLists();
    _loadHotel();
  }

  Future<void> _loadLists() async {
    try {
      final results = await Future.wait([
        _firestore.collection('hotel_lists').doc('main_types').get(),
        _firestore.collection('hotel_lists').doc('amenities').get(),
        _firestore.collection('hotel_lists').doc('services').get(),
      ]);
      if (mounted) {
        setState(() {
          _mainTypeOptions = List<String>.from(
            results[0].data()?['items'] ?? [],
          );
          _amenitiesOptions = List<String>.from(
            results[1].data()?['items'] ?? [],
          );
          _servicesOptions = List<String>.from(
            results[2].data()?['items'] ?? [],
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading lists: $e');
    }
  }

  Future<void> _loadHotel() async {
    try {
      final doc = await _firestore.collection('hotels').doc(_uid).get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _nameController.text = d['name'] ?? '';
          _mainType = d['mainType'];
          _descController.text = d['description'] ?? '';
          _addressController.text = d['address'] ?? '';
          _provinceController.text =
              _selectedAddress?.provinceTh ?? d['province'] ?? '';
          _districtController.text =
              _selectedAddress?.districtTh ?? d['district'] ?? '';
          _subDistrictController.text =
              _selectedAddress?.subDistrictTh ?? d['subDistrict'] ?? '';
          _zipCodeController.text =
              _selectedAddress?.zipCode ?? d['zipCode'] ?? '';
          _location = d['location'] as GeoPoint?;
          _existingImages.addAll(List<String>.from(d['images'] ?? []));

          final allAmenities = List<String>.from(d['amenities'] ?? []);
          for (final a in allAmenities) {
            if (a.startsWith('custom:')) {
              _customAmenities.add(a.substring(7));
            } else {
              _selectedAmenities.add(a);
            }
          }
          final allServices = List<String>.from(d['services'] ?? []);
          for (final s in allServices) {
            if (s.startsWith('custom:')) {
              _customServices.add(s.substring(7));
            } else {
              _selectedServices.add(s);
            }
          }
        });
      }
      // Lookup Province/District/SubDistrict objects for ThaiAddressForm initial values
      if (doc.exists) {
        final d = doc.data()!;
        try {
          final repo = ThaiAddressRepository();
          await repo.initialize();

          final provinceName = d['province'] as String? ?? '';
          final districtName = d['district'] as String? ?? '';
          final subDistrictName = d['subDistrict'] as String? ?? '';

          if (provinceName.isNotEmpty) {
            _initialProvince = repo.provinces.firstWhereOrNull(
              (p) => p.nameTh == provinceName,
            );
            if (_initialProvince != null && districtName.isNotEmpty) {
              _initialDistrict = repo.districts.firstWhereOrNull(
                (x) =>
                    x.nameTh == districtName &&
                    x.provinceId == _initialProvince!.id,
              );
              if (_initialDistrict != null && subDistrictName.isNotEmpty) {
                _initialSubDistrict = repo.subDistricts.firstWhereOrNull(
                  (x) =>
                      x.nameTh == subDistrictName &&
                      x.districtId == _initialDistrict!.id,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Error loading address objects: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading hotel: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
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
      setState(() => _location = GeoPoint(pos.latitude, pos.longitude));
      EasyLoading.showSuccess('ได้ตำแหน่งแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _pickImages() async {
    final total = _existingImages.length + _newImages.length;
    if (total >= 25) {
      Fluttertoast.showToast(msg: 'ใส่รูปได้สูงสุด 25 รูป');
      return;
    }
    final picked = await _picker.pickMultiImage(limit: 25 - total);
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.map((x) => File(x.path)));
    });
  }

  void _removeExistingImage(int index) =>
      setState(() => _existingImages.removeAt(index));

  void _removeNewImage(int index) => setState(() => _newImages.removeAt(index));

  void _addCustomAmenity() {
    final text = _customAmenityController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _customAmenities.add(text);
      _customAmenityController.clear();
    });
  }

  void _addCustomService() {
    final text = _customServiceController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _customServices.add(text);
      _customServiceController.clear();
    });
  }

  Future<List<String>> _uploadNewImages() async {
    final urls = <String>[];
    for (final file in _newImages) {
      final ref = _storage.ref(
        'hotel_images/$_uid/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}',
      );
      await ref.putFile(file);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_mainType == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกประเภทที่พัก');
      return;
    }
    if (_location == null) {
      Fluttertoast.showToast(msg: 'กรุณาระบุตำแหน่ง GPS');
      return;
    }
    if (_existingImages.isEmpty && _newImages.isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณาเพิ่มรูปอย่างน้อย 1 รูป');
      return;
    }

    setState(() => _saving = true);
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      final uploadedUrls = await _uploadNewImages();
      final allImages = [..._existingImages, ...uploadedUrls];

      final amenitiesData = [
        ..._selectedAmenities,
        ..._customAmenities.map((c) => 'custom:$c'),
      ];
      final servicesData = [
        ..._selectedServices,
        ..._customServices.map((c) => 'custom:$c'),
      ];

      await _firestore.collection('hotels').doc(_uid).set({
        'ownerId': _uid,
        'name': _nameController.text.trim(),
        'mainType': _mainType,
        'description': _descController.text.trim(),
        'province': _provinceController.text.trim(),
        'district': _districtController.text.trim(),
        'address': _addressController.text.trim(),
        'subDistrict': _subDistrictController.text.trim(),
        'zipCode': _zipCodeController.text.trim(),
        'location': _location,
        'amenities': amenitiesData,
        'services': servicesData,
        'images': allImages,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _newImages.clear();
      _existingImages
        ..clear()
        ..addAll(allImages);

      EasyLoading.showSuccess('บันทึกสำเร็จ');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    _subDistrictController.dispose();
    _addressController.dispose();
    _zipCodeController.dispose();
    _customAmenityController.dispose();
    _customServiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'ข้อมูลที่พัก',
            style: styles(color: Colors.white, fontSize: 18.sp),
          ),
          backgroundColor: mainColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white, size: 24),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.arrow_forward_ios_sharp,
                color: Colors.white,
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('vendor_last_mode');
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LandingPage()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
        body: Center(child: CircularProgressIndicator(color: mainColor)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ข้อมูลที่พัก',
          style: styles(color: Colors.white, fontSize: 18.sp),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.arrow_forward_ios_sharp,
              color: Colors.white,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('vendor_last_mode');
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('ข้อมูลพื้นฐาน'),
              TextFormField(
                controller: _nameController,
                style: styles(fontSize: 13.spMax, fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  labelText: 'ชื่อที่พัก *',
                  labelStyle: styles(
                    fontSize: 13.spMax,
                    fontWeight: FontWeight.w400,
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'กรุณากรอกชื่อที่พัก' : null,
              ),
              SizedBox(height: 12.w),
              DropdownButtonFormField<String>(
                initialValue: _mainTypeOptions.contains(_mainType)
                    ? _mainType
                    : null,
                decoration: InputDecoration(
                  labelText: 'ประเภทที่พัก *',
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                items: _mainTypeOptions.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(
                      t,
                      style: styles(
                        fontSize: 12.spMax,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _mainType = v),
                hint: _mainTypeOptions.isEmpty
                    ? const Text('กำลังโหลด...')
                    : const Text('เลือกประเภทที่พัก'),
              ),
              SizedBox(height: 12.w),
              TextFormField(
                controller: _descController,
                maxLines: 4,
                maxLength: 500,
                style: styles(fontSize: 13.spMax, fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  labelText: 'รายละเอียด',
                  labelStyle: styles(
                    fontSize: 13.spMax,
                    fontWeight: FontWeight.w400,
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.w),
              _sectionTitle('ที่อยู่'),
              TextFormField(
                controller: _addressController,
                maxLength: 224,
                style: styles(fontSize: 13.spMax, fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  labelText: 'เลขที่อยู่ / หมู่บ้าน / ซอย / ถนน',
                  labelStyle: styles(
                    fontSize: 13.spMax,
                    fontWeight: FontWeight.w400,
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.w),
              ThaiAddressForm(
                initialProvince: _initialProvince,
                initialDistrict: _initialDistrict,
                initialSubDistrict: _initialSubDistrict,
                textStyle: styles(
                  fontSize: 13.sp,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                provinceDecoration: InputDecoration(
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                districtDecoration: InputDecoration(
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                subDistrictDecoration: InputDecoration(
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                zipCodeDecoration: InputDecoration(
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellow.shade900,
                      width: 2,
                    ),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                onChanged: (address) {
                  if ((address.provinceTh ?? '').isEmpty) return;
                  if ((address.districtTh ?? '').isEmpty) return;
                  if ((address.subDistrictTh ?? '').isEmpty) return;
                  if ((address.zipCode ?? '').isEmpty) return;

                  setState(() {
                    _selectedAddress = address;
                    _provinceController.text = address.provinceTh ?? '';
                    _districtController.text = address.districtTh ?? '';
                    _subDistrictController.text = address.subDistrictTh ?? '';
                    _zipCodeController.text = address.zipCode ?? '';
                  });
                },
                useThai: true,
              ),
              SizedBox(height: 12.w),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _location == null
                          ? 'ยังไม่มีตำแหน่ง GPS'
                          : '📍 ${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}',
                      style: styles(
                        fontSize: 12.sp,
                        color: _location == null
                            ? Colors.red.shade400
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.my_location, size: 20.sp),
                    label: Text(
                      'ตำแหน่งปัจจุบัน',
                      style: styles(
                        fontSize: 14.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _getCurrentLocation,
                  ),
                ],
              ),

              SizedBox(height: 20.w),
              _sectionTitle(
                'รูปภาพ (${_existingImages.length + _newImages.length}/25)',
              ),
              _buildImageGrid(),

              SizedBox(height: 20.w),
              _sectionTitle('สิ่งอำนวยความสะดวก'),
              _buildCheckList(
                options: _amenitiesOptions,
                selected: _selectedAmenities,
                customs: _customAmenities,
                customController: _customAmenityController,
                onAddCustom: _addCustomAmenity,
                onRemoveCustom: (i) =>
                    setState(() => _customAmenities.removeAt(i)),
              ),

              SizedBox(height: 20.w),
              _sectionTitle('บริการ'),
              _buildCheckList(
                options: _servicesOptions,
                selected: _selectedServices,
                customs: _customServices,
                customController: _customServiceController,
                onAddCustom: _addCustomService,
                onRemoveCustom: (i) =>
                    setState(() => _customServices.removeAt(i)),
              ),

              SizedBox(height: 30.w),
              SizedBox(
                width: double.infinity,
                height: 50.w,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    _saving ? 'กำลังบันทึก...' : 'บันทึก',
                    style: styles(
                      fontSize: 16.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                ),
              ),
              SizedBox(height: 30.w),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.w, top: 4.w),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 18.w,
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
              fontWeight: FontWeight.w500,
              color: Colors.deepPurple[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    final allItems = <Widget>[];

    for (int i = 0; i < _existingImages.length; i++) {
      allItems.add(
        _imageItem(
          image: CachedNetworkImageProvider(_existingImages[i]),
          onRemove: () => _removeExistingImage(i),
        ),
      );
    }
    for (int i = 0; i < _newImages.length; i++) {
      allItems.add(
        _imageItem(
          image: FileImage(_newImages[i]),
          onRemove: () => _removeNewImage(i),
        ),
      );
    }

    final total = _existingImages.length + _newImages.length;
    if (total < 25) {
      allItems.add(
        InkWell(
          onTap: _pickImages,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: 28.sp, color: Colors.grey),
                SizedBox(height: 4.h),
                Text(
                  'เพิ่มรูป',
                  style: styles(fontSize: 11.sp, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: allItems,
    );
  }

  Widget _imageItem({
    required ImageProvider image,
    required VoidCallback onRemove,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(image: image, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckList({
    required List<String> options,
    required Set<String> selected,
    required List<String> customs,
    required TextEditingController customController,
    required VoidCallback onAddCustom,
    required void Function(int) onRemoveCustom,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (options.isEmpty)
          Text(
            'กำลังโหลดรายการ...',
            style: styles(fontSize: 12.sp, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return FilterChip(
                label: Text(opt, style: styles(fontSize: 12.sp)),
                selected: isSelected,
                onSelected: (v) => setState(() {
                  if (v) {
                    selected.add(opt);
                  } else {
                    selected.remove(opt);
                  }
                }),
                selectedColor: mainColor.withOpacity(0.2),
                checkmarkColor: mainColor,
              );
            }).toList(),
          ),
        if (customs.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(customs.length, (i) {
              return Chip(
                label: Text(customs[i], style: styles(fontSize: 12.sp)),
                backgroundColor: Colors.blue.shade50,
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => onRemoveCustom(i),
              );
            }),
          ),
        ],
        SizedBox(height: 8.w),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: customController,
                decoration: InputDecoration(
                  hintText: 'เพิ่มรายการอื่น...',
                  hintStyle: styles(fontSize: 12.sp, color: Colors.grey),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                ),
                onSubmitted: (_) => onAddCustom(),
              ),
            ),
            SizedBox(width: 8.w),
            IconButton(
              icon: Icon(Icons.add_circle, color: mainColor, size: 32.sp),
              onPressed: onAddCustom,
            ),
          ],
        ),
      ],
    );
  }
}
