// ignore_for_file: avoid_print, use_build_context_synchronously, unnecessary_cast, unused_catch_stack, use_null_aware_elements, unused_local_variable
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:colae_shop/services/cash_payment.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/pages/tabs/orders/buyer_details_widget.dart';
import 'package:colae_shop/pages/tabs/orders/prepar_info_widget.dart';
import 'package:geolocator/geolocator.dart';

bool _isCashPaymentPending(Map<String, dynamic> orderData) {
  final paymentMethod = orderData['paymentMethod']?.toString() ?? '';
  final status = orderData['status']?.toString() ?? '';
  return paymentMethod == 'cash' &&
      !['delivered', 'cancelled'].contains(status);
}

List<Map<String, dynamic>> _processItems(List itemsRaw) {
  return itemsRaw
      .asMap()
      .entries
      .where((entry) {
        final item = Map<String, dynamic>.from(entry.value ?? {});
        return item.isNotEmpty &&
            item['accepted'] != true &&
            item['cancelled'] != true;
      })
      .map((entry) {
        final item = Map<String, dynamic>.from(entry.value);
        item['__rawIndex'] = entry.key;
        return item;
      })
      .toList();
}

({IconData icon, Color color, String label}) _getServiceDetails(
  String serviceType,
  Map<String, dynamic> orderData,
) {
  final String tableId = orderData['tableId']?.toString() ?? '';
  final bool isDineIn = serviceType == 'dine-in' || tableId.isNotEmpty;
  if (isDineIn && tableId.isNotEmpty) {
    return (
      icon: Icons.table_restaurant,
      color: Colors.purple.shade700,
      label: 'โต๊ะ: $tableId',
    );
  } else if (isDineIn) {
    return (
      icon: Icons.storefront_sharp,
      color: Colors.green.shade700,
      label: 'รอรับที่ร้าน',
    );
  } else if (serviceType == 'ecommerce') {
    return (
      icon: Icons.inventory_2_outlined,
      color: Colors.blue.shade700,
      label: 'Ecommerce',
    );
  } else if (serviceType == 'delivery') {
    return (icon: Icons.delivery_dining, color: Colors.orange, label: 'จัดส่ง');
  } else {
    return (
      icon: Icons.store,
      color: Colors.cyan.shade700,
      label: 'รับที่ร้าน',
    );
  }
}

(
  double pendingSubTotal,
  int pendingItemCount,
  int pendingQuantity,
  double acceptedSubTotal,
  int acceptedItemCount,
  int acceptedQuantity,
)
_calcTotals(List itemsList, String serviceType) {
  double pendingSubTotal = 0.0;
  int pendingItemCount = 0;
  int pendingQuantity = 0;
  double acceptedSubTotal = 0.0;
  int acceptedItemCount = 0;
  int acceptedQuantity = 0;
  for (final it in itemsList) {
    final accepted = it['accepted'] ?? false;
    final cancelled = it['cancelled'] ?? false;
    final itPrice = (it['price'] as num?)?.toDouble() ?? 0.0;
    final itExtra = (it['extraPrice'] as num?)?.toDouble() ?? 0.0;
    final itQty = (it['quantity'] as num?)?.toInt() ?? 1;
    if (!accepted && !cancelled) {
      pendingSubTotal += (itPrice + itExtra) * itQty;
      pendingItemCount++;
      pendingQuantity += itQty;
    }
    if (accepted) {
      acceptedSubTotal += (itPrice + itExtra) * itQty;
      acceptedItemCount++;
      acceptedQuantity += itQty;
    }
  }
  return (
    pendingSubTotal,
    pendingItemCount,
    pendingQuantity,
    acceptedSubTotal,
    acceptedItemCount,
    acceptedQuantity,
  );
}

class PreparTab extends StatefulWidget {
  const PreparTab({super.key});
  @override
  State<PreparTab> createState() => _PreparTabState();
}

