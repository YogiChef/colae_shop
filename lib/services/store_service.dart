import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:colae_shop/models/vendor_model.dart';

class StoreService {
  final _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getStoreHours() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await _firestore.collection('vendors').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final vendor = VendorModel.fromJson(data);
      return vendor.storeHours;
    }
    return null;
  }

  Future<void> saveStoreHours(Map<String, dynamic> hours) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await _firestore.collection('vendors').doc(uid).update({
      'storeHours': hours,
    });
  }

  Stream<Map<String, dynamic>?> streamStoreHours() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return _firestore.collection('vendors').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final vendor = VendorModel.fromJson(data);
        return vendor.storeHours;
      }
      return null;
    });
  }
}
