// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:colae_shop/services/sevice.dart';

class RoomEditPage extends StatefulWidget {
  final String? roomId;
  final Map<String, dynamic>? initialData;
  const RoomEditPage({super.key, this.roomId, this.initialData});

  @override
  State<RoomEditPage> createState() => _RoomEditPageState();
}

class _RoomEditPageState extends State<RoomEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _picker = ImagePicker();

  bool get _isEditing => widget.roomId != null;

  // Controllers
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _sizeController = TextEditingController();
  final _maxGuestsController = TextEditingController();
  final _totalRoomsController = TextEditingController();
  final _basePriceController = TextEditingController();
  final _customAmenityController = TextEditingController();

  // State
  String? _roomType;
  int? _depositPercentage;
  List<String> _roomTypeOptions = [];
  List<String> _amenitiesOptions = [];
  final Set<String> _selectedAmenities = {};
  final List<String> _customAmenities = [];

  final List<String> _existingImages = [];
  final List<File> _newImages = [];
  bool _loading = true;
  bool _saving = false;

  static const _depositOptions = [10, 20, 30, 50];

  @override
  void initState() {
    super.initState();
    _prefillData();
    _loadLists();
  }

  void _prefillData() {
    final d = widget.initialData;
    if (d == null) return;
    _nameController.text = d['name'] as String? ?? '';
    _roomType = d['roomType'] as String?;
    _descController.text = d['description'] as String? ?? '';
    _sizeController.text = '${d['size'] ?? ''}';
    _maxGuestsController.text = '${d['maxGuests'] ?? ''}';
    _totalRoomsController.text = '${d['totalRooms'] ?? ''}';
    _basePriceController.text = '${d['basePrice'] ?? ''}';

    final dep = d['depositPercentage'];
    if (dep != null) _depositPercentage = (dep as num).toInt();

    _existingImages.addAll(List<String>.from(d['images'] ?? []));

    for (final a in List<String>.from(d['amenities'] ?? [])) {
      if (a.startsWith('custom:')) {
        _customAmenities.add(a.substring(7));
      } else {
        _selectedAmenities.add(a);
      }
    }
  }

  Future<void> _loadLists() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('hotel_lists')
            .doc('room_types')
            .get(),
        FirebaseFirestore.instance
            .collection('hotel_lists')
            .doc('amenities')
            .get(),
      ]);
      if (mounted) {
        setState(() {
          _roomTypeOptions =
              List<String>.from(results[0].data()?['items'] ?? []);
          _amenitiesOptions =
              List<String>.from(results[1].data()?['items'] ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading lists: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    final total = _existingImages.length + _newImages.length;
    if (total >= 10) {
      Fluttertoast.showToast(msg: 'ใส่รูปได้สูงสุด 10 รูป');
      return;
    }
    final picked = await _picker.pickMultiImage(limit: 10 - total);
    if (picked.isEmpty) return;
    setState(() => _newImages.addAll(picked.map((x) => File(x.path))));
  }

  void _addCustomAmenity() {
    final text = _customAmenityController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _customAmenities.add(text);
      _customAmenityController.clear();
    });
  }

  Future<List<String>> _uploadNewImages(String roomId) async {
    final urls = <String>[];
    for (final file in _newImages) {
      final ref = FirebaseStorage.instance.ref(
        'hotel_images/$_uid/rooms/$roomId/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}',
      );
      await ref.putFile(file);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_roomType == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกประเภทห้องพัก');
      return;
    }
    if (_existingImages.isEmpty && _newImages.isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณาเพิ่มรูปอย่างน้อย 1 รูป');
      return;
    }

    setState(() => _saving = true);
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      final roomsCol = FirebaseFirestore.instance
          .collection('hotels')
          .doc(_uid)
          .collection('rooms');

      // pre-generate id เพื่อใช้เป็น path upload รูป
      final roomId = widget.roomId ?? roomsCol.doc().id;
      final uploadedUrls = await _uploadNewImages(roomId);
      final allImages = [..._existingImages, ...uploadedUrls];

      final amenitiesData = [
        ..._selectedAmenities,
        ..._customAmenities.map((c) => 'custom:$c'),
      ];

      await roomsCol.doc(roomId).set(
        {
          'roomType': _roomType,
          'name': _nameController.text.trim(),
          'description': _descController.text.trim(),
          'size': num.tryParse(_sizeController.text.trim()),
          'maxGuests': int.tryParse(_maxGuestsController.text.trim()),
          'totalRooms': int.tryParse(_totalRoomsController.text.trim()),
          'basePrice': num.tryParse(_basePriceController.text.trim()),
          'depositPercentage': _depositPercentage,
          'amenities': amenitiesData,
          'images': allImages,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      _newImages.clear();
      _existingImages
        ..clear()
        ..addAll(allImages);

      EasyLoading.showSuccess('บันทึกสำเร็จ');
      if (mounted) Navigator.pop(context);
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
    _sizeController.dispose();
    _maxGuestsController.dispose();
    _totalRoomsController.dispose();
    _basePriceController.dispose();
    _customAmenityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing ? 'แก้ไขห้องพัก' : 'เพิ่มห้องพัก',
            style: styles(color: Colors.white, fontSize: 18.sp),
          ),
          backgroundColor: mainColor,
          foregroundColor: Colors.white,
        ),
        body: Center(child: CircularProgressIndicator(color: mainColor)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'แก้ไขห้องพัก' : 'เพิ่มห้องพัก',
          style: styles(color: Colors.white, fontSize: 18.sp),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('ประเภทและชื่อ'),
              DropdownButtonFormField<String>(
                value: _roomTypeOptions.contains(_roomType) ? _roomType : null,
                decoration: const InputDecoration(
                  labelText: 'ประเภทห้องพัก *',
                  border: OutlineInputBorder(),
                ),
                items: _roomTypeOptions
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _roomType = v),
                hint: const Text('เลือกประเภทห้อง'),
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อห้อง *',
                  hintText: 'เช่น Standard Sea View',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'กรุณากรอกชื่อห้อง' : null,
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                maxLength: 400,
                decoration: const InputDecoration(
                  labelText: 'รายละเอียด',
                  border: OutlineInputBorder(),
                ),
              ),

              SizedBox(height: 20.h),
              _sectionTitle('ขนาดและความจุ'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sizeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'ขนาด (ตร.ม.)',
                        border: OutlineInputBorder(),
                        suffixText: 'ตร.ม.',
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: TextFormField(
                      controller: _maxGuestsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'ผู้เข้าพักสูงสุด *',
                        border: OutlineInputBorder(),
                        suffixText: 'คน',
                      ),
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'กรุณากรอก' : null,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _totalRoomsController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'จำนวนห้องทั้งหมด *',
                  border: OutlineInputBorder(),
                  suffixText: 'ห้อง',
                ),
                validator: (v) => (v?.trim().isEmpty ?? true)
                    ? 'กรุณากรอกจำนวนห้อง'
                    : null,
              ),

              SizedBox(height: 20.h),
              _sectionTitle('ราคา'),
              TextFormField(
                controller: _basePriceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+\.?\d{0,2}'),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'ราคาปกติ/คืน *',
                  border: OutlineInputBorder(),
                  prefixText: '฿ ',
                ),
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'กรุณากรอกราคา';
                  if (num.tryParse(v!.trim()) == null) return 'ตัวเลขเท่านั้น';
                  return null;
                },
              ),
              SizedBox(height: 12.h),
              DropdownButtonFormField<int>(
                value: _depositOptions.contains(_depositPercentage)
                    ? _depositPercentage
                    : null,
                decoration: const InputDecoration(
                  labelText: 'มัดจำ (%)',
                  border: OutlineInputBorder(),
                ),
                items: _depositOptions
                    .map((p) =>
                        DropdownMenuItem(value: p, child: Text('$p%')))
                    .toList(),
                onChanged: (v) => setState(() => _depositPercentage = v),
                hint: const Text('เลือก %'),
              ),

              SizedBox(height: 20.h),
              _sectionTitle(
                'รูปภาพ (${_existingImages.length + _newImages.length}/10)',
              ),
              _buildImageGrid(),

              SizedBox(height: 20.h),
              _sectionTitle('สิ่งอำนวยความสะดวก'),
              _buildAmenitiesSection(),

              SizedBox(height: 30.h),
              SizedBox(
                width: double.infinity,
                height: 50.h,
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
              SizedBox(height: 30.h),
            ],
          ),
        ),
      ),
    );
  }

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
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    final allItems = <Widget>[];
    for (int i = 0; i < _existingImages.length; i++) {
      allItems.add(_imageItem(
        image: CachedNetworkImageProvider(_existingImages[i]),
        onRemove: () => setState(() => _existingImages.removeAt(i)),
      ));
    }
    for (int i = 0; i < _newImages.length; i++) {
      allItems.add(_imageItem(
        image: FileImage(_newImages[i]),
        onRemove: () => setState(() => _newImages.removeAt(i)),
      ));
    }
    if (_existingImages.length + _newImages.length < 10) {
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
                Text('เพิ่มรูป',
                    style: styles(fontSize: 11.sp, color: Colors.grey)),
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

  Widget _buildAmenitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_amenitiesOptions.isEmpty)
          Text(
            'กำลังโหลดรายการ...',
            style: styles(fontSize: 12.sp, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _amenitiesOptions.map((opt) {
              final isSelected = _selectedAmenities.contains(opt);
              return FilterChip(
                label: Text(opt, style: styles(fontSize: 12.sp)),
                selected: isSelected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _selectedAmenities.add(opt);
                  } else {
                    _selectedAmenities.remove(opt);
                  }
                }),
                selectedColor: mainColor.withOpacity(0.2),
                checkmarkColor: mainColor,
              );
            }).toList(),
          ),
        if (_customAmenities.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(_customAmenities.length, (i) {
              return Chip(
                label: Text(_customAmenities[i],
                    style: styles(fontSize: 12.sp)),
                backgroundColor: Colors.blue.shade50,
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () =>
                    setState(() => _customAmenities.removeAt(i)),
              );
            }),
          ),
        ],
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customAmenityController,
                decoration: InputDecoration(
                  hintText: 'เพิ่มรายการอื่น...',
                  hintStyle:
                      styles(fontSize: 12.sp, color: Colors.grey),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 10.h,
                  ),
                ),
                onSubmitted: (_) => _addCustomAmenity(),
              ),
            ),
            SizedBox(width: 8.w),
            IconButton(
              icon: Icon(Icons.add_circle, color: mainColor, size: 32.sp),
              onPressed: _addCustomAmenity,
            ),
          ],
        ),
      ],
    );
  }
}
