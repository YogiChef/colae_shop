// lib/services/cash_payment_helper.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/services.dart';
import 'package:colae_shop/services/sevice.dart';

class CashPaymentHelper {
  static Future<void> showCashPaymentDialog(
    BuildContext context,
    String orderId,
    Map<String, dynamic> orderData,
    double totalPrice, {
    VoidCallback? onSuccess,
  }) async {
    final controller = TextEditingController();
    double? receivedAmount;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'ชำระเงินสด',
              style: styles(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ยอดที่ต้องชำระ: ฿${totalPrice.toStringAsFixed(2)}',
                  style: styles(fontSize: 16.sp, color: Colors.deepOrange),
                ),
                SizedBox(height: 24.h),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'ลูกค้าให้เงินมา',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    hintText: 'เช่น 500',
                  ),
                  onChanged: (val) =>
                      setState(() => receivedAmount = double.tryParse(val)),
                ),
                if (receivedAmount != null && receivedAmount! >= totalPrice)
                  Padding(
                    padding: EdgeInsets.only(top: 16.h),
                    child: Text(
                      'เงินทอน: ฿${(receivedAmount! - totalPrice).toStringAsFixed(2)}',
                      style: styles(
                        color: Colors.green,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (receivedAmount != null && receivedAmount! < totalPrice)
                  Text('เงินไม่พอ', style: styles(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed:
                    (receivedAmount == null || receivedAmount! < totalPrice)
                    ? null
                    : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                child: Text(
                  'ยืนยัน',
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result != true || !context.mounted) return;

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
    EasyLoading.show(status: 'กำลังบันทึก...');

    try {
      final itemsList = List<Map<String, dynamic>>.from(
        orderData['items'] ?? [],
      );
      final serviceType = orderData['serviceType']?.toString() ?? 'pickup';
      final originalShippingCharge =
          (orderData['shippingCharge'] as num?)?.toDouble() ?? 0.0;
      final buyerId = orderData['buyerId']?.toString() ?? '';

      final List<DocumentReference> prodRefs = [];
      final List<int> quantities = [];

      for (var rawItem in itemsList) {
        final item = Map<String, dynamic>.from(rawItem);
        if (!(item['accepted'] ?? false) && !(item['cancelled'] ?? false)) {
          item['accepted'] = true;
          final proId = item['proId']?.toString() ?? '';
          final iQty = (item['quantity'] as num?)?.toInt() ?? 1;
          if (proId.isNotEmpty) {
            prodRefs.add(firestore.collection('products').doc(proId));
            quantities.add(iQty);
          }
        }
      }

      double foodTotal = 0.0;
      for (var item in itemsList) {
        if (item['cancelled'] ?? false) continue;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final extra = (item['extraPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        foodTotal += (price + extra) * qty;
      }
      double vendorEarnings = foodTotal;
      if (serviceType != 'delivery') vendorEarnings += originalShippingCharge;
      final newTotal = foodTotal + originalShippingCharge;

      final orderRef = firestore.collection('orders').doc(orderId);
      final batch = firestore.batch();

      for (int i = 0; i < prodRefs.length; i++) {
        batch.update(prodRefs[i], {
          'pqty': FieldValue.increment(-quantities[i]),
        });
      }

      batch.update(orderRef, {
        'items': itemsList,
        'totalPrice': newTotal,
        'status': 'delivered',
        'slipStatus': 'paid_cash',
        'deliveredAt': FieldValue.serverTimestamp(),
        'vendorEarnings': vendorEarnings,
      });

      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await batch.commit();

      if (buyerId.isNotEmpty) {
        firestore
            .collection('buyers')
            .doc(buyerId)
            .collection('notifications')
            .add({
              'type': 'order_delivered',
              'orderId': orderId,
              'timestamp': FieldValue.serverTimestamp(),
              'read': false,
            });
      }

      // TODO: chat deletion handled by Cloud Function onOrderDelivered
      Fluttertoast.showToast(msg: 'ชำระเงินสดเรียบร้อย');
      onSuccess?.call();
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'ชำระเงินล้มเหลว: $e',
        backgroundColor: Colors.red,
      );
    } finally {
      EasyLoading.dismiss();
    }
  }
}
