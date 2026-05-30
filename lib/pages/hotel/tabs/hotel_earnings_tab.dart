// ignore_for_file: unnecessary_cast

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:colae_shop/services/sevice.dart';

class HotelEarningsTab extends StatefulWidget {
  const HotelEarningsTab({super.key});

  @override
  State<HotelEarningsTab> createState() => _HotelEarningsTabState();
}

class _HotelEarningsTabState extends State<HotelEarningsTab> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _loading = true;
  double _totalAll = 0;
  double _totalThisMonth = 0;
  double _earningsCompleted = 0;
  double _earningsCheckedIn = 0;
  double _earningsConfirmed = 0;
  int _bookingCount = 0;
  double _occupancyRate = 0;

  Map<String, double> _monthlyEarnings = {};
  Map<String, double> _dailyEarnings = {};
  List<QueryDocumentSnapshot> _recentBookings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);

      final snap = await FirebaseFirestore.instance
          .collection('hotel_bookings')
          .where('hotelId', isEqualTo: _uid)
          .get();

      double totalAll = 0;
      double totalThisMonth = 0;
      double earningsCompleted = 0;
      double earningsCheckedIn = 0;
      double earningsConfirmed = 0;
      final monthly = <String, double>{};
      final daily = <String, double>{};
      int validBookings = 0;

      final roomsSnap = await FirebaseFirestore.instance
          .collection('hotels')
          .doc(_uid)
          .collection('rooms')
          .get();
      int totalRooms = 0;
      for (final r in roomsSnap.docs) {
        totalRooms += (r.data()['totalRooms'] as num?)?.toInt() ?? 0;
      }

      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final status = d['status'] as String? ?? '';
        if (status == 'cancelled') continue;

        validBookings++;
        final total = (d['totalPrice'] as num?)?.toDouble() ?? 0;

        if (status == 'completed' ||
            status == 'checked_in' ||
            status == 'confirmed') {
          totalAll += total;

          final checkIn = (d['checkIn'] as Timestamp).toDate();
          final inMonth = DateFormat('yyyy-MM').format(checkIn);
          if (inMonth == monthKey) totalThisMonth += total;

          monthly[inMonth] = (monthly[inMonth] ?? 0) + total;

          final dayKey = DateFormat('yyyy-MM-dd').format(checkIn);
          daily[dayKey] = (daily[dayKey] ?? 0) + total;

          if (status == 'completed') {
            earningsCompleted += total;
          } else if (status == 'checked_in') {
            earningsCheckedIn += total;
          } else if (status == 'confirmed') {
            earningsConfirmed += total;
          }
        }
      }

      double occupancy = 0;
      final last30Days = totalRooms * 30;
      if (last30Days > 0) {
        int recentBookedDays = 0;
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        for (final doc in snap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          if ((d['status'] as String?) == 'cancelled') continue;
          final ci = (d['checkIn'] as Timestamp).toDate();
          if (ci.isAfter(thirtyDaysAgo)) {
            final nights = (d['nights'] as num?)?.toInt() ?? 0;
            final rooms = (d['rooms'] as num?)?.toInt() ?? 1;
            recentBookedDays += (nights * rooms);
          }
        }
        occupancy = (recentBookedDays / last30Days * 100).clamp(0, 100);
      }

      final recentSnap = await FirebaseFirestore.instance
          .collection('hotel_bookings')
          .where('hotelId', isEqualTo: _uid)
          .where(
            'status',
            whereIn: ['pending', 'confirmed', 'checked_in', 'completed'],
          )
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      if (mounted) {
        setState(() {
          _totalAll = totalAll;
          _totalThisMonth = totalThisMonth;
          _earningsCompleted = earningsCompleted;
          _earningsCheckedIn = earningsCheckedIn;
          _earningsConfirmed = earningsConfirmed;
          _bookingCount = validBookings;
          _occupancyRate = occupancy;
          _monthlyEarnings = monthly;
          _dailyEarnings = daily;
          _recentBookings = recentSnap.docs;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Earnings load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'รายได้',
          style: styles(color: Colors.white, fontSize: 18.sp),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('ภาพรวม'),
                    _overviewCards(),
                    SizedBox(height: 16.h),
                    _sectionTitle('รายได้ตามสถานะ'),
                    _statusCards(),
                    SizedBox(height: 16.h),
                    _sectionTitle('รายได้รายเดือน (12 เดือน)'),
                    _monthlyChart(),
                    SizedBox(height: 16.h),
                    _sectionTitle('แนวโน้ม 30 วันล่าสุด'),
                    _dailyChart(),
                    SizedBox(height: 16.h),
                    _sectionTitle('การจองล่าสุด'),
                    _recentList(),
                    SizedBox(height: 32.h),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Text(
        text,
        style: styles(
          fontSize: 16.sp,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _overviewCards() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        _statCard(
          'รายได้เดือนนี้',
          '฿${_totalThisMonth.toStringAsFixed(0)}',
          Icons.calendar_today,
          Colors.green,
        ),
        _statCard(
          'รายได้ทั้งหมด',
          '฿${_totalAll.toStringAsFixed(0)}',
          Icons.account_balance_wallet,
          Colors.blue,
        ),
        _statCard(
          'Booking ทั้งหมด',
          '$_bookingCount',
          Icons.book_online,
          Colors.orange,
        ),
        _statCard(
          'อัตราเข้าพัก',
          '${_occupancyRate.toStringAsFixed(0)}%',
          Icons.hotel,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _statusCards() {
    return Row(
      children: [
        _statusBox('เสร็จสิ้น', _earningsCompleted, Colors.grey),
        SizedBox(width: 8.w),
        _statusBox('เข้าพัก', _earningsCheckedIn, Colors.green),
        SizedBox(width: 8.w),
        _statusBox('ยืนยันแล้ว', _earningsConfirmed, Colors.blue),
      ],
    );
  }

  Widget _statusBox(String label, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: styles(fontSize: 11.sp, color: Colors.grey[700]),
            ),
            SizedBox(height: 4.h),
            Text(
              '฿${amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 24.sp, color: color),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  label,
                  style: styles(fontSize: 12.sp, color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _monthlyChart() {
    final now = DateTime.now();
    final months = <String>[];
    final values = <double>[];

    for (int i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('yyyy-MM').format(d);
      months.add(DateFormat('MMM').format(d));
      values.add(_monthlyEarnings[key] ?? 0);
    }

    final maxY = values.fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(
        height: 200.h,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY > 0 ? maxY * 1.2 : 1000,
            barGroups: List.generate(12, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: mainColor,
                    width: 16.w,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i >= months.length) return const Text('');
                    return Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: Text(
                        months[i],
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.grey[700],
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '฿${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dailyChart() {
    final now = DateTime.now();
    final spots = <FlSpot>[];
    double maxY = 0;

    for (int i = 29; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      final v = _dailyEarnings[key] ?? 0;
      spots.add(FlSpot((29 - i).toDouble(), v));
      if (v > maxY) maxY = v;
    }

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(
        height: 180.h,
        child: LineChart(
          LineChartData(
            maxY: maxY > 0 ? maxY * 1.2 : 1000,
            minY: 0,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 5,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i > 29) return const Text('');
                    final d = DateTime.now().subtract(Duration(days: 29 - i));
                    return Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: Text(
                        DateFormat('d/M').format(d),
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.grey[700],
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.green,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.green.withOpacity(0.15),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touched) => touched.map((t) {
                  return LineTooltipItem(
                    '฿${t.y.toStringAsFixed(0)}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentList() {
    if (_recentBookings.isEmpty) {
      return Container(
        padding: EdgeInsets.all(20.w),
        alignment: Alignment.center,
        child: Text('ยังไม่มีการจอง', style: styles(color: Colors.grey)),
      );
    }

    return Column(
      children: _recentBookings.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final status = d['status'] as String? ?? '';
        final checkIn = (d['checkIn'] as Timestamp).toDate();
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _statusColor(status).withOpacity(0.2),
              child: Icon(
                _statusIcon(status),
                color: _statusColor(status),
                size: 18,
              ),
            ),
            title: Text(
              d['guestName'] ?? '-',
              style: styles(fontSize: 14.sp, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${d['roomName'] ?? '-'} • ${DateFormat('d MMM').format(checkIn)} • ${d['nights']} คืน',
              style: styles(fontSize: 12.sp, color: Colors.grey[700]),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '฿${(d['totalPrice'] as num?)?.toStringAsFixed(0) ?? '0'}',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: mainColor,
                  ),
                ),
                Text(
                  _statusLabel(status),
                  style: styles(fontSize: 10.sp, color: _statusColor(status)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
        return 'เข้าพัก';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return s;
    }
  }
}
