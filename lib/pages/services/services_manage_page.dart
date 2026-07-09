// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/add_service_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ServicesManagePage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final bool openAddOnStart;

  const ServicesManagePage({
    super.key,
    required this.shopId,
    required this.shopData,
    this.openAddOnStart = false,
  });

  @override
  State<ServicesManagePage> createState() => _ServicesManagePageState();
}

class _ServicesManagePageState extends State<ServicesManagePage> {
  String get _catId => widget.shopData['categoryId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.openAddOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _goAddService(context);
      });
    }
  }

  void _goAddService(BuildContext context) {
    if (_catId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddServicePage(shopCategoryId: _catId, shopId: widget.shopId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'บริการของร้าน',
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('services')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return Center(child: CircularProgressIndicator(color: mainColor));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyServices(onAdd: () => _goAddService(context));
          }

          return ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return _ServiceTile(
                doc: docs[index] as QueryDocumentSnapshot<Map<String, dynamic>>,
                shopId: widget.shopId,
                catId: _catId,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyServices({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 40.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.content_cut_rounded,
              size: 52.r,
              color: Colors.grey[300],
            ),
            SizedBox(height: 12.h),
            Text(
              'ยังไม่มีบริการ',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'เริ่มเพิ่มบริการแรกของคุณเลย',
              style: styles(fontSize: 13.sp, color: Colors.grey[400]),
            ),
            SizedBox(height: 20.h),
            ElevatedButton.icon(
              icon: Icon(Icons.add, size: 18.r, color: Colors.white),
              label: Text(
                'เพิ่มบริการ',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String shopId;
  final String catId;

  const _ServiceTile({
    required this.doc,
    required this.shopId,
    required this.catId,
  });

  Future<void> _toggleAvailability(bool val) async {
    try {
      await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(shopId)
          .collection('services')
          .doc(doc.id)
          .update({'available': val});
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _deleteService(BuildContext context, List<String> images) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ลบบริการนี้?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'บริการและรูปทั้งหมดจะถูกลบถาวร',
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
      for (final url in images) {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(shopId)
          .collection('services')
          .doc(doc.id)
          .delete();
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ลบบริการแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final name = data['name'] as String? ?? '';
    final duration = (data['duration'] as num?)?.toInt() ?? 0;
    final price = (data['price'] as num?)?.toInt() ?? 0;
    final typeName = data['typeName'] as String? ?? '';
    final available = data['available'] as bool? ?? true;
    final providerCount = (data['providerCount'] as num?)?.toInt() ?? 1;
    final images = List<String>.from(data['images'] as List? ?? []);

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        errorWidget: (_, _, _) => _placeholder(available),
                      )
                    : _placeholder(available),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: available
                                ? context.purpleColor
                                : Colors.grey[400],
                          ),
                        ),
                      ),

                      Transform.scale(
                        scale: 0.9,
                        child: Switch(
                          value: available,
                          activeThumbColor: mainColor,
                          activeTrackColor: mainColor.withValues(alpha: 0.2),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: _toggleAvailability,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 24.r,
                          color: Colors.grey[500],
                        ),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddServicePage(
                                  shopCategoryId: catId,
                                  shopId: shopId,
                                  existingService:
                                      doc
                                          as DocumentSnapshot<
                                            Map<String, dynamic>
                                          >,
                                ),
                              ),
                            );
                          } else if (value == 'delete') {
                            await _deleteService(context, images);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_outlined,
                                  size: 18.r,
                                  color: mainColor,
                                ),
                                SizedBox(width: 8.w),
                                Text('แก้ไข', style: styles(fontSize: 13.sp)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18.r,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'ลบ',
                                  style: styles(
                                    fontSize: 13.sp,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    '$duration นาที · ฿$price',
                    style: styles(
                      fontSize: 12.sp,
                      color: available ? context.subColor : Colors.grey[400],
                    ),
                  ),
                  Row(
                    children: [
                      if (typeName.isNotEmpty) ...[
                        Text(
                          typeName,
                          style: styles(
                            fontSize: 11.sp,
                            color: Colors.grey[400],
                          ),
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Icon(
                        Icons.people_alt_outlined,
                        size: 12.r,
                        color: Colors.grey[400],
                      ),
                      SizedBox(width: 3.w),
                      Text(
                        '$providerCount คน',
                        style: styles(fontSize: 11.sp, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool available) {
    return Container(
      color: available ? mainColor.withValues(alpha: 0.12) : Colors.grey[100],
      child: Icon(
        Icons.spa_rounded,
        size: 22.r,
        color: available ? mainColor : Colors.grey[400],
      ),
    );
  }
}
