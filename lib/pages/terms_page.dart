// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String CURRENT_TERMS_VERSION = '1.0';

class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _acceptTerms() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);

    try {
      final uid = auth.currentUser!.uid;
      await firestore.collection('vendors').doc(uid).set({
        'termsAcceptedVersion': CURRENT_TERMS_VERSION,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Get.offAllNamed('/landing');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
      }
    }
  }

  Future<void> _declineTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vendor_last_mode');

    await auth.signOut();

    if (!mounted) return;
    Get.offAllNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'ข้อกำหนดและเงื่อนไข',
            style: styles(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: mainColor,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ก่อนเริ่มใช้งาน Colae',
                      style: styles(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: mainColor,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'โปรดอ่านเงื่อนไขต่อไปนี้อย่างละเอียด',
                      style: styles(fontSize: 13.sp, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 20.h),
                    _buildTermsContent(),
                    SizedBox(height: 8.h),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      title: Text(
                        'ฉันได้อ่านและยอมรับเงื่อนไขทั้งหมด',
                        style: styles(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      activeColor: mainColor,
                    ),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                              side: BorderSide(color: Colors.red.shade300),
                            ),
                            onPressed: _saving ? null : _declineTerms,
                            child: Text(
                              'ไม่ยอมรับ',
                              style: styles(
                                color: Colors.red.shade700,
                                fontSize: 14.sp,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accepted
                                  ? mainColor
                                  : Colors.grey,
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                            ),
                            onPressed: (_accepted && !_saving)
                                ? _acceptTerms
                                : null,
                            child: Text(
                              _saving ? 'กำลังบันทึก...' : 'ยอมรับ',
                              style: styles(
                                color: Colors.white,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          '1. มาตรฐานสินค้าและบริการ',
          '• สินค้าต้องสะอาด ปลอดภัย ตรงตามรายละเอียดที่แสดง\n'
              '• ราคาต้องตรงกับที่ระบุในแอป ห้ามเรียกเก็บเพิ่ม\n'
              '• เวลาเตรียม/จัดส่งต้องตรงตามที่แจ้งลูกค้า',
        ),
        _section(
          '2. การยืนยัน Order',
          '• ต้องยืนยันรับ order ภายใน 5 นาทีหลังลูกค้าสั่ง\n'
              '• หากไม่สะดวกรับ order ให้กดปฏิเสธ — ห้ามปล่อยค้าง\n'
              '• การยกเลิก order หลังลูกค้าจ่ายเงินแล้ว ต้องคืนเงินภายใน 24 ชม.',
        ),
        _section(
          '3. ระบบให้คะแนน',
          '• ลูกค้าจะให้คะแนนสินค้าและร้านค้าหลังรับของ\n'
              '• ท่านสามารถให้คะแนนลูกค้าได้ในด้านความสุภาพและการจ่ายเงิน\n'
              '• คะแนนเฉลี่ยส่งผลต่อ:\n'
              '   - การจัดอันดับร้านในหน้าค้นหา\n'
              '   - สิทธิ์รับรายได้ MLM (คะแนน < 4.0 รายได้ลด)\n'
              '   - การพิจารณาระงับบัญชีหากต่ำกว่ามาตรฐาน',
        ),
        _section(
          '4. ค่าบริการแพลตฟอร์ม',
          '• Colae ไม่หักค่าธรรมเนียมจากร้านโดยตรง\n'
              '• ร้านสนับสนุนค่าส่ง 5-7% ของยอดอาหาร (Delivery mode)\n'
              '• รายได้ MLM จาก downline จะจ่ายตามเกณฑ์ที่กำหนด',
        ),
        _section(
          '5. การชำระเงิน',
          '• รับเงินสดต้องตรวจนับและกดยืนยันในแอป\n'
              '• รับ QR/โอน ต้องตรวจสลิปก่อนยืนยัน\n'
              '• การยืนยันรับเงินถือเป็นการรับรองว่าได้รับเงินครบ',
        ),
        _section(
          '6. พฤติกรรมที่ไม่ยอมรับ',
          '• ปลอมแปลงเมนู/รูปภาพ/รีวิว\n'
              '• เรียกเก็บเงินเพิ่มนอกระบบ\n'
              '• หยาบคาย/คุกคามลูกค้าหรือไรเดอร์\n'
              '• ขายของผิดกฎหมาย / สิ่งที่เป็นอันตราย',
        ),
        _section(
          '7. ปรัชญาของระบบ',
          'Colae เชื่อว่าร้านค้าคือหุ้นส่วนทางธุรกิจ ไม่ใช่ผู้ใต้บังคับบัญชา '
              'ท่านมีสิทธิ์เลือกรับ/ปฏิเสธ order มีสิทธิ์ให้คะแนนลูกค้า '
              'และมีสิทธิ์ได้รับการเคารพจากทุกฝ่าย',
        ),
      ],
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: styles(
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            content,
            style: styles(
              fontSize: 13.sp,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
