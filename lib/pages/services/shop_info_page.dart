// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/edit_service_shop_page.dart';
import 'package:colae_shop/pages/services/manage_custom_types_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class ShopInfoPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final String? categoryName;
  final String? typeName;

  const ShopInfoPage({
    super.key,
    required this.shopId,
    required this.shopData,
    this.categoryName,
    this.typeName,
  });

  @override
  State<ShopInfoPage> createState() => _ShopInfoPageState();
}

class _ShopInfoPageState extends State<ShopInfoPage> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  late List<String> _shopImages;

  static const _dayLabels = {
    'mon': 'จ',
    'tue': 'อ',
    'wed': 'พ',
    'thu': 'พฤ',
    'fri': 'ศ',
    'sat': 'ส',
    'sun': 'อา',
  };
  static const _dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  @override
  void initState() {
    super.initState();
    _shopImages = List<String>.from(widget.shopData['images'] as List? ?? []);
  }

  Future<void> _pickShopImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;

    EasyLoading.show(status: 'กำลังอัปโหลด...');
    try {
      final uuid = const Uuid().v4();
      final ref = _storage.ref(
        'service_shop_images/${widget.shopId}/$uuid.jpg',
      );
      await ref.putFile(
        File(picked.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await _db.collection('service_shops').doc(widget.shopId).update({
        'images': FieldValue.arrayUnion([url]),
      });
      if (mounted) setState(() => _shopImages.add(url));
      EasyLoading.showSuccess('อัปโหลดสำเร็จ');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  void _showImageSourceDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'เพิ่มรูปร้าน',
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
                _pickShopImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: mainColor),
              title: Text('แกลเลอรี', style: styles(fontSize: 14.sp)),
              onTap: () {
                Navigator.pop(ctx);
                _pickShopImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteShopImage(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ลบรูปนี้?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'รูปจะถูกลบถาวร ไม่สามารถเรียกคืนได้',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ลบ',
              style: styles(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    EasyLoading.show(status: 'กำลังลบ...');
    try {
      await _db.collection('service_shops').doc(widget.shopId).update({
        'images': FieldValue.arrayRemove([url]),
      });
      try {
        await _storage.refFromURL(url).delete();
      } catch (_) {}
      if (mounted) setState(() => _shopImages.remove(url));
      EasyLoading.showSuccess('ลบรูปแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  void _viewImage(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(12.w),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
            Positioned(
              top: 8.r,
              right: 8.r,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 32.r,
                  height: 32.r,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 18.r, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.shopData;
    final shopName = d['shopName'] as String? ?? '';
    final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
    final totalReviews = (d['totalReviews'] as num?)?.toInt() ?? 0;
    final description = d['description'] as String? ?? '';
    final phone = d['phone'] as String? ?? '';

    final address = d['address'] as String? ?? '';
    final subDistrict = d['subDistrict'] as String? ?? '';
    final district = d['district'] as String? ?? '';
    final province = d['province'] as String? ?? '';
    final postalCode = d['postalCode'] as String? ?? '';

    final businessHours = d['businessHours'] as Map<String, dynamic>? ?? {};
    final serviceLocation = d['serviceLocation'] as String? ?? 'shop';
    final homeServiceFee = (d['homeServiceFee'] as num?)?.toInt() ?? 0;
    final homeServiceRadius = (d['homeServiceRadius'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'ข้อมูลร้าน',
          style: styles(
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('ข้อมูลทั่วไป'),
                  _infoRow(Icons.store_outlined, 'ชื่อร้าน', shopName),
                  if (widget.categoryName != null)
                    _infoRow(
                      Icons.category_outlined,
                      'หมวดหมู่',
                      widget.categoryName!,
                    ),
                  if (widget.typeName != null)
                    _infoRow(Icons.label_outline, 'ประเภท', widget.typeName!),
                  _infoRow(
                    Icons.star_rounded,
                    'คะแนน',
                    rating > 0
                        ? '${rating.toStringAsFixed(1)} ($totalReviews รีวิว)'
                        : 'ยังไม่มีรีวิว',
                    iconColor: Colors.amber,
                  ),
                  if (description.isNotEmpty)
                    _infoRow(
                      Icons.description_outlined,
                      'รายละเอียด',
                      description,
                    ),
                  if (phone.isNotEmpty)
                    _infoRow(Icons.phone_outlined, 'โทร', phone),
                ],
              ),
            ),
            SizedBox(height: 12.h),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('ที่อยู่'),
                  if (address.isNotEmpty)
                    _infoRow(Icons.home_outlined, 'บ้านเลขที่', address),
                  if (subDistrict.isNotEmpty)
                    _infoRow(Icons.place_outlined, 'ตำบล', subDistrict),
                  if (district.isNotEmpty)
                    _infoRow(Icons.place_outlined, 'อำเภอ', district),
                  if (province.isNotEmpty)
                    _infoRow(Icons.map_outlined, 'จังหวัด', province),
                  if (postalCode.isNotEmpty)
                    _infoRow(
                      Icons.markunread_mailbox_outlined,
                      'รหัสไปรษณีย์',
                      postalCode,
                    ),
                  if (address.isEmpty &&
                      subDistrict.isEmpty &&
                      district.isEmpty)
                    Text(
                      'ยังไม่ได้ระบุที่อยู่',
                      style: styles(fontSize: 13.sp, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('เวลาทำการ'),
                  ..._dayOrder.map((key) {
                    final info = businessHours[key] as Map<String, dynamic>?;
                    final isOpen = info?['isOpen'] as bool? ?? true;
                    final open = info?['openTime'] as String? ?? '09:00';
                    final close = info?['closeTime'] as String? ?? '21:00';
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 3.h),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28.w,
                            child: Text(
                              _dayLabels[key] ?? key,
                              style: styles(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                color: context.textColor,
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          if (!isOpen)
                            Text(
                              'ปิด',
                              style: styles(
                                fontSize: 13.sp,
                                color: Colors.red[400],
                              ),
                            )
                          else
                            Text(
                              '$open – $close',
                              style: styles(
                                fontSize: 13.sp,
                                color: context.subColor,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            SizedBox(height: 12.h),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('รูปแบบบริการ'),
                  _infoRow(
                    Icons.storefront_outlined,
                    'รูปแบบ',
                    serviceLocation == 'shop'
                        ? 'บริการที่ร้านเท่านั้น'
                        : serviceLocation == 'home'
                        ? 'บริการนอกสถานที่เท่านั้น'
                        : 'บริการทั้งที่ร้านและนอกสถานที่',
                  ),
                  if (serviceLocation != 'shop') ...[
                    if (homeServiceFee > 0)
                      _infoRow(
                        Icons.directions_car_outlined,
                        'ค่าเดินทาง',
                        '฿$homeServiceFee',
                      ),
                    if (homeServiceRadius > 0)
                      _infoRow(
                        Icons.radar_outlined,
                        'รัศมี',
                        '$homeServiceRadius กม.',
                      ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 12.h),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _sectionTitle(
                          'รูปร้าน (${_shopImages.length}/5)',
                          noBottom: true,
                        ),
                      ),
                      if (_shopImages.length < 5)
                        TextButton.icon(
                          icon: Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 18.r,
                            color: mainColor,
                          ),
                          label: Text(
                            'เพิ่มรูป',
                            style: styles(
                              fontSize: 12.sp,
                              color: mainColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _showImageSourceDialog,
                        ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  if (_shopImages.isEmpty)
                    GestureDetector(
                      onTap: _showImageSourceDialog,
                      child: Container(
                        width: double.infinity,
                        height: 80.h,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 32.r,
                              color: Colors.grey[300],
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'แตะเพื่อเพิ่มรูปร้าน',
                              style: styles(
                                fontSize: 12.sp,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    _buildShopImageGrid(),
                ],
              ),
            ),
            SizedBox(height: 12.h),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _sectionTitle(
                          'ประเภทบริการของร้าน',
                          noBottom: true,
                        ),
                      ),
                      TextButton.icon(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 16.r,
                          color: mainColor,
                        ),
                        label: Text(
                          'จัดการ',
                          style: styles(
                            fontSize: 12.sp,
                            color: mainColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          final categoryId =
                              widget.shopData['categoryId'] as String? ?? '';
                          if (categoryId.isEmpty) {
                            Fluttertoast.showToast(msg: 'ไม่พบหมวดหมู่ร้าน');
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageCustomTypesPage(
                                shopId: widget.shopId,
                                categoryId: categoryId,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'เพิ่มประเภทบริการเฉพาะร้านที่ไม่มีในรายการหลัก',
                    style: styles(fontSize: 12.sp, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18.r,
                  color: Colors.white,
                ),
                label: Text(
                  'แก้ไขข้อมูล',
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mainColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditServiceShopPage(shopData: widget.shopData),
                  ),
                ),
              ),
            ),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: context.isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text, {bool noBottom = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: noBottom ? 0 : 10.h),
      child: Text(
        text,
        style: styles(
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: context.purpleColor,
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color? iconColor,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16.r, color: iconColor ?? context.subColor),
          SizedBox(width: 8.w),
          SizedBox(
            width: 80.w,
            child: Text(
              label,
              style: styles(fontSize: 12.sp, color: context.subColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: styles(fontSize: 13.sp, color: context.textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8.w,
        mainAxisSpacing: 8.h,
        childAspectRatio: 1,
      ),
      itemCount: _shopImages.length,
      itemBuilder: (context, index) {
        final url = _shopImages[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _viewImage(url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: Colors.grey[100],
                    child: Center(
                      child: SizedBox(
                        width: 20.r,
                        height: 20.r,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: mainColor,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[100],
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey[300],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4.r,
              right: 4.r,
              child: GestureDetector(
                onTap: () => _deleteShopImage(url),
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
      },
    );
  }
}
