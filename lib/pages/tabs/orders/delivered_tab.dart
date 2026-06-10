// ignore_for_file: unnecessary_to_list_in_spreads

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:colae_shop/services/sevice.dart';

class Delivered extends StatefulWidget {
  const Delivered({super.key});

  @override
  State<Delivered> createState() => _DeliveredState();
}

class _DeliveredState extends State<Delivered>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Stream<QuerySnapshot> _ordersStream;

  @override
  void initState() {
    super.initState();
    _ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
        .where('status', whereIn: ['delivered', 'cancelled'])
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _ordersStream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.only(left: 20.w, right: 20.w),
              child: Text(
                'ยังไม่มีออร์เดอร์ที่เสร็จสิ้นหรือยกเลิก',
                style: styles(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ),
          );
        }

        final allDocs = snapshot.data!.docs;

        final Map<String, List<DocumentSnapshot>> groupedOrders = {};
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          Timestamp ts;
          if (data.containsKey('deliveredAt') &&
              data['deliveredAt'] is Timestamp) {
            ts = data['deliveredAt'] as Timestamp;
          } else if (data.containsKey('timestamp') &&
              data['timestamp'] is Timestamp) {
            ts = data['timestamp'] as Timestamp;
          } else {
            ts = Timestamp.now();
          }
          final dateStr = DateFormat('dd/MM/yyyy').format(ts.toDate());
          groupedOrders.putIfAbsent(dateStr, () => []).add(doc);
        }

        final sortedDates = groupedOrders.keys.toList()
          ..sort(
            (a, b) => DateFormat(
              'dd/MM/yyyy',
            ).parse(b).compareTo(DateFormat('dd/MM/yyyy').parse(a)),
          );

        return ListView.builder(
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final dateKey = sortedDates[index];
            final ordersInThisDate = groupedOrders[dateKey]!;

            ordersInThisDate.sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>? ?? {};
              final dataB = b.data() as Map<String, dynamic>? ?? {};

              Timestamp tsA;
              if (dataA.containsKey('deliveredAt') &&
                  dataA['deliveredAt'] is Timestamp) {
                tsA = dataA['deliveredAt'] as Timestamp;
              } else if (dataA.containsKey('timestamp') &&
                  dataA['timestamp'] is Timestamp) {
                tsA = dataA['timestamp'] as Timestamp;
              } else {
                tsA = Timestamp.now();
              }

              Timestamp tsB;
              if (dataB.containsKey('deliveredAt') &&
                  dataB['deliveredAt'] is Timestamp) {
                tsB = dataB['deliveredAt'] as Timestamp;
              } else if (dataB.containsKey('timestamp') &&
                  dataB['timestamp'] is Timestamp) {
                tsB = dataB['timestamp'] as Timestamp;
              } else {
                tsB = Timestamp.now();
              }

              return tsB.toDate().compareTo(tsA.toDate());
            });

            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    vertical: 16.h,
                    horizontal: 16.w,
                  ),
                  color: Colors.grey.shade300,
                  child: Text(
                    dateKey,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                ...ordersInThisDate.map((document) {
                  final orderData =
                      document.data() as Map<String, dynamic>? ?? {};

                  final String serviceType =
                      orderData['serviceType']?.toString() ?? 'pickup';
                  final String tableId = orderData['tableId']?.toString() ?? '';
                  final String orderId = orderData['orderId']?.toString() ?? '';
                  final bool isDineIn =
                      serviceType == 'dine-in' || tableId.isNotEmpty;
                  final bool isSelfDeliver = orderData['selfDeliver'] ?? false;
                  final double shippingCharge =
                      (orderData['shippingCharge'] as num?)?.toDouble() ?? 0.0;
                  final double riderEarnings =
                      (orderData['riderEarnings'] as num?)?.toDouble() ?? 00;
                  final double vendorEarnings =
                      (orderData['vendorEarnings'] as num?)?.toDouble() ?? 0.0;
                  // totalPrice = foodTotal + customerShipping

                  final Map<String, dynamic> bi =
                      (orderData['buyerInfo'] as Map<String, dynamic>?) ?? {};
                  final String fullName =
                      bi['fullName']?.toString() ??
                      orderData['fullName']?.toString() ??
                      'ไม่ระบุชื่อ';
                  final String phone =
                      bi['custphone']?.toString() ??
                      orderData['custphone']?.toString() ??
                      '';
                  final String email =
                      bi['custemail']?.toString() ??
                      orderData['custemail']?.toString() ??
                      '';
                  final String? buyerImageUrl =
                      bi['buyerImage']?.toString() ??
                      orderData['buyerImage']?.toString();

                  final Map<String, dynamic> vi =
                      (orderData['vendorInfo'] as Map<String, dynamic>?) ?? {};
                  final String vAddress =
                      vi['vaddress'] as String? ??
                      orderData['vaddress'] as String? ??
                      '';
                  final String vSubdistrict =
                      vi['vsubdistrict'] as String? ??
                      orderData['vsubdistrict'] as String? ??
                      '';
                  final String vDistrict =
                      vi['vdistrict'] as String? ??
                      orderData['vdistrict'] as String? ??
                      '';
                  final String vProvince =
                      vi['vprovince'] as String? ??
                      orderData['vprovince'] as String? ??
                      '';
                  final String vZipcode =
                      vi['vzipcode'] as String? ??
                      orderData['vzipcode'] as String? ??
                      '';
                  final String address = [
                    if (vAddress.isNotEmpty) vAddress,
                    if (vSubdistrict.isNotEmpty) 'ต.$vSubdistrict',
                    if (vDistrict.isNotEmpty) 'อ.$vDistrict',
                    if (vProvince.isNotEmpty) 'จ.$vProvince',
                    if (vZipcode.isNotEmpty) vZipcode,
                  ].join(' ');

                  Timestamp timestamp;
                  if (orderData.containsKey('timestamp') &&
                      orderData['timestamp'] is Timestamp) {
                    timestamp = orderData['timestamp'] as Timestamp;
                  } else {
                    timestamp = Timestamp.now();
                  }

                  Timestamp deliveredTime;
                  if (orderData.containsKey('deliveredAt') &&
                      orderData['deliveredAt'] is Timestamp) {
                    deliveredTime = orderData['deliveredAt'] as Timestamp;
                  } else {
                    deliveredTime = timestamp;
                  }

                  IconData serviceIcon = Icons.store;
                  Color serviceColor = Colors.blue.shade900;
                  String serviceLabel = 'รับที่ร้าน';
                  if (isDineIn) {
                    serviceIcon = Icons.table_restaurant;
                    serviceColor = Colors.green.shade500;
                    serviceLabel = tableId.isNotEmpty
                        ? 'โต๊ะ: $tableId'
                        : 'นั่งกินที่ร้าน';
                  } else if (serviceType == 'delivery') {
                    serviceIcon = isSelfDeliver
                        ? Icons.delivery_dining_sharp
                        : Icons.delivery_dining;
                    serviceColor = isSelfDeliver
                        ? Colors.pink.shade700
                        : Colors.amber.shade800;
                    serviceLabel = isSelfDeliver ? 'ร้านส่งเอง' : 'Rider ส่ง';
                  }

                  final List itemsRaw = orderData['items'] ?? [];
                  final List<Map<String, dynamic>> deliveredItems = [];
                  final List<Map<String, dynamic>> cancelledItems = [];
                  double deliveredSubTotal = 0.0;

                  for (var rawItem in itemsRaw) {
                    final item = Map<String, dynamic>.from(rawItem ?? {});
                    final bool isCancelled = item['cancelled'] ?? false;
                    if (!isCancelled) {
                      deliveredItems.add(item);
                      final double price =
                          (item['price'] as num?)?.toDouble() ?? 0.0;
                      final double extraPrice =
                          (item['extraPrice'] as num?)?.toDouble() ?? 0.0;
                      final int quantity =
                          (item['quantity'] as num?)?.toInt() ?? 1;
                      deliveredSubTotal += (price + extraPrice) * quantity;
                    } else {
                      cancelledItems.add(item);
                    }
                  }

                  final double deliveredTotal = vendorEarnings > 0
                      ? vendorEarnings
                      : deliveredSubTotal;

                  if (deliveredItems.isEmpty && cancelledItems.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 1.h),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: 12.w,
                            right: 12.w,
                            top: 12.h,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                orderId,
                                style: styles(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black54,
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        serviceIcon,
                                        size: 32.w,
                                        color: serviceColor,
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        serviceLabel,
                                        style: styles(
                                          fontSize: 13.sp,
                                          color: serviceColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    riderEarnings > 0
                                        ? '฿${riderEarnings.toStringAsFixed(2)}'
                                        : '',
                                    style: styles(
                                      fontSize: riderEarnings > 0
                                          ? 13.sp
                                          : 12.sp,
                                      fontWeight: riderEarnings > 0
                                          ? FontWeight.w600
                                          : FontWeight.w600,
                                      color: riderEarnings > 0
                                          ? Colors.deepOrange.shade900
                                          : Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                deliveredItems.isNotEmpty
                                    ? '${deliveredItems.length} สำเร็จ${cancelledItems.isNotEmpty ? ' (ยกเลิก ${cancelledItems.length})' : ''}'
                                    : 'ยกเลิก ${cancelledItems.length} รายการ',
                                style: styles(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w600,
                                  color: deliveredItems.isNotEmpty
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.symmetric(horizontal: 12.w),
                          showTrailingIcon: false,
                          childrenPadding: EdgeInsets.only(
                            left: 12.w,
                            right: 12.w,
                          ),
                          title: Text(
                            '${DateFormat('HH:mm').format(timestamp.toDate())} → ${DateFormat('HH:mm').format(deliveredTime.toDate())}',
                            style: styles(
                              fontSize: 11.sp,
                              color: Colors.blue.shade900,
                              height: 1,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'สินค้าที่ส่งแล้ว',
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  ...deliveredItems.map<Widget>((item) {
                                    final String proName =
                                        item['proName']?.toString() ??
                                        'ไม่ระบุชื่อสินค้า';

                                    final int quantity =
                                        (item['quantity'] as num?)?.toInt() ??
                                        1;
                                    final double price =
                                        (item['price'] as num?)?.toDouble() ??
                                        0.0;
                                    final double? optionPrice =
                                        (item['extraPrice'] as num?)
                                            ?.toDouble();
                                    final double extraPrice =
                                        (optionPrice ?? 0.0) * quantity;

                                    final double itemSubtotal =
                                        price * quantity;
                                    final List selectedOptionsRaw =
                                        item['selectedOptions'] ?? [];
                                    final String
                                    optionsText = selectedOptionsRaw
                                        .map(
                                          (opt) =>
                                              '${(opt['name'] ?? '')} (+฿${(opt['price'] as num?)?.toDouble() ?? 0})',
                                        )
                                        .join(', ');

                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4.h,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            proName,
                                            style: styles(
                                              fontSize: 13.sp,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.indigo.shade900,
                                            ),
                                          ),
                                          if (optionsText.isNotEmpty)
                                            Text(
                                              optionsText,
                                              style: styles(
                                                fontSize: 12.sp,
                                                color: Colors.black45,
                                              ),
                                            ),

                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '฿${price.toStringAsFixed(2)} x $quantity',
                                                style: styles(
                                                  fontSize: 12.sp,
                                                  color: Colors.black45,
                                                ),
                                              ),
                                              Text(
                                                '= ฿${itemSubtotal.toStringAsFixed(2)}',
                                                style: styles(
                                                  color: Colors.black45,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 12.sp,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (extraPrice > 0) ...[
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Extra: ฿$optionPrice x $quantity',
                                                ),
                                                Text(
                                                  '= ฿${extraPrice.toStringAsFixed(2)}',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                  if (cancelledItems.isNotEmpty) ...[
                                    SizedBox(height: 16.h),
                                    Text(
                                      'รายการที่ถูกยกเลิก',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.red,
                                      ),
                                    ),
                                    SizedBox(height: 8.h),
                                    ...cancelledItems.map<Widget>((item) {
                                      final String proName =
                                          item['proName']?.toString() ??
                                          'ไม่ระบุชื่อสินค้า';
                                      final String productSize =
                                          item['productSize']?.toString() ?? '';
                                      final int quantity =
                                          (item['quantity'] as num?)?.toInt() ??
                                          1;
                                      final double price =
                                          (item['price'] as num?)?.toDouble() ??
                                          0.0;
                                      final double? optionPrice =
                                          (item['extraPrice'] as num?)
                                              ?.toDouble();
                                      final double extraPrice =
                                          (optionPrice ?? 0.0) * quantity;
                                      final double itemSubtotal =
                                          price * quantity;
                                      final List selectedOptionsRaw =
                                          item['selectedOptions'] ?? [];
                                      final String
                                      optionsText = selectedOptionsRaw
                                          .map(
                                            (opt) =>
                                                '${(opt['name'] ?? '')} (+฿${(opt['price'] as num?)?.toDouble() ?? 0})',
                                          )
                                          .join(', ');

                                      final TextStyle cancelledStyle = styles(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                        decoration: TextDecoration.lineThrough,
                                      );
                                      final TextStyle cancelledSmallStyle =
                                          styles(
                                            fontSize: 12.sp,
                                            color: Colors.black45,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          );
                                      final TextStyle cancelledPriceStyle =
                                          styles(
                                            fontSize: 12.sp,
                                            color: Colors.black45,
                                            fontWeight: FontWeight.w600,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          );
                                      final TextStyle extraCancelStyle = styles(
                                        fontSize: 12.sp,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.lineThrough,
                                      );

                                      return Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 4.h,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              proName,
                                              style: cancelledStyle,
                                            ),
                                            if (productSize.isNotEmpty)
                                              Text(
                                                'Size: $productSize',
                                                style: cancelledSmallStyle,
                                              ),
                                            if (optionsText.isNotEmpty)
                                              Text(
                                                optionsText,
                                                style: cancelledSmallStyle,
                                              ),
                                            SizedBox(height: 4.h),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  '฿${price.toStringAsFixed(2)} x $quantity',
                                                  style: cancelledSmallStyle,
                                                ),
                                                Text(
                                                  '= ฿${itemSubtotal.toStringAsFixed(2)}',
                                                  style: cancelledPriceStyle,
                                                ),
                                              ],
                                            ),
                                            if (extraPrice > 0) ...[
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    'Extra: ฿$optionPrice x $quantity',
                                                    style: extraCancelStyle,
                                                  ),
                                                  Text(
                                                    '= ฿${extraPrice.toStringAsFixed(2)}',
                                                    style: extraCancelStyle,
                                                  ),
                                                ],
                                              ),
                                            ],
                                            SizedBox(height: 4.h),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.warning,
                                                  size: 16.sp,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 4.w),
                                                Text(
                                                  'รายการนี้ถูกยกเลิก',
                                                  style: styles(
                                                    fontSize: 12.sp,
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],

                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(
                                      vertical: 8.h,
                                    ),

                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'ยอดรวมสินค้า',
                                              style: styles(
                                                fontSize: 12.sp,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            Text(
                                              '฿${deliveredSubTotal.toStringAsFixed(2)}',
                                              style: styles(
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (serviceType == 'delivery' &&
                                            isSelfDeliver) ...[
                                          SizedBox(height: 8.h),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'ค่าส่ง',
                                                style: styles(
                                                  fontSize: 12.sp,
                                                  color: Colors
                                                      .deepOrange
                                                      .shade900,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Text(
                                                '฿${shippingCharge.toStringAsFixed(2)}',
                                                style: styles(
                                                  fontSize: 12.sp,
                                                  color: Colors
                                                      .deepOrange
                                                      .shade900,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        Divider(
                                          height: 20.h,
                                          color: Colors.transparent,
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'ยอดคงเหลือ',
                                              style: TextStyle(
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              '฿${deliveredTotal.toStringAsFixed(2)}',
                                              style: styles(
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.w400,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 12.h),

                                  Text(
                                    'ข้อมูลผู้สั่งซื้อ',
                                    style: styles(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(
                                          right: 12.w,
                                          top: 8.w,
                                        ),
                                        child: CircleAvatar(
                                          radius: 20.r,
                                          backgroundImage: buyerImageUrl != null
                                              ? NetworkImage(buyerImageUrl)
                                              : null,
                                          child: buyerImageUrl == null
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fullName,
                                              style: styles(
                                                fontSize: 13.sp,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            Text(
                                              address,
                                              maxLines: 3,
                                              style: styles(
                                                fontSize: 11.sp,
                                                color: Colors.black54,
                                              ),
                                            ),
                                            if (phone.isNotEmpty) ...[
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.phone,
                                                    size: 16.sp,
                                                    color: Colors.green,
                                                  ),
                                                  SizedBox(width: 4.w),
                                                  Text(
                                                    phone,
                                                    style: styles(
                                                      fontSize: 12.sp,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (email.isNotEmpty) ...[
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.email,
                                                    size: 16.sp,
                                                    color: Colors.blue,
                                                  ),
                                                  SizedBox(width: 4.w),
                                                  Text(
                                                    email,
                                                    style: styles(
                                                      fontSize: 12.sp,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}
