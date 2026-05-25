// ignore_for_file: avoid_print, empty_catches

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/models/vendor_model.dart';
import 'package:colae_shop/pages/main_vendor_page.dart';
import 'package:colae_shop/auth/vendor_auth.dart';
import 'package:colae_shop/pages/tabs/settings/store_settings_page.dart';
import 'package:colae_shop/services/sevice.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Timer? _autoCheckTimer;
  Timer? _countdownTimer;
  final ValueNotifier<String> _countdownNotifier = ValueNotifier<String>('');
  Stream<DocumentSnapshot>? _vendorStream;
  String? _lastUid;
  String? _lastTimerModelKey;

  Stream<DocumentSnapshot> _getVendorStream(String uid) {
    if (_lastUid != uid) {
      _lastUid = uid;
      _vendorStream = firestore.collection('vendors').doc(uid).snapshots();
    }
    return _vendorStream!;
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _countdownTimer?.cancel();
    _countdownNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!authSnapshot.hasData || authSnapshot.data == null) {
          _cancelTimers();
          return const VendorAuthPage();
        }

        final String uid = authSnapshot.data!.uid;

        return Scaffold(
          body: StreamBuilder<DocumentSnapshot>(
            stream: _getVendorStream(uid),
            builder: (context, vendorSnapshot) {
              if (vendorSnapshot.hasError) {
                return Center(
                  child: Text('เกิดข้อผิดพลาด: ${vendorSnapshot.error}'),
                );
              }

              if (vendorSnapshot.connectionState == ConnectionState.waiting ||
                  !vendorSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!vendorSnapshot.data!.exists) {
                _cancelTimers();
                return const VendorAuthPage();
              }

              final VendorModel vendorsModel = VendorModel.fromJson(
                vendorSnapshot.data!.data() as Map<String, dynamic>,
              );

              if (vendorsModel.temporarilyClosed) {
                _cancelTimers();
                return _buildClosedUI(
                  context,
                  'ปิดชั่วคราว',
                  Icons.block,
                  Colors.red,
                  vendorsModel,
                );
              }

              final bool isOpenNow = _checkIsOpenNow(vendorsModel);

              if (vendorsModel.approved == true) {
                if (!isOpenNow) {
                  final String modelKey =
                      '${vendorsModel.bussinessName}_closed';
                  if (_lastTimerModelKey != modelKey) {
                    _lastTimerModelKey = modelKey;
                    _startAutoCheckTimer(vendorsModel);
                    _startCountdownTimer(vendorsModel);
                  }
                  return _buildClosedUI(
                    context,
                    'วันนี้ร้านปิด',
                    Icons.schedule,
                    Colors.orange,
                    vendorsModel,
                  );
                }
                _cancelTimers();
                return const MainVendorPage();
              } else {
                _cancelTimers();
                return _buildPendingApprovalUI(vendorsModel);
              }
            },
          ),
        );
      },
    );
  }

  void _cancelTimers() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownNotifier.value = '';
    _lastTimerModelKey = null;
  }

  Widget _buildPendingApprovalUI(VendorModel vendorsModel) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Image.network(
              vendorsModel.image.isNotEmpty
                  ? vendorsModel.image
                  : 'https://via.placeholder.com/90',
              width: 90,
              height: 90,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.error, size: 90),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            vendorsModel.bussinessName,
            style: styles(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Text(
              'ใบสมัครของคุณได้ถูกส่งไป\nยังผู้ดูแลร้านค้าแล้ว\nผู้ดูแลจะติดต่อกลับในเร็วๆ นี้',
              textAlign: TextAlign.center,
              style: styles(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.red.shade200,
              ),
            ),
          ),
          const SizedBox(height: 15),
          TextButton(
            onPressed: () async {
              _cancelTimers();
              await auth.signOut();
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
    );
  }

  bool _checkIsOpenNow(VendorModel vendorsModel) {
    if (vendorsModel.storeHours == null || vendorsModel.storeHours!.isEmpty) {
      return true;
    }

    final now = DateTime.now();
    final dayKey = _getDayKey(now.weekday);
    final dayHours = vendorsModel.storeHours![dayKey];

    if (dayHours == null) return true;
    if (dayHours['closed'] == true) return false;

    try {
      final openParts = (dayHours['open'] as String).split(':');
      final closeParts = (dayHours['close'] as String).split(':');
      final openTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(openParts[0]),
        int.parse(openParts[1]),
      ).toLocal();
      final closeTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(closeParts[0]),
        int.parse(closeParts[1]),
      ).toLocal();
      return now.isAfter(openTime) && now.isBefore(closeTime);
    } catch (e) {
      return true;
    }
  }

  void _startAutoCheckTimer(VendorModel vendorsModel) {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_checkIsOpenNow(vendorsModel)) {
        timer.cancel();
        _lastTimerModelKey = null;
        setState(() {});
      }
    });
  }

  void _startCountdownTimer(VendorModel vendorsModel) {
    _countdownTimer?.cancel();

    final DateTime nextOpenTime = _calculateNextOpenTime(vendorsModel);
    _updateCountdownValue(nextOpenTime);

    _countdownTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      if (now.isAfter(nextOpenTime)) {
        timer.cancel();
        _lastTimerModelKey = null;
        if (mounted) setState(() {});
        return;
      }
      _updateCountdownValue(nextOpenTime);
    });
  }

  void _updateCountdownValue(DateTime nextOpenTime) {
    final duration = nextOpenTime.toLocal().difference(
      DateTime.now().toLocal(),
    );
    if (duration.isNegative || duration.inSeconds == 0) {
      _countdownNotifier.value = '00:00 น.';
      return;
    }
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    _countdownNotifier.value = '$hours:$minutes น.';
  }

  Widget _buildClosedUI(
    BuildContext context,
    String message,
    IconData icon,
    Color color,
    VendorModel vendorsModel,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: width * 0.25.w, color: color),
          const SizedBox(height: 16),
          Text(
            message,
            style: styles(
              fontSize: 18.sp,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (message == 'วันนี้ร้านปิด')
            ValueListenableBuilder<String>(
              valueListenable: _countdownNotifier,
              builder: (context, text, child) {
                return Column(
                  children: [
                    Text(
                      'จะเปิดให้บริการในอีก',
                      style: styles(
                        fontSize: 16.sp,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 20.h),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StoreSettingsPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 54.w,
                          vertical: 20.h,
                        ),
                        backgroundColor: mainColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        text.isEmpty ? '...' : text,
                        style: styles(
                          fontSize: 14.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          if (message == 'ปิดชั่วคราว')
            Text(
              'กรุณารอการแจ้งเตือนจากผู้ดูแล',
              style: styles(fontSize: 14.sp, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  DateTime _calculateNextOpenTime(VendorModel vendorsModel) {
    final now = DateTime.now();
    for (int daysAhead = 0; daysAhead < 7; daysAhead++) {
      final targetDay = now.add(Duration(days: daysAhead));
      final dayKey = _getDayKey(targetDay.weekday);
      final dayHours = vendorsModel.storeHours?[dayKey];

      if (dayHours == null || dayHours['open'] == null) continue;
      if (dayHours['closed'] == true) continue;

      try {
        final openParts = (dayHours['open'] as String).split(':');
        final closeParts = (dayHours['close'] as String).split(':');
        final openTime = DateTime(
          targetDay.year,
          targetDay.month,
          targetDay.day,
          int.parse(openParts[0]),
          int.parse(openParts[1]),
        ).toLocal();
        final closeTime = DateTime(
          targetDay.year,
          targetDay.month,
          targetDay.day,
          int.parse(closeParts[0]),
          int.parse(closeParts[1]),
        ).toLocal();

        if (daysAhead == 0) {
          if (now.isBefore(openTime)) return openTime;
          if (now.isAfter(openTime) && now.isBefore(closeTime)) {
            break;
          }
        } else {
          return openTime;
        }
      } catch (e) {
        continue;
      }
    }
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      0,
      0,
    ).toLocal();
  }

  String _getDayKey(int weekday) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    return days[weekday - 1];
  }
}
