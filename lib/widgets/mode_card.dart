// ignore_for_file: use_build_context_synchronously

import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.badgeCount = 0,
    required this.image, // ← เพิ่ม
  });

  final Image image;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final int badgeCount; // ← เพิ่ม

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7.r),
      child: Container(
        padding: EdgeInsets.only(
          top: 20.h,
          left: 8.w,
          bottom: 20.h,
          right: 20.w,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7.r),
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 90.w,
                  height: 90.w,
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (enabled ? Colors.white : color),
                    shape: BoxShape.circle,
                  ),
                  child: image,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 22.w,
                        minHeight: 22.h,
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: styles(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
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
                          fontWeight: FontWeight.w600,
                          color: enabled ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: styles(
                      fontSize: 12.sp,
                      color: enabled ? Colors.white : Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
