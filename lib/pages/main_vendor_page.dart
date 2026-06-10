// ignore_for_file: avoid_print, use_build_context_synchronously, deprecated_member_use, curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:badges/badges.dart' as badges;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:promptpay_qrcode_generate/promptpay_qrcode_generate.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';

import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/models/vendor_model.dart';
import 'package:colae_shop/pages/tabs/upload/general_upload.dart';
import 'package:colae_shop/pages/tabs/eanings_tab/eanings_page.dart';
import 'package:colae_shop/pages/tabs/edit_tab/edit_page.dart';
import 'package:colae_shop/pages/tabs/orders/orders.dart';
import 'package:colae_shop/pages/tabs/settings/store_settings_page.dart';
import 'package:colae_shop/providers/vendor_order_provider.dart';
import 'package:colae_shop/services/sevice.dart';

class _SlipOcrResult {
  final bool amountMatch;
  final bool nameMatch;
  final bool dateMatch;

  const _SlipOcrResult({
    required this.amountMatch,
    required this.nameMatch,
    required this.dateMatch,
  });

  bool get allPassed => amountMatch && nameMatch && dateMatch;
  int get passedCount =>
      (amountMatch ? 1 : 0) + (nameMatch ? 1 : 0) + (dateMatch ? 1 : 0);
}

class MainVendorPage extends StatefulWidget {
  const MainVendorPage({super.key});

  @override
  State<MainVendorPage> createState() => _MainVendorPageState();
}

class _MainVendorPageState extends State<MainVendorPage> {
  int _currentTab = 0;
  final String vendorUid = auth.currentUser!.uid;
  Timer? _closeCheckTimer;
  VendorModel? _cachedVendor;
  static const double vatRate = 0.07;
  bool _hasShownDialog = false;
  StreamSubscription<DocumentSnapshot>? _vendorStream;
  StateSetter? _dialogSetState;

  String _getDueDateInfo(Timestamp? nextDue) {
    if (nextDue == null) return 'กำลังคำนวณ...';
    final due = nextDue.toDate();
    final daysLeft = due.difference(DateTime.now()).inDays;
    const thaiMonths = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    final dueFormatted =
        '${due.day} ${thaiMonths[due.month]} ${due.year + 543}';
    if (daysLeft > 1) {
      return 'เหลือ $daysLeft วัน ถึงกำหนดชำระ\n($dueFormatted)';
    }
    if (daysLeft == 1) return 'เหลือ 1 วัน ถึงกำหนดชำระ\n($dueFormatted)';
    if (daysLeft == 0) return 'ครบกำหนดชำระวันนี้\n($dueFormatted)';
    return 'เลยกำหนดชำระ ${-daysLeft} วัน\n($dueFormatted)';
  }

  @override
  void initState() {
    super.initState();
    _checkAndShowBillingAlert();
    _vendorStream = firestore
        .collection('vendors')
        .doc(vendorUid)
        .snapshots()
        .listen((snap) {
          if (!snap.exists || snap.data() == null) return;
          final model = VendorModel.fromJson(
            snap.data() as Map<String, dynamic>,
          );
          if (mounted) {
            setState(() => _cachedVendor = model);
            _dialogSetState?.call(() {});
          }
        });
  }

