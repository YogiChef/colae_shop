import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VendorOrderProvider with ChangeNotifier {
  int _pendingOrderCount = 0;
  StreamSubscription<QuerySnapshot>? _subscription;

  int get pendingOrderCount => _pendingOrderCount;

  VendorOrderProvider() {
    _startListening();
  }

  void _startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _pendingOrderCount = 0;
      notifyListeners();
      return;
    }
    _subscription?.cancel();

    _subscription = FirebaseFirestore.instance
        .collection('orders')
        .where('vendorId', isEqualTo: user.uid)
        .where(
          'status',
          whereIn: [
            'pending',
            'paid',
            'preparing',
            'pending_rider',
            'rider_accepted',
            'picked_up',
            'self_delivering',
            'shipped',
          ],
        )
        .snapshots()
        .listen(
          (snapshot) {
            final newCount = snapshot.docs.length;
            if (newCount != _pendingOrderCount) {
              _pendingOrderCount = newCount;
              notifyListeners();
            }
          },
          onError: (error) {
            if (_pendingOrderCount != 0) {
              _pendingOrderCount = 0;
              notifyListeners();
            }
          },
        );
  }

  void restartListening() {
    _startListening();
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _pendingOrderCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
