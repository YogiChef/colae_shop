import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/category_widget.dart';

class TypeTab extends StatefulWidget {
  static const String route = 'categories';

  const TypeTab({super.key});

  @override
  State<TypeTab> createState() => _TypeTabState();
}

class _TypeTabState extends State<TypeTab> {
  final FirebaseStorage storage = FirebaseStorage.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? fileName;
  late String categoryName;

  Future<void> uploadSubCategory() async {
    EasyLoading.show();
    if (_formKey.currentState!.validate()) {
      await firestore
          .collection('type')
          .doc(fileName)
          .set({'typename': categoryName})
          .whenComplete(() {
            EasyLoading.dismiss();
          });
      _formKey.currentState!.reset();
    } else {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.cyan.shade500,
        leading: Padding(
          padding: EdgeInsets.only(left: 12.w),
          child: CircleAvatar(
            radius: 20.w,
            child: IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
        title: Container(
          margin: EdgeInsets.only(top: 20.h, bottom: 20.h),
          child: Text(
            'Food of type',
            style: styles(fontSize: 20.sp, fontWeight: FontWeight.w500),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: EdgeInsets.only(left: 20.w, right: 20.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.w),
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.only(left: 12.w),
                          width: MediaQuery.of(context).size.width * 0.7,
                          child: TextFormField(
                            onChanged: (value) {
                              categoryName = value;
                            },
                            validator: (value) {
                              if (value!.isEmpty) {
                                return 'Please Category Name Must not be empty';
                              } else {
                                return null;
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Enter Category Name',
                            ),
                          ),
                        ),
                      ),
                      ButtonWidget(
                        label: 'Save',
                        style: styles(color: Colors.white),
                        icon: Icons.save_rounded,
                        press: uploadSubCategory,
                      ),
                    ],
                  ),
                ),
                const CategoryWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
