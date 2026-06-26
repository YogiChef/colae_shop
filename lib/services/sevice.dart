// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:colae_shop/controllers/vendor_controller.dart';

FirebaseAuth auth = FirebaseAuth.instance;
FirebaseFirestore firestore = FirebaseFirestore.instance;
FirebaseStorage storage = FirebaseStorage.instance;
VendorController vendorController = VendorController();
Future<SharedPreferences> sharedPreferences = SharedPreferences.getInstance();

double height = 825.h;
double width = 375.w;

final mainColor = const Color(0xFF2ec415);
TextStyle styles({
  double? letterSpacing,
  double? fontSize = 13,
  double? height,
  FontWeight? fontWeight = FontWeight.w400,
  Color? color = Colors.black87,
  TextDecoration? decoration,
}) {
  return GoogleFonts.ibmPlexSansThaiLooped(
    height: height,
    letterSpacing: letterSpacing,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    decoration: decoration,
  );
}

List<String> sizeList = [];

Future<String> uploadImagToStorage(Uint8List imageBytes) async {
  try {
    String fileName = 'qr_${DateTime.now().millisecondsSinceEpoch}.png';
    Reference ref = FirebaseStorage.instance.ref().child('vendors/$fileName');

    SettableMetadata metadata = SettableMetadata(contentType: 'image/png');

    UploadTask uploadTask = ref.putData(imageBytes, metadata);
    TaskSnapshot snapshot = await uploadTask;

    String downloadUrl = await snapshot.ref.getDownloadURL();

    return downloadUrl;
  } catch (e) {
    rethrow;
  }
}

Future<String> coverImageToStorage(Uint8List coverimage) async {
  Reference ref = storage.ref().child('coverPick').child(auth.currentUser!.uid);
  UploadTask uploadTask = ref.putData(coverimage);
  TaskSnapshot snapshot = await uploadTask;
  String downloadUrl = await snapshot.ref.getDownloadURL();
  return downloadUrl;
}

Future<Uint8List?> pickStoreImage(ImageSource source) async {
  final ImagePicker _imgPicker = ImagePicker();
  XFile? _file = await _imgPicker.pickImage(source: source);

  if (_file != null) {
    return await _file.readAsBytes();
  } else {
    Fluttertoast.showToast(msg: 'No image seleted');
    return null;
  }
}

extension ThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get textColor => isDark ? Colors.white : Colors.black54;
  Color get purpleColor => isDark ? Colors.grey[300]! : Colors.deepPurple[900]!;
  Color get bgColor => isDark ? Colors.blue[700]! : Colors.grey[900]!;
  Color get subColor => isDark ? Colors.white : Colors.grey[700]!;
}
