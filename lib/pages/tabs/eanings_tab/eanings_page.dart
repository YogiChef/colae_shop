// earnings_page.dart - เวอร์ชันแก้ lag (ใช้ compute + clean code)

// ignore_for_file: unnecessary_cast

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/pages/hotel/hotel_main_page.dart';
import 'package:colae_shop/pages/services/service_shop_dashboard.dart';
import 'package:colae_shop/pages/services/vendor_service_home_page.dart';
import 'package:colae_shop/widgets/mode_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
            final isFromBuyer = data['senderId'] != auth.currentUser!.uid;
            final isUnread = data['read'] != true;
            return isFromBuyer && isUnread;
          }).length,
        );
    _checkLastMode();
  }

  Future<void> _checkLastMode() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMode = prefs.getString('vendor_last_mode');
    if (lastMode != null && mounted) {
      await _navigateToMode(lastMode);
      return;
    }
  }

  Future<void> _selectMode(String mode) async {
    if (mode == 'vehicle') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เร็วๆ นี้! โหมดนี้กำลังพัฒนา')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendor_last_mode', mode);
    await _navigateToMode(mode);
  }

  Future<void> _navigateToMode(String mode) async {
    if (mode == 'hotel') {
      Get.offAll(() => const HotelMainPage());
    } else if (mode == 'services') {
      // Query shop before navigating — bypass VendorServiceHomePage for active shops.
      // Navigator.push preserves the stack so back() returns to EarningPage.
      try {
        final uid = auth.currentUser!.uid;
        final doc = await FirebaseFirestore.instance
            .collection('service_shops')
            .doc(uid)
            .get();
        if (!mounted) return;

        if (doc.exists && doc.data()?['status'] == 'active') {
          final data = doc.data()!;
          String? catName;
          final catId = data['categoryId'] as String?;
          if (catId != null) {
            final catDoc = await FirebaseFirestore.instance
                .collection('service_categories')
                .doc(catId)
                .get();
            if (catDoc.exists) catName = catDoc.data()?['name'] as String?;
          }
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ServiceShopDashboard(shopData: data, categoryName: catName),
            ),
          );
        } else {
          // No shop / pending / suspended — VendorServiceHomePage handles those states.
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VendorServiceHomePage()),
          );
        }
      } catch (_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VendorServiceHomePage()),
        );
      }
    } else {
      Get.offAll(() => const LandingPage());
    }
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

  Widget _infoTable({
    required List<MapEntry<String, String>> rows,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7.r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: mainColor, width: 0.5),
          borderRadius: BorderRadius.circular(7.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: List.generate(rows.length, (i) {
            final isLast = i == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                color: Colors.amber,

                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: Colors.white, width: 1)),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      rows[i].key,
                      style: styles(
                        fontSize: 15.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
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
                      radius: 20.sp,
                      backgroundImage: data['image'] != null
                          ? CachedNetworkImageProvider(data['image'])
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
                        'images/map.webp',
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
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 12.h,
                    left: 20.w,
                    right: 20.w,
                    bottom: 12.h,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      SizedBox(height: 12.h),
                      SizedBox(
                        width: screenWidth * 0.90,
                        child: _infoTable(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BillingPage(),
                            ),
                          ),
                          rows: [
                            MapEntry(
                              'รายได้รวม',
                              '฿${totalEarnings.toStringAsFixed(2)}',
                            ),
                            MapEntry(
                              'ค่าจัดส่ง',
                              '฿${totalShippingEarnings.toStringAsFixed(2)}',
                            ),
                            MapEntry('ออร์เดอร์', '$totalOrders'),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('hotel_bookings')
                            .where(
                              'hotelId',
                              isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                            )
                            .where('status', isEqualTo: 'pending')
                            .snapshots(),
                        builder: (context, snap) {
                          final count = snap.data?.docs.length ?? 0;
                          return ModeCard(
                            image: Image.asset(
                              'images/hotel.webp',
                              width: 90.w,
                              height: 90.w,
                              fit: BoxFit.contain,
                            ),
                            color: Colors.blue,
                            title: 'ที่พัก',
                            subtitle: 'โรงแรม รีสอร์ท โฮมสเตย์',
                            enabled: true,
                            badgeCount: count,
                            onTap: () => _selectMode('hotel'),
                          );
                        },
                      ),
                      SizedBox(height: 12.h),
                      ModeCard(
                        image: Image.asset(
                          'images/services.png',
                          width: 90.w,
                          height: 90.w,
                          fit: BoxFit.contain,
                        ),
                        color: mainColor,
                        title: 'บริการ',
                        subtitle: 'นวด ตัดผม ช่าง ครูสอนพิเศษ',
                        enabled: true,
                        onTap: () => _selectMode('services'),
                      ),
                      SizedBox(height: 12.h),
                      Card(
                        margin: EdgeInsets.zero,
                        color: const Color(0xFFFF6B9D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7.r),
                        ),
                        elevation: 4,
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ReferralDashboardPage(),
                            ),
                          ),
                          child: Container(
                            padding: EdgeInsets.all(12),
                            width: screenWidth * 0.9,
                            height: 160.h,
                            child: Row(
                              children: [
                                Container(
                                  height: 80,
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                  ),
                                  child: Image.asset(
                                    'images/mlm.webp',
                                    width: 80.w,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'บริหารธุรกิจ',
                                      style: styles(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'รายได้ Referral',
                                      style: styles(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
            backgroundColor: Colors.white,
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
              child: Icon(IconlyLight.chat, color: mainColor, size: 35.r),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
