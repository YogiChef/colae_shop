// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/referral_dashboard_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

// ─── Month data model ─────────────────────────────────────────────────────────

class _SvcMonth {
  final String key;
  final String label;
  double revenue = 0;
  int bookings = 0;
  int completed = 0;
  int cancelled = 0;

  _SvcMonth({required this.key, required this.label});
}

class ServiceEarningsPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> shopData;
  final String? categoryName;

  const ServiceEarningsPage({
    super.key,
    required this.shopId,
    required this.shopData,
    this.categoryName,
  });

  @override
  State<ServiceEarningsPage> createState() => _ServiceEarningsPageState();
}

class _ServiceEarningsPageState extends State<ServiceEarningsPage> {
  bool _loading = true;

  double _revenueThisMonth = 0;
  int _bookingsThisMonth = 0;
  int _completedThisMonth = 0;
  int _cancelledThisMonth = 0;

  List<_SvcMonth> _monthlyHistory = [];
  List<Map<String, dynamic>> _topServices = [];
  List<Map<String, dynamic>> _recentBookings = [];

  double _mlmPendingThisMonth = 0;
  double _mlmPending = 0;
  double _mlmTotal = 0;

  static const _monthNames = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  String _mKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  String _mLabel(DateTime d) {
    final be = (d.year + 543) % 100;
    return "${_monthNames[d.month - 1]}'${be.toString().padLeft(2, '0')}";
  }

  bool _isThisMonth(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month;
  }

  double _extractPrice(Map<String, dynamic> data) =>
      (data['totalAmount'] as num?)?.toDouble() ??
      (data['servicePrice'] as num?)?.toDouble() ??
      (data['price'] as num?)?.toDouble() ??
      0.0;

