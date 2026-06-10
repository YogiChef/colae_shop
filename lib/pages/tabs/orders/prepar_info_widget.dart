// ignore_for_file: avoid_print, use_build_context_synchronously, dead_code, no_leading_underscores_for_local_identifiers, unnecessary_to_list_in_spreads

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:colae_shop/services/cash_payment.dart';
import 'package:colae_shop/services/sevice.dart';

class PreparInfoWidget extends StatefulWidget {
  final Map<String, dynamic> item;
  final String orderId;
  final Map<String, dynamic> orderData;
  final List itemsRaw;
  final int uiIndex;
  final double width;
  final bool isCashPaymentPending;
  final bool isSelfDeliver;
  final VoidCallback? onOrderFullyAccepted;
  final bool showCheckbox;
  final Function(bool?)? onCheckbox;
  final bool value;

  const PreparInfoWidget({
    super.key,
    required this.item,
    required this.orderId,
    required this.orderData,
    required this.itemsRaw,
    required this.uiIndex,
    required this.width,
    required this.isCashPaymentPending,
    required this.isSelfDeliver,
    this.onOrderFullyAccepted,
    this.showCheckbox = false,
    this.onCheckbox,
    required this.value,
  });

  @override
  State<PreparInfoWidget> createState() => _PreparInfoWidgetState();
}

