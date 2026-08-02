// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/add_edit_provider_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ManageProvidersPage extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic> shopData;

  const ManageProvidersPage({
    super.key,
    required this.shopId,
    required this.shopData,
  });

  @override
  Widget build(BuildContext context) {
    final categoryId = shopData['categoryId'] as String? ?? '';

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'จัดการพนักงาน',
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
        actions: [
          IconButton(
            icon: Icon(Icons.person_add_outlined, size: 22.r),
            tooltip: 'เพิ่มพนักงาน',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AddEditProviderPage(shopId: shopId, categoryId: categoryId),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('service_shops')
            .doc(shopId)
            .collection('providers')
            .orderBy('order')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return Center(child: CircularProgressIndicator(color: mainColor));
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return _buildEmpty(context, shopId, categoryId);
          }

          return ListView(
            padding: EdgeInsets.all(16.w),
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Text(
                  'พนักงานทั้งหมด: ${docs.length} คน',
                  style: styles(fontSize: 13.sp, color: context.subColor),
                ),
              ),
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _ProviderCard(
                  docId: doc.id,
                  data: data,
                  shopId: shopId,
                  categoryId: categoryId,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, String shopId, String categoryId) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 64.r,
              color: Colors.grey[300],
            ),
            SizedBox(height: 16.h),
            Text(
              'ยังไม่มีพนักงาน',
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'เพิ่มพนักงานเพื่อจัดการตารางบริการ',
              style: styles(fontSize: 13.sp, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            ElevatedButton.icon(
              icon: Icon(
                Icons.person_add_outlined,
                size: 18.r,
                color: Colors.white,
              ),
              label: Text(
                '+ เพิ่มพนักงานแรกของคุณ',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddEditProviderPage(
                    shopId: shopId,
                    categoryId: categoryId,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String shopId;
  final String categoryId;

  const _ProviderCard({
    required this.docId,
    required this.data,
    required this.shopId,
    required this.categoryId,
  });

  Future<void> _toggleActive(BuildContext context, bool current) async {
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(shopId)
          .collection('providers')
          .doc(docId)
          .update({
            'active': !current,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      EasyLoading.dismiss();
      Fluttertoast.showToast(
        msg: !current ? 'เปิดใช้งานแล้ว' : 'ปิดใช้งานแล้ว',
      );
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _delete(BuildContext context) async {
    // Check active bookings first
    EasyLoading.show(status: 'กำลังตรวจสอบ...');
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: shopId)
          .where('providerId', isEqualTo: docId)
          .where('status', whereIn: ['pending', 'confirmed', 'in_service'])
          .get();
      EasyLoading.dismiss();

      if (snap.docs.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
            ),
            title: Text(
              'ลบไม่ได้',
              style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'พนักงาน "${data['name']}" ยังมีการจองรอ ${snap.docs.length} รายการ\nกรุณาจัดการการจองก่อนลบ',
              style: styles(fontSize: 13.sp, color: context.subColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'ตกลง',
                  style: styles(color: mainColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
        title: Text(
          'ลบพนักงาน?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ข้อมูลพนักงาน "${data['name']}" จะถูกลบถาวร',
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
    if (ok != true) return;

    EasyLoading.show(status: 'กำลังลบ...');
    try {
      await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(shopId)
          .collection('providers')
          .doc(docId)
          .delete();
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ลบพนักงานแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? '';
    final photo = data['photo'] as String?;
    final active = data['active'] as bool? ?? true;

    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12.w,
          right: 8.w,
          top: 12.h,
          bottom: 12.h,
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(photo, name, active),
            SizedBox(width: 12.w),

            // Info
            Text(
              name,
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: active ? context.purpleColor : Colors.grey[400],
              ),
            ),
            const Spacer(),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: active,
                activeThumbColor: mainColor,
                trackOutlineColor: WidgetStateProperty.all(Colors.grey[400]),
                inactiveThumbColor: Colors.grey[400],
                onChanged: (_) => _toggleActive(context, active),
              ),
            ),

            // Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20.r, color: Colors.grey[500]),
              onSelected: (val) async {
                switch (val) {
                  case 'edit':
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddEditProviderPage(
                          shopId: shopId,
                          categoryId: categoryId,
                          existingProviderId: docId,
                          existingProviderData: data,
                        ),
                      ),
                    );
                  case 'delete':
                    await _delete(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: _menuItem(
                    context,
                    Icons.edit_outlined,
                    'แก้ไข',
                    mainColor,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: _menuItem(
                    context,
                    Icons.delete_outline,
                    'ลบ',
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photo, String name, bool active) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Stack(
      children: [
        CircleAvatar(
          radius: 26.r,
          backgroundColor: mainColor.withValues(alpha: active ? 0.15 : 0.06),
          backgroundImage: photo != null
              ? CachedNetworkImageProvider(photo)
              : null,
          child: photo == null
              ? Text(
                  initials,
                  style: styles(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: active ? mainColor : Colors.grey[400],
                  ),
                )
              : null,
        ),
        if (!active)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 14.r,
              height: 14.r,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.block, size: 10.r, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18.r, color: color),
        SizedBox(width: 8.w),
        Text(label, style: styles(fontSize: 13.sp)),
      ],
    );
  }
}
