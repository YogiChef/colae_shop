// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/pages/hotel/hotel_main_page.dart';

class ModeSelectorPage extends StatefulWidget {
  const ModeSelectorPage({super.key});

  @override
  State<ModeSelectorPage> createState() => _ModeSelectorPageState();
}

class _ModeSelectorPageState extends State<ModeSelectorPage> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkLastMode();
  }

  Future<void> _checkLastMode() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMode = prefs.getString('vendor_last_mode');
    if (lastMode != null && mounted) {
      _navigateToMode(lastMode);
      return;
    }
    if (mounted) setState(() => _isChecking = false);
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
    _navigateToMode(mode);
  }

  void _navigateToMode(String mode) {
    if (mode == 'hotel') {
      Get.offAll(() => const HotelMainPage());
    } else {
      Get.offAll(() => const LandingPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            children: [
              SizedBox(height: 16.h),
              Text(
                'เลือกบริการ',
                style: styles(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'คุณต้องการจัดการบริการอะไร?',
                style: styles(fontSize: 14.sp, color: Colors.grey),
              ),
              SizedBox(height: 40.h),
              _modeCard(
                icon: Icons.restaurant_menu,
                color: Colors.orange,
                title: 'ร้านอาหาร',
                subtitle: 'จัดการเมนู รับออเดอร์ จัดส่ง',
                enabled: true,
                onTap: () => _selectMode('delivery'),
              ),
              SizedBox(height: 16.h),
              _modeCard(
                icon: Icons.hotel,
                color: Colors.blue,
                title: 'ที่พัก',
                subtitle: 'โรงแรม รีสอร์ท โฮมสเตย์',
                enabled: true,
                onTap: () => _selectMode('hotel'),
              ),
              SizedBox(height: 16.h),
              _modeCard(
                icon: Icons.local_taxi,
                color: Colors.green,
                title: 'บริการรถ',
                subtitle: 'มอเตอร์ไซค์ รถยนต์ รถบรรทุก',
                enabled: false,
                onTap: () => _selectMode('vehicle'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: enabled ? color : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: (enabled ? color : Colors.grey).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40.sp,
                color: enabled ? color : Colors.grey,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: styles(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: enabled ? Colors.black87 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: styles(
                      fontSize: 12.sp,
                      color: enabled ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                  if (!enabled) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        'เร็วๆ นี้',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: enabled ? color : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}