class _PreparTabState extends State<PreparTab>
    with AutomaticKeepAliveClientMixin<PreparTab> {
  @override
  bool get wantKeepAlive => true;

  final Map<String, Timer> _orderTimers = {};
  Set<String> _timerOrderIds = <String>{};
  final Map<String, int> _orderRetryCount = {};

  final Set<String> _shownDialogs = <String>{};
  final Set<String> _processedDeliveryOrders = <String>{};
  final Set<String> _processingOrders = <String>{};

  late final StreamSubscription<QuerySnapshot> _orderSubscription;
  StreamSubscription<Position>? _positionStream;
  Position? currentPosition;

  List<DocumentSnapshot> _cachedOrders = [];
  bool _isLoading = true;
  bool _hasError = false;
  Object? _error;
  final Map<String, ValueNotifier<DocumentSnapshot>> _cardNotifiers = {};

  late Stream<Map<String, int>> _unreadCountsStream;

  static const int _maxRiderOrders = 5;

  @override
  void initState() {
    super.initState();
    final orderStream = FirebaseFirestore.instance
        .collection('orders')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
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
        .orderBy('timestamp')
        .snapshots();

    _orderSubscription = orderStream.listen(
      (snapshot) {
        final newDocs = snapshot.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .map((c) => c.doc)
            .toList();
        if (newDocs.isNotEmpty) _handleNewDeliveryOrders(newDocs);

        for (final change in snapshot.docChanges) {
          switch (change.type) {
            case DocumentChangeType.added:
              _cardNotifiers.putIfAbsent(
                change.doc.id,
                () => ValueNotifier(change.doc),
              );
            case DocumentChangeType.modified:
              _cardNotifiers[change.doc.id]?.value = change.doc;
            case DocumentChangeType.removed:
              final id = change.doc.id;
              _cardNotifiers.remove(id)?.dispose();
              _processedDeliveryOrders.remove(id);
              _shownDialogs.remove(id);
              _stopOrderTimer(id);
          }
        }

        final newCount = snapshot.docs.length;
        if (_isLoading || newCount != _cachedOrders.length) {
          setState(() {
            _cachedOrders = snapshot.docs;
            _isLoading = false;
          });
        } else {
          _cachedOrders = snapshot.docs;
        }
      },
      onError: (e) {
        setState(() {
          _hasError = true;
          _error = e;
          _isLoading = false;
        });
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startLocationStream());

    final String vendorUid = auth.currentUser!.uid;
    _unreadCountsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('vendorId', isEqualTo: vendorUid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          Map<String, int> counts = {};
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['senderId'] == vendorUid) continue;
            final String? buyerId = data['buyerId'] as String?;
            final String? orderId =
                data['orderId'] as String? ?? data['proId'] as String?;
            if (buyerId != null && orderId != null) {
              final String key = '$buyerId-$orderId';
              counts[key] = (counts[key] ?? 0) + 1;
            }
          }
          return counts;
        });
  }

  void _startLocationStream() async {
    if (_positionStream != null) return;
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Fluttertoast.showToast(msg: 'กรุณาเปิด GPS/Location Service');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Fluttertoast.showToast(msg: 'กรุณาอนุญาตตำแหน่งเพื่อใช้งานฟีเจอร์นี้');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      Fluttertoast.showToast(
        msg: 'ตำแหน่งถูกปฏิเสธถาวร – กรุณาเปิดในตั้งค่าแอป',
      );
      await Geolocator.openAppSettings();
      return;
    }
    currentPosition ??= await Geolocator.getLastKnownPosition();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 20,
          ),
        ).listen((Position position) {
          currentPosition = position;
        });
  }

  void _handleNewDeliveryOrders(List<DocumentSnapshot> docs) {
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final orderId = doc.id;
      if (_processedDeliveryOrders.contains(orderId)) continue;
      final status = data['status']?.toString() ?? 'pending';
      final serviceType = data['serviceType']?.toString() ?? 'pickup';
      final selfDeliver = data['selfDeliver'] ?? false;
      final bool isMultiVendor = data['isMultiVendor'] ?? false;
      if (serviceType == 'delivery' && status == 'paid' && !selfDeliver) {
        _processedDeliveryOrders.add(orderId);
        final Map<String, dynamic> viD =
            (data['vendorInfo'] as Map<String, dynamic>?) ?? {};
        final GeoPoint? vendorGeo =
            viD['vendorLocation'] as GeoPoint? ??
            data['vendorLocation'] as GeoPoint?;
        final vendorLat =
            vendorGeo?.latitude ?? currentPosition?.latitude ?? 0.0;
        final vendorLng =
            vendorGeo?.longitude ?? currentPosition?.longitude ?? 0.0;
        final shippingCharge =
            (data['shippingCharge'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = (data['totalPrice'] as num?)?.toDouble() ?? 0.0;
        final subTotal = totalPrice - shippingCharge;
        if (isMultiVendor) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_shownDialogs.contains(orderId)) {
              _shownDialogs.add(orderId);
              _startOrderTimer(
                orderId,
                vendorLat,
                vendorLng,
                shippingCharge,
                subTotal,
              );
              _assignToNearestRider(
                orderId,
                vendorLat,
                vendorLng,
                shippingCharge,
                subTotal,
              ).then((assigned) async {
                if (assigned) {
                  _stopOrderTimer(orderId);
                  // assign rider คนเดียวกันให้ order อื่นในกลุ่ม
                  final groupId = data['multiVendorGroupId'] as String?;
                  if (groupId != null) {
                    await _assignSameRiderToGroup(orderId, groupId);
                  }
                }
              });
            }
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_shownDialogs.contains(orderId)) {
              _shownDialogs.add(orderId);
              _showDeliveryDecisionDialog(
                context: context,
                orderId: orderId,
                vendorLat: vendorLat,
                vendorLng: vendorLng,
                shippingCharge: shippingCharge,
                subTotal: subTotal,
                totalPrice: totalPrice,
                items: List<Map<String, dynamic>>.from(data['items'] ?? []),
              );
            }
          });
        }
      }
    }
  }

  void _startOrderTimer(
    String orderId,
    double vendorLat,
    double vendorLng,
    double shippingCharge,
    double subTotal,
  ) {
    if (_orderTimers.containsKey(orderId)) return;
    final retryCount = _orderRetryCount[orderId] ?? 0;
    _orderTimers[orderId] = Timer(const Duration(minutes: 1), () async {
      _orderTimers.remove(orderId);
      if (mounted) {
        setState(() {
          _timerOrderIds = _timerOrderIds.difference({orderId});
        });
      }
      final assigned = await _assignToNearestRider(
        orderId,
        vendorLat,
        vendorLng,
        shippingCharge,
        subTotal,
      );
      if (!assigned && mounted) {
        final newCount = retryCount + 1;
        _orderRetryCount[orderId] = newCount;
        if (newCount >= 10) {
          _orderRetryCount.remove(orderId);
          Fluttertoast.showToast(
            msg: 'ไม่สามารถหาไรเดอร์ได้ กรุณาส่งเอง',
            backgroundColor: Colors.red,
            toastLength: Toast.LENGTH_LONG,
          );
        } else {
          _startOrderTimer(
            orderId,
            vendorLat,
            vendorLng,
            shippingCharge,
            subTotal,
          );
        }
      } else if (assigned) {
        _orderRetryCount.remove(orderId);
      }
    });
    if (mounted) {
      setState(() {
        _timerOrderIds = {..._timerOrderIds, orderId};
      });
    }
  }

  void _stopOrderTimer(String orderId) {
    _orderTimers[orderId]?.cancel();
    _orderTimers.remove(orderId);
    _orderRetryCount.remove(orderId);
    if (mounted) {
      setState(() {
        _timerOrderIds = _timerOrderIds.difference({orderId});
      });
    }
  }

  void _cleanupOrder(String orderId) {
    _processedDeliveryOrders.remove(orderId);
    _shownDialogs.remove(orderId);
    _stopOrderTimer(orderId);
  }

  Future<bool> _assignToNearestRider(
    String orderId,
    double vendorLat,
    double vendorLng,
    double shippingCharge,
    double subTotal,
  ) async {
    final t0 = DateTime.now();

    try {
      const activeStatuses = ['pending_rider', 'rider_accepted', 'picked_up'];

      final results = await Future.wait([
        firestore
            .collection('riders')
            .where('online', isEqualTo: true)
            .limit(20)
            .get(),
        firestore
            .collection('orders')
            .where('status', whereIn: activeStatuses)
            .get(),
      ]);
      final t1 = DateTime.now();

      final ridersSnapshot = results[0];
      final activeOrdersSnapshot = results[1];
      print(
        '[ASSIGN] riders online=${ridersSnapshot.docs.length}  active-orders=${activeOrdersSnapshot.docs.length}',
      );
      if (ridersSnapshot.docs.isEmpty) {
        Fluttertoast.showToast(msg: 'ไม่มี rider ออนไลน์ในขณะนี้');
        return false;
      }
      final Map<String, int> riderOrderCounts = {};
      for (final doc in activeOrdersSnapshot.docs) {
        final riderId =
            (doc.data() as Map<String, dynamic>)['riderId'] as String?;
        if (riderId != null) {
          riderOrderCounts[riderId] = (riderOrderCounts[riderId] ?? 0) + 1;
        }
      }
      final Set<String> ridersWithPickedUp = {};
      for (final doc in activeOrdersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] == 'picked_up') {
          final rid = data['riderId'] as String?;
          if (rid != null) ridersWithPickedUp.add(rid);
        }
      }
      double minDistance = double.infinity;
      String? nearestRiderId;
      for (final doc in ridersSnapshot.docs) {
        final riderData = doc.data() as Map<String, dynamic>;
        final GeoPoint? riderGeo = riderData['location'] as GeoPoint?;
        final riderLat = riderGeo?.latitude ?? 0.0;
        final riderLng = riderGeo?.longitude ?? 0.0;
        if (ridersWithPickedUp.contains(doc.id)) {
          continue;
        }
        if ((riderOrderCounts[doc.id] ?? 0) >= _maxRiderOrders) {
          print(
            '[ASSIGN] skip rider=${doc.id} (${riderOrderCounts[doc.id]} orders)',
          );
          continue;
        }
        final distance =
            Geolocator.distanceBetween(
              vendorLat,
              vendorLng,
              riderLat,
              riderLng,
            ) /
            1000;
        print(
          '[ASSIGN] rider=${doc.id}  dist=${distance.toStringAsFixed(2)}km',
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestRiderId = doc.id;
        }
      }
      if (nearestRiderId != null) {
        print(
          '[ASSIGN] ⏳ writing order update → nearest=$nearestRiderId  dist=${minDistance.toStringAsFixed(2)}km',
        );
        try {
          await FirebaseFirestore.instance.enableNetwork();
        } catch (_) {}

        await firestore.collection('orders').doc(orderId).update({
          'status': 'pending_rider',
          'riderId': nearestRiderId,
          'assignedAt': FieldValue.serverTimestamp(),
          'assignedDistance': minDistance,
        });
        final t2 = DateTime.now();
        print(
          '[ASSIGN] ✅ order updated  +${t2.difference(t1).inMilliseconds}ms  total=${t2.difference(t0).inMilliseconds}ms',
        );
        Fluttertoast.showToast(msg: 'มอบหมายให้ Rider สำเร็จ ✅');
        return true;
      } else {
        Fluttertoast.showToast(
          msg:
              'ไม่มี rider ว่าง (ทุกคนมีออร์เดอร์เต็ม $_maxRiderOrders รายการแล้ว)',
          backgroundColor: Colors.orange,
        );
        return false;
      }
    } catch (e, st) {
      Fluttertoast.showToast(msg: 'มอบหมาย rider ล้มเหลว: $e');
      return false;
    }
  }

  Future<void> _assignSameRiderToGroup(
    String assignedOrderId,
    String groupId,
  ) async {
    print('[GROUP] 🔍 start assignedOrderId=$assignedOrderId groupId=$groupId');
    try {
      final assignedDoc = await firestore
          .collection('orders')
          .doc(assignedOrderId)
          .get();
      if (!assignedDoc.exists) {
        print('[GROUP] ❌ assignedDoc not found');
        return;
      }
      final riderId = assignedDoc.data()?['riderId'] as String?;
      if (riderId == null) {
        print('[GROUP] ❌ riderId is null');
        return;
      }
      print('[GROUP] ✅ riderId=$riderId');

      final linkedSnapshot = await firestore
          .collection('orders')
          .where('multiVendorGroupId', isEqualTo: groupId)
          .where('status', isEqualTo: 'paid')
          .get();
      print('[GROUP] 🔍 linked orders found: ${linkedSnapshot.docs.length}');

      final batch = firestore.batch();
      for (final doc in linkedSnapshot.docs) {
        if (doc.id != assignedOrderId) {
          print('[GROUP] 🔁 updating orderId=${doc.id}');
          batch.update(doc.reference, {
            'status': 'pending_rider',
            'riderId': riderId,
            'assignedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      print('[GROUP] ✅ assigned rider=$riderId to group=$groupId');
    } catch (e) {
      print('[GROUP] ❌ error: $e');
    }
  }

  Future<void> _handleVendorSelfDeliver(
    String orderId,
    double totalPrice,
    double shippingCharge,
  ) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);
    try {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await firestore.collection('orders').doc(orderId).update({
        'selfDeliver': true,
        'status': 'preparing',
      });
      _cleanupOrder(orderId);
      Fluttertoast.showToast(
        msg: 'เลือกส่งเองแล้ว - กดยืนยันรายการอาหารให้ครบเพื่อจบออร์เดอร์',
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'รับส่งเองล้มเหลวชั่วคราว');
    } finally {
      _processingOrders.remove(orderId);
    }
  }

  Future<void> markOrderReady(
    String orderId,
    List<Map<String, dynamic>> itemsList,
    double vendorLat,
    double vendorLng,
    double shippingCharge,
    double subTotal,
  ) async {
    final t0 = DateTime.now();

    if (_processingOrders.contains(orderId)) {
      return;
    }
    _processingOrders.add(orderId);
    EasyLoading.show(status: 'กำลังอัปเดตสถานะและตัดสต็อก...');
    try {
      final List<Map<String, dynamic>> updatedItems = [];
      final batch = firestore.batch();
      final orderRef = firestore.collection('orders').doc(orderId);
      int acceptedCount = 0;
      for (final item in itemsList) {
        final mutableItem = Map<String, dynamic>.from(item);
        if (!(mutableItem['accepted'] ?? false) &&
            !(mutableItem['cancelled'] ?? false)) {
          mutableItem['accepted'] = true;
          acceptedCount++;
          final proId = mutableItem['proId']?.toString() ?? '';
          final qty = (mutableItem['quantity'] as num?)?.toInt() ?? 1;
          if (proId.isNotEmpty) {
            batch.update(firestore.collection('products').doc(proId), {
              'pqty': FieldValue.increment(-qty),
            });
          }
        }
        updatedItems.add(mutableItem);
      }
      final t1 = DateTime.now();
      print(
        '[MARK_READY] ✅ batch built  accepted=$acceptedCount  +${t1.difference(t0).inMilliseconds}ms',
      );
      batch.update(orderRef, {
        'items': updatedItems,
        'status': 'pending_rider',
        'preparingCompletedAt': FieldValue.serverTimestamp(),
      });
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await batch.commit();
      final t2 = DateTime.now();
      print(
        '[MARK_READY] ✅ batch committed  +${t2.difference(t1).inMilliseconds}ms  total=${t2.difference(t0).inMilliseconds}ms',
      );
      _cleanupOrder(orderId);
      Fluttertoast.showToast(msg: 'ทำอาหารเสร็จแล้วและตัดสต็อกเรียบร้อย ✅');
    } catch (e, st) {
      Fluttertoast.showToast(
        msg: 'อัปเดตสถานะล้มเหลว: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      _processingOrders.remove(orderId);
      EasyLoading.dismiss();
    }
  }

  Future<void> _completeSelfDeliverOrder(
    String orderId,
    List<Map<String, dynamic>> itemsList,
    String serviceType,
    double originalShippingCharge,
  ) async {
    if (_processingOrders.contains(orderId)) return;
    _processingOrders.add(orderId);
    EasyLoading.show(status: 'กำลังจบออร์เดอร์...');
    try {
      final List<Map<String, dynamic>> updatedItems = itemsList
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      double foodTotal = 0.0;
      final batch = firestore.batch();
      for (var item in updatedItems) {
        final bool cancelled = item['cancelled'] ?? false;
        if (!cancelled) {
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final extra = (item['extraPrice'] as num?)?.toDouble() ?? 0.0;
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          foodTotal += (price + extra) * qty;
        }
        if (!(item['accepted'] ?? false) && !cancelled) {
          item['accepted'] = true;
          final proId = item['proId']?.toString() ?? '';
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          if (proId.isNotEmpty) {
            batch.update(firestore.collection('products').doc(proId), {
              'pqty': FieldValue.increment(-qty),
            });
          }
        }
      }
      final double vendorEarnings = foodTotal + originalShippingCharge;
      batch.update(firestore.collection('orders').doc(orderId), {
        'items': updatedItems,
        'totalPrice': foodTotal + originalShippingCharge,
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
        'vendorEarnings': vendorEarnings,
      });
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await batch.commit();
      _cleanupOrder(orderId);
      Fluttertoast.showToast(msg: 'ส่งสำเร็จ! ได้เงินครบแล้ว 🚀');
    } catch (e) {
      Fluttertoast.showToast(msg: 'ล้มเหลว: $e', backgroundColor: Colors.red);
    } finally {
      _processingOrders.remove(orderId);
      EasyLoading.dismiss();
    }
  }

  Future<void> _markChatsAsRead({
    required String buyerId,
    required String proId,
  }) async {
    try {
      final batch = firestore.batch();
      final unreadSnapshot = await firestore
          .collection('chats')
          .where('vendorId', isEqualTo: auth.currentUser!.uid)
          .where('buyerId', isEqualTo: buyerId)
          .where('proId', isEqualTo: proId)
          .where('senderId', isEqualTo: buyerId)
          .where('read', isEqualTo: false)
          .get();
      for (var doc in unreadSnapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await batch.commit();
    } catch (e) {
      print('Error marking chats as read: $e');
    }
  }

  Future<void> _showDeliveryDecisionDialog({
    required BuildContext context,
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    required double shippingCharge,
    required double subTotal,
    required double totalPrice,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delivery',
          textAlign: TextAlign.center,
          style: styles(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: Colors.green,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'สินค้า: ${items.length} รายการ',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: Colors.blue.shade600,
              ),
            ),
            Text(
              'ค่าอาหาร: ฿${subTotal.toStringAsFixed(2)}',
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            Text(
              'ค่าส่ง: ฿${shippingCharge.toStringAsFixed(2)}',
              style: styles(
                color: Colors.green,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'รวมทั้งหมด: ฿${totalPrice.toStringAsFixed(2)}',
              style: styles(
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange.shade900,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'คุณต้องการส่งเอง หรือมอบหมาย rider?',
              textAlign: TextAlign.center,
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.orange,
              ),
            ),
            SizedBox(height: 24.sp),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, 'assign_rider'),
            child: Text(
              'ส่งผ่าน Rider',
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, 'self_deliver'),
            child: Text(
              'ร้านส่งเอง',
              style: styles(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result == 'self_deliver') {
      _stopOrderTimer(orderId);
      Future.microtask(() => _handleVendorSelfDeliver(orderId, totalPrice, 0));
    } else if (result == 'assign_rider') {
      _startOrderTimer(orderId, vendorLat, vendorLng, shippingCharge, subTotal);
      Future.microtask(() async {
        final assigned = await _assignToNearestRider(
          orderId,
          vendorLat,
          vendorLng,
          shippingCharge,
          subTotal,
        );
        if (assigned) _stopOrderTimer(orderId);
      });
    } else {
      _processedDeliveryOrders.remove(orderId);
      _shownDialogs.remove(orderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(body: _buildBody());
  }

  Widget _buildBody() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 60.sp),
            SizedBox(height: 16.h),
            Text(
              'เกิดข้อผิดพลาดในการโหลดออร์เดอร์',
              style: styles(fontSize: 18.sp, color: Colors.red),
            ),
            Text(
              '$_error',
              style: styles(fontSize: 14.sp, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.yellow.shade900),
            SizedBox(height: 20.h),
            Text(
              'กำลังโหลดออร์เดอร์...',
              style: styles(fontSize: 16.sp, color: Colors.yellow.shade900),
            ),
          ],
        ),
      );
    }
    if (_cachedOrders.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.restaurant_menu_outlined,
                size: 90.sp,
                color: Colors.yellow.shade900,
              ),
              SizedBox(height: 20.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Text(
                  'รอออร์เดอร์ใหม่เข้ามานะครับ 🍕',
                  textAlign: TextAlign.center,
                  style: styles(
                    fontSize: 20.sp,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<Map<String, int>>(
      stream: _unreadCountsStream,
      builder: (context, unreadSnapshot) {
        final unreadCountsMap = unreadSnapshot.data ?? {};

        final nonEcomDocs = _cachedOrders.where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          return (d['orderType'] as String?) != 'ecommerce';
        }).toList();

        final nearEcomDocs = _cachedOrders.where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          if ((d['orderType'] as String?) != 'ecommerce') return false;
          final dist = (d['orderDistance'] as num?)?.toDouble();
          return dist != null && dist <= 200;
        }).toList();

        final farEcomDocs = _cachedOrders.where((doc) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          if ((d['orderType'] as String?) != 'ecommerce') return false;
          final dist = (d['orderDistance'] as num?)?.toDouble();
          return dist == null || dist > 200;
        }).toList();

        OrderCard buildCard(DocumentSnapshot doc) {
          final orderId = doc.id;
          final orderData = doc.data() as Map<String, dynamic>? ?? {};
          final buyerId = orderData['buyerId']?.toString() ?? '';
          final unreadCount = unreadCountsMap['$buyerId-$orderId'] ?? 0;
          final notifier = _cardNotifiers.putIfAbsent(
            orderId,
            () => ValueNotifier(doc),
          );
          return OrderCard(
            key: ValueKey(orderId),
            notifier: notifier,
            unreadCount: unreadCount,
            timerOrderIds: _timerOrderIds,
            orderRetryCount: _orderRetryCount,
            onMarkReady: markOrderReady,
            onCompleteSelfDeliver: _completeSelfDeliverOrder,
            onVendorSelfDeliver: _handleVendorSelfDeliver,
            onAssignRider: _assignToNearestRider,
            onStopTimer: _stopOrderTimer,
            onStartTimer: _startOrderTimer,
            onMarkChatsRead: _markChatsAsRead,
            onCleanup: _cleanupOrder,
          );
        }

        Widget sectionHeader({
          required String label,
          required int count,
          required IconData icon,
          required Color color,
        }) {
          return Container(
            margin: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 16.sp),
                SizedBox(width: 8.w),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                SizedBox(width: 6.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(bottom: 16.h),
          children: [
            ...nonEcomDocs.map(buildCard),
            if (nearEcomDocs.isNotEmpty) ...[
              sectionHeader(
                label: 'Ecommerce  10-200 กม.',
                count: nearEcomDocs.length,
                icon: Icons.near_me,
                color: Colors.blue.shade700,
              ),
              ...nearEcomDocs.map(buildCard),
            ],
            if (farEcomDocs.isNotEmpty) ...[
              sectionHeader(
                label: 'Ecommerce  เกิน 200 กม.',
                count: farEcomDocs.length,
                icon: Icons.local_shipping,
                color: Colors.orange.shade700,
              ),
              ...farEcomDocs.map(buildCard),
            ],
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _orderSubscription.cancel();
    for (final timer in _orderTimers.values) {
      timer.cancel();
    }
    _orderTimers.clear();
    _orderRetryCount.clear();
    _timerOrderIds = {};
    _shownDialogs.clear();
    _positionStream?.cancel();
    _processedDeliveryOrders.clear();
    _processingOrders.clear();
    for (final notifier in _cardNotifiers.values) {
      notifier.dispose();
    }
    _cardNotifiers.clear();
    super.dispose();
  }
}

class OrderCard extends StatefulWidget {
  final ValueNotifier<DocumentSnapshot> notifier;
  final int unreadCount;
  final Set<String> timerOrderIds;
  final Map<String, int> orderRetryCount;

  final Future<void> Function(
    String,
    List<Map<String, dynamic>>,
    double,
    double,
    double,
    double,
  )
  onMarkReady;
  final Future<void> Function(
    String,
    List<Map<String, dynamic>>,
    String,
    double,
  )
  onCompleteSelfDeliver;
  final Future<void> Function(String, double, double) onVendorSelfDeliver;
  final Future<bool> Function(String, double, double, double, double)
  onAssignRider;
  final void Function(String) onStopTimer;
  final void Function(String, double, double, double, double) onStartTimer;
  final Future<void> Function({required String buyerId, required String proId})
  onMarkChatsRead;
  final void Function(String) onCleanup;

  const OrderCard({
    super.key,
    required this.notifier,
    required this.unreadCount,
    required this.timerOrderIds,
    required this.orderRetryCount,
    required this.onMarkReady,
    required this.onCompleteSelfDeliver,
    required this.onVendorSelfDeliver,
    required this.onAssignRider,
    required this.onStopTimer,
    required this.onStartTimer,
    required this.onMarkChatsRead,
    required this.onCleanup,
  });

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  bool _isExpanded = false;
  final Set<int> _selectedToCancel = {};

  Timer? _countdownTimer;
  int _secondsLeft = 60;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onDocChanged);
    final orderId = widget.notifier.value.id;
    if (widget.timerOrderIds.contains(orderId)) _startCountdown();
  }

  @override
  void didUpdateWidget(OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.removeListener(_onDocChanged);
      widget.notifier.addListener(_onDocChanged);
    }
    final orderId = _doc.id;
    final wasSearching = oldWidget.timerOrderIds.contains(orderId);
    final isSearching = widget.timerOrderIds.contains(orderId);
    if (!wasSearching && isSearching) _startCountdown();
    if (wasSearching && !isSearching) _stopCountdown();
  }

  void _startCountdown() {
    _secondsLeft = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--;
      });
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _secondsLeft = 60;
  }

  void _onDocChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    widget.notifier.removeListener(_onDocChanged);
    super.dispose();
  }

  DocumentSnapshot get _doc => widget.notifier.value;

  @override
  Widget build(BuildContext context) {
    final orderData = _doc.data() as Map? ?? {};
    final Map<String, dynamic> orderDataMap = orderData.cast<String, dynamic>();
    final orderId = _doc.id;
    final buyerId = orderData['buyerId']?.toString() ?? '';
    final itemsRaw = orderData['items'] ?? [];
    final items = _processItems(itemsRaw);
    final Map<String, dynamic> vi =
        (orderData['vendorInfo'] as Map<String, dynamic>?) ?? {};
    final GeoPoint? vendorGeoPoint =
        vi['vendorLocation'] as GeoPoint? ??
        orderData['vendorLocation'] as GeoPoint?;
    final double vendorLat = vendorGeoPoint?.latitude ?? 0.0;
    final double vendorLng = vendorGeoPoint?.longitude ?? 0.0;
    final String vAddress =
        vi['vaddress'] as String? ?? orderData['vaddress'] as String? ?? '';
    final String vSubdistrict =
        vi['vsubdistrict'] as String? ??
        orderData['vsubdistrict'] as String? ??
        '';
    final String vDistrict =
        vi['vdistrict'] as String? ?? orderData['vdistrict'] as String? ?? '';
    final String vProvince =
        vi['vprovince'] as String? ?? orderData['vprovince'] as String? ?? '';
    final String vZipcode =
        vi['vzipcode'] as String? ?? orderData['vzipcode'] as String? ?? '';
    final String fullVendorAddress = [
      if (vAddress.isNotEmpty) vAddress,
      if (vSubdistrict.isNotEmpty) vSubdistrict,
      if (vDistrict.isNotEmpty) 'อ.$vDistrict',
      if (vProvince.isNotEmpty) 'จ.$vProvince',
      if (vZipcode.isNotEmpty) vZipcode,
    ].join(' ');
    final Map<String, dynamic> bi =
        (orderData['buyerInfo'] as Map<String, dynamic>?) ?? {};
    final String custAddress =
        bi['address'] as String? ?? orderData['address'] as String? ?? '';
    final String custPhone =
        bi['custphone'] as String? ?? orderData['custphone'] as String? ?? '';
    final String custEmail =
        bi['custemail'] as String? ?? orderData['custemail'] as String? ?? '';
    final serviceType = orderData['serviceType']?.toString() ?? 'pickup';
    final ecomStatus = orderData['status']?.toString() ?? '';
    final bool isEcomActive =
        serviceType == 'ecommerce' &&
        (ecomStatus == 'paid' ||
            ecomStatus == 'preparing' ||
            ecomStatus == 'shipped');
    if (items.isEmpty && !isEcomActive) return const SizedBox.shrink();
    final timestamp = orderData['timestamp'] as Timestamp? ?? Timestamp.now();
    final totalPrice = (orderData['totalPrice'] as num?)?.toDouble() ?? 0.0;
    final shippingCharge =
        (orderData['shippingCharge'] as num?)?.toDouble() ?? 0.0;
    final double vendorEarnings =
        (orderData['vendorEarnings'] as num?)?.toDouble() ?? 0.0;
    final subTotal = serviceType == 'delivery'
        ? vendorEarnings > 0
              ? vendorEarnings / 0.93
              : totalPrice - shippingCharge
        : totalPrice;
    final orderCancelRequested = orderData['orderCancelRequested'] ?? false;
    final pendingCount = items.length;
    final serviceDetails = _getServiceDetails(serviceType, orderDataMap);
    final status = orderData['status']?.toString() ?? 'pending';
    final isCashPending = _isCashPaymentPending(orderDataMap);
    final double originalShippingCharge =
        (orderData['shippingCharge'] as num?)?.toDouble() ?? 0.0;
    final List<Map<String, dynamic>> itemsList = (itemsRaw as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final bool isSelfDeliver = orderData['selfDeliver'] ?? false;
    final bool showSelfDeliverActions =
        isSelfDeliver && serviceType == 'delivery';

    Widget? chatBadge;
    if (widget.unreadCount > 0) {
      chatBadge = Positioned(
        top: 8.h,
        right: 40.w,
        child: CircleAvatar(
          radius: 10.r,
          backgroundColor: Colors.red,
          child: Text(
            '${widget.unreadCount}',
            style: TextStyle(color: Colors.white, fontSize: 10.sp),
          ),
        ),
      );
    }

    Widget? statusBadge;
    if (orderCancelRequested) {
      statusBadge = _buildStatusBadge('ยกเลิกคำสั่งซื้อ', Colors.red);
    } else if (isCashPending) {
      statusBadge = _buildStatusBadge('รอชำระ', Colors.deepOrange);
    } else if (status == 'pending_rider') {
      statusBadge = _buildStatusBadge('Rider', Colors.orange.shade400);
    } else if (isSelfDeliver || status == 'self_delivering') {
      statusBadge = _buildStatusBadge('ร้านส่งเอง', Colors.blue);
    } else if (status == 'pending' &&
        serviceType == 'delivery' &&
        !widget.timerOrderIds.contains(orderId)) {
      statusBadge = _buildRetryAssignBadge(
        orderId,
        vendorLat,
        vendorLng,
        shippingCharge,
        subTotal,
        totalPrice,
      );
    } else if (widget.timerOrderIds.contains(orderId)) {
      statusBadge = _buildSearchingRiderBadge(orderId, totalPrice);
    } else if (status == 'paid' &&
        serviceType == 'delivery' &&
        !isSelfDeliver) {
      statusBadge = _buildSelfDeliverButton(orderId, totalPrice);
    }

    final expansionChildren = [
      if (items.isNotEmpty)
        _buildItemsSection(
          items,
          orderId,
          orderDataMap,
          itemsRaw,
          width,
          isCashPending,
          isSelfDeliver,
        ),
      _buildSummary(
        subTotal,
        shippingCharge,
        serviceType,
        totalPrice,
        orderId,
        itemsList,
        originalShippingCharge,
        showSelfDeliverActions,
        isCashPending,
        orderDataMap,
      ),
      BuyerDetailsWidget(
        buyerId: buyerId,
        orderData: orderData,
        items: items,
        orderId: orderId,
        unreadCount: widget.unreadCount,
        onMarkRead: (buyerId, proId) =>
            widget.onMarkChatsRead(buyerId: buyerId, proId: proId),
      ),
    ];

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8.h),
      color: Colors.white,
      child: ExpansionTile(
        backgroundColor: Colors.grey.shade100,
        collapsedIconColor: Colors.transparent,
        iconColor: Colors.transparent,
        tilePadding: EdgeInsets.only(left: 8.w, right: 12.w),
        showTrailingIcon: false,
        collapsedBackgroundColor: Colors.white,
        initiallyExpanded: _isExpanded,
        onExpansionChanged: (expanded) {
          _isExpanded = expanded;
          Slidable.of(context)?.close();
        },
        title: Stack(
          children: [
            _buildTitle(
              serviceDetails,
              orderCancelRequested,
              pendingCount,
              totalPrice,
              timestamp,
              orderDataMap,
              serviceType,
              orderId,
              isCashPending: isCashPending,
            ),
            if (statusBadge != null)
              Positioned(top: 38.h, right: 0.w, child: statusBadge),
            if (chatBadge != null) chatBadge,
          ],
        ),
        childrenPadding: EdgeInsets.zero,
        children: expansionChildren,
      ),
    );
  }

  Future<void> _confirmEcommerceOrder(
    String orderId,
    Map<String, dynamic> orderData,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันรับออเดอร์'),
        content: const Text(
          'ยืนยันรับออเดอร์ ecommerce นี้?\nหลังยืนยันจะเตรียมส่งของให้ลูกค้า',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    EasyLoading.show(status: 'กำลังยืนยัน...');
    try {
      final items = List<Map<String, dynamic>>.from(
        (orderData['items'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      for (final item in items) {
        item['accepted'] = true;
      }
      final subtotal = items.fold<double>(
        0.0,
        (acc, item) =>
            acc +
            ((item['price'] as num? ?? 0).toDouble() *
                (item['quantity'] as num? ?? 1).toInt()),
      );
      final double ecomShipping = (orderData['shippingFee'] as num? ?? 0)
          .toDouble();
      final double platformCommission = subtotal * 0.07;
      final double vendorEarnings = subtotal - platformCommission;

      await firestore.collection('orders').doc(orderId).update({
        'status': 'preparing',
        'items': items,
        'totalPrice': subtotal + ecomShipping,
        'vendorEarnings': vendorEarnings,
        'platformCommission': platformCommission,
        'preparingStartedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.showSuccess('ยืนยันรับออเดอร์แล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _handleShipped(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final vendorDoc = await FirebaseFirestore.instance
        .collection('vendors')
        .doc(uid)
        .get();
    final carrier = (vendorDoc.data()?['defaultCarrier'] as String?) ?? 'Kerry';

    if (carrier.isEmpty) {
      Fluttertoast.showToast(msg: 'กรุณาตั้งค่าขนส่งใน Settings ก่อน');
      return;
    }

    final trackingController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการส่งของ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      color: Colors.blue[800],
                      size: 18.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'ขนส่ง: $carrier',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[900],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: trackingController,
                decoration: const InputDecoration(
                  labelText: 'หมายเลขพัสดุ (Tracking)',
                  hintText: 'เช่น TH1234567890',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              if (trackingController.text.trim().isEmpty) {
                Fluttertoast.showToast(msg: 'กรุณากรอกหมายเลขพัสดุ');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text(
              'ยืนยันส่งแล้ว',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result != true) return;

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await firestore.collection('orders').doc(orderId).update({
        'status': 'shipped',
        'shippedAt': FieldValue.serverTimestamp(),
        'trackingNumber': trackingController.text.trim(),
        'shippingCarrier': carrier,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.showSuccess('บันทึกการส่งแล้ว');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Widget _buildStatusBadge(String text, Color color) => Text(
    text,
    style: styles(fontSize: 12.sp, color: color, fontWeight: FontWeight.bold),
  );

  Widget _buildSelfDeliverButton(String orderId, double totalPrice) {
    return GestureDetector(
      onTap: () {
        widget.onStopTimer(orderId);
        Future.microtask(
          () => widget.onVendorSelfDeliver(orderId, totalPrice, 0.0),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 16.sp, color: Colors.white),
            SizedBox(width: 4.w),
            Text(
              'ร้านส่งเอง',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingRiderBadge(String orderId, double totalPrice) {
    final retryCount = widget.orderRetryCount[orderId] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10.sp,
                  height: 10.sp,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4.w),
                Text(
                  'กำลังหาไรเดอร์...',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              'ลองใหม่ ${_secondsLeft}s (${retryCount + 1}/10)',
              style: TextStyle(fontSize: 9.sp, color: Colors.orange),
            ),
          ],
        ),
        SizedBox(width: 4.w),
        GestureDetector(
          onTap: () {
            widget.onStopTimer(orderId);
            Future.microtask(
              () => widget.onVendorSelfDeliver(orderId, totalPrice, 0.0),
            );
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              'ร้านส่งเอง',
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRetryAssignBadge(
    String orderId,
    double vendorLat,
    double vendorLng,
    double shippingCharge,
    double subTotal,
    double totalPrice,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Future.microtask(
            () => widget.onAssignRider(
              orderId,
              vendorLat,
              vendorLng,
              shippingCharge,
              subTotal,
            ),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              'ส่งต่อ Rider อีกครั้ง',
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(width: 6.w),
        GestureDetector(
          onTap: () => Future.microtask(
            () => widget.onVendorSelfDeliver(orderId, totalPrice, 0),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              'ร้านส่งเอง',
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSection(
    List<Map<String, dynamic>> items,
    String orderId,
    Map<String, dynamic> orderDataMap,
    List itemsRaw,
    double width,
    bool isCashPending,
    bool isSelfDeliver,
  ) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    child: Column(
      children: items.asMap().entries.map((e) {
        final item = e.value;
        final int rawIndex = item['__rawIndex'] as int;
        return PreparInfoWidget(
          item: item,
          orderId: orderId,
          orderData: orderDataMap,
          itemsRaw: itemsRaw,
          uiIndex: e.key,
          width: width,
          isCashPaymentPending: isCashPending,
          isSelfDeliver: isSelfDeliver,
          showCheckbox: true,
          value: _selectedToCancel.contains(rawIndex),
          onCheckbox: (val) {
            setState(() {
              if (val ?? false) {
                _selectedToCancel.add(rawIndex);
              } else {
                _selectedToCancel.remove(rawIndex);
              }
            });
          },
          onOrderFullyAccepted: () {},
        );
      }).toList(),
    ),
  );

  Widget _buildTitle(
    ({IconData icon, Color color, String label}) serviceDetails,
    bool orderCancelRequested,
    int pendingCount,
    double totalPrice,
    Timestamp timestamp,
    Map<String, dynamic> orderData,
    String serviceType,
    String orderId, {

    required bool isCashPending,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: 12.w),
        child: Text(
          orderId,
          style: styles(
            fontSize: 12.sp,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        serviceDetails.icon,
                        size: 24.w,
                        color: serviceDetails.color,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        serviceDetails.label,
                        style: styles(
                          fontSize: 12.sp,
                          color: serviceDetails.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '$pendingCount รายการ',
                    style: styles(fontSize: 12.sp, color: Colors.black54),
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Text(
                        '฿${totalPrice.toStringAsFixed(2)}',
                        style: styles(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      Spacer(),
                      Text(
                        DateFormat(
                          'dd/MM/yy - kk:mm',
                        ).format(timestamp.toDate()),
                        style: styles(
                          fontSize: 11.sp,
                          color: Colors.grey,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  if (serviceType == 'ecommerce' &&
                      orderData['orderDistance'] != null) ...[
                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13.sp,
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'ระยะ: ${(orderData['orderDistance'] as num).toStringAsFixed(1)} กม.',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildSummary(
    double subTotal,
    double shippingCharge,
    String serviceType,
    double totalPrice,
    String orderId,
    List<Map<String, dynamic>> itemsList,
    double originalShippingCharge,
    bool isSelfDeliver,
    bool isCashPending,
    Map<String, dynamic> orderDataMap,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ยอดรวมสินค้า',
                style: styles(fontSize: 14.sp, color: Colors.black54),
              ),
              Text(
                '฿${subTotal.toStringAsFixed(2)}',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          if (serviceType == 'delivery') ...[
            SizedBox(height: 4.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ค่าส่ง',
                  style: styles(fontSize: 14.sp, color: Colors.cyan),
                ),
                Text(
                  '฿${shippingCharge.toStringAsFixed(2)}',
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.cyan,
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: 16.h),
          if (serviceType == 'ecommerce') ...[
            Builder(
              builder: (context) {
                final eStatus = orderDataMap['status']?.toString() ?? '';
                if (eStatus == 'paid') {
                  return Center(
                    child: SizedBox(
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                        ),
                        label: Text(
                          'รับออเดอร์',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: EdgeInsets.symmetric(
                            vertical: 2.h,
                            horizontal: 10.w,
                          ),
                        ),
                        onPressed: () =>
                            _confirmEcommerceOrder(orderId, orderDataMap),
                      ),
                    ),
                  );
                }
                if (eStatus == 'preparing') {
                  return Center(
                    child: SizedBox(
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.local_shipping,
                          color: Colors.white,
                        ),
                        label: Text(
                          'ส่งแล้ว',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: EdgeInsets.symmetric(
                            vertical: 2.h,
                            horizontal: 10.w,
                          ),
                        ),
                        onPressed: () => _handleShipped(orderId),
                      ),
                    ),
                  );
                } else if (eStatus == 'shipped') {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_shipping,
                              color: Colors.orange[800],
                              size: 16.sp,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              'ส่งแล้ว — รอลูกค้ายืนยัน',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                          ],
                        ),
                        if ((orderDataMap['trackingNumber'] as String?)
                                ?.isNotEmpty ??
                            false) ...[
                          SizedBox(height: 4.h),
                          Text(
                            'พัสดุ: ${orderDataMap['shippingCarrier'] ?? '-'} | ${orderDataMap['trackingNumber']}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: Colors.orange[800],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _selectedToCancel.isEmpty
                    ? InkWell(
                        onTap: () => _cancelSelectedItems(orderId),
                        child: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: Colors.red,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 26.r,
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: () => _cancelSelectedItems(orderId),
                        child: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: Colors.red,
                          child: Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                if (isCashPending)
                  InkWell(
                    onTap: () => _notifyCustomerReady(orderId, orderDataMap),
                    child: CircleAvatar(
                      radius: 20.r,
                      backgroundColor: Colors.orange,
                      child: Icon(
                        Icons.notifications_active,
                        color: Colors.white,
                        size: 26.sp,
                      ),
                    ),
                  ),
                isCashPending
                    ? InkWell(
                        onTap: () => CashPaymentHelper.showCashPaymentDialog(
                          context,
                          orderId,
                          orderDataMap,
                          totalPrice,
                        ),
                        child: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: Colors.amber,
                          child: Icon(
                            Icons.calculate,
                            color: Colors.white,
                            size: 26.sp,
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: serviceType == 'delivery' && !isSelfDeliver
                            ? () {
                                final Map<String, dynamic> vi =
                                    (orderDataMap['vendorInfo']
                                        as Map<String, dynamic>?) ??
                                    {};
                                final GeoPoint? vGeo =
                                    vi['vendorLocation'] as GeoPoint? ??
                                    orderDataMap['vendorLocation'] as GeoPoint?;
                                widget.onMarkReady(
                                  orderId,
                                  itemsList,
                                  vGeo?.latitude ?? 0.0,
                                  vGeo?.longitude ?? 0.0,
                                  shippingCharge,
                                  subTotal,
                                );
                              }
                            : () async => await widget.onCompleteSelfDeliver(
                                orderId,
                                itemsList,
                                serviceType,
                                originalShippingCharge,
                              ),
                        child: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: Colors.green,
                          child: Icon(
                            serviceType == 'delivery' && !isSelfDeliver
                                ? Icons.delivery_dining
                                : Icons.check_box_outlined,
                            color: Colors.white,
                            size: 26.sp,
                          ),
                        ),
                      ),
                isSelfDeliver && serviceType == 'delivery'
                    ? InkWell(
                        onTap: () => _selfDeliveryNavigationDialog(
                          context,
                          orderDataMap,
                        ),
                        child: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: Colors.blue,
                          child: Icon(
                            Icons.navigation_outlined,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _notifyCustomerReady(
    String orderId,
    Map<String, dynamic> orderData,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'แจ้งลูกค้า',
          style: styles(fontSize: 18.sp, fontWeight: FontWeight.bold),
        ),
        content: Text('แจ้งลูกค้าว่าอาหารพร้อมแล้ว รอชำระเงิน?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('แจ้งเลย', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    EasyLoading.show(status: 'กำลังแจ้งลูกค้า...');
    try {
      await firestore.collection('orders').doc(orderId).update({
        'notifyCustomerReady': true,
        'notifyCustomerReadyAt': FieldValue.serverTimestamp(),
      });
      Fluttertoast.showToast(msg: 'แจ้งลูกค้าแล้ว 🔔');
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'แจ้งล้มเหลว: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _selfDeliveryNavigationDialog(
    BuildContext ctx,
    Map<String, dynamic> orderData,
  ) async {
    if (!mounted) return;
    final Map<String, dynamic> biNav =
        (orderData['buyerInfo'] as Map<String, dynamic>?) ?? {};
    final String address =
        biNav['address']?.toString() ??
        orderData['address']?.toString() ??
        'ไม่ระบุที่อยู่';
    final GeoPoint? location = orderData['customerLocation'] as GeoPoint?;
    final bool? confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'พร้อมส่ง! 🚚',
          textAlign: TextAlign.center,
          style: styles(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: Colors.green,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 12.h),
            Text(
              'ที่อยู่ลูกค้า:\n$address',
              style: styles(fontWeight: FontWeight.w500, fontSize: 16.sp),
            ),
            SizedBox(height: 40.h),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'ไม่ใช่ตอนนี้',
              style: styles(fontSize: 14.sp, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(width: 8.w),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ไปส่งลูกค้า',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final Uri mapsUrl = location != null
          ? Uri.parse(
              'geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}',
            )
          : Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
            );
      await launchUrl(mapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _cancelSelectedItems(String orderId) async {
    if (_selectedToCancel.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'ยกเลิกทั้งออร์เดอร์',
            style: styles(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: const Text(
            'คุณไม่ได้เลือกรายการใดเลย\n\nต้องการยกเลิกออร์เดอร์ทั้งหมดใช่หรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ไม่'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'ยกเลิกทั้งหมด',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _vendorCancelOrder(orderId);
      }
      return;
    }

    final selectedCount = _selectedToCancel.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ยืนยันยกเลิก',
          style: styles(fontSize: 18.sp, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'คุณเลือก $selectedCount รายการ\nต้องการยกเลิกเฉพาะรายการที่เลือกใช่หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ยกเลิก $selectedCount รายการ',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    EasyLoading.show(status: 'กำลังยกเลิกรายการ...');
    try {
      final selectedIndexes = Set<int>.from(_selectedToCancel);
      await firestore.runTransaction((tx) async {
        final orderRef = firestore.collection('orders').doc(orderId);
        final snap = await tx.get(orderRef);
        if (!snap.exists) throw Exception('ไม่พบออร์เดอร์');
        final data = snap.data() as Map<String, dynamic>;
        final List<Map<String, dynamic>> itemsList =
            List<Map<String, dynamic>>.from(data['items'] ?? []);
        for (int idx in selectedIndexes) {
          if (idx < itemsList.length) {
            final item = Map<String, dynamic>.from(itemsList[idx]);
            if (!(item['accepted'] ?? false) && !(item['cancelled'] ?? false)) {
              item['cancelled'] = true;
              itemsList[idx] = item;
            }
          }
        }
        final serviceType = data['serviceType']?.toString() ?? 'pickup';
        final originalShipping =
            (data['shippingCharge'] as num?)?.toDouble() ?? 0.0;
        final (pendingSub, _, _, acceptedSub, _, _) = _calcTotals(
          itemsList,
          serviceType,
        );
        final newTotal = pendingSub + acceptedSub + originalShipping;
        final bool hasPendingLeft = itemsList.any(
          (i) => !(i['accepted'] ?? false) && !(i['cancelled'] ?? false),
        );
        final bool hasAcceptedItems = itemsList.any(
          (i) => (i['accepted'] ?? false) && !(i['cancelled'] ?? false),
        );
        final newStatus = !hasPendingLeft
            ? (hasAcceptedItems ? 'delivered' : 'cancelled')
            : 'preparing';
        tx.update(orderRef, {
          'items': itemsList,
          'totalPrice': newTotal,
          'status': newStatus,
        });
      });
      setState(() => _selectedToCancel.clear());
      widget.onCleanup(orderId);
      Fluttertoast.showToast(
        msg: 'ยกเลิกรายการสำเร็จ ✅',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'เกิดข้อผิดพลาด: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _vendorCancelOrder(String orderId) async {
    EasyLoading.show(status: 'กำลังยกเลิกคำสั่งซื้อ...');
    try {
      await _updateOrderCancel(orderId, isApprove: false);
      setState(() => _selectedToCancel.clear());
      widget.onCleanup(orderId);
      Fluttertoast.showToast(
        msg: 'ยกเลิกคำสั่งซื้อโดยผู้ขายแล้ว',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'ยกเลิกคำสั่งซื้อล้มเหลว: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _updateOrderCancel(
    String orderId, {
    required bool isApprove,
  }) async {
    await firestore.runTransaction((tx) async {
      final docRef = firestore.collection('orders').doc(orderId);
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final data = snap.data() as Map;
      final itemsList = List.from(data['items'] ?? []);
      final serviceType = data['serviceType']?.toString() ?? 'pickup';
      final originalShippingCharge =
          (data['shippingCharge'] as num?)?.toDouble() ?? 0.0;
      for (int i = 0; i < itemsList.length; i++) {
        final it = Map<String, dynamic>.from(itemsList[i]);
        if (!(it['accepted'] ?? false) && !(it['cancelled'] ?? false)) {
          it['cancelled'] = true;
          if (isApprove) it['cancelRequested'] = false;
          itemsList[i] = it;
        }
      }
      final (
        pendingSubTotal,
        pendingItemCount,
        _,
        acceptedSubTotal,
        acceptedItemCount,
        _,
      ) = _calcTotals(
        itemsList,
        serviceType,
      );
      final newTotal =
          pendingSubTotal + acceptedSubTotal + originalShippingCharge;
      Map<String, dynamic> updates = {
        'items': itemsList,
        'totalPrice': newTotal,
      };
      if (isApprove) updates['orderCancelRequested'] = false;
      if (pendingItemCount == 0) {
        if (acceptedItemCount > 0) {
          updates['status'] = 'delivered';
          updates['deliveredAt'] = FieldValue.serverTimestamp();
          updates['totalPrice'] = acceptedSubTotal + originalShippingCharge;
        } else {
          updates['status'] = 'cancelled';
          updates['totalPrice'] = 0.0;
          if (serviceType == 'delivery') {
            updates['riderId'] = null;
            updates['cancelledAt'] = FieldValue.serverTimestamp();
            updates['cancelledBy'] = 'vendor';
          }
        }
      } else {
        updates['status'] = 'pending';
      }
      tx.update(docRef, updates);
    });
  }
}
