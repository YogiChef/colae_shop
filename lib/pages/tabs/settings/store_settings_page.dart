// ignore_for_file: avoid_print, use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:colae_shop/controllers/vendor_controller.dart';
import 'package:colae_shop/models/vendor_model.dart';
import 'package:colae_shop/pages/tabs/settings/edit_profile_page.dart';
import 'package:colae_shop/pages/tabs/settings/logout.dart';
import 'package:colae_shop/pages/main_vendor_page.dart';
import 'package:colae_shop/pages/tabs/settings/table_qr_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/time_selector_widget.dart';

class StoreSettingsPage extends StatefulWidget {
  const StoreSettingsPage({super.key});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  final VendorController _vendorController = VendorController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, Map<String, dynamic>> hours = {};
  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final Map<String, String> _dayMap = {
    'mon': 'monday',
    'tue': 'tuesday',
    'wed': 'wednesday',
    'thu': 'thursday',
    'fri': 'friday',
    'sat': 'saturday',
    'sun': 'sunday',
  };
  bool _isTemporarilyClosed = false;
  late Stream<DocumentSnapshot> _vendorStream;

  @override
  void initState() {
    super.initState();
    final uid = _auth.currentUser!.uid;
    _vendorStream = _firestore.collection('vendors').doc(uid).snapshots();
  }

