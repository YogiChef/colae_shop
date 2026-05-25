// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures, use_build_context_synchronously, unnecessary_cast

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:uuid/uuid.dart';
import 'package:colae_shop/pages/main_vendor_page.dart';
import 'package:colae_shop/services/sevice.dart';

enum OptionGroupType {
  free('ฟรี'),
  singleSelect('เลือกได้อย่างเดียว'),
  multiSelect('เลือกได้หลายอย่าง'),
  size('ขนาด');

  final String label;
  const OptionGroupType(this.label);
}

class ProductProvider with ChangeNotifier {
  Map<String, dynamic> productData = {};
  List<Map<String, dynamic>> optionGroups = [];
  String notes = '';

  void getFormData({
    String? productName,
    double? productPrice,
    int? qty,
    String? type,
    String? description,
    DateTime? date,
    List<String>? imageUrlList,
    bool? chargeShipping,
    double? shippingCharge,
    List<Map<String, dynamic>>? optionGroupsData,
    String? notes,
    bool notify = true,
  }) {
    if (productName != null) productData['productName'] = productName;
    if (productPrice != null) productData['productPrice'] = productPrice;
    if (qty != null) productData['qty'] = qty;
    if (type != null) productData['type'] = type;
    if (description != null) productData['description'] = description;
    if (date != null) productData['date'] = date;
    if (imageUrlList != null) {
      productData['imageUrlList'] = List<String>.from(imageUrlList);
    }
    if (chargeShipping != null) productData['chargeShipping'] = chargeShipping;
    if (shippingCharge != null) productData['shippingCharge'] = shippingCharge;

    // Deep copy optionGroups ให้ปลอดภัย
    if (optionGroupsData != null) {
      optionGroups = optionGroupsData
          .map((e) => Map<String, dynamic>.from(e))
          .map((map) {
            final newMap = Map<String, dynamic>.from(map);
            newMap['options'] = (newMap['options'] as List? ?? [])
                .map((o) => Map<String, dynamic>.from(o as Map))
                .toList();
            return newMap;
          })
          .toList();

      productData['optionGroups'] = optionGroups;
    }

    if (notes != null) {
      this.notes = notes;
      productData['notes'] = notes;
    }

    if (notify) notifyListeners();
  }

  void addOptionGroup(OptionGroupType groupType, {String? groupName}) {
    final group = {
      'type': groupType.toString().split('.').last,
      'name': groupName,
      'options': <Map<String, dynamic>>[],
    };
    optionGroups.add(group);
    notifyListeners();
  }

  void removeOptionGroup(int groupIndex) {
    if (groupIndex >= 0 && groupIndex < optionGroups.length) {
      optionGroups.removeAt(groupIndex);
      notifyListeners();
    }
  }

  void addOptionToGroup(int groupIndex, Map<String, dynamic> option) {
    if (groupIndex >= 0 && groupIndex < optionGroups.length) {
      optionGroups[groupIndex]['options'].add(
        Map<String, dynamic>.from(option),
      );
      notifyListeners();
    }
  }

  void removeOptionFromGroup(int groupIndex, int optionIndex) {
    if (groupIndex >= 0 &&
        groupIndex < optionGroups.length &&
        optionIndex >= 0 &&
        optionIndex < optionGroups[groupIndex]['options'].length) {
      optionGroups[groupIndex]['options'].removeAt(optionIndex);
      notifyListeners();
    }
  }

  void loadOptionGroups(List<dynamic> groups) {
    optionGroups = groups.map((g) {
      final map = Map<String, dynamic>.from(g as Map);
      map['options'] = (map['options'] as List? ?? [])
          .map((o) => Map<String, dynamic>.from(o as Map))
          .toList();
      return map;
    }).toList();
  }

  void clearData() {
    productData.clear();
    optionGroups.clear();
    notes = '';
    notifyListeners();
  }

  void loadFromSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) return;
    final data = snapshot.data() as Map<String, dynamic>? ?? {};

    getFormData(
      productName: data['proName']?.toString() ?? '',
      productPrice: (data['price'] as num?)?.toDouble() ?? 0.0,
      qty: (data['pqty'] ?? data['qty']) as int? ?? 0,
      type: data['type']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      date: (data['date'] as Timestamp?)?.toDate(),
      imageUrlList: List<String>.from(data['imageUrl'] ?? []),
      chargeShipping: data['chargeShipping'] as bool? ?? false,
      shippingCharge: (data['shippingCharge'] as num?)?.toDouble() ?? 0.0,
      notes: data['notes']?.toString() ?? '',
      notify: false,
    );

    final optionGroupsData = data['optionGroups'] as List<dynamic>? ?? [];
    loadOptionGroups(optionGroupsData);

    notifyListeners();
  }

  bool isFormValid() {
    final data = productData;
    final String? productName = data['productName']?.toString();
    final num? productPrice = data['productPrice'] as num?;
    final num? qty = data['qty'] as num?;
    final String? type = data['type']?.toString();
    final String? description = data['description']?.toString();
    final bool? chargeShipping = data['chargeShipping'] as bool?;
    final num? shippingCharge = data['shippingCharge'] as num?;

    if (productName == null || productName.isEmpty) return false;
    if (productPrice == null || productPrice <= 0) return false;
    if (qty == null || qty <= 0) return false;
    if (type == null || type.isEmpty) return false;
    if (description == null || description.isEmpty) return false;
    if ((chargeShipping ?? false) &&
        (shippingCharge == null || shippingCharge <= 0))
      return false;

    return true;
  }

  Future<void> saveProduct(BuildContext context) async {
    if (!isFormValid()) {
      throw Exception('กรุณากรอกข้อมูลให้ครบทุกช่อง');
    }
    if (auth.currentUser == null) {
      throw Exception('กรุณาเข้าสู่ระบบก่อน');
    }

    EasyLoading.show(status: 'Uploading...');
    try {
      final userDoc = await firestore
          .collection('vendors')
          .doc(auth.currentUser!.uid)
          .get();
      final vendorData = userDoc.data() as Map<String, dynamic>? ?? {};

      final proId = const Uuid().v4();

      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}

      await firestore.collection('products').doc(proId).set({
        'approved': false,
        'proId': proId,
        'proName': productData['productName'],
        'price': productData['productPrice'],
        'pqty': productData['qty'],
        'type': productData['type'],
        'description': productData['description'],
        'date': productData['date'] ?? DateTime.now(),
        'chargeShipping': productData['chargeShipping'] ?? false,
        'shippingCharge': productData['shippingCharge'] ?? 0.0,
        'optionGroups': optionGroups, // ใช้ตัวนี้แทน sizeList
        'notes': productData['notes'] ?? '',
        'imageUrl': productData['imageUrlList'] ?? [],
        'bussiName': vendorData['bussinessName'] ?? '',
        'storeImage': vendorData['image'] ?? '',
        'vaddress': vendorData['address'] ?? '',
        'country': vendorData['country'] ?? '',
        'city': vendorData['city'] ?? '',
        'state': vendorData['state'] ?? '',
        'vzipcode': vendorData['vzipcode'] ?? '',
        'phone': vendorData['phone'] ?? '',
        'email': vendorData['email'] ?? '',
        'vendorId': auth.currentUser!.uid,
      });

      clearData();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MainVendorPage()),
      );
      EasyLoading.dismiss();
      Fluttertoast.showToast(msg: 'Product uploaded successfully!');
    } catch (e) {
      EasyLoading.dismiss();
      Fluttertoast.showToast(
        msg: 'Upload failed: $e',
        backgroundColor: Colors.red,
      );
    }
  }
}
