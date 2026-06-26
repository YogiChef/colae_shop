import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:colae_shop/services/sevice.dart';

enum _QrMode { table, storefront }

class TableQRGeneratorPage extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;

  const TableQRGeneratorPage({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  @override
  State<TableQRGeneratorPage> createState() => _TableQRGeneratorPageState();
}

class _TableQRGeneratorPageState extends State<TableQRGeneratorPage> {
  final TextEditingController _tableController = TextEditingController();
  String? _qrData;
  _QrMode? _currentMode;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void dispose() {
    _tableController.dispose();
    super.dispose();
  }

  void _showModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.r)),
        title: Text(
          'ประเภท Qr Code',
          textAlign: TextAlign.center,
          style: styles(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: context.isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeCard(
              icon: Icons.table_restaurant,
              iconColor: Colors.amber,
              title: 'โต๊ะในร้าน',
              subtitle:
                  'ลูกค้าสแกนแล้วระบุโต๊ะ\nเหมาะสำหรับร้านที่มีพนักงานเสิร์ฟ',
              onTap: () {
                Navigator.pop(ctx);
                _showTableInput();
              },
            ),
            SizedBox(height: 12.h),

            _ModeCard(
              icon: Icons.storefront,
              iconColor: Colors.green,
              title: 'หน้าร้าน',
              subtitle:
                  'ลูกค้าสแกนแล้วเห็นเมนูทันที\nเหมาะสำหรับ Takeaway / Counter',
              onTap: () {
                Navigator.pop(ctx);
                _generateStorefrontQR();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'ยกเลิก',
              style: styles(fontSize: 14.sp, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  void _showTableInput() {
    _tableController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.r)),
        title: Text(
          'ระบุเลขโต๊ะ',
          style: styles(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: context.isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: TextField(
          controller: _tableController,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'เลขโต๊ะ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7.r),
            ),
            prefixIcon: const Icon(Icons.table_bar),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'ยกเลิก',
              style: styles(fontSize: 13.sp, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            onPressed: () {
              final table = _tableController.text.trim();
              if (table.isEmpty) {
                Fluttertoast.showToast(msg: 'กรุณากรอกเลขโต๊ะ');
                return;
              }
              Navigator.pop(ctx);
              _generateTableQR(table);
            },
            child: Text(
              'สร้าง QR',
              style: styles(fontSize: 13.sp, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _generateTableQR(String table) {
    setState(() {
      _currentMode = _QrMode.table;
      _qrData =
          'delibox://table'
          '?restaurant_id=${widget.restaurantId}'
          '&table=${Uri.encodeComponent(table)}'
          '&name=${Uri.encodeComponent(widget.restaurantName)}';
    });
  }

  void _generateStorefrontQR() {
    _tableController.clear();
    setState(() {
      _currentMode = _QrMode.storefront;
      _qrData =
          'delibox://table'
          '?restaurant_id=${widget.restaurantId}'
          '&name=${Uri.encodeComponent(widget.restaurantName)}';
    });
  }

  Future<void> _saveQRToGallery() async {
    if (_qrData == null) {
      Fluttertoast.showToast(msg: 'กรุณาสร้าง QR ก่อน');
      return;
    }

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        Fluttertoast.showToast(msg: 'ต้องการสิทธิ์เพื่อบันทึกภาพลง Gallery');
        return;
      }
    }

    try {
      final boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final suffix = _currentMode == _QrMode.table
          ? 'โต๊ะ_${_tableController.text}'
          : 'หน้าร้าน';
      final fileName =
          'QR_${suffix}_${widget.restaurantName.replaceAll(' ', '_')}';

      await Gal.putImageBytes(pngBytes, album: 'DeliBox QR', name: fileName);
      Fluttertoast.showToast(
        msg: 'บันทึก QR สำเร็จ! อยู่ใน Gallery (อัลบั้ม DeliBox QR)',
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'เกิดข้อผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTable = _currentMode == _QrMode.table;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: Icon(Icons.arrow_back, color: context.textColor),
                  ),
                  Text(
                    'ร้าน: ${widget.restaurantName}',
                    style: styles(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: context.isDark ? Colors.white : mainColor,
                    ),
                  ),
                  SizedBox(),
                ],
              ),
              SizedBox(height: _qrData != null ? 60 : 120),
              if (_qrData != null) ...[
                Container(
                  margin: EdgeInsets.only(bottom: 16.h),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 5.h,
                  ),

                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTable ? Icons.table_restaurant : Icons.storefront,
                        size: 42.sp,
                        color: context.isDark
                            ? Colors.white
                            : isTable
                            ? mainColor
                            : Colors.indigo.shade700,
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        isTable ? 'โหมดโต๊ะ' : 'โหมดหน้าร้าน',
                        style: styles(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: context.isDark
                              ? Colors.white
                              : isTable
                              ? mainColor
                              : Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                // QR card
                Center(
                  child: RepaintBoundary(
                    key: _qrKey,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(16.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          QrImageView(
                            data: _qrData!,
                            version: QrVersions.auto,
                            size: 240.r,
                            gapless: false,
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            widget.restaurantName,
                            style: styles(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          if (isTable && _tableController.text.isNotEmpty)
                            Text(
                              'โต๊ะ ${_tableController.text}',
                              style: styles(
                                fontSize: 12.sp,
                                color: Colors.amber.shade700,
                              ),
                            )
                          else if (!isTable)
                            Text(
                              'สแกนเพื่อดูเมนู',
                              style: styles(
                                fontSize: 14.sp,
                                color: Colors.green.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 120.h),
              ] else ...[
                // placeholder
                InkWell(
                  onTap: _showModeDialog,
                  child: Center(
                    child: Container(
                      height: 310.h,
                      width: width * 0.8,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_2,
                            size: 170.sp,
                            color: Colors.black38,
                          ),
                          SizedBox(height: 10.h),
                          Text(
                            'กด "สร้าง QR Code"\nเพื่อเริ่มต้น',
                            textAlign: TextAlign.center,
                            style: styles(
                              fontSize: 13.sp,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 120.h),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 70.h,
          padding: EdgeInsets.only(
            left: 20.w,
            right: 20.w,

            bottom: MediaQuery.of(context).viewPadding.bottom + 20.h,
          ),
          child: _qrData != null
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showModeDialog,
                        icon: Icon(
                          Icons.refresh,
                          size: 24.sp,
                          color: context.isDark
                              ? Colors.white
                              : Colors.amber.shade700,
                        ),
                        label: Text(
                          'แก้ไข',
                          style: styles(
                            fontSize: 13.sp,
                            color: context.isDark
                                ? Colors.white
                                : Colors.amber.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: context.isDark
                                ? Colors.white
                                : Colors.amber.shade700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveQRToGallery,
                        icon: Icon(
                          Icons.download,
                          color: Colors.white,
                          size: 24.sp,
                        ),
                        label: Text(
                          'บันทึก',
                          style: styles(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mainColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7.r),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox(),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7.r),
          border: Border.all(color: Colors.grey.shade200),
          color: context.isDark ? Colors.white38 : Colors.grey.shade50,
        ),
        child: Row(
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: iconColor, size: 22.sp),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: styles(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: context.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: styles(
                      fontSize: 11.sp,
                      color: context.isDark
                          ? Colors.white70
                          : Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 20.sp,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
