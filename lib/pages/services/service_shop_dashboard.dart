// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/services/add_service_page.dart';
import 'package:colae_shop/pages/services/edit_service_shop_page.dart';
import 'package:colae_shop/pages/services/manage_providers_page.dart';
import 'package:colae_shop/pages/services/service_earnings_page.dart';
import 'package:colae_shop/pages/services/services_manage_page.dart';
import 'package:colae_shop/pages/services/shop_info_page.dart';
import 'package:colae_shop/pages/services/vendor_service_bookings_page.dart';
import 'package:colae_shop/pages/services/walk_in_service_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ServiceShopDashboard extends StatefulWidget {
  final Map<String, dynamic> shopData;
  final String? categoryName;

  const ServiceShopDashboard({
    super.key,
    required this.shopData,
    this.categoryName,
  });

  @override
  State<ServiceShopDashboard> createState() => _ServiceShopDashboardState();
}

class _ServiceShopDashboardState extends State<ServiceShopDashboard> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;

  String? _typeName;
  String? _shopCode;

  @override
  void initState() {
    super.initState();
    _shopCode = widget.shopData['shopCode'] as String?;
    _loadTypeName();
    if (_shopCode == null) _loadShopCode();
  }

  Future<void> _loadShopCode() async {
    try {
      final doc = await _db.collection('service_shops').doc(_uid).get();
      if (doc.exists && mounted) {
        setState(() => _shopCode = doc.data()?['shopCode'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _loadTypeName() async {
    final typeId = widget.shopData['typeId'] as String?;
    if (typeId == null) return;
    try {
      final doc = await _db.collection('service_types').doc(typeId).get();
      if (doc.exists && mounted) {
        setState(() => _typeName = doc.data()?['name'] as String?);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final shopName = widget.shopData['shopName'] as String? ?? '';
    final rating = (widget.shopData['rating'] as num?)?.toDouble() ?? 0.0;
    final totalReviews =
        (widget.shopData['totalReviews'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 24.r),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              '$shopName   ($totalReviews) ',
              style: styles(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                Icon(Icons.star_rounded, color: Colors.amber, size: 24.r),
                SizedBox(width: 3.w),
                Text(
                  rating > 0 ? rating.toStringAsFixed(1) : 'ยังไม่มีรีวิว',
                  style: styles(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 20.h),
            StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('service_bookings')
                  .where('shopId', isEqualTo: _uid)
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snap) {
                final pendingCount = snap.data?.docs.length ?? 0;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: .9,
                  mainAxisSpacing: 12.h,
                  crossAxisSpacing: 12.w,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  children: [
                    _buildBlock(
                      icon: Icons.store_outlined,
                      title: 'ข้อมูลร้าน',
                      color: const Color(0xFFFCE4EC),
                      iconColor: const Color(0xFFC2185B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShopInfoPage(
                            shopId: _uid,
                            shopData: widget.shopData,
                            categoryName: widget.categoryName,
                            typeName: _typeName,
                          ),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: Icons.calendar_month_outlined,
                      title: 'การจอง',
                      badge: pendingCount,
                      color: const Color(0xFFE8F5E9),
                      iconColor: const Color(0xFF2E7D32),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VendorServiceBookingsPage(),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: Icons.person_add_alt_1_outlined,
                      title: 'ลูกค้าเข้าร้าน',
                      color: const Color(0xFFFFF3E0),
                      iconColor: const Color(0xFFE65100),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WalkInServicePage(
                            shopId: _uid,
                            shopData: widget.shopData,
                          ),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: Icons.add_business_outlined,
                      title: 'เพิ่มบริการ',
                      color: const Color(0xFFF3E5F5),
                      iconColor: const Color(0xFF6A1B9A),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddServicePage(
                            shopCategoryId:
                                widget.shopData['categoryId'] as String? ?? '',
                            shopId: _uid,
                          ),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: IconlyLight.bag,
                      title: 'บริการของร้าน',
                      color: Colors.blue.withOpacity(0.1),
                      iconColor: Colors.amber,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServicesManagePage(
                            shopId: _uid,
                            shopData: widget.shopData,
                          ),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: IconlyLight.edit,
                      title: 'แก้ไขข้อมูลร้าน',
                      color: Colors.blueGrey.shade100,
                      iconColor: Colors.blueGrey,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              EditServiceShopPage(shopData: widget.shopData),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: Icons.people_alt_outlined,
                      title: 'พนักงาน',
                      color: Colors.deepPurple.shade50,
                      iconColor: Colors.deepPurple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManageProvidersPage(
                            shopId: _uid,
                            shopData: widget.shopData,
                          ),
                        ),
                      ),
                    ),
                    _buildBlock(
                      icon: Icons.people_alt_outlined,
                      title: 'รายได้จากบริการ',
                      color: Colors.brown.shade50,
                      iconColor: Colors.brown,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceEarningsPage(
                            shopId: _uid,
                            shopData: widget.shopData,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock({
    required IconData icon,
    required String title,
    Color color = Colors.white,
    Color iconColor = Colors.grey,
    int? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7.r),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7.r),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 80.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 32.r, color: iconColor),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: styles(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: context.textColor,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null && badge > 0)
              Positioned(
                top: 4.h,
                right: 4.w,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    '$badge',
                    style: styles(
                      fontSize: 11.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
