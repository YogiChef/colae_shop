// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/pages/services/service_shop_dashboard.dart';
import 'package:colae_shop/pages/services/service_shop_registration_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class VendorServiceHomePage extends StatefulWidget {
  const VendorServiceHomePage({super.key});

  @override
  State<VendorServiceHomePage> createState() => _VendorServiceHomePageState();
}

class _VendorServiceHomePageState extends State<VendorServiceHomePage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  Map<String, dynamic>? _shopData;
  String? _categoryName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(_uid)
          .get();
      if (!doc.exists || !mounted) {
        setState(() {
          _shopData = null;
          _loading = false;
        });
        return;
      }
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
      if (mounted) {
        setState(() {
          _shopData = data;
          _categoryName = catName;
          _loading = false;
        });
        if (data['status'] == 'active') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ServiceShopDashboard(shopData: data, categoryName: catName),
              ),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('[VendorServiceHome] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vendor_last_mode');
    Get.offAll(() => const LandingPage());
  }

  Future<void> _goToRegistration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServiceShopRegistrationPage()),
    );
    _loadShop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _changeMode,
        ),
        title: Text(
          'จัดการบริการ',
          style: styles(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final status = _shopData?['status'] as String?;
    if (_shopData == null) return _buildNoShop();
    switch (status) {
      case 'pending_approval':
        return _buildPending();
      case 'active':
        return _buildActive();
      case 'suspended':
      case 'rejected':
        return _buildSuspended(status!);
      default:
        return _buildNoShop();
    }
  }

  Widget _buildNoShop() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(32.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store, size: 72.r, color: mainColor),
                SizedBox(height: 16.h),
                Text(
                  'เริ่มต้นรับลูกค้าผ่านบริการของคุณ',
                  textAlign: TextAlign.center,
                  style: styles(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'ลงทะเบียนร้านบริการเพื่อรับลูกค้าผ่าน Colae',
                  textAlign: TextAlign.center,
                  style: styles(fontSize: 14.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: ElevatedButton(
                    onPressed: _goToRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'ลงทะเบียนร้านบริการ',
                      style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPending() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(32.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top, size: 64.r, color: Colors.orange),
                SizedBox(height: 16.h),
                Text(
                  'รอการอนุมัติ',
                  style: styles(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange[800],
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'ข้อมูลของคุณกำลังถูกตรวจสอบ\nใช้เวลาประมาณ 1-2 วันทำการ',
                  textAlign: TextAlign.center,
                  style: styles(fontSize: 14.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 20.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _shopData?['shopName'] as String? ?? '',
                        style: styles(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_categoryName != null) ...[
                        SizedBox(height: 4.h),
                        Text(
                          _categoryName!,
                          style: styles(
                            fontSize: 13.sp,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActive() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(20.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: mainColor, size: 36.r),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shopData?['shopName'] as String? ?? '',
                          style: styles(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_categoryName != null)
                          Text(
                            _categoryName!,
                            style: styles(
                              fontSize: 13.sp,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: mainColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text(
                      'เปิดให้บริการ',
                      style: styles(
                        fontSize: 11.sp,
                        color: mainColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                height: 50.h,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  label: Text(
                    'จัดการบริการ',
                    style: styles(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceShopDashboard(
                          shopData: _shopData!,
                          categoryName: _categoryName,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuspended(String status) {
    final isSuspended = status == 'suspended';
    final reason = _shopData?['rejectionReason'] as String?;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(32.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error, size: 64.r, color: Colors.red),
                SizedBox(height: 16.h),
                Text(
                  isSuspended ? 'บัญชีถูกระงับ' : 'ถูกปฏิเสธ',
                  style: styles(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.red[800],
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: styles(fontSize: 13.sp, color: Colors.grey[700]),
                  ),
                ],
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.mail_outline, color: Colors.white),
                    label: Text(
                      'ติดต่อ admin',
                      style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse('mailto:admin@colaepapa.com');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
