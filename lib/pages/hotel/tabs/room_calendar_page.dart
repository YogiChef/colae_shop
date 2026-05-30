// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:colae_shop/services/sevice.dart';

class RoomCalendarPage extends StatefulWidget {
  final String roomId;
  final String roomName;
  final double basePrice;
  const RoomCalendarPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.basePrice,
  });

  @override
  State<RoomCalendarPage> createState() => _RoomCalendarPageState();
}

class _RoomCalendarPageState extends State<RoomCalendarPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  DateTime _focused = DateTime.now();
  Map<String, Map<String, dynamic>> _specialPrices = {};

  @override
  void initState() {
    super.initState();
    _loadSpecialPrices();
  }

  Future<void> _loadSpecialPrices() async {
    final snap = await FirebaseFirestore.instance
        .collection('hotels')
        .doc(_uid)
        .collection('rooms')
        .doc(widget.roomId)
        .collection('special_prices')
        .get();
    final m = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      m[doc.id] = doc.data();
    }
    if (mounted) setState(() => _specialPrices = m);
  }

  Future<void> _editPrice(DateTime day) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final existing = _specialPrices[dateKey];
    final priceController = TextEditingController(
      text: existing?['price']?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: existing?['note']?.toString() ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ราคาพิเศษ ${DateFormat('d MMM yyyy').format(day)}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ราคา default: ฿${widget.basePrice.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ราคาพิเศษ (฿)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ (เช่น ปีใหม่)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('ยกเลิก'),
          ),
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mainColor),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('บันทึก', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    final ref = FirebaseFirestore.instance
        .collection('hotels')
        .doc(_uid)
        .collection('rooms')
        .doc(widget.roomId)
        .collection('special_prices')
        .doc(dateKey);

    if (result == 'save') {
      final price = double.tryParse(priceController.text.trim()) ?? 0;
      if (price <= 0) return;
      await ref.set({
        'price': price,
        'note': noteController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadSpecialPrices();
    } else if (result == 'delete') {
      await ref.delete();
      _loadSpecialPrices();
    }

    priceController.dispose();
    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ราคาพิเศษ - ${widget.roomName}',
          style: styles(color: Colors.white, fontSize: 16.sp),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีโหลด',
            onPressed: _loadSpecialPrices,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blue.shade50,
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'ราคา default ฿${widget.basePrice.toStringAsFixed(0)}/คืน — กดวันเพื่อตั้งราคาพิเศษ',
                    style: styles(fontSize: 12.sp, color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ),
          TableCalendar(
            firstDay: DateTime.now().subtract(const Duration(days: 30)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focused,
            calendarFormat: CalendarFormat.month,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: mainColor.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: mainColor,
                shape: BoxShape.circle,
              ),
            ),
            onPageChanged: (d) => setState(() => _focused = d),
            onDaySelected: (sel, _) => _editPrice(sel),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) {
                final key = DateFormat('yyyy-MM-dd').format(day);
                final sp = _specialPrices[key];
                if (sp == null) return null;
                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(fontSize: 12.sp),
                      ),
                      Text(
                        '฿${(sp['price'] as num).toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.orange[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_specialPrices.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              child: Row(
                children: [
                  Icon(Icons.list_alt, size: 16.sp, color: Colors.grey),
                  SizedBox(width: 6.w),
                  Text(
                    'รายการราคาพิเศษ (${_specialPrices.length})',
                    style: styles(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                children: (_specialPrices.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key)))
                    .map((e) {
                  final date = DateTime.parse(e.key);
                  final note = e.value['note'] as String? ?? '';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.event, color: Colors.orange),
                      title: Text(DateFormat('d MMM yyyy').format(date)),
                      subtitle: note.isNotEmpty ? Text(note) : null,
                      trailing: Text(
                        '฿${(e.value['price'] as num).toStringAsFixed(0)}',
                        style: styles(
                          fontSize: 14.sp,
                          color: mainColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _editPrice(date),
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Text(
                  'ยังไม่มีราคาพิเศษ',
                  style: styles(fontSize: 14.sp, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