  String _formatCurrency(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _revenueThisMonth = 0;
      _bookingsThisMonth = 0;
      _completedThisMonth = 0;
      _cancelledThisMonth = 0;
      _mlmPendingThisMonth = 0;
      _mlmPending = 0;
      _mlmTotal = 0;
    });

    await Future.wait([_loadBookings(), _loadMlm()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBookings() async {
    final now = DateTime.now();
    final historyStart = DateTime(now.year, now.month - 5, 1);

    final snap = await FirebaseFirestore.instance
        .collection('service_bookings')
        .where('shopId', isEqualTo: widget.shopId)
        .get();

    final monthMap = <String, _SvcMonth>{};
    for (int i = 0; i < 6; i++) {
      final d = DateTime(now.year, now.month - (5 - i), 1);
      final mk = _mKey(d);
      monthMap[mk] = _SvcMonth(key: mk, label: _mLabel(d));
    }

    final serviceMap = <String, Map<String, dynamic>>{};
    final completedList = <Map<String, dynamic>>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null || createdAt.isBefore(historyStart)) continue;

      final status = data['status']?.toString() ?? '';
      final price = _extractPrice(data);
      final mk = _mKey(createdAt);
      final serviceName = (data['serviceName'] as String?)?.isNotEmpty == true
          ? data['serviceName'] as String
          : 'ไม่ระบุ';
      final serviceId = (data['serviceId'] as String?)?.isNotEmpty == true
          ? data['serviceId'] as String
          : serviceName;

      if (monthMap.containsKey(mk)) {
        monthMap[mk]!.bookings++;
        if (status == 'completed') {
          monthMap[mk]!.completed++;
          monthMap[mk]!.revenue += price;
        }
        if (status == 'cancelled' || status == 'rejected') {
          monthMap[mk]!.cancelled++;
        }
      }

      if (_isThisMonth(createdAt)) {
        _bookingsThisMonth++;
        if (status == 'completed') {
          _completedThisMonth++;
          _revenueThisMonth += price;
        }
        if (status == 'cancelled' || status == 'rejected') {
          _cancelledThisMonth++;
        }
      }

      serviceMap.putIfAbsent(
        serviceId,
        () => {'name': serviceName, 'count': 0, 'revenue': 0.0},
      );
      serviceMap[serviceId]!['count'] =
          (serviceMap[serviceId]!['count'] as int) + 1;
      if (status == 'completed') {
        serviceMap[serviceId]!['revenue'] =
            (serviceMap[serviceId]!['revenue'] as double) + price;
      }

      if (status == 'completed') {
        completedList.add({...data, '__createdAt': createdAt});
      }
    }

    _monthlyHistory = monthMap.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    _topServices = serviceMap.values.toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    if (_topServices.length > 5) _topServices = _topServices.sublist(0, 5);

    completedList.sort(
      (a, b) => (b['__createdAt'] as DateTime).compareTo(
        a['__createdAt'] as DateTime,
      ),
    );
    _recentBookings = completedList.take(10).toList();
  }

  Future<void> _loadMlm() async {
    final snap = await FirebaseFirestore.instance
        .collection('referral_transactions')
        .where('toUserId', isEqualTo: widget.shopId)
        .get();

    final thisMonthKey = _mKey(DateTime.now());

    for (final doc in snap.docs) {
      final data = doc.data();
      final source = data['source']?.toString() ?? '';
      if (source != 'services') continue;

      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final status = data['status']?.toString() ?? '';
      final month = data['month']?.toString() ?? '';

      _mlmTotal += amount;
      if (status == 'pending_payout') {
        _mlmPending += amount;
        if (month == thisMonthKey) _mlmPendingThisMonth += amount;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopName = widget.shopData['shopName'] as String? ?? '';

    return Scaffold(
      backgroundColor: context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          shopName,
          style: styles(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'โหลดใหม่',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: mainColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: mainColor,
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  _buildSummaryGrid(),
                  SizedBox(height: 16.h),
                  _buildBarChart(),
                  SizedBox(height: 16.h),
                  _buildTopServices(),
                  SizedBox(height: 16.h),
                  _buildRecentBookings(),
                  SizedBox(height: 16.h),
                  _buildMlmSection(),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryGrid() {
    final completedRate = _bookingsThisMonth > 0
        ? (_completedThisMonth / _bookingsThisMonth * 100).round()
        : 0;
    final cancelledRate = _bookingsThisMonth > 0
        ? (_cancelledThisMonth / _bookingsThisMonth * 100).round()
        : 0;

    final items = [
      (
        'รายได้เดือนนี้',
        '฿${_formatCurrency(_revenueThisMonth)}',
        Icons.payments_outlined,
        mainColor,
      ),
      (
        'การจองทั้งหมด',
        '$_bookingsThisMonth ครั้ง',
        Icons.event_note_outlined,
        Colors.blue[600]!,
      ),
      (
        'อัตราสำเร็จ',
        '$completedRate%',
        Icons.check_circle_outline_rounded,
        Colors.green[600]!,
      ),
      (
        'อัตรายกเลิก',
        '$cancelledRate%',
        Icons.cancel_outlined,
        Colors.orange[700]!,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 4.w,
      mainAxisSpacing: 4.h,
      childAspectRatio: 1.2,
      children: items.map((item) {
        final (label, value, icon, color) = item;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7.r),
          ),
          elevation: 1,
          child: Padding(
            padding: EdgeInsets.all(14.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24.r),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: styles(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      style: styles(fontSize: 11.sp, color: context.subColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarChart() {
    final maxY = _monthlyHistory.fold(
      0.0,
      (m, d) => d.revenue > m ? d.revenue : m,
    );
    final interval = maxY > 0 ? (maxY / 4).ceilToDouble() : 100.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.r, 16.r, 8.r, 8.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รายได้ 6 เดือนล่าสุด',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              height: 160.h,
              child: BarChart(
                BarChartData(
                  maxY: maxY > 0 ? maxY * 1.25 : 100,
                  barGroups: _monthlyHistory.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.revenue,
                          color: mainColor,
                          width: 16.w,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(4.r),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final i = val.toInt();
                          if (i < 0 || i >= _monthlyHistory.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: Text(
                              _monthlyHistory[i].label,
                              style: styles(
                                fontSize: 7.sp,
                                letterSpacing: 0.1,
                                color: context.subColor,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28.h,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: interval,
                        getTitlesWidget: (val, _) => Text(
                          _formatCurrency(val),
                          style: styles(
                            fontSize: 7.sp,
                            color: context.subColor,
                          ),
                        ),
                        reservedSize: 38.w,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) =>
                          Colors.black87.withValues(alpha: 0.85),
                      getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                        '฿${rod.toY.toStringAsFixed(0)}',
                        styles(fontSize: 11.sp, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopServices() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'บริการยอดนิยม (6 เดือน)',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 12.h),
            if (_topServices.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20.h),
                child: Center(
                  child: Text(
                    'ยังไม่มีข้อมูล',
                    style: styles(fontSize: 13.sp, color: context.subColor),
                  ),
                ),
              )
            else
              ..._topServices.asMap().entries.map((e) {
                final rank = e.key + 1;
                final svc = e.value;
                final isTop = rank == 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Row(
                    children: [
                      Container(
                        width: 26.r,
                        height: 26.r,
                        decoration: BoxDecoration(
                          color: isTop
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: styles(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              color: isTop
                                  ? Colors.amber[700]
                                  : Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          svc['name'] as String,
                          style: styles(fontSize: 13.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${svc['count']} ครั้ง',
                            style: styles(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: mainColor,
                            ),
                          ),
                          Text(
                            '฿${_formatCurrency(svc['revenue'] as double)}',
                            style: styles(
                              fontSize: 11.sp,
                              color: context.subColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── Recent Completed Bookings ─────────────────────────────────────────────

  Widget _buildRecentBookings() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'การจองสำเร็จล่าสุด',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: context.purpleColor,
              ),
            ),
            SizedBox(height: 12.h),
            if (_recentBookings.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20.h),
                child: Center(
                  child: Text(
                    'ยังไม่มีการจองที่สำเร็จ',
                    style: styles(fontSize: 13.sp, color: context.subColor),
                  ),
                ),
              )
            else
              ..._recentBookings.map((booking) {
                final createdAt = booking['__createdAt'] as DateTime;
                final rawName =
                    (booking['guestName'] as String?)?.isNotEmpty == true
                    ? booking['guestName'] as String
                    : (booking['customerName'] as String?)?.isNotEmpty == true
                    ? booking['customerName'] as String
                    : 'ลูกค้า';
                final displayName = rawName.isNotEmpty
                    ? '${rawName[0]}***'
                    : '***';
                final serviceName =
                    (booking['serviceName'] as String?)?.isNotEmpty == true
                    ? booking['serviceName'] as String
                    : 'บริการ';
                final price = _extractPrice(booking);
                final dateStr = DateFormat('d MMM yy', 'th').format(createdAt);

                return Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: styles(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              serviceName,
                              style: styles(
                                fontSize: 11.sp,
                                color: context.subColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '฿${price.toStringAsFixed(0)}',
                            style: styles(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: mainColor,
                            ),
                          ),
                          Text(
                            dateStr,
                            style: styles(
                              fontSize: 11.sp,
                              color: context.subColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── MLM from Services ─────────────────────────────────────────────────────

  Widget _buildMlmSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: Colors.purple[400], size: 20.r),
                SizedBox(width: 8.w),
                Text(
                  'MLM จากบริการ',
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: context.purpleColor,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                _mlmStat(
                  'เดือนนี้ (รอจ่าย)',
                  '฿${_mlmPendingThisMonth.toStringAsFixed(2)}',
                  Colors.orange[700]!,
                ),
                _mlmStat(
                  'รอจ่ายทั้งหมด',
                  '฿${_mlmPending.toStringAsFixed(2)}',
                  Colors.blue[600]!,
                ),
                _mlmStat(
                  'สะสมทั้งหมด',
                  '฿${_mlmTotal.toStringAsFixed(2)}',
                  Colors.green[600]!,
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'ดู MLM รวมทุกบริการได้ที่ "บริหารธุรกิจ"',
                style: styles(fontSize: 11.sp, color: context.subColor),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.hub_outlined, size: 18.r, color: mainColor),
                label: Text(
                  'ไปหน้าบริหารธุรกิจ',
                  style: styles(
                    fontSize: 13.sp,
                    color: mainColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReferralDashboardPage(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: mainColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mlmStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: styles(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: styles(fontSize: 10.sp, color: context.subColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
