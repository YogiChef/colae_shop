import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart';

class InputTextfield extends StatelessWidget {
  const InputTextfield({
    super.key,
    required this.textInputType,
    required this.prefixIcon,
    this.suffixIcon,
    required this.hintText,
    this.validator,
    this.onChanged,
    this.maxLength,
    this.obscureText = false,
    this.controller,
    this.label,
    this.initialValue,
    this.enabled = true,
    this.maxLines,
  });

  final TextInputType textInputType;
  final Widget prefixIcon;
  final String hintText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final Function(String)? onChanged;
  final int? maxLength;
  final int? maxLines;
  final bool obscureText;
  final TextEditingController? controller;
  final Widget? label;
  final String? initialValue;
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        validator: validator,
        obscureText: obscureText,
        obscuringCharacter: '*',
        keyboardType: textInputType,
        maxLength: maxLength,
        maxLines: obscureText ? 1 : maxLines,
        controller: controller,
        style: styles(fontSize: 14.sp, color: context.textColor),
        decoration: InputDecoration(
          prefixIcon: prefixIcon,
          hintText: hintText,
          label: label,
          labelStyle: styles(fontSize: 14.sp, color: context.textColor),
          suffixIcon: suffixIcon,
          hintStyle: styles(fontSize: 14.sp, color: context.textColor),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.yellow.shade900, width: 2),
          ),
          errorBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: context.isDark ? Colors.white70 : Colors.grey,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}

extension EmailValidator on String {
  bool isValidEmail() {
    return RegExp(
      r'^([a-zA-Z0-9]+)([\-\_\.]*)([a-zA-Z0-9]*)([@])([a-zA-Z0-9]{2,})([\.][a-zA-Z0-9]{2,3})$',
    ).hasMatch(this);
  }
}