  @override
  void dispose() {
    super.dispose();
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

  void _onSaveTime(String day, String? open, String? close, bool? isClosed) {
    final shortLower = day.toLowerCase();
    final fullKey = _dayMap[shortLower] ?? shortLower;

    final Map<String, dynamic> dayEntry =
        hours[fullKey] ??
        <String, dynamic>{'open': null, 'close': null, 'closed': false};

    bool hasChange = false;
    if (isClosed != null) {
      dayEntry['closed'] = isClosed;
      hasChange = true;
      if (isClosed) {
        dayEntry['open'] = null;
        dayEntry['close'] = null;
      } else {}
    }

    if (!dayEntry['closed'] && open != null) {
      dayEntry['open'] = open;
      hasChange = true;
    }
    if (!dayEntry['closed'] && close != null) {
      dayEntry['close'] = close;
      hasChange = true;
    }

    if (hasChange) {
      setState(() {
        hours[fullKey] = dayEntry;
      });
    } else if (dayEntry['open'] == null &&
        dayEntry['close'] == null &&
        !dayEntry['closed']) {
      setState(() {
        hours.remove(fullKey);
      });
    }

    if (!dayEntry['closed'] &&
        dayEntry['open'] != null &&
        dayEntry['close'] != null) {
      final openStr = dayEntry['open'] as String;
      final closeStr = dayEntry['close'] as String;
      if (openStr.contains(':') && closeStr.contains(':')) {
        try {
          final openHour = int.parse(openStr.split(':')[0]);
          final closeHour = int.parse(closeStr.split(':')[0]);
          if (closeHour <= openHour) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('คำเตือน: เวลาปิดควรหลังเวลาเปิด'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } catch (e) {
          Fluttertoast.showToast(
            msg: e.toString(),
            backgroundColor: Colors.red,
          );
        }
      }
    }
  }

  Future<void> _saveHours() async {
    if (hours.values
        .where(
          (entry) =>
              entry['open'] != null ||
              entry['close'] != null ||
              entry['closed'] == true,
        )
        .isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเลือกเวลาอย่างน้อยหนึ่งวัน')),
        );
      }
      return;
    }
    try {
      await _vendorController.saveTemporaryClose(_isTemporarilyClosed);
      await _vendorController.saveStoreHours(hours);

      final uid = _auth.currentUser!.uid;
      final doc = await _firestore.collection('vendors').doc(uid).get();
      if (doc.exists) {
        final updatedModel = VendorModel.fromJson(
          doc.data() as Map<String, dynamic>,
        );
        final isOpenNow =
            !_isTemporarilyClosed && _checkIsOpenNow(updatedModel);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'บันทึกสำเร็จ! สถานะ: ${isOpenNow ? 'เปิดแล้ว' : 'ปิด'}',
              ),
            ),
          );
        }

        if (isOpenNow && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainVendorPage()),
            (route) => false,
          );
        } else if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  bool _checkIsOpenNow(VendorModel vendorsModel) {
    bool isOpenNow = true;
    if (vendorsModel.storeHours != null &&
        vendorsModel.storeHours!.isNotEmpty) {
      final now = DateTime.now();
      final dayKey = _getDayKey(now.weekday);
      final dayHours = vendorsModel.storeHours![dayKey];
      if (dayHours != null) {
        if (dayHours['closed'] == true) {
          isOpenNow = false;
        } else {
          final openStr = dayHours['open'] as String?;
          final closeStr = dayHours['close'] as String?;
          if (openStr == null ||
              openStr.isEmpty ||
              closeStr == null ||
              closeStr.isEmpty) {
            isOpenNow = true;
            return isOpenNow;
          }
          try {
            final openParts = openStr.split(':');
            final closeParts = closeStr.split(':');
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
            ).toLocal();
            final closeTime = DateTime(
              now.year,
              now.month,
              now.day,
              closeHour,
              closeMinute,
            ).toLocal();
            isOpenNow = now.isAfter(openTime) && now.isBefore(closeTime);
          } catch (e) {
            Fluttertoast.showToast(
              msg: e.toString(),
              backgroundColor: Colors.red,
            );
          }
        }
      }
    }
    return isOpenNow;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        leading: IconButton(
          icon: Icon(IconlyLight.profile, size: 26.sp, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const VendorProfileEditPage(),
              ),
            );
          },
        ),
        title: Text(
          'ตั้งค่าเวลาร้านค้า',
          style: styles(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(IconlyLight.logout, size: 26.sp, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogOutPage()),
              );
            },
          ),
        ],
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _vendorStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No vendor data'));
          }

          final vendorData = snapshot.data!.data() as Map<String, dynamic>;

          if (hours.isEmpty) {
            final Map<String, Map<String, dynamic>> loadedHours = {};
            final rawHours =
                vendorData['storeHours'] as Map<String, dynamic>? ?? {};
            rawHours.forEach((fullKey, value) {
              loadedHours[fullKey] = Map<String, dynamic>.from(
                value as Map<String, dynamic>,
              )..putIfAbsent('closed', () => false);
            });
            hours = loadedHours;

            _isTemporarilyClosed = vendorData['temporarilyClosed'] ?? false;
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                SizedBox(height: 20.h),
                ..._days.asMap().entries.map((entry) {
                  final index = entry.key;
                  final shortDay = entry.value; // 'Mon'
                  final fullKey = _getDayKey(index + 1);
                  final dayEntry =
                      hours[fullKey] ??
                      {'open': null, 'close': null, 'closed': false};
                  return Padding(
                    padding: EdgeInsets.only(bottom: 2.h),
                    child: TimeSelectorWidget(
                      key: ValueKey(
                        '$shortDay-${dayEntry['closed']}-${dayEntry['open'] ?? ''}-${dayEntry['close'] ?? ''}',
                      ),
                      dayLabel: shortDay,
                      onSave: (d, o, c) => _onSaveTime(d, o, c, null),
                      onClosed: (isClosed) =>
                          _onSaveTime(shortDay, null, null, isClosed),
                      currentOpen: !(dayEntry['closed'] as bool)
                          ? (dayEntry['open'] as String?)
                          : null,
                      currentClose: !(dayEntry['closed'] as bool)
                          ? (dayEntry['close'] as String?)
                          : null,
                      currentClosed: dayEntry['closed'] as bool,
                    ),
                  );
                }),
                SizedBox(height: 40.h),
                SizedBox(
                  width: width * 0.5,
                  child: ButtonWidget(
                    label: 'บันทึก',
                    style: styles(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    icon: Icons.save,
                    press: _saveHours,
                    color: mainColor,
                    height: 50.h,
                  ),
                ),

                SizedBox(height: 70.h),
              ],
            ),
          );
        },
      ),

      floatingActionButton: FloatingActionButton(
        heroTag: 'table qr ',
        backgroundColor: Colors.white,

        child: Icon(
          Icons.table_restaurant_rounded,
          color: mainColor,
          size: 35.r,
        ),
        onPressed: () async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            Fluttertoast.showToast(msg: 'กรุณา login ก่อน');
            return;
          }

          try {
            final vendorDoc = await FirebaseFirestore.instance
                .collection('vendors')
                .doc(user.uid)
                .get();

            if (!vendorDoc.exists) {
              Fluttertoast.showToast(
                msg: 'ไม่พบข้อมูลร้านค้า กรุณาตั้งค่าโปรไฟล์',
              );
              return;
            }

            final vendorData = vendorDoc.data() as Map<String, dynamic>;

            final String restaurantId = user.uid;
            final String restaurantName =
                vendorData['bussinessName'] ?? 'ร้านไม่มีชื่อ';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TableQRGeneratorPage(
                  restaurantId: restaurantId,
                  restaurantName: restaurantName,
                ),
              ),
            );
          } catch (e) {
            Fluttertoast.showToast(msg: 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e');
          }
        },
      ),
    );
  }
}