class _PreparInfoWidgetState extends State<PreparInfoWidget>
    with TickerProviderStateMixin {
  late SlidableController _slidableController;
  bool _triggered = false;

  late int rawIndex;
  late bool itemCancelRequested;
  late String proName;

  @override
  void initState() {
    super.initState();
    _updateItemData();

    _slidableController = SlidableController(this);
    _slidableController.animation.addStatusListener(_onAnimationStatusChanged);
  }

  @override
  void didUpdateWidget(covariant PreparInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _updateItemData();
    }
  }

  void _updateItemData() {
    final dynamic rawIndexRaw = widget.item['__rawIndex'];
    rawIndex = (rawIndexRaw is int) ? rawIndexRaw : widget.uiIndex;
    if (rawIndex < 0) {
      rawIndex = widget.uiIndex;
    }
    itemCancelRequested = widget.item['cancelRequested'] ?? false;
    proName = widget.item['proName']?.toString() ?? '';
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _slidableController.ratio >= 0.5 &&
        !_triggered) {
      _triggered = true;

      final currentProductImage =
          (widget.item['imageUrl'] as List?)?.isNotEmpty == true
          ? widget.item['imageUrl'].first.toString()
          : '';

      _showActionDialog(
        context,
        rawIndex,
        itemCancelRequested,
        proName,
        widget.orderId,
        currentProductImage,
      );
      _slidableController.close();
    } else if (status == AnimationStatus.dismissed) {
      _triggered = false;
    }
  }

  @override
  void dispose() {
    _slidableController.animation.removeStatusListener(
      _onAnimationStatusChanged,
    );
    _slidableController.dispose();
    super.dispose();
  }

  bool _isCashPaymentRequired() => widget.isCashPaymentPending;

  Future<void> _showActionDialog(
    BuildContext context,
    int rawIndex,
    bool itemCancelRequested,
    String proName,
    String orderId,
    String productImage,
  ) async {
    if (!mounted) return;

    double totalPrice = 0.0;
    for (final it in widget.itemsRaw) {
      if (it is Map && !(it['cancelled'] ?? false)) {
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        final extra = (it['extraPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        totalPrice += (price + extra) * qty;
      }
    }

    List<Map<String, dynamic>> buttonConfigs = [];
    if (itemCancelRequested) {
      buttonConfigs = [
        {
          'label': 'อนุมัติยกเลิก',
          'value': 'approve_cancel',
          'color': Colors.red,
        },
        {'label': 'รับสินค้า', 'value': 'accept', 'color': Colors.green},
      ];
    } else {
      buttonConfigs = [
        {'label': 'ยืนยัน', 'value': 'confirm', 'color': Colors.green},
        {
          'label': 'ยกเลิกสินค้า',
          'value': 'cancel_item',
          'color': Colors.deepOrange,
        },
      ];
    }

    String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(29.r),
          ),
          title: Text(
            itemCancelRequested ? 'ขอยกเลิก $proName' : proName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: styles(
              fontSize: 16.sp,
              color: mainColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              children: [
                ...buttonConfigs.map((config) {
                  return IconButton(
                    iconSize: 32.sp,
                    onPressed: () =>
                        Navigator.of(context).pop(config['value'] as String),

                    icon: Icon(
                      config['value'] == 'accept' ||
                              config['value'] == 'confirm'
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      color: config['color'] as Color,
                    ),
                  );
                }).toList(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('nothing'),
                  child: Text(
                    'ปิด',
                    style: styles(color: Colors.grey, fontSize: 14.sp),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (result == null || result == 'nothing') return;

    EasyLoading.show(status: 'กำลังดำเนินการ...');

    try {
      if (result == 'confirm' || result == 'accept') {
        final bool isCashRequired = _isCashPaymentRequired();
        if (isCashRequired) {
          EasyLoading.dismiss();
          await CashPaymentHelper.showCashPaymentDialog(
            context,
            orderId,
            widget.orderData,
            totalPrice,
            onSuccess: () {
              if (mounted) setState(() {});
            },
          );

          final stillRequired = _isCashPaymentRequired();
          if (stillRequired) {
            EasyLoading.dismiss();
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('ยังไม่ชำระเงินสด'),
                content: const Text(
                  'ต้องการยืนยันสินค้าต่อหรือไม่?\n(สามารถเก็บเงินตอนรับสินค้า)',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('ยกเลิก'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ยืนยันสินค้า'),
                  ),
                ],
              ),
            );
            if (confirm != true) {
              EasyLoading.dismiss();
              return;
            }
          }
          EasyLoading.show(status: 'กำลังยืนยันสินค้า...');
        }

        await _handleAccept(orderId, rawIndex, proName);
        Fluttertoast.showToast(msg: 'ยืนยันสินค้าสำเร็จ');
      } else if (result == 'approve_cancel') {
        await _handleApproveCancel(orderId, rawIndex, proName);
        Fluttertoast.showToast(msg: 'อนุมัติยกเลิก "$proName" สำเร็จ');
      } else if (result == 'cancel_item') {
        await _handleCancel(orderId, rawIndex, proName);
        Fluttertoast.showToast(msg: 'ยกเลิกสินค้า "$proName" สำเร็จ');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'เกิดข้อผิดพลาด: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _handleAccept(
    String orderId,
    int rawIndex,
    String proName,
  ) async {
    final items = List.from(widget.itemsRaw);

    if (rawIndex >= 0 || rawIndex >= widget.itemsRaw.length) {
      items[rawIndex]['accepted'] = true;
      final pendingItems = items
          .where(
            (it) => !(it['accepted'] ?? false) && !(it['cancelled'] ?? false),
          )
          .length;

      if (pendingItems == 0) {
        setState(() {});
        if (widget.onOrderFullyAccepted != null) {
          widget.onOrderFullyAccepted!();
        }
      }
    }

    bool orderDelivered = false;

    try {
      await firestore.runTransaction((tx) async {
        orderDelivered = await _processAccept(tx, orderId, rawIndex);
      });
      Fluttertoast.showToast(
        msg: orderDelivered
            ? 'ส่งมอบสำเร็จ! ออร์เดอร์หายจากรายการแล้ว'
            : 'ยืนยันรายการเรียบร้อย (พร้อมส่ง rider)',
        backgroundColor: orderDelivered ? Colors.green : Colors.blue,
        toastLength: Toast.LENGTH_LONG,
      );

      final updatedSnap = await firestore
          .collection('orders')
          .doc(orderId)
          .get();
      if (updatedSnap.exists && mounted) {
        final updatedData = updatedSnap.data() as Map<String, dynamic>;

        final bool isSelfDeliver = updatedData['selfDeliver'] ?? false;
        final itemsList = List<Map<String, dynamic>>.from(
          updatedData['items'] ?? [],
        );
        final int pendingCount = itemsList
            .where(
              (it) => !(it['accepted'] ?? false) && !(it['cancelled'] ?? false),
            )
            .length;

        if (pendingCount == 0 && isSelfDeliver) {
          await _launchNavigationToCustomer(updatedData);
        }
      }
    } catch (e, _) {
      Fluttertoast.showToast(
        msg: 'เกิดข้อผิดพลาด: $e',
        backgroundColor: Colors.red,
        toastLength: Toast.LENGTH_LONG,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _launchNavigationToCustomer(
    Map<String, dynamic> orderData,
  ) async {
    final Map<String, dynamic> bi =
        (orderData['buyerInfo'] as Map<String, dynamic>?) ?? {};
    final String address =
        bi['address']?.toString() ??
        orderData['address']?.toString() ??
        'ไม่ระบุที่อยู่';
    final GeoPoint? location = orderData['customerLocation'] as GeoPoint?;

    Uri url;

    if (location != null) {
      url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${location.latitude},${location.longitude}&travelmode=driving',
      );
    } else {
      url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
      );
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      Fluttertoast.showToast(msg: 'กำลังนำทางไปหาลูกค้า...');
    } else {
      Fluttertoast.showToast(msg: 'ไม่สามารถเปิด Google Maps ได้');
    }
  }

  Future<void> _handleApproveCancel(
    String orderId,
    int rawIndex,
    String proName,
  ) async {
    if (rawIndex < 0 || rawIndex >= widget.itemsRaw.length) {
      Fluttertoast.showToast(msg: 'Invalid item index: $rawIndex');
      return;
    }
    EasyLoading.show(status: 'Approving cancel...');
    try {
      await _processCancel(orderId, rawIndex, isApprove: true);
      Fluttertoast.showToast(
        msg: 'Item cancel approved',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Approve cancel failed: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<void> _handleCancel(
    String orderId,
    int rawIndex,
    String proName,
  ) async {
    if (rawIndex < 0 || rawIndex >= widget.itemsRaw.length) {
      Fluttertoast.showToast(msg: 'Invalid item index: $rawIndex');
      return;
    }
    EasyLoading.show(status: 'Cancelling item...');
    try {
      await _processCancel(orderId, rawIndex, isApprove: false);
      Fluttertoast.showToast(
        msg: 'Item cancelled by vendor',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Cancel failed: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }

  Future<bool> _processAccept(
    Transaction tx,
    String orderId,
    int rawIndex,
  ) async {
    final docRef = firestore.collection('orders').doc(orderId);
    final snap = await tx.get(docRef);
    if (!snap.exists) throw Exception('Order not found');

    final data = snap.data() as Map;
    final itemsList = List.from(data['items'] ?? []);
    final serviceType = data['serviceType']?.toString() ?? 'pickup';

    bool _orderDeliveredInTransaction = false;

    if (rawIndex >= 0 && rawIndex < itemsList.length) {
      final targetItem = Map<String, dynamic>.from(itemsList[rawIndex]);
      targetItem['cancelRequested'] = false;
      targetItem['accepted'] = true;
      itemsList[rawIndex] = targetItem;

      final proId = targetItem['proId']?.toString() ?? '';
      final iQty = (targetItem['quantity'] as num?)?.toInt() ?? 1;
      if (proId.isNotEmpty) {
        final prodRef = FirebaseFirestore.instance
            .collection('products')
            .doc(proId);
        final prodSnap = await tx.get(prodRef);
        if (prodSnap.exists) {
          final pqty = (prodSnap.data()?['pqty'] as num? ?? 0).toInt();
          if (pqty < iQty) throw Exception('Insufficient stock');
          tx.update(prodRef, {'pqty': pqty - iQty});
        }
      }

      final (
        pendingSubTotal,
        pendingItemCount,
        pendingQuantity,
        acceptedSubTotal,
        acceptedItemCount,
        acceptedQuantity,
      ) = _calcTotals(
        itemsList,
        serviceType,
      );

      final double currentFoodTotal = pendingSubTotal + acceptedSubTotal;
      final double subsidy = currentFoodTotal * 0.07;
      final double customerShipping = (15.0 - subsidy).clamp(0.0, 15.0);
      final double newTotal = currentFoodTotal + customerShipping;

      final approveTime = Timestamp.now();
      final updates = {'items': itemsList, 'totalPrice': newTotal};
      if (acceptedItemCount > 0) {
        updates['readyForPickup'] = true;
        updates['preparedAt'] = approveTime;
      }
      if (pendingItemCount == 0) {
        if (acceptedItemCount > 0) {
          if (serviceType == 'pickup' || serviceType == 'dine-in') {
            updates['status'] = 'delivered';
            updates['totalPrice'] = acceptedSubTotal;
            updates['vendorEarnings'] = acceptedSubTotal;
            updates['platformCommission'] = 0.0;
            updates['riderEarnings'] = 0.0;
            updates['shippingCharge'] = 0.0;
            updates['deliveredAt'] = approveTime;
            _orderDeliveredInTransaction = true;
          } else if (serviceType == 'ecommerce') {
            // ecommerce: ยืนยันครบ → preparing (รอ vendor แพ็คและส่งของ)
            final double ecomShipping =
                (data['shippingFee'] as num? ?? 0).toDouble();
            final double ecomSubsidy = acceptedSubTotal * 0.07;
            updates['status'] = 'preparing';
            updates['totalPrice'] = acceptedSubTotal + ecomShipping;
            updates['vendorEarnings'] = acceptedSubTotal - ecomSubsidy;
            updates['platformCommission'] = ecomSubsidy;
          } else if (serviceType == 'delivery') {
            final bool isSelfDeliver = data['selfDeliver'] ?? false;

            if (isSelfDeliver) {
              updates['status'] = 'delivered';
              updates['deliveredAt'] = approveTime;
              final double sdSubsidy = acceptedSubTotal * 0.07;
              final double sdRiderBase = sdSubsidy.clamp(15.0, 30.0);
              updates['vendorEarnings'] =
                  acceptedSubTotal - sdSubsidy + sdRiderBase;
              updates['riderEarnings'] = 0.0;
              updates['platformCommission'] = (sdSubsidy - 30.0).clamp(
                0.0,
                double.infinity,
              );
            } else {
              updates['status'] = 'pending_rider';
              final double prSubsidy = acceptedSubTotal * 0.07;
              updates['vendorEarnings'] = acceptedSubTotal - prSubsidy;
              updates['platformCommission'] = (prSubsidy - 30.0).clamp(
                0.0,
                double.infinity,
              );
            }
          }
        } else {
          updates['status'] = 'cancelled';
          updates['totalPrice'] = 0.0;
        }
      }

      tx.update(docRef, updates);

      return _orderDeliveredInTransaction;
    }
    throw Exception('Invalid index $rawIndex');
  }

  Future<void> _processCancel(
    String orderId,
    int rawIndex, {
    required bool isApprove,
  }) async {
    await firestore.runTransaction((tx) async {
      final docRef = firestore.collection('orders').doc(orderId);
      final snap = await tx.get(docRef);
      if (!snap.exists) throw Exception('Order not found');

      final data = snap.data() as Map;
      final itemsList = List.from(data['items'] ?? []);
      final serviceType = data['serviceType']?.toString() ?? 'pickup';

      if (rawIndex >= 0 && rawIndex < itemsList.length) {
        final targetItem = Map<String, dynamic>.from(itemsList[rawIndex]);
        targetItem['cancelled'] = true;
        if (isApprove) targetItem['cancelRequested'] = false;
        itemsList[rawIndex] = targetItem;

        final (
          pendingSubTotal,
          pendingItemCount,
          pendingQuantity,
          acceptedSubTotal,
          acceptedItemCount,
          acceptedQuantity,
        ) = _calcTotals(
          itemsList,
          serviceType,
        );

        final double cancelFoodTotal = pendingSubTotal + acceptedSubTotal;
        final double cancelSubsidy = cancelFoodTotal * 0.07;
        final double cancelCustomerShipping = (15.0 - cancelSubsidy).clamp(
          0.0,
          15.0,
        );
        final double newTotal = cancelFoodTotal + cancelCustomerShipping;

        final updates = {'items': itemsList, 'totalPrice': newTotal};

        if (pendingItemCount == 0) {
          if (acceptedItemCount > 0) {
            if (serviceType == 'pickup') {
              updates['status'] = 'delivered';
              final double cancelPickupSubsidy = acceptedSubTotal * 0.07;
              final double cancelPickupShipping = (15.0 - cancelPickupSubsidy)
                  .clamp(0.0, 15.0);
              updates['totalPrice'] = acceptedSubTotal + cancelPickupShipping;
              updates['deliveredAt'] = FieldValue.serverTimestamp();
              updates['vendorEarnings'] =
                  acceptedSubTotal - cancelPickupSubsidy;
              updates['platformCommission'] = (cancelPickupSubsidy - 30.0)
                  .clamp(0.0, double.infinity);
            } else if (serviceType == 'ecommerce') {
              final double ecomShipping =
                  (data['shippingFee'] as num? ?? 0).toDouble();
              final double ecomSubsidy = acceptedSubTotal * 0.07;
              updates['status'] = 'preparing';
              updates['totalPrice'] = acceptedSubTotal + ecomShipping;
              updates['vendorEarnings'] = acceptedSubTotal - ecomSubsidy;
              updates['platformCommission'] = ecomSubsidy;
            } else if (serviceType == 'delivery') {
              final bool isSelfDeliver = data['selfDeliver'] ?? false;
              if (isSelfDeliver) {
                updates['status'] = 'delivered';
                updates['deliveredAt'] = FieldValue.serverTimestamp();
                final double cancelSdSubsidy = acceptedSubTotal * 0.07;
                final double cancelSdShipping = (15.0 - cancelSdSubsidy).clamp(
                  0.0,
                  15.0,
                );
                updates['totalPrice'] = acceptedSubTotal + cancelSdShipping;
                updates['vendorEarnings'] = acceptedSubTotal - cancelSdSubsidy;
                updates['platformCommission'] = (cancelSdSubsidy - 30.0).clamp(
                  0.0,
                  double.infinity,
                );
              } else {
                updates['status'] = 'pending_rider';
                final double cancelPrSubsidy = acceptedSubTotal * 0.07;
                updates['vendorEarnings'] = acceptedSubTotal - cancelPrSubsidy;
                updates['platformCommission'] = (cancelPrSubsidy - 30.0).clamp(
                  0.0,
                  double.infinity,
                );
              }
            }
          } else {
            updates['status'] = 'cancelled';
            updates['totalPrice'] = 0.0;
          }
        } else {
          updates['status'] = 'pending';
        }

        tx.update(docRef, updates);
      } else {
        throw Exception('Invalid index $rawIndex');
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final quantity = (widget.item['quantity'] as num?)?.toInt() ?? 1;
    final price = (widget.item['price'] as num?)?.toDouble() ?? 0.0;
    final optionPrice = (widget.item['extraPrice'] as num?)?.toDouble();
    final extraPrice =
        ((widget.item['extraPrice'] as num?)?.toDouble() ?? 0.0) * quantity;
    final productSize = widget.item['productSize']?.toString() ?? '';
    final selectedOptions = (widget.item['selectedOptions'] ?? [])
        .map((opt) => Map<String, dynamic>.from(opt ?? {}))
        .toList();
    final optionsText = selectedOptions
        .map(
          (opt) =>
              '${opt['name']?.toString()} (+฿${(opt['price'] as num?)?.toDouble() ?? 0})',
        )
        .join(', ');
    final itemSubtotal = price * quantity;

    return Container(
      key: ValueKey(
        '${widget.orderId}-${widget.item['proId'] ?? 'unknown'}-$rawIndex',
      ),
      padding: EdgeInsets.only(left: 16.w, right: 16.w, bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: widget.value,
            onChanged: widget.showCheckbox ? widget.onCheckbox : null,
            activeColor: Colors.green,
            checkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildItemDetails(
                  proName,
                  productSize,
                  optionsText,
                  price,
                  quantity,
                  itemSubtotal,
                  optionPrice,
                  extraPrice,
                  itemCancelRequested,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetails(
    String proName,
    String productSize,
    String optionsText,
    double price,
    int quantity,
    double itemSubtotal,
    double? optionPrice,
    double? extraPrice,
    bool itemCancelRequested,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          proName,
          style: styles(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),

        if (optionsText.isNotEmpty) ...[
          Text(
            optionsText,
            style: styles(fontSize: 12.sp, color: Colors.black45),
          ),
        ],

        Row(
          children: [
            Text(
              '฿${price.toStringAsFixed(2)} x $quantity',
              style: styles(fontSize: 12.sp, color: Colors.black45),
            ),
            const Spacer(),
            Text(
              '= ฿${itemSubtotal.toStringAsFixed(2)}',
              style: styles(
                fontSize: 13.sp,
                color: Colors.deepOrange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (extraPrice != null && extraPrice > 0) ...[
          Row(
            children: [
              Text(
                'Extra: ฿$optionPrice x $quantity',
                style: styles(fontSize: 12.sp, color: Colors.orange),
              ),
              const Spacer(),
              Text(
                '= ฿${extraPrice.toStringAsFixed(2)}',
                style: styles(fontSize: 12.sp, color: Colors.orange),
              ),
            ],
          ),
        ],
        if (itemCancelRequested) ...[
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Row(
              children: [
                Icon(Icons.hourglass_top, size: 20.sp, color: Colors.red),
                SizedBox(width: 4.w),
                Text(
                  'ขอยกเลิกรายการนี้',
                  style: styles(fontSize: 12.sp, color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
