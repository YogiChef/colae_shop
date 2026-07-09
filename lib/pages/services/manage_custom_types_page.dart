// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ManageCustomTypesPage extends StatefulWidget {
  final String shopId;
  final String categoryId;

  const ManageCustomTypesPage({
    super.key,
    required this.shopId,
    required this.categoryId,
  });

  @override
  State<ManageCustomTypesPage> createState() => _ManageCustomTypesPageState();
}

class _ManageCustomTypesPageState extends State<ManageCustomTypesPage> {
  final _db = FirebaseFirestore.instance;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final snap = await _db
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('custom_types')
          .where('categoryId', isEqualTo: widget.categoryId)
          .orderBy('order')
          .get();
      if (mounted) {
        setState(() {
          _docs = snap.docs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(
        msg: 'โหลดข้อมูลล้มเหลว: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _editType(
    String typeId,
    String currentName,
  ) async {
    final ctrl = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'แก้ไขชื่อประเภท',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.w,
              vertical: 10.h,
            ),
          ),
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
              if (name.isEmpty || name == currentName) {
                Navigator.pop(ctx);
                return;
              }
              EasyLoading.show();
              try {
                await _db
                    .collection('service_shops')
                    .doc(widget.shopId)
                    .collection('custom_types')
                    .doc(typeId)
                    .update({'name': name});
                EasyLoading.dismiss();
                if (ctx.mounted) Navigator.pop(ctx);
                Fluttertoast.showToast(msg: 'แก้ไขสำเร็จ');
                await _loadTypes();
              } catch (e) {
                EasyLoading.dismiss();
                Fluttertoast.showToast(
                  msg: 'ผิดพลาด: $e',
                  backgroundColor: Colors.red,
                );
              }
            },
            child: Text(
              'บันทึก',
              style: styles(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteType(String typeId, String name) async {
    // Check usage
    EasyLoading.show(status: 'กำลังตรวจสอบ...');
    try {
      final results = await Future.wait([
        _db
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('services')
            .where('typeId', isEqualTo: typeId)
            .limit(1)
            .get(),
        _db
            .collection('service_shops')
            .doc(widget.shopId)
            .collection('providers')
            .where('specialties', arrayContains: typeId)
            .limit(1)
            .get(),
      ]);
      EasyLoading.dismiss();

      if (results[0].docs.isNotEmpty || results[1].docs.isNotEmpty) {
        Fluttertoast.showToast(
          msg: 'ไม่สามารถลบได้ มีบริการหรือพนักงานที่ใช้ประเภทนี้อยู่',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.orange,
        );
        return;
      }
    } catch (e) {
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ผิดพลาด: $e', backgroundColor: Colors.red);
      return;
    }

    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ลบ "$name"?',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ประเภทนี้จะถูกลบถาวร',
          style: styles(fontSize: 13.sp, color: Colors.grey[600]),
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
      await _db
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('custom_types')
          .doc(typeId)
          .delete();
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ลบแล้ว');
      await _loadTypes();
    } catch (e) {
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'ผิดพลาด: $e', backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'ประเภทบริการของร้าน',
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
      body: _loading
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : _docs.isEmpty
          ? _buildEmpty()
          : ListView.separated(
              padding: EdgeInsets.all(16.w),
              itemCount: _docs.length,
              separatorBuilder: (_, _) => SizedBox(height: 8.h),
              itemBuilder: (context, index) {
                final doc = _docs[index];
                final name = doc.data()['name'] as String? ?? '';
                return Container(
                  decoration: BoxDecoration(
                    color: context.isDark ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: context.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[200]!,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.star,
                      color: Colors.orange,
                      size: 20.r,
                    ),
                    title: Text(name, style: styles(fontSize: 14.sp)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 20.r,
                            color: mainColor,
                          ),
                          onPressed: () => _editType(doc.id, name),
                          tooltip: 'แก้ไข',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20.r,
                            color: Colors.red[400],
                          ),
                          onPressed: () => _deleteType(doc.id, name),
                          tooltip: 'ลบ',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: Text(
            '★ = ประเภทเฉพาะร้านของคุณ  ·  ไม่สามารถลบได้หากมีบริการหรือพนักงานใช้อยู่',
            style: styles(fontSize: 11.sp, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.label_off_outlined, size: 48.r, color: Colors.grey[300]),
          SizedBox(height: 12.h),
          Text(
            'ยังไม่มีประเภทบริการเฉพาะร้าน',
            style: styles(fontSize: 14.sp, color: Colors.grey[500]),
          ),
          SizedBox(height: 6.h),
          Text(
            'เพิ่มได้จากหน้าเพิ่มบริการ หรือเพิ่มพนักงาน',
            style: styles(fontSize: 12.sp, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
