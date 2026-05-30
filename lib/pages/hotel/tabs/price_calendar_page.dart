// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:colae_shop/services/sevice.dart';

class PriceCalendarPage extends StatefulWidget {
  final String roomId;
  final String roomName;

  const PriceCalendarPage({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<PriceCalendarPage> createState() => _PriceCalendarPageState();
}

class _PriceCalendarPageState extends State<PriceCalendarPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late DateTime _focusedMonth;
  Map<String, Map<String, dynamic>> _specialPrices = {};
  bool _loading = true;

  static const _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _loadPrices();
  }

  DocumentReference get _roomRef => FirebaseFirestore.instance
      .collection('hotels')
      .doc(_uid)
      .collection('rooms')
      .doc(widget.roomId);

  Future<void> _loadPrices() async {
    setState(() => _loading = true);
    try {
      final snap = await _roomRef.collection('special_prices').get();
      if (mounted) {
        setState(() {
          _specialPrices = {
            for (final doc in snap.docs) doc.id: doc.data(),
          };
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(
        msg: 'โหลดข้อมูลผิดพลาด: $e',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _showPriceDialog(
    String dateKey,
    Map<String, dynamic>? existing,
  ) async {
    final priceController = TextEditingController(
      text: existing != null ? '${existing['price'] ?? ''}' : '',
    );
    final noteController = TextEditingController(
      text: existing?['note'] as String? ?? '',
    );

    final parts = dateKey.split('-');
    final displayDate = '${parts[2]}/${parts[1]}/${int.parse(parts[0]) + 543}';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20.w,
          right: 20.w,
          top: 20.h,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20.h,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'ราคาพิเศษ — $displayDate',
              style: styles(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: priceController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d+\.?\d{0,2}'),
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'ราคา (฿)',
                border: OutlineInputBorder(),
                prefixText: '฿ ',
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ',
                hintText: 'เช่น วันหยุดนักขัตฤกษ์, ปีใหม่',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                if (existing != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 18.sp,
                      ),
                      label: Text(
                        'ลบ',
                        style: styles(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _deletePrice(dateKey);
                      },
                    ),
                  ),
                  SizedBox(width: 12.w),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                      Icons.save,
                      color: Colors.white,
                      size: 18.sp,
                    ),
                    label: Text(
                      'บันทึก',
                      style: styles(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                    ),
                    onPressed: () async {
                      final priceText = priceController.text.trim();
                      if (priceText.isEmpty) {
                        Fluttertoast.showToast(msg: 'กรุณากรอกราคา');
                        return;
                      }
                      final price = num.tryParse(priceText);
                      if (price == null) {
                        Fluttertoast.showToast(msg: 'ราคาไม่ถูกต้อง');
                        return;
                      }
                      Navigator.pop(ctx);
                      await _savePrice(
                        dateKey,
                        price,
                        noteController.text.trim(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    priceController.dispose();
    noteController.dispose();
  }

  Future<void> _savePrice(String dateKey, num price, String note) async {
    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await _roomRef.collection('special_prices').doc(dateKey).set({
        'price': price,
        'note': note,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _specialPrices[dateKey] = {'price': price, 'note': note};
      });
      EasyLoading.showSuccess('บันทึกสำเร็จ');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Future<void> _deletePrice(String dateKey) async {
    EasyLoading.show(status: 'กำลังลบ...');
    try {
      await _roomRef.collection('special_prices').doc(dateKey).delete();
      setState(() => _specialPrices.remove(dateKey));
      EasyLoading.showSuccess('ลบสำเร็จ');
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ราคาพิเศษ',
              style: styles(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.roomName,
              style: styles(color: Colors.white70, fontSize: 12.sp),
            ),
          ],
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีโหลด',
            onPressed: _loadPrices,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : Column(
              children: [
                _buildMonthNavigator(),
                const Divider(height: 1),
                _buildDayHeaders(),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildCalendarGrid(),
                  ),
                ),
                _buildLegend(),
              ],
            ),
    );
  }

  Widget _buildMonthNavigator() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month - 1,
              );
            }),
          ),
          Column(
            children: [
              Text(
                _thaiMonths[_focusedMonth.month - 1],
                style: styles(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'พ.ศ. ${_focusedMonth.year + 543}',
                style: styles(fontSize: 12.sp, color: Colors.grey),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month + 1,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    const labels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final colors = [
      Colors.black87,
      Colors.black87,
      Colors.black87,
      Colors.black87,
      Colors.black87,
      Colors.blue.shade700,
      Colors.red.shade700,
    ];
    return Row(
      children: List.generate(7, (i) {
        return Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            color: Colors.grey.shade50,
            child: Text(
              labels[i],
              textAlign: TextAlign.center,
              style: styles(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: colors[i],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    // weekday: 1=Mon ... 7=Sun → offset เพื่อให้จันทร์อยู่คอลัมน์แรก
    final offset = firstDay.weekday - 1;
    final today = DateTime.now();
    final cells = <Widget>[];

    // ช่องว่างก่อนวันที่ 1
    for (int i = 0; i < offset; i++) {
      cells.add(Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          color: Colors.grey.shade50,
        ),
      ));
    }

    for (int day = 1; day <= lastDay.day; day++) {
      final date =
          DateTime(_focusedMonth.year, _focusedMonth.month, day);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      final specialPrice = _specialPrices[dateKey];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isPast =
          date.isBefore(DateTime(today.year, today.month, today.day));

      cells.add(_DayCell(
        day: day,
        specialPrice: specialPrice,
        isToday: isToday,
        isPast: isPast,
        isSaturday: date.weekday == 6,
        isSunday: date.weekday == 7,
        onTap: () => _showPriceDialog(dateKey, specialPrice),
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.72,
      children: cells,
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          _legendDot(Colors.orange.shade100, 'ราคาพิเศษ'),
          SizedBox(width: 20.w),
          _legendDot(mainColor.withOpacity(0.2), 'วันนี้'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16.w,
          height: 16.h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4.r),
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),
        SizedBox(width: 6.w),
        Text(
          label,
          style: styles(fontSize: 12.sp, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final Map<String, dynamic>? specialPrice;
  final bool isToday;
  final bool isPast;
  final bool isSaturday;
  final bool isSunday;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.specialPrice,
    required this.isToday,
    required this.isPast,
    required this.isSaturday,
    required this.isSunday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSpecial = specialPrice != null;

    Color bgColor = Colors.white;
    if (isToday) bgColor = mainColor.withOpacity(0.2);
    if (hasSpecial) bgColor = Colors.orange.shade100;

    Color dayColor = Colors.black87;
    if (isSunday) dayColor = Colors.red.shade700;
    if (isSaturday) dayColor = Colors.blue.shade700;
    if (isPast) dayColor = dayColor.withOpacity(0.35);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: isToday ? mainColor : Colors.grey.shade200,
            width: isToday ? 1.5 : 0.5,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 4.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              '$day',
              style: styles(
                fontSize: 13.sp,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w400,
                color: dayColor,
              ),
            ),
            if (hasSpecial) ...[
              SizedBox(height: 2.h),
              Text(
                '฿${specialPrice!['price']}',
                style: styles(
                  fontSize: 9.sp,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if ((specialPrice!['note'] as String?)?.isNotEmpty == true)
                Text(
                  specialPrice!['note'] as String,
                  style: styles(
                    fontSize: 8.sp,
                    color: Colors.orange.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
