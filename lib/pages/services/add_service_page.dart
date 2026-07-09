// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:colae_shop/utils/service_types_loader.dart';
import 'package:uuid/uuid.dart';

class AddServicePage extends StatefulWidget {
  final String shopCategoryId;
  final String shopId;
  // null = add mode, non-null = edit mode
  final DocumentSnapshot<Map<String, dynamic>>? existingService;

  const AddServicePage({
    super.key,
    required this.shopCategoryId,
    required this.shopId,
    this.existingService,
  });

  @override
  State<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends State<AddServicePage> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _customDurationController = TextEditingController();

  List<Map<String, dynamic>> _types = [];
  Map<String, dynamic>? _selectedType;
  String? _selectedTypeId;
  bool _loadingTypes = true;

  int? _selectedDuration;
  bool _customDuration = false;

  // Images
  List<String> _existingImages = []; // URLs from Firestore (edit mode)
  final List<File> _selectedImages = []; // new local files

  String? _initialTypeId;
  int? _initialDuration;

  bool get _isEdit => widget.existingService != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final data = widget.existingService!.data()!;
      _nameController.text = data['name'] as String? ?? '';
      _priceController.text = (data['price'] as num?)?.toStringAsFixed(0) ?? '';
      _descController.text = data['description'] as String? ?? '';
      _existingImages = List<String>.from(data['images'] as List? ?? []);
      _initialTypeId = data['typeId'] as String?;
      _initialDuration = (data['duration'] as num?)?.toInt();
    }
    _loadTypes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _customDurationController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      // Single-field queries only — avoids composite index requirement.
      // active filter + order sort are done in Dart instead.
      final results = await Future.wait([
        _db
            .collection('service_types')
            .where('categoryId', isEqualTo: widget.shopCategoryId)
            .get(),
        _db
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('custom_types')
            .where('categoryId', isEqualTo: widget.shopCategoryId)
            .get(),
      ]);

      final globalTypes = results[0].docs
          .where((d) => d.data()['active'] != false)
          .map((d) => <String, dynamic>{'id': d.id, ...d.data(), 'isCustom': false})
          .toList()
        ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0));

      final customTypes = results[1].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data(), 'isCustom': true})
          .toList()
        ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0)
            .compareTo((b['order'] as num?)?.toInt() ?? 0));

      final types = [...globalTypes, ...customTypes];

      if (!mounted) return;
      setState(() {
        _types = types;
        _loadingTypes = false;
      });

      if (_initialTypeId != null) {
        final found = _types.where((t) => t['id'] == _initialTypeId).toList();
        if (found.isNotEmpty && mounted) {
          final t = found.first;
          final opts =
              (t['durationOptions'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              [];
          setState(() {
            _selectedType = t;
            _selectedTypeId = t['id'] as String;
            if (_initialDuration != null) {
              if (opts.contains(_initialDuration)) {
                _selectedDuration = _initialDuration;
              } else {
                _customDuration = true;
                _customDurationController.text = _initialDuration.toString();
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[AddService] load types error: $e');
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  void _onTypeChanged(String? typeId) {
    final found = _types.where((t) => t['id'] == typeId).toList();
    if (found.isEmpty) return;
    final t = found.first;
    setState(() {
      _selectedType = t;
      _selectedTypeId = typeId;
      _selectedDuration = null;
      _customDuration = false;
      _customDurationController.clear();
      if (_nameController.text.isEmpty) {
        _nameController.text = t['name'] as String? ?? '';
      }
      if (!_isEdit) _priceController.clear();
    });
  }

  static const _defaultDurations = [30, 60, 90, 120];

  List<int> get _durationOptions {
    final raw = _selectedType?['durationOptions'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => (e as num).toInt()).toList();
    }
    return _defaultDurations;
  }

  int? get _effectiveDuration {
    if (_customDuration) {
      return int.tryParse(_customDurationController.text.trim());
    }
    return _selectedDuration;
  }

  int get _totalImages => _existingImages.length + _selectedImages.length;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;
    setState(() => _selectedImages.add(File(picked.path)));
  }

  void _showImageSourceDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'เลือกรูปภาพ',
          style: styles(
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
            color: context.purpleColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: mainColor),
              title: Text('ถ่ายรูป', style: styles(fontSize: 14.sp)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: mainColor),
              title: Text('แกลเลอรี', style: styles(fontSize: 14.sp)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeExistingImage(String url) async {
    setState(() => _existingImages.remove(url));
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == null) {
      Fluttertoast.showToast(msg: 'กรุณาเลือกประเภทบริการ');
      return;
    }

    final duration = _effectiveDuration;
    if (duration == null || duration <= 0) {
      Fluttertoast.showToast(msg: 'กรุณาระบุระยะเวลาให้บริการ');
      return;
    }

    final price = int.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      Fluttertoast.showToast(msg: 'กรุณาระบุราคาที่ถูกต้อง');
      return;
    }

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      if (_isEdit) {
        final serviceId = widget.existingService!.id;

        // Upload new images
        List<String> newUrls = [];
        if (_selectedImages.isNotEmpty) {
          EasyLoading.show(status: 'กำลังอัปโหลดรูป...');
          for (final file in _selectedImages) {
            final uuid = const Uuid().v4();
            final ref = _storage.ref(
              'service_images/$_uid/$serviceId/$uuid.jpg',
            );
            await ref.putFile(
              file,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            newUrls.add(await ref.getDownloadURL());
          }
        }

        await _db
            .collection('service_shops')
            .doc(_uid)
            .collection('services')
            .doc(serviceId)
            .update({
              'name': _nameController.text.trim(),
              'duration': duration,
              'price': price,
              'description': _descController.text.trim(),
              'images': [..._existingImages, ...newUrls],
              'providerCount': 1,
              'updatedAt': FieldValue.serverTimestamp(),
            });

        EasyLoading.dismiss();
        Fluttertoast.showToast(msg: 'อัปเดตบริการแล้ว');
      } else {
        final docRef = await _db
            .collection('service_shops')
            .doc(_uid)
            .collection('services')
            .add({
              'typeId': _selectedType!['id'] as String,
              'typeName': _selectedType!['name'] as String? ?? '',
              'name': _nameController.text.trim(),
              'duration': duration,
              'price': price,
              'description': _descController.text.trim(),
              'available': true,
              'providerCount': 1,
              'images': [],
              'createdAt': FieldValue.serverTimestamp(),
            });

        if (_selectedImages.isNotEmpty) {
          EasyLoading.show(status: 'กำลังอัปโหลดรูป...');
          final serviceId = docRef.id;
          final urls = <String>[];
          for (final file in _selectedImages) {
            final uuid = const Uuid().v4();
            final ref = _storage.ref(
              'service_images/$_uid/$serviceId/$uuid.jpg',
            );
            await ref.putFile(
              file,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            urls.add(await ref.getDownloadURL());
          }
          await docRef.update({'images': urls});
        }

        EasyLoading.dismiss();
        Fluttertoast.showToast(msg: 'เพิ่มบริการสำเร็จ');
      }

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
          _isEdit ? 'แก้ไขบริการ' : 'เพิ่มบริการ',
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
      body: _loadingTypes
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : SingleChildScrollView(
              padding: EdgeInsets.all(20.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _sectionTitle('ประเภทบริการ')),
                        if (!_isEdit)
                          TextButton.icon(
                            icon: Icon(Icons.add, size: 16.r, color: mainColor),
                            label: Text(
                              'เพิ่มใหม่',
                              style: styles(fontSize: 12.sp, color: mainColor),
                            ),
                            onPressed: _showAddCustomTypeDialog,
                          ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: _selectedTypeId,
                      decoration: _inputDec('เลือกประเภทบริการ *'),
                      hint: Text(
                        'เลือกประเภท',
                        style: styles(fontSize: 13.sp, color: Colors.grey),
                      ),
                      items: _types.map((t) {
                        final isCustom = t['isCustom'] as bool? ?? false;
                        final name = t['name'] as String? ?? '';
                        return DropdownMenuItem<String>(
                          value: t['id'] as String,
                          child: Text(
                            isCustom ? '★ $name' : name,
                            style: styles(fontSize: 13.sp),
                          ),
                        );
                      }).toList(),
                      onChanged: _isEdit ? null : _onTypeChanged,
                      validator: (v) => v == null ? 'ประเภทบริการ' : null,
                    ),
                    if (_isEdit)
                      Padding(
                        padding: EdgeInsets.only(top: 4.h),
                        child: Text(
                          'ไม่สามารถเปลี่ยนประเภทบริการได้',
                          style: styles(
                            fontSize: 11.sp,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),

                    if (_selectedType != null) ...[
                      SizedBox(height: 8.h),
                      _buildTypePreview(_selectedType!),
                    ],

                    SizedBox(height: 20.h),
                    _sectionTitle('ชื่อบริการ'),
                    TextFormField(
                      controller: _nameController,
                      maxLength: 80,
                      style: styles(fontSize: 13.sp),
                      decoration: _inputDec('ชื่อบริการ *'),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'กรุณากรอกชื่อบริการ'
                          : null,
                    ),

                    SizedBox(height: 8.h),

                    _sectionTitle('ระยะเวลาให้บริการ'),
                    if (_durationOptions.isEmpty && _selectedType == null)
                      Text(
                        'เลือกประเภทบริการก่อนเพื่อดูตัวเลือกเวลา',
                        style: styles(fontSize: 12.sp, color: Colors.grey[500]),
                      )
                    else
                      _buildDurationChips(),

                    if (_customDuration) ...[
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _customDurationController,
                        keyboardType: TextInputType.number,
                        style: styles(fontSize: 13.sp),
                        decoration: _inputDec('ระยะเวลา (นาที) *').copyWith(
                          helperText: 'กรอกจำนวนนาทีที่ต้องการ',
                          helperStyle: styles(
                            fontSize: 11.sp,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: 20.h),

                    _sectionTitle('ราคา'),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      style: styles(fontSize: 13.sp),
                      decoration: _inputDec('ราคา (บาท) *').copyWith(
                        hintText: (!_isEdit && _selectedType != null)
                            ? '฿${(_selectedType!['basePrice'] as num?)?.toStringAsFixed(0) ?? ''}'
                            : null,
                        hintStyle: styles(
                          fontSize: 13.sp,
                          color: Colors.grey[400],
                        ),
                      ),
                      validator: (v) {
                        if (v?.trim().isEmpty ?? true) return 'กรุณากรอกราคา';
                        final n = int.tryParse(v!.trim());
                        if (n == null || n <= 0) return 'ราคาต้องมากกว่า 0';
                        return null;
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionTitle('รายละเอียด (ไม่บังคับ)'),
                    TextFormField(
                      controller: _descController,
                      maxLines: 3,
                      maxLength: 300,
                      style: styles(fontSize: 13.sp),
                      decoration: _inputDec('รายละเอียดบริการ'),
                    ),

                    SizedBox(height: 20.h),

                    _sectionTitle('รูปบริการ ($_totalImages/5)'),
                    _buildImageGrid(),

                    SizedBox(height: 32.h),

                    SizedBox(
                      width: double.infinity,
                      height: 52.h,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mainColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        onPressed: _save,
                        child: Text(
                          _isEdit ? 'บันทึกการแก้ไข' : 'บันทึก',
                          style: styles(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _showAddCustomTypeDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'เพิ่มประเภทบริการใหม่',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'เพิ่มประเภทที่ไม่มีในรายการหลัก',
              style: styles(fontSize: 13.sp, color: Colors.grey[600]),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'เช่น นวดสมุนไพร',
                border: const OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 10.h,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mainColor),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              EasyLoading.show();
              try {
                await ServiceTypesLoader.addCustomType(
                  shopId: widget.shopId,
                  categoryId: widget.shopCategoryId,
                  name: name,
                );
                EasyLoading.dismiss();
                if (ctx.mounted) Navigator.pop(ctx);
                Fluttertoast.showToast(msg: 'เพิ่มสำเร็จ กรุณาเลือกจากรายการ');
              } catch (e) {
                EasyLoading.dismiss();
                Fluttertoast.showToast(
                  msg: 'ผิดพลาด: $e',
                  backgroundColor: Colors.red,
                );
              }
            },
            child: Text(
              'เพิ่ม',
              style: styles(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (mounted) await _loadTypes();
  }

  Widget _buildImageGrid() {
    final canAdd = _totalImages < 5;
    final itemCount = _totalImages + (canAdd ? 1 : 0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8.w,
        mainAxisSpacing: 8.h,
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Existing URL images first
        if (index < _existingImages.length) {
          return _existingImageCell(index);
        }
        final localIndex = index - _existingImages.length;
        if (localIndex < _selectedImages.length) {
          return _newImageCell(localIndex);
        }
        return _addImageCell();
      },
    );
  }

  Widget _existingImageCell(int index) {
    final url = _existingImages[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: Colors.grey[100],
              child: Icon(Icons.broken_image_outlined, color: Colors.grey[300]),
            ),
          ),
        ),
        Positioned(
          top: 4.r,
          right: 4.r,
          child: GestureDetector(
            onTap: () => _removeExistingImage(url),
            child: Container(
              width: 22.r,
              height: 22.r,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14.r, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _newImageCell(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Image.file(_selectedImages[index], fit: BoxFit.cover),
        ),
        Positioned(
          top: 4.r,
          right: 4.r,
          child: GestureDetector(
            onTap: () => setState(() => _selectedImages.removeAt(index)),
            child: Container(
              width: 22.r,
              height: 22.r,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14.r, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addImageCell() {
    return GestureDetector(
      onTap: _showImageSourceDialog,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28.r,
              color: Colors.grey[400],
            ),
            SizedBox(height: 4.h),
            Text(
              'เพิ่มรูป',
              style: styles(fontSize: 11.sp, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChips() {
    return Wrap(
      spacing: 8.w,
      runSpacing: 6.h,
      children: [
        ..._durationOptions.map((min) => _durationChip('$min นาที', min)),
        _durationChip('อื่นๆ', null),
      ],
    );
  }

  Widget _durationChip(String label, int? value) {
    final isOther = value == null;
    final isSelected = isOther ? _customDuration : _selectedDuration == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isOther) {
            _customDuration = true;
            _selectedDuration = null;
          } else {
            _customDuration = false;
            _selectedDuration = value;
            _customDurationController.clear();
          }
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? mainColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected ? mainColor : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: styles(
            fontSize: 13.sp,
            color: isSelected ? Colors.white : context.subColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildTypePreview(Map<String, dynamic> t) {
    final description = t['description'] as String?;
    final basePrice = t['basePrice'] as num?;
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: mainColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: mainColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null && description.isNotEmpty)
            Text(
              description,
              style: styles(fontSize: 12.sp, color: context.subColor),
            ),
          if (basePrice != null && !_isEdit) ...[
            SizedBox(height: 4.h),
            Text(
              'ราคาเริ่มต้น ฿${basePrice.toStringAsFixed(0)}',
              style: styles(
                fontSize: 12.sp,
                color: Colors.green[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, top: 4.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 16.h,
            decoration: BoxDecoration(
              color: mainColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            text,
            style: styles(
              fontSize: 14.sp,
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
      disabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
    );
  }
}
