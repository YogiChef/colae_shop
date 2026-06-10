// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/auth/landing_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fluttertoast/fluttertoast.dart';

class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  Map<String, List<QueryDocumentSnapshot>> _bookingsByDate = {};
  Map<String, int> _roomTotals = {};
  int _totalRoomsAll = 0;

  @override
  void initState() {
    super.initState();
    _loadRoomTotals();
    _loadBookings();
  }

  Future<void> _loadRoomTotals() async {
    final snap = await FirebaseFirestore.instance
        .collection('hotels')
        .doc(_uid)
        .collection('rooms')
        .get();
    int total = 0;
    final m = <String, int>{};
    for (final d in snap.docs) {
      final t = (d.data()['totalRooms'] as num?)?.toInt() ?? 0;
      m[d.id] = t;
      total += t;
    }
    if (mounted) {
      setState(() {
        _roomTotals = m;
        _totalRoomsAll = total;
      });
    }
  }

  Future<void> _loadBookings() async {
    final snap = await FirebaseFirestore.instance
        .collection('hotel_bookings')
        .where('hotelId', isEqualTo: _uid)
        .where('status', whereIn: ['pending', 'confirmed', 'checked_in'])
        .get();

    final m = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final checkIn = (d['checkIn'] as Timestamp).toDate();
      final checkOut = (d['checkOut'] as Timestamp).toDate();

      DateTime cursor = DateTime(checkIn.year, checkIn.month, checkIn.day);
      final endDate = DateTime(checkOut.year, checkOut.month, checkOut.day);
      while (cursor.isBefore(endDate)) {
        final key = DateFormat('yyyy-MM-dd').format(cursor);
        m.putIfAbsent(key, () => []).add(doc);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    if (mounted) setState(() => _bookingsByDate = m);
  }

  int _roomsBookedOnDate(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final list = _bookingsByDate[key] ?? [];
    int count = 0;
    for (final doc in list) {
      final d = doc.data() as Map<String, dynamic>;
      count += (d['rooms'] as num?)?.toInt() ?? 1;
    }
    return count;
  }

  Color _dayColor(DateTime day) {
    if (_totalRoomsAll == 0) return Colors.white;
    final booked = _roomsBookedOnDate(day);
    if (booked == 0) return Colors.white;
    if (booked >= _totalRoomsAll) return Colors.red.shade300;
    return Colors.yellow.shade300;
  }

  void _showDayDetails(DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DayDetailsSheet(
        day: day,
        bookings: _bookingsByDate[DateFormat('yyyy-MM-dd').format(day)] ?? [],
        roomTotals: _roomTotals,
        onUpdated: () {
          _loadBookings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'การจอง',
          style: styles(
            color: Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('vendor_last_mode');
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (route) => false,
            );
          },
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadRoomTotals();
              _loadBookings();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Legend
            Container(
              padding: EdgeInsets.all(12.w),
              color: Colors.grey.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _legendItem(Colors.white, 'ว่าง', Colors.grey),
                  _legendItem(Colors.yellow.shade300, 'จองบางส่วน', null),
                  _legendItem(Colors.red.shade300, 'เต็ม', null),
                ],
              ),
            ),
            // Calendar
            TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 60)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focused,
              rowHeight: 48.w,
              daysOfWeekHeight: 20.spMax,
              selectedDayPredicate: (day) => isSameDay(day, _selected),
              calendarFormat: CalendarFormat.month,
              onPageChanged: (d) => setState(() => _focused = d),
              onDaySelected: (sel, foc) {
                setState(() {
                  _selected = sel;
                  _focused = foc;
                });
                _showDayDetails(sel);
              },
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              calendarStyle: const CalendarStyle(
                cellMargin: EdgeInsets.zero,
                cellPadding: EdgeInsets.zero,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, _) {
                  final color = _dayColor(day);
                  final booked = _roomsBookedOnDate(day);
                  return Container(
                    margin: EdgeInsets.zero,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${day.day}', style: TextStyle(fontSize: 12.sp)),
                        if (booked > 0)
                          Text(
                            '$booked',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.red[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                },
                todayBuilder: (context, day, _) {
                  final color = _dayColor(day);
                  final booked = _roomsBookedOnDate(day);
                  return Container(
                    margin: EdgeInsets.zero,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color == Colors.white
                          ? mainColor.withOpacity(0.15)
                          : color,
                      border: Border.all(color: mainColor, width: 2),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        if (booked > 0)
                          Text(
                            '$booked',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.red[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                },
                selectedBuilder: (context, day, _) {
                  final color = _dayColor(day);
                  final booked = _roomsBookedOnDate(day);
                  return Container(
                    margin: EdgeInsets.zero,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color == Colors.white
                          ? mainColor.withOpacity(0.3)
                          : color,
                      border: Border.all(color: mainColor, width: 2),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        if (booked > 0)
                          Text(
                            '$booked',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.red[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Stat + booking list
            _buildSelectedDayStats(),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label, Color? borderColor) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor ?? Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(width: 6.w),
        Text(label, style: styles(fontSize: 12.sp)),
      ],
    );
  }

  Widget _buildSelectedDayStats() {
    final key = DateFormat('yyyy-MM-dd').format(_selected);
    final list = _bookingsByDate[key] ?? [];
    final booked = _roomsBookedOnDate(_selected);
    final available = _totalRoomsAll - booked;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('d MMMM yyyy', 'th').format(_selected),
            style: styles(fontSize: 15.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              _statBox('ห้องว่าง', '$available', Colors.green),
              SizedBox(width: 8.w),
              _statBox('จองแล้ว', '$booked', Colors.orange),
              SizedBox(width: 8.w),
              _statBox('ทั้งหมด', '$_totalRoomsAll', Colors.blue),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            'การจอง (${list.length})',
            style: styles(fontSize: 14.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),
          list.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.h),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 40.sp,
                          color: Colors.grey.shade300,
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'ไม่มีการจองวันนี้',
                          style: styles(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _bookingCard(list[i]),
                ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: styles(fontSize: 11.sp, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingCard(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    return Card(
      margin: EdgeInsets.only(bottom: 6.h),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withOpacity(0.15),
          child: Icon(
            _statusIcon(status),
            color: _statusColor(status),
            size: 20,
          ),
        ),
        title: Text(
          d['guestName'] ?? '-',
          style: styles(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${d['roomName'] ?? '-'} × ${d['rooms'] ?? 1}\n'
          '${_statusLabel(status)} • '
          '฿${(d['totalPrice'] as num?)?.toStringAsFixed(0) ?? '0'}',
          style: styles(fontSize: 12.sp),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showBookingDetails(doc),
      ),
    );
  }

  void _showBookingDetails(QueryDocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BookingDetailSheet(
        bookingDoc: doc,
        onUpdated: () {
          Navigator.pop(ctx);
          _loadBookings();
        },
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'checked_in':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'pending':
        return Icons.schedule;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'checked_in':
        return Icons.login;
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'รอยืนยัน';
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'checked_in':
        return 'เข้าพักแล้ว';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return s;
    }
  }
}

class _DayDetailsSheet extends StatelessWidget {
  final DateTime day;
  final List<QueryDocumentSnapshot> bookings;
  final Map<String, int> roomTotals;
  final VoidCallback onUpdated;

  const _DayDetailsSheet({
    required this.day,
    required this.bookings,
    required this.roomTotals,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              DateFormat('d MMMM yyyy', 'th').format(day),
              style: styles(fontSize: 15.sp, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8.h),
            Text(
              'การจอง ${bookings.length} รายการ',
              style: styles(
                fontSize: 14.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Expanded(
              child: bookings.isEmpty
                  ? Center(
                      child: Text(
                        'ไม่มีการจองวันนี้',
                        style: styles(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: bookings.length,
                      itemBuilder: (_, i) {
                        final d = bookings[i].data() as Map<String, dynamic>;
                        return Card(
                          child: ListTile(
                            title: Text(d['guestName'] ?? '-'),
                            subtitle: Text(
                              '${d['roomName'] ?? '-'} • ฿${(d['totalPrice'] as num?)?.toStringAsFixed(0) ?? '0'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(context);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                builder: (ctx) => _BookingDetailSheet(
                                  bookingDoc: bookings[i],
                                  onUpdated: () {
                                    Navigator.pop(ctx);
                                    onUpdated();
                                  },
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingDetailSheet extends StatelessWidget {
  final QueryDocumentSnapshot bookingDoc;
  final VoidCallback onUpdated;

  const _BookingDetailSheet({
    required this.bookingDoc,
    required this.onUpdated,
  });

  Future<void> _updateStatus(
    BuildContext context,
    String newStatus,
    String label,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ยืนยัน$label'),
        content: Text('คุณต้องการ$label การจองนี้ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: mainColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await bookingDoc.reference.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      onUpdated();
    }
  }

  Future<void> _refundAndCancel(
    BuildContext context,
    double totalPrice,
    double depositAmount,
    bool isAfterCheckIn,
  ) async {
    final refundController = TextEditingController(
      text: isAfterCheckIn ? '' : depositAmount.toStringAsFixed(0),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยินยอมคืนเงิน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAfterCheckIn
                  ? 'ลูกค้า check-in แล้ว — คืนเงินบางส่วน\nยอดที่จ่าย: ฿${totalPrice.toStringAsFixed(0)}'
                  : 'คืนมัดจำให้ลูกค้า\nมัดจำที่จ่าย: ฿${depositAmount.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 13.sp),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: refundController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'จำนวนเงินที่คืน (฿)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              isAfterCheckIn
                  ? 'ระบบจะคิดค่าคอมมิชชั่นจากยอดที่เหลือหลังคืนเงิน'
                  : 'การจองจะถูกยกเลิก',
              style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'ยืนยันคืนเงิน',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result != true) return;

    final refund = double.tryParse(refundController.text.trim()) ?? 0;
    final maxRefund = isAfterCheckIn ? totalPrice : depositAmount;
    if (refund < 0 || refund > maxRefund) {
      Fluttertoast.showToast(
        msg: 'จำนวนเงินไม่ถูกต้อง (0 - ${maxRefund.toStringAsFixed(0)})',
      );
      return;
    }

    EasyLoading.show(status: 'กำลังบันทึก...');
    try {
      await bookingDoc.reference.update({
        'status': isAfterCheckIn ? 'completed' : 'cancelled',
        'refundAmount': refund,
        'refundedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.showSuccess('บันทึกการคืนเงินแล้ว');
      onUpdated();
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = bookingDoc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    final checkIn = (d['checkIn'] as Timestamp).toDate();
    final checkOut = (d['checkOut'] as Timestamp).toDate();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'รายละเอียดการจอง',
              style: styles(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16.h),
            _infoTable(
              rows: [
                MapEntry('ผู้จอง', d['guestName'] ?? '-'),
                MapEntry('เบอร์โทร', d['guestPhone'] ?? '-'),
                if ((d['bookingCode'] ?? '').toString().isNotEmpty)
                  MapEntry('รหัสจอง', d['bookingCode'] ?? '-'),
              ],
            ),
            SizedBox(height: 12.h),
            _infoTable(
              rows: [
                MapEntry(
                  'ห้อง',
                  '${d['roomName'] ?? '-'} × ${d['rooms'] ?? 1}',
                ),
                MapEntry(
                  'Check-in',
                  DateFormat('d MMM yyyy', 'th').format(checkIn),
                ),
                MapEntry(
                  'Check-out',
                  DateFormat('d MMM yyyy', 'th').format(checkOut),
                ),
                MapEntry('จำนวนคืน', '${d['nights'] ?? 0} คืน'),
                MapEntry('จำนวนคน', '${d['guests'] ?? 0} คน'),
              ],
            ),
            SizedBox(height: 12.h),
            _infoTable(
              rows: [
                MapEntry(
                  'ราคา/คืน',
                  '฿${(d['pricePerNight'] as num?)?.toStringAsFixed(0) ?? '0'}',
                ),
                MapEntry(
                  'ยอดรวม',
                  '฿${(d['totalPrice'] as num?)?.toStringAsFixed(0) ?? '0'}',
                ),
                MapEntry(
                  'มัดจำ',
                  '฿${(d['depositAmount'] as num?)?.toStringAsFixed(0) ?? '0'} '
                      '${d['depositPaid'] == true ? "✅" : "⏳"}',
                ),
                if ((d['refundAmount'] as num?) != null &&
                    (d['refundAmount'] as num) > 0)
                  MapEntry(
                    'คืนเงินแล้ว',
                    '฿${(d['refundAmount'] as num).toStringAsFixed(0)} ↩️',
                  ),
                MapEntry('สถานะ', _statusLabel(status)),
              ],
            ),
            SizedBox(height: 20.h),
            _buildActionButtons(
              context,
              status,
              (d['totalPrice'] as num?)?.toDouble() ?? 0,
              (d['depositAmount'] as num?)?.toDouble() ?? 0,
              d['cancelRequested'] as bool? ?? false,
              d['cancelReason'] as String? ?? '',
              d['depositPaid'] as bool? ?? false,
            ),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }

  Widget _infoTable({required List<MapEntry<String, String>> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
        borderRadius: BorderRadius.circular(12.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ...List.generate(rows.length, (i) {
            final isLast = i == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: Colors.grey.shade200,
                          width: 0.5,
                        ),
                      ),
              ),
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      rows[i].key,
                      style: styles(fontSize: 13.sp, color: Colors.grey[700]),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    String status,
    double totalPrice,
    double depositAmount,
    bool cancelRequested,
    String cancelReason,
    bool depositPaid,
  ) {
    final buttons = <Widget>[];
    if (cancelRequested && status != 'cancelled' && status != 'completed') {
      buttons.add(
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.w),
          margin: EdgeInsets.only(bottom: 8.h),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.red[800],
                    size: 18.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'ลูกค้าขอยกเลิก',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                ],
              ),
              if (cancelReason.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  'เหตุผล: $cancelReason',
                  style: TextStyle(fontSize: 12.sp, color: Colors.red[800]),
                ),
              ],
            ],
          ),
        ),
      );
      if (!depositPaid) {
        buttons.add(
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                label: Text(
                  'อนุมัติยกเลิก (ไม่คืนเงิน)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7.r),
                  ),
                ),
                onPressed: () => _approveCancelNoRefund(context),
              ),
            ),
          ),
        );
      } else {
        buttons.add(
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.currency_exchange, color: Colors.white),
                label: Text(
                  'ยกเลิก + คืนเงิน',
                  style: styles(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7.r),
                  ),
                ),
                onPressed: () => _refundAndCancel(
                  context,
                  totalPrice,
                  depositAmount,
                  status == 'checked_in',
                ),
              ),
            ),
          ),
        );
      }
      buttons.add(SizedBox(height: 8.h));
    }

    if (status == 'pending') {
      buttons.add(
        _actionButton(
          context,
          'ยืนยันการจอง',
          Colors.green,
          'confirmed',
          'ยืนยันการจอง',
        ),
      );
      buttons.add(
        _actionButton(context, 'ปฏิเสธ', Colors.red, 'cancelled', 'ปฏิเสธ'),
      );
    } else if (status == 'confirmed') {
      buttons.add(
        _actionButton(
          context,
          'Check-in',
          Colors.blue,
          'checked_in',
          'Check-in',
        ),
      );
    } else if (status == 'checked_in') {
      buttons.add(
        _actionButton(
          context,
          'Check-out',
          Colors.amber,
          'completed',
          'Check-out',
        ),
      );
    }
    return Column(children: buttons);
  }

  Future<void> _approveCancelNoRefund(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('อนุมัติการยกเลิก'),
        content: const Text('ยืนยันยกเลิกการจองนี้? (ลูกค้ายังไม่ได้จ่ายเงิน)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    EasyLoading.show(status: 'กำลังยกเลิก...');
    try {
      await bookingDoc.reference.update({
        'status': 'cancelled',
        'refundAmount': 0,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      EasyLoading.showSuccess('ยกเลิกแล้ว');
      onUpdated();
    } catch (e) {
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  Widget _actionButton(
    BuildContext context,
    String label,
    Color color,
    String newStatus,
    String confirmLabel,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: EdgeInsets.symmetric(vertical: 12.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
          onPressed: () => _updateStatus(context, newStatus, confirmLabel),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return '🟡 รอยืนยัน';
      case 'confirmed':
        return '🔵 ยืนยันแล้ว';
      case 'checked_in':
        return '🟢 เข้าพักแล้ว';
      case 'completed':
        return '⚫ เสร็จสิ้น';
      case 'cancelled':
        return '🔴 ยกเลิก';
      default:
        return s;
    }
  }
}
