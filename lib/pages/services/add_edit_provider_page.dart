// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:colae_shop/utils/service_types_loader.dart';
import 'package:uuid/uuid.dart';

class AddEditProviderPage extends StatefulWidget {
  final String shopId;
  final String categoryId;
  final String? existingProviderId;
  final Map<String, dynamic>? existingProviderData;

  const AddEditProviderPage({
    super.key,
    required this.shopId,
    required this.categoryId,
    this.existingProviderId,
    this.existingProviderData,
  });

  @override
  State<AddEditProviderPage> createState() => _AddEditProviderPageState();
}

class _AddEditProviderPageState extends State<AddEditProviderPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _active = true;
  bool _isSaving = false;

  List<String> _selectedSpecialties = [];

  List<ServiceType> _availableTypes = [];
  bool _loadingTypes = true;

  File? _photoFile;
  String? _existingPhotoUrl;

  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;

  bool get _isEdit => widget.existingProviderId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit && widget.existingProviderData != null) {
      final d = widget.existingProviderData!;
      _nameCtrl.text = d['name'] as String? ?? '';
      _active = d['active'] as bool? ?? true;
      _selectedSpecialties = List<String>.from(d['specialties'] as List? ?? []);
      _existingPhotoUrl = d['photo'] as String?;
    }
    _loadTypes();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await ServiceTypesLoader.loadForShop(
        shopId: widget.shopId,
        categoryId: widget.categoryId,
      );
      if (mounted) {
        setState(() {
          _availableTypes = types;
          _loadingTypes = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  Future<String?> _uploadPhoto(String providerId) async {
    if (_photoFile == null) return _existingPhotoUrl;
    final uuid = const Uuid().v4();
    final ref = _storage.ref(
      'provider_photos/${widget.shopId}/$providerId/$uuid.jpg',
    );
    await ref.putFile(_photoFile!, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> _pickPhoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'เลือกรูปพนักงาน',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: mainColor),
              title: Text('ถ่ายรูป', style: styles(fontSize: 14.sp)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: mainColor),
              title: Text('แกลเลอรี', style: styles(fontSize: 14.sp)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _photoFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    EasyLoading.show(status: 'กำลังบันทึก...');

    try {
      final providersRef = FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('providers');

      if (_isEdit) {
        final providerId = widget.existingProviderId!;
        String? photoUrl = _existingPhotoUrl;
        if (_photoFile != null) {
          EasyLoading.show(status: 'กำลังอัปโหลดรูป...');
          photoUrl = await _uploadPhoto(providerId);
        }

        await providersRef.doc(providerId).update({
          'name': _nameCtrl.text.trim(),
          'photo': photoUrl,
          'specialties': _selectedSpecialties,
          'active': _active,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        EasyLoading.dismiss();
        Fluttertoast.showToast(msg: 'อัปเดตข้อมูลพนักงานแล้ว');
      } else {
        final countSnap = await providersRef.get();
        final order = countSnap.docs.length;

        final newDoc = await providersRef.add({
          'name': _nameCtrl.text.trim(),
          'specialties': _selectedSpecialties,
          'active': _active,
          'photo': null,
          'order': order,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (_photoFile != null) {
          EasyLoading.show(status: 'กำลังอัปโหลดรูป...');
          final photoUrl = await _uploadPhoto(newDoc.id);
          if (photoUrl != null) {
            await newDoc.update({'photo': photoUrl});
          }
        }

        EasyLoading.dismiss();
        Fluttertoast.showToast(msg: 'เพิ่มพนักงานสำเร็จ');
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ผิดพลาด: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _isEdit ? 'แก้ไขพนักงาน' : 'เพิ่มพนักงาน',
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
      body: _loadingTypes
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _buildPhotoPicker()),
                    SizedBox(height: 24.h),

                    _sectionTitle('ชื่อพนักงาน'),
                    TextFormField(
                      controller: _nameCtrl,
                      maxLength: 60,
                      style: styles(fontSize: 14.sp),
                      decoration: _inputDec('ชื่อ-นามสกุล *'),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'กรุณากรอกชื่อพนักงาน'
                          : null,
                    ),

                    SizedBox(height: 16.h),

                    _sectionTitle('ความเชี่ยวชาญ'),
                    Text(
                      'เลือกบริการที่พนักงานทำได้ (ไม่เลือก = ทำได้ทุกอย่าง)',
                      style: styles(fontSize: 12.sp, color: Colors.grey[500]),
                    ),
                    SizedBox(height: 8.h),

                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        ..._availableTypes.map((type) {
                          final selected = _selectedSpecialties.contains(
                            type.id,
                          );
                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (type.isCustom) ...[
                                  Icon(
                                    Icons.star,
                                    size: 12.r,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(width: 4.w),
                                ],
                                Text(
                                  type.name,
                                  style: styles(
                                    fontSize: 12.sp,
                                    color: selected
                                        ? Colors.white
                                        : context.textColor,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                            selected: selected,
                            selectedColor: mainColor,
                            checkmarkColor: Colors.white,
                            backgroundColor: Theme.of(context).cardColor,
                            side: BorderSide(
                              color: selected ? mainColor : Colors.grey[300]!,
                            ),
                            onSelected: (val) => setState(() {
                              if (val) {
                                _selectedSpecialties.add(type.id);
                              } else {
                                _selectedSpecialties.remove(type.id);
                              }
                            }),
                          );
                        }),
                        ActionChip(
                          avatar: Icon(Icons.add, size: 16.r, color: mainColor),
                          label: Text(
                            'เพิ่มใหม่',
                            style: styles(fontSize: 12.sp, color: mainColor),
                          ),
                          backgroundColor: mainColor.withValues(alpha: 0.08),
                          side: BorderSide(
                            color: mainColor.withValues(alpha: 0.3),
                          ),
                          onPressed: _showAddCustomTypeDialog,
                        ),
                      ],
                    ),

                    SizedBox(height: 16.h),

                    _sectionTitle('สถานะ'),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: SwitchListTile(
                        title: Text(
                          'เปิดใช้งาน',
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: context.purpleColor,
                          ),
                        ),
                        subtitle: Text(
                          _active
                              ? 'พนักงานพร้อมรับงาน'
                              : 'พนักงานหยุดรับงานชั่วคราว',
                          style: styles(
                            fontSize: 12.sp,
                            color: context.subColor,
                          ),
                        ),
                        value: _active,
                        activeThumbColor: mainColor,
                        activeTrackColor: mainColor.withValues(alpha: 0.5),
                        onChanged: (val) => setState(() => _active = val),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    ),

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
                        onPressed: _isSaving ? null : _save,
                        child: Text(
                          _isEdit ? 'บันทึกการแก้ไข' : 'เพิ่มพนักงาน',
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
                final newId = await ServiceTypesLoader.addCustomType(
                  shopId: widget.shopId,
                  categoryId: widget.categoryId,
                  name: name,
                );
                EasyLoading.dismiss();
                if (ctx.mounted) Navigator.pop(ctx);
                Fluttertoast.showToast(msg: 'เพิ่มสำเร็จ');
                await _loadTypes();
                if (mounted) setState(() => _selectedSpecialties.add(newId));
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
  }

  Widget _buildPhotoPicker() {
    final hasPhoto = _photoFile != null || _existingPhotoUrl != null;
    return GestureDetector(
      onTap: _pickPhoto,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 44.r,
            backgroundColor: mainColor.withValues(alpha: 0.12),
            backgroundImage: _photoFile != null
                ? FileImage(_photoFile!)
                : (_existingPhotoUrl != null
                          ? NetworkImage(_existingPhotoUrl!)
                          : null)
                      as ImageProvider?,
            child: !hasPhoto
                ? Icon(Icons.person, size: 40.r, color: mainColor)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 28.r,
              height: 28.r,
              decoration: BoxDecoration(
                color: mainColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.camera_alt, size: 14.r, color: Colors.white),
            ),
          ),
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
          Expanded(
            child: Text(
              text,
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: context.purpleColor,
              ),
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
}
