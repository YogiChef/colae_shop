// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/auth/registor/vendor_registor_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  CollectionReference buyers = firestore.collection('buyers');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late String email;
  late String password;
  bool _obscureText = true;
  bool _isLoading = false;

  Future<void> login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await vendorController.loginUser(email, password);
        await auth.currentUser!.reload();

        final uid = auth.currentUser!.uid;
        final vendorDoc = await firestore.collection('vendors').doc(uid).get();

        if (!vendorDoc.exists) {
          await auth.signOut();
          setState(() => _isLoading = false);
          Fluttertoast.showToast(msg: 'ไม่พบบัญชีร้านค้า กรุณาตรวจสอบอีเมล');
          return;
        }

        _formKey.currentState!.reset();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LandingPage()),
        );
      } on FirebaseAuthException catch (e) {
        setState(() => _isLoading = false);
        String msg = e.code == 'user-not-found'
            ? 'ไม่พบผู้ใช้'
            : 'กรุณากรอกข้อมูลให้ถูกต้อง';
        Fluttertoast.showToast(msg: msg);
      } catch (e) {
        setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
        behavior: HitTestBehavior.opaque,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                Container(
                  height: 190.h,
                  margin: EdgeInsets.only(bottom: 10.h),
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('images/colae2.png'),
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 120.h),
                      InputTextfield(
                        onChanged: (value) {
                          setState(() {
                            email = value;
                          });
                        },
                        validator: (value) {
                          if (value!.isEmpty) {
                            return 'Please enter your email address';
                          } else if (value.isValidEmail() == false) {
                            return 'invalid email';
                          } else {
                            return null;
                          }
                        },
                        hintText: 'Enter Email',
                        textInputType: TextInputType.emailAddress,
                        prefixIcon: Icon(
                          Icons.email,
                          color: Colors.cyan.shade400,
                        ),
                      ),
                      InputTextfield(
                        hintText: 'Enter Password',
                        textInputType: TextInputType.text,
                        prefixIcon: Icon(
                          Icons.lock,
                          color: Colors.red.shade600,
                        ),
                        obscureText: _obscureText,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText == true
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 20.r,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                        ),
                        onChanged: (value) {
                          setState(() {
                            password = value;
                          });
                        },
                        validator: (value) {
                          if (value!.isEmpty) {
                            return 'Please enter your password';
                          } else if (value.length < 8) {
                            return 'Passwords longer than eight characters';
                          } else {
                            return null;
                          }
                        },
                      ),
                      SizedBox(height: 50.h),
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: Colors.yellow.shade900,
                                ),
                              )
                            : ButtonWidget(
                                label: 'Login',
                                style: styles(
                                  fontSize: 16.sp,
                                  color: Colors.white,
                                  letterSpacing: null,
                                ),
                                icon: Icons.login,
                                press: login,
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: 20.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Need an account',
                              style: GoogleFonts.righteous(fontSize: 14.sp),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const VendorRegistorPage(),
                                  ),
                                );
                              },
                              child: Text(
                                'SignUp',
                                style: GoogleFonts.righteous(
                                  color: Colors.cyan.shade400,
                                  letterSpacing: 1,
                                  fontSize: 16.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
