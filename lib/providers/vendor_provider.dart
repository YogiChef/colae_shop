import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/models/vendor_model.dart';

class VendorProvider with ChangeNotifier {
  VendorModel? _vendorModel;
  bool _isLoading = false;
  String? _error;

  VendorModel? get vendorModel => _vendorModel;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadVendor(String uid) async {
    if (_vendorModel != null || _isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(uid)
          .get();

      if (doc.exists) {
        _vendorModel = VendorModel.fromJson(doc.data()!);
      } else {
        _error = 'ไม่พบข้อมูลร้านค้า';
      }
    } catch (e) {
      _error = 'โหลดข้อมูลล้มเหลว: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _vendorModel = null;
    _error = null;
    notifyListeners();
  }
}
