// earnings_page.dart - เวอร์ชันแก้ lag (ใช้ compute + clean code)

// ignore_for_file: unnecessary_cast

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/auth/registor/store_location_page.dart';
import 'package:colae_shop/pages/tabs/eanings_tab/billing_page.dart';
import 'package:colae_shop/pages/chats/vendor_chat_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:badges/badges.dart' as badges;
import 'package:colae_shop/pages/referral_dashboard_page.dart';

class EarningPage extends StatefulWidget {
  const EarningPage({super.key});

  @override
  State<EarningPage> createState() => _EarningPageState();
}

class _EarningPageState extends State<EarningPage> {
  late final Stream<QuerySnapshot> _ordersStream;
  late final Future<DocumentSnapshot> _vendorFuture;
  late final Stream<int> _unreadStream;

  @override
  void initState() {
    super.initState();
    _ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
        .where('status', whereIn: ['completed', 'delivered'])
        .snapshots();
    _vendorFuture = firestore
        .collection('vendors')
        .doc(auth.currentUser!.uid)
        .get();
    _unreadStream = FirebaseFirestore.instance
        .collection('chats')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
        .snapshots()
        .map(
          (snap) => snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // นับทุก doc ที่ buyer ส่ง และ read เป็น null หรือ false
            final isFromBuyer = data['senderId'] != auth.currentUser!.uid;
            final isUnread = data['read'] != true;
            return isFromBuyer && isUnread;
          }).length,
        );
  }

  static Map<String, double> calculateEarnings(
    List<QueryDocumentSnapshot> docs,
  ) {
    double totalEarnings = 0.0;
    double totalShippingEarnings = 0.0;

    for (var orderDoc in docs) {
      final orderData = orderDoc.data() as Map<String, dynamic>? ?? {};

      totalEarnings += (orderData['vendorEarnings'] as num?)?.toDouble() ?? 0.0;

      final String serviceType =
          orderData['serviceType']?.toString() ?? 'pickup';
      final bool isSelfDeliver = orderData['selfDeliver'] ?? false;
      final double shippingCharge =
          (orderData['shippingCharge'] as num?)?.toDouble() ?? 0.0;

      if (serviceType == 'delivery' && isSelfDeliver) {
        totalShippingEarnings += shippingCharge;
      }
    }

    return {'total': totalEarnings, 'shipping': totalShippingEarnings};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: FutureBuilder<DocumentSnapshot>(
          future: _vendorFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Hi Vendor', style: TextStyle(fontSize: 14)),
                  Image.asset('images/pin.png', width: 32.w, height: 32.h),
                ],
              );
            }
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22.r,
                      backgroundImage: data['image'] != null
                          ? NetworkImage(data['image'])
                          : null,
                      child: data['image'] == null
                          ? const Icon(Icons.store)
                          : null,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 12.w),
                      child: Text(
                        'Hi ${data['bussinessName'] ?? 'Vendor'}',
                        style: styles(
                          fontSize: 18.sp,
                          color: mainColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StoreLocationPage(),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Image.asset(
                        'images/pin.png',
                        width: 40.w,
                        height: 40.h,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          return FutureBuilder<Map<String, double>>(
            future: compute(calculateEarnings, docs),
            builder: (context, earningsSnapshot) {
              if (!earningsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final earnings = earningsSnapshot.data!;
              final double totalEarnings = earnings['total'] ?? 0.0;
              final double totalShippingEarnings = earnings['shipping'] ?? 0.0;
              final int totalOrders = docs.length;

              final screenWidth = MediaQuery.of(context).size.width;

              return SingleChildScrollView(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 50.h,
                      horizontal: 20.w,
                    ),
                    child: Column(
                      children: [
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 4,
                          child: ListTile(
                            leading: const Icon(
                              Icons.card_giftcard,
                              color: Colors.orange,
                            ),
                            title: Text(
                              'รายได้จากการแนะนำเพื่อน',
                              style: styles(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReferralDashboardPage(),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BillingPage(),
                            ),
                          ),
                          child: Material(
                            borderRadius: BorderRadius.circular(15),
                            elevation: 10,
                            shadowColor: Colors.pink,
                            child: Container(
                              height: height * 0.26.h,
                              width: screenWidth * 0.8,
                              constraints: BoxConstraints(
                                minHeight: 150.h,
                                maxHeight: 200.h,
                              ),
                              decoration: BoxDecoration(
                                color: mainColor,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'รายได้รวม',
                                      style: styles(
                                        fontSize: 16.sp,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '฿${totalEarnings.toStringAsFixed(2)}',
                                      style: styles(
                                        fontSize: 16.sp,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Material(
                          borderRadius: BorderRadius.circular(15),
                          elevation: 10,
                          shadowColor: Colors.pink,
                          child: Container(
                            height: height * 0.26.h,
                            width: screenWidth * 0.8,
                            constraints: BoxConstraints(
                              minHeight: 150.h,
                              maxHeight: 200.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'รวมค่าจัดส่ง',
                                    style: styles(
                                      fontSize: 16.sp,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '฿${totalShippingEarnings.toStringAsFixed(2)}',
                                    style: styles(
                                      fontSize: 16.sp,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Material(
                          elevation: 15,
                          shadowColor: Colors.blueGrey,
                          borderRadius: BorderRadius.circular(15.r),
                          child: Container(
                            height: height * 0.26.h,
                            width: screenWidth * 0.8,
                            constraints: BoxConstraints(
                              minHeight: 150.h,
                              maxHeight: 200.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade800,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'ออร์เดอร์ทั้งหมด',
                                    style: styles(
                                      fontSize: 16.sp,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    totalOrders.toString(),
                                    style: styles(
                                      fontSize: 16.sp,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<int>(
        stream: _unreadStream,
        builder: (context, snapshot) {
          final unreadCount = snapshot.data ?? 0;
          return FloatingActionButton(
            heroTag: 'earning_fab_chat',
            backgroundColor: mainColor,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VendorChatPage()),
              );
            },
            child: badges.Badge(
              showBadge: unreadCount > 0,
              badgeContent: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: TextStyle(color: Colors.white, fontSize: 12.sp),
              ),
              badgeStyle: badges.BadgeStyle(badgeColor: Colors.red),
              child: Icon(IconlyLight.chat, color: Colors.white, size: 35.r),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
