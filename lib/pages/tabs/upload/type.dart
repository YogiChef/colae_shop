import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/category_widget.dart';

class TypeTab extends StatefulWidget {
  static const String route = 'categories';
  const TypeTab({super.key});

  @override
  State<TypeTab> createState() => _TypeTabState();
}

class _TypeTabState extends State<TypeTab> {
  final TextEditingController _nameController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อประเภทอาหาร')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณา login ก่อน')),
      );
      return;
    }

    setState(() => _saving = true);
    EasyLoading.show();

    try {
      await FirebaseFirestore.instance.collection('type').add({
        'typename': name,
        'vendorId': uid,
      });
      _nameController.clear();
      EasyLoading.showSuccess('เพิ่มแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'ประเภทอาหาร',
          style: styles(fontSize: 18.sp, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'เพิ่มประเภทอาหาร',
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: Text('Save', style: TextStyle(color: Colors.white, fontSize: 13.sp)),
                    style: ElevatedButton.styleFrom(backgroundColor: mainColor),
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              const CategoryWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
