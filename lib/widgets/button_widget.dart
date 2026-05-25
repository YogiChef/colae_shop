import 'package:flutter/material.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ButtonWidget extends StatelessWidget {
  final String label;
  final IconData icon;
  final Function() press;
  final TextStyle? style;
  final Color? color;
  final double? size;
  final double? height;

  const ButtonWidget({
    super.key,
    required this.label,
    required this.icon,
    this.style,
    required this.press,
    this.color,
    this.size,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        minimumSize: Size(double.infinity, 60.h),
        backgroundColor: color ?? mainColor,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      label: Text(label, style: style),
      onPressed: press,
      icon: Icon(icon, size: size ?? 24.sp, color: Colors.white),
    );
  }
}
