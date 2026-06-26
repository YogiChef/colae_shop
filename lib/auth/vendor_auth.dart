// lib/auth/vendor_auth_page.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:colae_shop/auth/registor/vendor_registor_page.dart';
import 'package:colae_shop/models/vendor_model.dart';
import 'package:colae_shop/pages/main_vendor_page.dart';
import 'package:colae_shop/pages/terms_page.dart';
import 'package:colae_shop/providers/vendor_order_provider.dart';
import 'package:colae_shop/services/sevice.dart';

class VendorAuthPage extends StatefulWidget {
  const VendorAuthPage({super.key});

  @override
  State<VendorAuthPage> createState() => _VendorAuthPageState();
}

class _VendorAuthPageState extends State<VendorAuthPage> {
  // cache future ป้องกันการสร้างใหม่ทุกครั้งที่ snapshot emit
  String? _lastCheckedEmail;
  Future<bool>? _emailCheckFuture;

  Future<bool> _getCachedEmailFuture(String email) {
    if (email != _lastCheckedEmail) {
      _lastCheckedEmail = email;
      _emailCheckFuture = _checkIfEmailUsedInOtherApps(email);
    }
    return _emailCheckFuture!;
  }

  Future<bool> _checkIfEmailUsedInOtherApps(String email) async {
    if (email.isEmpty) return false;

    try {
      final buyerQuery = await firestore
          .collection('buyers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (buyerQuery.docs.isNotEmpty) {
        return true;
      }

      final riderQuery = await firestore
          .collection('riders')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (riderQuery.docs.isNotEmpty) {
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  String _getDayKey(int weekday) {
    const days = [
      'sunday',
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
    ];
    return days[(weekday % 7) - 1 < 0 ? 6 : (weekday % 7) - 1];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: Text('กำลังโหลด...')));
        }

        if (authSnapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('เกิดข้อผิดพลาด: ${authSnapshot.error}')),
          );
        }

        if (!authSnapshot.hasData || authSnapshot.data == null) {
          return SignInScreen(
            providers: [EmailAuthProvider()],
            actions: [AuthStateChangeAction<SignedIn>((context, _) {})],
          );
        }

        final CollectionReference vendorsCollection = firestore.collection(
          'vendors',
        );

        return Scaffold(
          body: StreamBuilder<DocumentSnapshot>(
            stream: vendorsCollection.doc(authSnapshot.data!.uid).snapshots(),
            builder: (context, vendorSnapshot) {
              if (vendorSnapshot.hasError) {
                return Center(
                  child: Text('เกิดข้อผิดพลาด: ${vendorSnapshot.error}'),
                );
              }

              if (vendorSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!vendorSnapshot.hasData || !vendorSnapshot.data!.exists) {
                final String currentEmail = authSnapshot.data!.email ?? '';

                return FutureBuilder<bool>(
                  future: _getCachedEmailFuture(currentEmail),
                  builder: (context, emailCheckSnapshot) {
                    if (emailCheckSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (emailCheckSnapshot.hasData &&
                        emailCheckSnapshot.data == true) {
                      return Scaffold(
                        body: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.w),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.block,
                                  size: 80.sp,
                                  color: Colors.red,
                                ),
                                SizedBox(height: 24.h),
                                Text(
                                  'ไม่สามารถสมัครเป็นผู้ขายได้',
                                  style: TextStyle(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'อีเมลนี้ถูกใช้ในแอป Deli Box (ลูกค้า) หรือ Bike Box (rider) แล้ว\nไม่สามารถใช้สมัครเป็นร้านค้าได้',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 32.h),
                                ElevatedButton(
                                  onPressed: () async {
                                    await FirebaseAuth.instance.signOut();
                                    if (mounted) setState(() {});
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: Text(
                                    'ออกจากระบบ',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return const VendorRegistorPage();
                  },
                );
              }
              final VendorModel vendorModel = VendorModel.fromJson(
                vendorSnapshot.data!.data() as Map<String, dynamic>,
              );

              bool isOpenNow = true;
              if (vendorModel.storeHours != null &&
                  vendorModel.storeHours!.isNotEmpty) {
                final now = DateTime.now();
                final dayKey = _getDayKey(now.weekday);
                final dayHours = vendorModel.storeHours![dayKey];

                if (dayHours != null) {
                  try {
                    final openParts = (dayHours['open'] as String).split(':');
                    final closeParts = (dayHours['close'] as String).split(':');
                    final openHour = int.parse(openParts[0]);
                    final openMinute = int.parse(openParts[1]);
                    final closeHour = int.parse(closeParts[0]);
                    final closeMinute = int.parse(closeParts[1]);

                    final openTime = DateTime(
                      now.year,
                      now.month,
                      now.day,
                      openHour,
                      openMinute,
                    );
                    final closeTime = DateTime(
                      now.year,
                      now.month,
                      now.day,
                      closeHour,
                      closeMinute,
                    );

                    isOpenNow =
                        now.isAfter(openTime) && now.isBefore(closeTime);
                  } catch (e) {
                    Fluttertoast.showToast(
                      msg: e.toString(),
                      backgroundColor: Colors.red,
                    );
                  }
                }
              }

              if (vendorModel.approved != true) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CachedNetworkImage(
                            imageUrl: vendorModel.image.isNotEmpty
                                ? vendorModel.image
                                : 'https://via.placeholder.com/90',
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            placeholder: (_, __) => Container(color: Colors.grey.shade200),
                            errorWidget: (_, __, ___) => const Icon(Icons.error, size: 90),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          vendorModel.bussinessName.isNotEmpty
                              ? vendorModel.bussinessName
                              : 'ไม่ทราบชื่อธุรกิจ',
                          style: styles(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          'ใบสมัครของคุณได้ถูกส่งไปยังผู้ดูแลร้านค้าแล้ว\nผู้ดูแลจะติดต่อกลับในเร็วๆ นี้',
                          textAlign: TextAlign.center,
                          style: styles(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.red.shade200,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextButton(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                            setState(() {});
                          },
                          child: Text(
                            'ออกจากระบบ',
                            style: styles(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.cyan.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!isOpenNow) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.store_mall_directory_outlined,
                        size: 64,
                        color: Colors.orange,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'ร้านปิดวันนี้ – ตรวจสอบ orders ในเวลาทำการ',
                        style: styles(fontSize: 16.sp),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: Text('รีเฟรช'),
                      ),
                    ],
                  ),
                );
              }
              final rawVendorData =
                  vendorSnapshot.data!.data() as Map<String, dynamic>;
              final acceptedVer =
                  rawVendorData['termsAcceptedVersion'] as String?;
              if (acceptedVer != CURRENT_TERMS_VERSION) {
                return const TermsPage();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Provider.of<VendorOrderProvider>(
                  context,
                  listen: false,
                ).restartListening();
              });
              return const MainVendorPage();
            },
          ),
        );
      },
    );
  }
}
