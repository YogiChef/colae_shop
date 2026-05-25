// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:colae_shop/auth/vendor_auth.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/dialog.dart';

import '../../../providers/vendor_order_provider.dart';

class LogOutPage extends StatefulWidget {
  const LogOutPage({super.key});

  @override
  State<LogOutPage> createState() => _LogOutPageState();
}

class _LogOutPageState extends State<LogOutPage> {
  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 24.w, top: 20.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24.r,
                  backgroundColor: mainColor,
                  child: IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: Icon(
                      Icons.arrow_back,
                      size: 24.r,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 40, bottom: 30),
                  child: Text(
                    'Sign Out',
                    style: GoogleFonts.righteous(
                      fontSize: 30,
                      color: Colors.red,
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 120.r,
                  backgroundImage: AssetImage('images/signout.png'),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 50),
                  width: size.width * 0.8,
                  child: ButtonWidget(
                    label: 'Sign Out',
                    style: styles(color: Colors.white, fontSize: 20.sp),
                    icon: Icons.logout,
                    size: 24.sp,
                    press: () async {
                      MyAlertDialog.showMyDialog(
                        img: const AssetImage('images/signout.png'),
                        contant: 'Are you sure to log out ',
                        context: context,
                        tabNo: () {
                          Navigator.pop(context);
                        },
                        tabYes: () async {
                          Provider.of<VendorOrderProvider>(
                            context,
                            listen: false,
                          ).clear();

                          await auth.signOut();

                          if (mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => const VendorAuthPage(),
                              ),
                              (route) => false,
                            );
                          }

                          await Future.delayed(
                            const Duration(microseconds: 100),
                          );
                        },
                        title: 'Log Out',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
