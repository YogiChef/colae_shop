// ignore_for_file: no_leading_underscores_for_local_identifiers, use_rethrow_when_possible

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:colae_shop/services/sevice.dart';

class VendorController {
  Future<void> loginUser(String email, String password) async {
    try {
     

      if (email.isEmpty || password.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณากรอกข้อมูลให้ครบ');
        return;
      }

      await auth
          .signInWithEmailAndPassword(email: email, password: password);

     
      Fluttertoast.showToast(msg: 'เข้าสู่ระบบสำเร็จ');
    } on FirebaseAuthException catch (e) {
     
      Fluttertoast.showToast(
        timeInSecForIosWeb: 5,
        msg: "Login Error: ${e.message ?? e.code}",
        backgroundColor: Colors.red,
      );
    } catch (e) {
      
      Fluttertoast.showToast(
        msg: "เกิดข้อผิดพลาด: $e",
        backgroundColor: Colors.red,
      );
    }
  }

  Future<Uint8List> pickStoreImage(ImageSource source) async {
    final ImagePicker _imgPicker = ImagePicker();
    XFile? _file = await _imgPicker.pickImage(source: source);

    if (_file != null) {
      return await _file.readAsBytes();
    } else {
      Fluttertoast.showToast(msg: 'ไม่เลือกรูปภาพ');
      throw Exception('No image selected');
    }
  }

  Future<String> uploadImagToStorage(Uint8List imageBytes) async {
    try {
      Reference ref = storage
          .ref()
          .child('vendorImages')
          .child(auth.currentUser!.uid);
      UploadTask uploadTask = ref.putData(imageBytes);
      TaskSnapshot snap = await uploadTask;
      String downloadUrl = await snap.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      Fluttertoast.showToast(msg: 'อัปโหลดรูปภาพล้มเหลว: $e');
      throw e;
    }
  }

  Future<void> saveStoreHours(Map<String, dynamic> hours) async {
    try {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await firestore.collection('vendors').doc(auth.currentUser!.uid).update({
        'storeHours': hours,
      });
      Fluttertoast.showToast(msg: 'บันทึกเวลาร้านค้าสำเร็จ');
    } catch (e) {
      Fluttertoast.showToast(msg: 'เกิดข้อผิดพลาด: $e');
      rethrow;
    }
  }

  Future<void> saveTemporaryClose(bool isClosed) async {
    final uid = auth.currentUser!.uid;
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await firestore.collection('vendors').doc(uid).update({
      'temporarilyClosed': isClosed,
    });
  }
}
