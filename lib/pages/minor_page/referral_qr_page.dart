import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:colae_shop/services/sevice.dart';

class ReferralQrPage extends StatefulWidget {
  final String referralCode;
  final String userName;

  const ReferralQrPage({
    super.key,
    required this.referralCode,
    required this.userName,
  });

  @override
  State<ReferralQrPage> createState() => _ReferralQrPageState();
}

class _ReferralQrPageState extends State<ReferralQrPage> {
  String _selectedApp = 'cust';
  final ScreenshotController _screenshotController = ScreenshotController();

  static const String _baseUrl = 'https://colae-app.web.app/r';

  String get _currentUrl =>
      '$_baseUrl?code=${widget.referralCode}&app=$_selectedApp';

  final List<Map<String, dynamic>> _apps = [
    {
      'key': 'cust',
      'label': 'แอปลูกค้า',
      'icon': Icons.shopping_cart,
      'color': Colors.blue,
      'description': 'สั่งอาหาร + จองโรงแรม',
    },
    {
      'key': 'shop',
      'label': 'แอปร้านค้า',
      'icon': Icons.storefront,
      'color': Colors.orange,
      'description': 'เปิดร้านขายของ',
    },
    {
      'key': 'bike',
      'label': 'แอปไรเดอร์',
      'icon': Icons.delivery_dining,
      'color': Colors.green,
      'description': 'รับส่งอาหาร',
    },
  ];

  Widget _buildQrCard() {
    return Container(
      width: 400,
      height: 500,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            'เชิญเข้าร่วม Colae',
            style: styles(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: mainColor,
            ),
          ),
          Column(
            children: [
              Text(
                widget.userName,
                style: styles(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ร้านค้าคู่ค้า',
                style: styles(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: QrImageView(
              data: widget.referralCode,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          Column(
            children: [
              Text(
                'รหัสแนะนำ: ${widget.referralCode}',
                style: styles(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'สแกน QR หรือใช้รหัสแนะนำ',
                style: styles(
                  fontSize: 12,
                  color: Colors.grey[600],
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveQrToGallery() async {
    try {
      final bytes = await _screenshotController.captureFromWidget(
        _buildQrCard(),
        pixelRatio: 3.0,
        delay: const Duration(milliseconds: 200),
      );

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (!mounted) return;
          Fluttertoast.showToast(msg: 'ต้องอนุญาตให้เข้าถึงคลังภาพก่อน');
          return;
        }
      }

      await Gal.putImageBytes(bytes);
      if (!mounted) return;
      Fluttertoast.showToast(msg: 'บันทึกภาพสำเร็จ');
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: 'เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _shareLink() async {
    final app = _apps.firstWhere((a) => a['key'] == _selectedApp);
    final text =
        'มาสมัครใช้ ${app['label']} กับฉันสิ!\n\n'
        'รหัสแนะนำ: ${widget.referralCode}\n'
        'ลิ้งค์: $_currentUrl';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final selectedApp = _apps.firstWhere((a) => a['key'] == _selectedApp);
    final color = selectedApp['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: Text(
          'QR Code เชิญสมัคร',
          style: styles(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'เลือกแอป:',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple[900],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: _apps.map((app) {
                final isSelected = _selectedApp == app['key'];
                final c = app['color'] as Color;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: InkWell(
                      onTap: () =>
                          setState(() => _selectedApp = app['key'] as String),
                      child: Column(
                        children: [
                          Icon(
                            app['icon'] as IconData,
                            color: isSelected ? c : Colors.grey,
                            size: 24.sp,
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            app['label'] as String,
                            style: styles(
                              fontSize: 10.sp,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: isSelected ? c : Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 16.h),

            // QR Code แสดงบนหน้าจอ (interactive)
            Column(
              children: [
                SizedBox(height: 12.h),
                Text(
                  selectedApp['label'] as String,
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  selectedApp['description'] as String,
                  style: styles(fontSize: 11.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 16.h),
                QrImageView(
                  data: _currentUrl,
                  version: QrVersions.auto,
                  size: 220.w,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black54,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'รหัส: ${widget.referralCode}',
                  style: styles(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepPurple[900],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // ปุ่ม บันทึก QR + แชร์
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('บันทึก'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      fixedSize: const Size.fromHeight(40),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                      side: BorderSide(color: color),
                      foregroundColor: color,
                    ),
                    onPressed: _saveQrToGallery,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(
                      Icons.share,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'แชร์',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      fixedSize: const Size.fromHeight(40),
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                    ),
                    onPressed: _shareLink,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // วิธีใช้งาน
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(7.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'วิธีใช้งาน:',
                    style: styles(fontSize: 12.sp, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    '1. แสดง QR Code ให้คนที่จะแนะนำ\n'
                    '2. เขา/เธอใช้กล้องสแกน หรือกดที่ลิ้งค์\n'
                    '3. แอปจะเปิดอัตโนมัติ (หรือพาไป Play Store)\n'
                    '4. ตอนสมัคร — รหัสแนะนำของคุณจะถูกใส่อัตโนมัติ',
                    style: styles(
                      fontSize: 11.sp,
                      color: Colors.black54,
                      height: 1.6,
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
