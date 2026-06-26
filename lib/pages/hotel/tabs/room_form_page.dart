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
import 'package:colae_shop/pages/hotel/tabs/price_calendar_page.dart';
import 'package:colae_shop/services/sevice.dart';

class RoomFormPage extends StatefulWidget {
  final String? roomId; // null = เพิ่มใหม่
  const RoomFormPage({super.key, this.roomId});

  @override
  State<RoomFormPage> createState() => _RoomFormPageState();
}

class _RoomFormPageState extends State<RoomFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  bool get _isEditing => widget.roomId != null;

  // Controllers
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _sizeController = TextEditingController();
  final _maxGuestsController = TextEditingController();
  final _totalRoomsController = TextEditingController();
  final _basePriceController = TextEditingController();
  final _depositController = TextEditingController();
  final _customAmenityController = TextEditingController();

  // State
  String? _roomType;
  List<String> _roomTypeOptions = [];
  List<String> _amenitiesOptions = [];
  final Set<String> _selectedAmenities = {};
  final List<String> _customAmenities = [];

  final List<String> _existingImages = [];
  final List<File> _newImages = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLists().then((_) {
      if (_isEditing) {
        _loadRoom();
      } else {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _loadLists() async {
    try {
      final results = await Future.wait([
        _firestore.collection('hotel_lists').doc('room_types').get(),
        _firestore.collection('hotel_lists').doc('amenities').get(),
      ]);
      if (mounted) {
        setState(() {
          _roomTypeOptions =
              List<String>.from(results[0].data()?['items'] ?? []);
          _amenitiesOptions =
              List<String>.from(results[1].data()?['items'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error loading lists: $e');
    }
  }

  Future<void> _loadRoom() async {
    try {
      final doc = await _firestore
          .collection('hotels')
          .doc(_uid)
          .collection('rooms')
          .doc(widget.roomId)
          .get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _roomType = d['roomType'] as String?;
          _nameController.text = d['name'] as String? ?? '';
          _descController.text = d['description'] as String? ?? '';
          _sizeController.text = '${d['size'] ?? ''}';
          _maxGuestsController.text = '${d['maxGuests'] ?? ''}';
          _totalRoomsController.text = '${d['totalRooms'] ?? ''}';
          _basePriceController.text = '${d['basePrice'] ?? ''}';
          _depositController.text = '${d['depositPercentage'] ?? ''}';
          _existingImages.addAll(List<String>.from(d['images'] ?? []));

          final allAmenities = List<String>.from(d['amenities'] ?? []);
          for (final a in allAmenities) {
            if (a.startsWith('custom:')) {
              _customAmenities.add(a.substring(7));
            } else {
              _selectedAmenities.add(a);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading room: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    final total = _existingImages.length + _newImages.length;
    if (total >= 20) {
      Fluttertoast.showToast(msg: 'ใส่รูปได้สูงสุด 20 รูป');
      return;
    }
    final picked = await _picker.pickMultiImage(limit: 20 - total);
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.map((x) => File(x.path)));
    });
  }

  void _addCustomAmenity() {
    final text = _customAmenityController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _customAmenities.add(text);
      _customAmenityController.clear();
    });
  }

  Future<List<String>> _uploadNewImages() async {
    final urls = <String>[];
    final folder =
        widget.roomId ?? 'new_${DateTime.now().millisecondsSinceEpoch}';
    for (final file in _newImages) {
      final ref = _storage.ref(
        'hotel_room_images/$_uid/$folder/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}',
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
      final uploadedUrls = await _uploadNewImages();
      final allImages = [..._existingImages, ...uploadedUrls];

      final amenitiesData = [
        ..._selectedAmenities,
        ..._customAmenities.map((c) => 'custom:$c'),
      ];

      final data = <String, dynamic>{
        'roomType': _roomType,
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'size': num.tryParse(_sizeController.text.trim()),
        'maxGuests': int.tryParse(_maxGuestsController.text.trim()),
        'totalRooms': int.tryParse(_totalRoomsController.text.trim()),
        'basePrice': num.tryParse(_basePriceController.text.trim()),
        'depositPercentage': num.tryParse(_depositController.text.trim()),
        'amenities': amenitiesData,
        'images': allImages,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final roomsCol = _firestore
          .collection('hotels')
          .doc(_uid)
          .collection('rooms');

      if (_isEditing) {
        await roomsCol.doc(widget.roomId).set(data, SetOptions(merge: true));
      } else {
        await roomsCol.add(data);
      }

      _newImages.clear();
      _existingImages
        ..clear()
        ..addAll(allImages);

      EasyLoading.showSuccess('บันทึกสำเร็จ');
      if (!_isEditing && mounted) {
        Navigator.pop(context);
      }
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
    _depositController.dispose();
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
        actions: _isEditing
            ? [
                Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: TextButton.icon(
                    icon: const Icon(
                      Icons.calendar_month,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      'ราคาพิเศษ',
                      style: styles(color: Colors.white, fontSize: 13.sp),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PriceCalendarPage(
                          roomId: widget.roomId!,
                          roomName: _nameController.text.isNotEmpty
                              ? _nameController.text
                              : 'ห้องพัก',
                        ),
                      ),
                    ),
                  ),
                ),
              ]
            : null,
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
                value:
                    _roomTypeOptions.contains(_roomType) ? _roomType : null,
                decoration: const InputDecoration(
                  labelText: 'ประเภทห้องพัก *',
                  border: OutlineInputBorder(),
                ),
                items: _roomTypeOptions.map((t) {
                  return DropdownMenuItem(value: t, child: Text(t));
                }).toList(),
                onChanged: (v) => setState(() => _roomType = v),
                hint: _roomTypeOptions.isEmpty
                    ? const Text('กำลังโหลด...')
                    : const Text('เลือกประเภทห้อง'),
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _basePriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                        if (num.tryParse(v!.trim()) == null) {
                          return 'ตัวเลขเท่านั้น';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: TextFormField(
                      controller: _depositController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'มัดจำ (%)',
                        border: OutlineInputBorder(),
                        suffixText: '%',
                        hintText: '30',
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20.h),
              _sectionTitle(
                'รูปภาพ (${_existingImages.length + _newImages.length}/20)',
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
    final total = _existingImages.length + _newImages.length;
    if (total < 20) {
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
                label:
                    Text(_customAmenities[i], style: styles(fontSize: 12.sp)),
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
