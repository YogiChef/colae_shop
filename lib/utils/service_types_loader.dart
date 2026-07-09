import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ServiceType {
  final String id;
  final String name;
  final String categoryId;
  final int order;
  final bool isCustom;

  const ServiceType({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.order,
    required this.isCustom,
  });
}

class ServiceTypesLoader {
  /// Load combined types: global (from service_types) + shop's custom types.
  static Future<List<ServiceType>> loadForShop({
    required String shopId,
    required String categoryId,
  }) async {
    final db = FirebaseFirestore.instance;

    // Avoid composite-index-requiring queries by filtering/sorting in Dart.
    // Global types: only filter by categoryId in Firestore (single-field index),
    // then filter active=true and sort by order in Dart.
    var globalQuery = db.collection('service_types');
    Future<QuerySnapshot<Map<String, dynamic>>> globalFuture;
    if (categoryId.isNotEmpty) {
      globalFuture = globalQuery
          .where('categoryId', isEqualTo: categoryId)
          .get();
    } else {
      globalFuture = globalQuery.get();
    }

    // Custom types: no orderBy in Firestore to avoid index issues; sort in Dart.
    Future<QuerySnapshot<Map<String, dynamic>>> customFuture;
    if (categoryId.isNotEmpty) {
      customFuture = db
          .collection('service_shops')
          .doc(shopId)
          .collection('custom_types')
          .where('categoryId', isEqualTo: categoryId)
          .get();
    } else {
      customFuture = db
          .collection('service_shops')
          .doc(shopId)
          .collection('custom_types')
          .get();
    }

    final results = await Future.wait([globalFuture, customFuture]);

    final globalTypes = results[0].docs
        .where((d) => d.data()['active'] != false) // filter active in Dart
        .map((d) => ServiceType(
              id: d.id,
              name: d.data()['name'] as String? ?? '',
              categoryId: d.data()['categoryId'] as String? ?? categoryId,
              order: (d.data()['order'] as num?)?.toInt() ?? 0,
              isCustom: false,
            ))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final customTypes = results[1].docs
        .map((d) => ServiceType(
              id: d.id,
              name: d.data()['name'] as String? ?? '',
              categoryId: d.data()['categoryId'] as String? ?? categoryId,
              order: (d.data()['order'] as num?)?.toInt() ?? 0,
              isCustom: true,
            ))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return [...globalTypes, ...customTypes];
  }

  /// Add a new custom type under a shop. Returns the new document ID.
  static Future<String> addCustomType({
    required String shopId,
    required String categoryId,
    required String name,
  }) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Avoid composite index: load all custom types, find max order in Dart.
    final snap = await db
        .collection('service_shops')
        .doc(shopId)
        .collection('custom_types')
        .where('categoryId', isEqualTo: categoryId)
        .get();

    int maxOrder = 999;
    for (final d in snap.docs) {
      final o = (d.data()['order'] as num?)?.toInt() ?? 0;
      if (o > maxOrder) maxOrder = o;
    }
    final nextOrder = snap.docs.isEmpty ? 1000 : maxOrder + 1;

    final docRef = await db
        .collection('service_shops')
        .doc(shopId)
        .collection('custom_types')
        .add({
      'name': name.trim(),
      'categoryId': categoryId,
      'order': nextOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
    });

    return docRef.id;
  }
}