  @override
  void dispose() {
    _closeCheckTimer?.cancel();
    _vendorStream?.cancel();
    super.dispose();
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
          final openStr = dayHours['open']?.toString() ?? '';
          final closeStr = dayHours['close']?.toString() ?? '';
          if (openStr.isEmpty || closeStr.isEmpty) return true;

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
            isOpenNow = true;
          }
        }
      }
    }
    return isOpenNow;
  }

  void _startCloseCheckTimer(VendorModel vendorsModel) {
    _cachedVendor = vendorsModel;
    _closeCheckTimer?.cancel();
    _closeCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final isOpenNow = _checkIsOpenNow(_cachedVendor!);
      if (!isOpenNow || _cachedVendor!.temporarilyClosed) {
        timer.cancel();
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (route) => false,
              );
            }
          });
        }
      }
    });
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

  Future<double> getVendorFee(
    double? totalSales, {
    double accumulatedCommission = 0.0,
  }) async {
    if (totalSales == null || totalSales < 0) return 0.0;
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('calculateVendorFee');
      final result = await callable.call({
        'totalSales': totalSales,
        'accumulatedCommission': accumulatedCommission,
      });
      return (result.data['fee'] as num).toDouble();
    } catch (e) {
      double fee = 0;
      if (totalSales <= 5000) {
        fee = 0;
      } else if (totalSales <= 25000)
        fee = 159;
      else if (totalSales <= 55000)
        fee = 359;
      else if (totalSales <= 150000)
        fee = 759;
      else if (totalSales <= 250000)
        fee = 1259;
      else
        fee = 1259 + (totalSales - 250000) * 0.07;
      return double.parse((fee + accumulatedCommission).toStringAsFixed(2));
    }
  }

  Future<_SlipOcrResult> _runSlipOcr(
    String imagePath,
    double totalWithVat,
    String storeName,
  ) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final text = recognized.text;

      bool amountMatch = false;
      for (final m in RegExp(r'[\d,]+\.?\d*').allMatches(text)) {
        final val = double.tryParse(m.group(0)!.replaceAll(',', ''));
        if (val != null && (val - totalWithVat).abs() < 1.0) {
          amountMatch = true;
          break;
        }
      }

      bool nameMatch = false;
      if (storeName.isNotEmpty) {
        final lowerText = text.toLowerCase();
        for (final word in storeName.toLowerCase().trim().split(
          RegExp(r'\s+'),
        )) {
          if (word.length >= 3 && lowerText.contains(word)) {
            nameMatch = true;
            break;
          }
        }
      }

      bool dateMatch = false;
      final now = DateTime.now();
      final d = now.day;
      final mo = now.month;
      final yAD = now.year;
      final yBE4 = yAD + 543;
      final yBE2 = yBE4 % 100;
      final dp = d.toString().padLeft(2, '0');
      final mp = mo.toString().padLeft(2, '0');
      for (final pattern in [
        '$dp/$mp/$yAD', // 01/03/2025 (ค.ศ.)
        '$dp/$mp/$yBE4', // 01/03/2568 (พ.ศ.)
        '$dp/$mp/${yBE2.toString().padLeft(2, '0')}', // 01/03/68
        '$d/$mo/${yBE2.toString().padLeft(2, '0')}', // 1/3/68
        '$yAD-$mp-$dp', // 2025-03-01 (ISO)
      ]) {
        if (text.contains(pattern)) {
          dateMatch = true;
          break;
        }
      }

      return _SlipOcrResult(
        amountMatch: amountMatch,
        nameMatch: nameMatch,
        dateMatch: dateMatch,
      );
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _confirmPayment(
    BuildContext dialogContext, {
    bool requiresAdminReview = false,
  }) async {
    final uid = auth.currentUser!.uid;
    final vendorRef = firestore.collection('vendors').doc(uid);

    final now = DateTime.now();
    final nextCycle = Timestamp.fromDate(now.add(const Duration(days: 30)));
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}'; // e.g. "2025-03"
    final monthlyRef = vendorRef.collection('monthly_sales').doc(monthKey);

    final vDoc = await vendorRef.get();
    final currentTotal =
        (vDoc.data()?['totalSales'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> vendorUpdates = {
      'pendingFee': 0,
      'lastBilledSales': currentTotal,
      'nextDueDate': nextCycle,
      'paymentStatus': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      if (requiresAdminReview) 'requiresAdminReview': true,
    };

    final Map<String, dynamic> monthlyUpdates = {
      'paid': true,
      'paidAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    await Future.wait([
      vendorRef.update(vendorUpdates),
      monthlyRef.set(monthlyUpdates, SetOptions(merge: true)),
    ]);

    _hasShownDialog = false;
    if (mounted) {
      Navigator.pop(dialogContext);
      _dialogSetState = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requiresAdminReview ? 'ชำระเงินสำเร็จ!' : 'ชำระเงินสำเร็จแล้ว',
            style: styles(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _checkAndShowBillingAlert();
        }
      });
    }
  }

  void _showPaymentAlert(double fee, double totalSales, Timestamp nextDue) {
    if (!mounted) return;
    final String storeName = _cachedVendor?.bussinessName ?? '';

    final screenshotController = ScreenshotController();

    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          _dialogSetState = setDialogState;
          final double liveFee = (_cachedVendor?.pendingFee ?? fee).toDouble();
          final double liveTotalSales =
              (_cachedVendor?.totalSales ?? totalSales).toDouble();
          final double liveVat = liveFee * vatRate;
          final double liveTotalWithVat = liveFee + liveVat;
          final Timestamp liveNextDue = (_cachedVendor?.nextDueDate) ?? nextDue;

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) {}
              Fluttertoast.showToast(
                msg: "กรุณาชำระค่าบริการก่อน",
                backgroundColor: Colors.red,
              );
            },
            child: Dialog(
              insetPadding: EdgeInsets.only(left: 6.w, right: 6.w),
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: 12.h),
                        Icon(
                          Icons.warning_rounded,
                          color: Colors.amber,
                          size: 54.r,
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          'แจ้งเตือนค่าบริการ',
                          textAlign: TextAlign.center,
                          style: styles(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 20.w, right: 20.w),
                          child: Text(
                            'โปรดชำระค่าบริการเพื่อการจัดการในระบบของท่าน!',
                            textAlign: TextAlign.center,
                            style: styles(
                              fontSize: 13.sp,
                              color: Colors.orange,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        Screenshot(
                          controller: screenshotController,
                          child: RepaintBoundary(
                            child: Container(
                              padding: EdgeInsets.all(16.r),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: QRCodeGenerate(
                                amount: liveTotalWithVat,
                                width: 270,
                                height: 270,
                                promptPayId: '0925403189',
                                isShowAccountDetail: false,
                                isShowAmountDetail: false,
                              ),
                            ),
                          ),
                        ),

                        Text(
                          'ยอดขายทั้งหมด: ฿${liveTotalSales.toStringAsFixed(2)}',
                          textAlign: TextAlign.center,
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'ค่าบริการ: ฿${liveFee.toStringAsFixed(2)}',
                          style: styles(fontSize: 12.sp, color: Colors.black87),
                        ),
                        Text(
                          'ภาษีมูลค่าเพิ่ม (VAT 7%): ฿${liveVat.toStringAsFixed(2)}',
                          style: styles(fontSize: 12.sp, color: Colors.black87),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          _getDueDateInfo(liveNextDue),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: styles(fontSize: 11.sp, color: Colors.orange),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'รวมชำระทั้งสิ้น: ฿${liveTotalWithVat.toStringAsFixed(2)}',
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange.shade900,
                          ),
                        ),
                        SizedBox(height: 22.h),
                        Padding(
                          padding: EdgeInsets.only(bottom: 20.h),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // ปุ่มบันทึก QR
                              paymentButton(
                                icon: Icons.file_download_outlined,
                                text: 'Qr Code',
                                color: Colors.amber,
                                onPressed: () async {
                                  final Uint8List? capturedImage =
                                      await screenshotController.capture();
                                  if (capturedImage == null) {
                                    Fluttertoast.showToast(
                                      msg: 'ไม่สามารถ capture QR ได้',
                                    );
                                    return;
                                  }
                                  try {
                                    await Gal.putImageBytes(
                                      capturedImage,
                                      album: 'VendorBox',
                                      name:
                                          'qr_promptpay_${DateTime.now().millisecondsSinceEpoch}.png',
                                    );
                                    Fluttertoast.showToast(
                                      msg: 'บันทึก QR ลง Gallery สำเร็จ!',
                                    );
                                  } catch (e) {
                                    Fluttertoast.showToast(
                                      msg: 'บันทึกล้มเหลว: $e',
                                    );
                                  }
                                },
                              ),
                              SizedBox(width: 6.w),
                              paymentButton(
                                icon: Icons.upload_file,
                                text: 'ส่งสลิป',
                                color: Colors.blue,
                                onPressed: () async {
                                  final picker = ImagePicker();
                                  final XFile? image = await picker.pickImage(
                                    source: ImageSource.gallery,
                                  );
                                  if (image == null) {
                                    Fluttertoast.showToast(
                                      msg: 'ไม่ได้เลือกภาพ',
                                    );
                                    return;
                                  }
                                  EasyLoading.show(
                                    status: 'กำลังตรวจสอบสลิป OCR...',
                                  );
                                  try {
                                    final slipRef = FirebaseStorage.instance
                                        .ref()
                                        .child(
                                          'slips/${auth.currentUser!.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
                                        );
                                    final results = await Future.wait<dynamic>([
                                      slipRef.putFile(File(image.path)),
                                      _runSlipOcr(
                                        image.path,
                                        liveTotalWithVat,
                                        storeName,
                                      ),
                                    ]);
                                    final ocr = results[1] as _SlipOcrResult;
                                    EasyLoading.dismiss();

                                    if (ocr.passedCount == 3) {
                                      EasyLoading.show(
                                        status: 'ยืนยันการชำระเงิน...',
                                      );
                                      try {
                                        await _confirmPayment(dialogContext);
                                      } finally {
                                        EasyLoading.dismiss();
                                      }
                                    } else if (ocr.passedCount >= 1) {
                                      EasyLoading.show(
                                        status: 'ยืนยันการชำระเงิน...',
                                      );
                                      try {
                                        await _confirmPayment(
                                          dialogContext,
                                          requiresAdminReview: true,
                                        );
                                      } finally {
                                        EasyLoading.dismiss();
                                      }
                                      Fluttertoast.showToast(
                                        msg:
                                            'ชำระสำเร็จ (รอ admin ตรวจสอบเพิ่มเติม)',
                                        backgroundColor: Colors.orange,
                                      );
                                    } else {
                                      Fluttertoast.showToast(
                                        msg:
                                            'ไม่สามารถอ่านสลิปได้\nกรุณาตรวจสอบสลิปและลองใหม่',
                                        backgroundColor: Colors.red,
                                        toastLength: Toast.LENGTH_LONG,
                                      );
                                    }
                                  } catch (e) {
                                    EasyLoading.dismiss();
                                    Fluttertoast.showToast(
                                      msg: 'เกิดข้อผิดพลาด: $e',
                                      backgroundColor: Colors.red,
                                    );
                                  }
                                },
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
          );
        },
      ),
    ).then((_) => _dialogSetState = null);
  }

  Widget paymentButton({
    Key? key,
    required IconData icon,
    required String text,
    required Color color,
    required Function() onPressed,
  }) {
    return SizedBox(
      key: key,
      height: 50.h,
      width: width * 0.45.w,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Text(
          text,
          style: styles(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7.r),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Future<void> _checkAndShowBillingAlert() async {
    if (!mounted || _hasShownDialog) return;

    try {
      final vendorRef = firestore
          .collection('vendors')
          .doc(auth.currentUser!.uid);
      final vendorDoc = await vendorRef.get();
      if (!vendorDoc.exists) return;

      final data = vendorDoc.data() as Map<String, dynamic>;

      double totalSales = (data['totalSales'] as num?)?.toDouble() ?? 0.0;
      double lastBilledSales =
          (data['lastBilledSales'] as num?)?.toDouble() ?? 0.0;
      double pendingFee = (data['pendingFee'] as num?)?.toDouble() ?? 0.0;
      Timestamp? nextDueDate = data['nextDueDate'] as Timestamp?;

      // ตั้งค่า nextDueDate ครั้งแรกถ้ายังไม่มี
      if (nextDueDate == null) {
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        nextDueDate = Timestamp.fromDate(
          createdAt.add(const Duration(days: 30)),
        );
        try {
          await FirebaseFirestore.instance.enableNetwork();
        } catch (_) {}
        await vendorRef.update({
          'nextDueDate': nextDueDate,
          'lastBilledSales': 0,
          'pendingFee': 0,
        });
      }

      final double accumulatedCommission =
          (data['accumulatedCommission'] as num?)?.toDouble() ?? 0.0;
      final double billable = totalSales - lastBilledSales;
      if (billable > 5000) {
        pendingFee = await getVendorFee(
          billable,
          accumulatedCommission: accumulatedCommission,
        );
        try {
          await FirebaseFirestore.instance.enableNetwork();
        } catch (_) {}
        await vendorRef.update({'pendingFee': pendingFee});
      }

      if (pendingFee <= 0) return;
      final DateTime dueDate = nextDueDate.toDate();
      final bool isDue = !DateTime.now().isBefore(dueDate);
      if (!isDue) return;

      _hasShownDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPaymentAlert(pendingFee, totalSales, nextDueDate!);
        }
      });
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedVendor == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final vendorsModel = _cachedVendor!;

    if (vendorsModel.temporarilyClosed ||
        vendorsModel.approved != true ||
        !_checkIsOpenNow(vendorsModel)) {
      _startCloseCheckTimer(vendorsModel);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: mainColor,
      bottomNavigationBar: SafeArea(
        child: BottomNavigationBar(
          backgroundColor: mainColor,
          currentIndex: _currentTab,
          selectedItemColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          unselectedItemColor: Colors.white70,
          selectedIconTheme: IconThemeData(size: 22.sp),
          selectedLabelStyle: GoogleFonts.righteous(fontSize: 14.sp),
          onTap: (index) => setState(() => _currentTab = index),
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                _currentTab == 0 ? IconlyBold.wallet : IconlyLight.wallet,
              ),
              label: 'Earnings',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentTab == 1 ? IconlyBold.upload : IconlyLight.upload,
              ),
              label: 'Upload',
            ),
            BottomNavigationBarItem(
              icon: Icon(_currentTab == 2 ? IconlyBold.edit : IconlyLight.edit),
              label: 'Edit',
            ),
            BottomNavigationBarItem(
              icon: Consumer<VendorOrderProvider>(
                builder: (context, provider, child) {
                  final count = provider.pendingOrderCount;
                  return badges.Badge(
                    showBadge: count > 0,
                    badgeContent: Text(
                      count.toString(),
                      style: styles(color: Colors.white, fontSize: 11.sp),
                    ),
                    child: Icon(
                      _currentTab == 3 ? IconlyBold.bag2 : IconlyLight.bag2,
                    ),
                  );
                },
              ),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentTab == 4 ? IconlyBold.setting : IconlyLight.setting,
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentTab,
        children: const [
          EarningPage(),
          GeneralUpload(),
          EditPage(),
          OrderPage(),
          StoreSettingsPage(),
        ],
      ),
    );
  }
}
