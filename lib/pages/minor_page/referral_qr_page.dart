import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:colae_shop/services/sevice.dart';

class ReferralQrPage extends StatefulWidget {
  final String referralCode;

  const ReferralQrPage({super.key, required this.referralCode});

  @override
  State<ReferralQrPage> createState() => _ReferralQrPageState();
}

class _ReferralQrPageState extends State<ReferralQrPage> {
  String _selectedApp = 'cust';

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

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _currentUrl));
    Fluttertoast.showToast(msg: 'คัดลอกลิ้งค์แล้ว');
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

            // QR Code
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
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black54,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
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

            // ปุ่ม Copy + Share
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_copy, size: 18),
                    label: const Text('คัดลอกลิ้งค์'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      fixedSize: const Size.fromHeight(40),
                      minimumSize: const Size(0, 40),
                      maximumSize: const Size(200, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                      side: BorderSide(color: color),
                      foregroundColor: color,
                    ),
                    onPressed: _copyLink,
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
