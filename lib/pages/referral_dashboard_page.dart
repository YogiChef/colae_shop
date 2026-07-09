// ignore_for_file: use_build_context_synchronously, unnecessary_underscores

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/pages/minor_page/downline_detail_page.dart';
import 'package:colae_shop/pages/minor_page/referral_qr_page.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class _MonthData {
  final String monthKey;
  final String monthLabel;
  double delivery;
  double hotel;
  double services;
  double get total => delivery + hotel + services;

  _MonthData({
    required this.monthKey,
    required this.monthLabel,
    this.delivery = 0,
    this.hotel = 0,
    this.services = 0,
  });
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class ReferralDashboardPage extends StatefulWidget {
  const ReferralDashboardPage({super.key});

  @override
  State<ReferralDashboardPage> createState() => _ReferralDashboardPageState();
}

class _ReferralDashboardPageState extends State<ReferralDashboardPage> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isWithdrawing = false;

  // ── Aggregate earnings state ──────────────────────────────────────────────
  bool _earningsLoading = true;
  double _deliveryThisMonth = 0;
  double _hotelThisMonth = 0;
  double _servicesThisMonth = 0;
  int _bookingsThisMonth = 0;
  int _completedThisMonth = 0;
  int _cancelledThisMonth = 0;
  List<_MonthData> _monthlyHistory = [];
  double _mlmPendingThisMonthAgg = 0;
  double _mlmPendingAgg = 0;
  double _mlmTotalAgg = 0;
  Map<String, double> _mlmBySource = {};
  Map<String, double> _deliveryByMonth = {};
  Map<String, double> _hotelByMonth = {};
  Map<String, double> _servicesByMonth = {};

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const _monthNames = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  String _mKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  String _mLabel(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.year + 543}';

  bool _isThisMonth(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month;
  }

  DateTime get _historyStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 5, 1);
  }

  String _formatNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(2);
  }

  double get _revenueThisMonth =>
      _deliveryThisMonth + _hotelThisMonth + _servicesThisMonth;

  // ── Load ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    if (!mounted) return;
    setState(() => _earningsLoading = true);

    _deliveryThisMonth = 0;
    _hotelThisMonth = 0;
    _servicesThisMonth = 0;
    _bookingsThisMonth = 0;
    _completedThisMonth = 0;
    _cancelledThisMonth = 0;
    _deliveryByMonth = {};
    _hotelByMonth = {};
    _servicesByMonth = {};
    _mlmPendingThisMonthAgg = 0;
    _mlmPendingAgg = 0;
    _mlmTotalAgg = 0;
    _mlmBySource = {};

    try {
      await Future.wait([
        _loadDelivery(),
        _loadHotel(),
        _loadServices(),
        _loadMlmAgg(),
      ]);
      _buildHistory();
    } catch (_) {}

    if (mounted) setState(() => _earningsLoading = false);
  }

  Future<void> _loadDelivery() async {
    final snap = await FirebaseFirestore.instance
        .collection('vendors')
        .doc(_uid)
        .collection('monthly_sales')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(6)
        .get();

    final thisMonthKey = _mKey(DateTime.now());
    for (final doc in snap.docs) {
      final sales = (doc.data()['total_sales'] as num?)?.toDouble() ?? 0;
      _deliveryByMonth[doc.id] = sales;
      if (doc.id == thisMonthKey) _deliveryThisMonth = sales;
    }
  }

  Future<void> _loadHotel() async {
    final snap = await FirebaseFirestore.instance
        .collection('hotel_bookings')
        .where('hotelId', isEqualTo: _uid)
        .get();

    final start = _historyStart;

    for (final doc in snap.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null || createdAt.isBefore(start)) continue;

      final status = data['status']?.toString() ?? '';
      final price = (data['totalPrice'] as num?)?.toDouble() ?? 0;
      final mk = _mKey(createdAt);

      if (_isThisMonth(createdAt)) {
        _bookingsThisMonth++;
        if (status == 'completed') _completedThisMonth++;
        if (status == 'cancelled') _cancelledThisMonth++;
      }

      if (status == 'completed') {
        _hotelByMonth[mk] = (_hotelByMonth[mk] ?? 0) + price;
        if (_isThisMonth(createdAt)) _hotelThisMonth += price;
      }
    }
  }

  Future<void> _loadServices() async {
    final snap = await FirebaseFirestore.instance
        .collection('service_bookings')
        .where('shopId', isEqualTo: _uid)
        .get();

    if (snap.docs.isEmpty) return;

    final start = _historyStart;

    for (final doc in snap.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null || createdAt.isBefore(start)) continue;

      final status = data['status']?.toString() ?? '';
      final price = (data['totalAmount'] as num?)?.toDouble() ??
          (data['servicePrice'] as num?)?.toDouble() ??
          (data['price'] as num?)?.toDouble() ??
          0.0;
      final mk = _mKey(createdAt);

      if (_isThisMonth(createdAt)) {
        _bookingsThisMonth++;
        if (status == 'completed') _completedThisMonth++;
        if (status == 'cancelled' || status == 'rejected') _cancelledThisMonth++;
      }

      if (status == 'completed') {
        _servicesByMonth[mk] = (_servicesByMonth[mk] ?? 0) + price;
        if (_isThisMonth(createdAt)) _servicesThisMonth += price;
      }
    }
  }

  Future<void> _loadMlmAgg() async {
    final snap = await FirebaseFirestore.instance
        .collection('referral_transactions')
        .where('toUserId', isEqualTo: _uid)
        .get();

    final thisMonthKey = _mKey(DateTime.now());

    for (final doc in snap.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final status = data['status']?.toString() ?? '';
      final source = data['source']?.toString() ?? 'delivery';
      final month = data['month']?.toString() ?? '';

      _mlmTotalAgg += amount;
      _mlmBySource[source] = (_mlmBySource[source] ?? 0) + amount;

      if (status == 'pending_payout') {
        _mlmPendingAgg += amount;
        if (month == thisMonthKey) _mlmPendingThisMonthAgg += amount;
      }
    }
  }

  void _buildHistory() {
    final now = DateTime.now();
    _monthlyHistory = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - (5 - i), 1);
      final mk = _mKey(d);
      return _MonthData(
        monthKey: mk,
        monthLabel: _mLabel(d),
        delivery: _deliveryByMonth[mk] ?? 0,
        hotel: _hotelByMonth[mk] ?? 0,
        services: _servicesByMonth[mk] ?? 0,
      );
    });
  }

  // ── Existing logic ────────────────────────────────────────────────────────

  Future<void> _requestWithdrawal(double amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการถอนเงิน'),
        content: Text('ถอนเงิน ฿${amount.toStringAsFixed(2)} ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isWithdrawing = true);
    try {
      await FirebaseFirestore.instance.collection('withdrawal_requests').add({
        'userId': _uid,
        'amount': amount,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำขอถอนเงินแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  Future<List<int>> _getDownlineCounts() async {
    final db = FirebaseFirestore.instance;
    final List<int> counts = [];

    for (int i = 0; i < 5; i++) {
      int total = 0;
      for (final col in ['buyers', 'vendors', 'riders']) {
        final snap = await db
            .collection(col)
            .where('uplineIds', arrayContains: _uid)
            .get();
        total += snap.docs.where((doc) {
          final ids = List<String>.from(doc.data()['uplineIds'] ?? []);
          return ids.length > i && ids[i] == _uid;
        }).length;
      }
      counts.add(total);
    }
    return counts;
  }

  Future<double> _calculatePendingThisMonth() async {
    final now = DateTime.now();
    final monthKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final snap = await FirebaseFirestore.instance
        .collection('referral_transactions')
        .where('toUserId', isEqualTo: _uid)
        .where('month', isEqualTo: monthKey)
        .where('status', isEqualTo: 'pending_payout')
        .get();

    double total = 0;
    for (final doc in snap.docs) {
      total += (doc.data()['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  // ── New UI: aggregate earnings sections ───────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: styles(
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: Colors.deepPurple.shade900,
        ),
      );

  Widget _buildEarningsSummary() {
    if (_earningsLoading) {
      return SizedBox(
        height: 60.h,
        child: const Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('รายได้เดือน ${_mLabel(DateTime.now())}'),
        SizedBox(height: 12.h),
        _buildSummaryGrid(),
      ],
    );
  }

  Widget _buildSummaryGrid() {
    final totalBookings = _bookingsThisMonth;
    final successPct = totalBookings > 0
        ? '${(_completedThisMonth / totalBookings * 100).toStringAsFixed(0)}%'
        : '-';
    final cancelPct = totalBookings > 0
        ? '${(_cancelledThisMonth / totalBookings * 100).toStringAsFixed(0)}%'
        : '-';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10.h,
      crossAxisSpacing: 10.w,
      childAspectRatio: 1.4, // 1.6 → 1.4: fixes 4.9px bottom overflow
      children: [
        _statCard(
          icon: Icons.monetization_on_outlined,
          color: mainColor,
          label: 'รายได้รวม',
          value: '฿${_formatNum(_revenueThisMonth)}',
        ),
        _statCard(
          icon: Icons.shopping_bag_outlined,
          color: Colors.blue,
          label: 'การจอง',
          value: '$totalBookings รายการ',
        ),
        _statCard(
          icon: Icons.check_circle_outline,
          color: Colors.green,
          label: 'สำเร็จ',
          value: '$_completedThisMonth ($successPct)',
        ),
        _statCard(
          icon: Icons.cancel_outlined,
          color: Colors.red,
          label: 'ยกเลิก',
          value: '$_cancelledThisMonth ($cancelPct)',
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22.sp),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: context.isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                label,
                style: styles(fontSize: 11.sp, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (_earningsLoading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('แนวโน้มรายได้ 6 เดือน'),
        SizedBox(height: 12.h),
        _buildChart(),
        SizedBox(height: 8.h),
        _buildLegend(),
      ],
    );
  }

  Widget _buildChart() {
    final maxY = _monthlyHistory.fold(
          0.0,
          (a, m) => a > m.total ? a : m.total,
        ) *
        1.15;

    return Container(
      height: 220.h,
      padding: EdgeInsets.only(right: 8.w, top: 12.h, bottom: 4.h),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY : 1000,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: Colors.grey.shade300, width: 0.5),
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= _monthlyHistory.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      _monthlyHistory[i].monthLabel,
                      style: styles(fontSize: 7.sp, color: Colors.black54),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                  v >= 1000
                      ? '${(v / 1000).toStringAsFixed(0)}k'
                      : v.toInt().toString(),
                  style: styles(fontSize: 7.sp, color: Colors.black54),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barGroups: List.generate(_monthlyHistory.length, (i) {
            final m = _monthlyHistory[i];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: m.total,
                  width: 18.w,
                  borderRadius: BorderRadius.circular(2.r),
                  rodStackItems: [
                    BarChartRodStackItem(0, m.delivery, Colors.blue),
                    BarChartRodStackItem(
                      m.delivery,
                      m.delivery + m.hotel,
                      Colors.purple,
                    ),
                    BarChartRodStackItem(
                      m.delivery + m.hotel,
                      m.total,
                      const Color(0xFFFF6B9D),
                    ),
                  ],
                ),
              ],
            );
          }),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItem: (group, _, rod, _) {
                final m = _monthlyHistory[group.x];
                return BarTooltipItem(
                  '${m.monthLabel}\n฿${_formatNum(m.total)}',
                  styles(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendDot(Colors.blue, 'Delivery'),
        SizedBox(width: 16.w),
        _legendDot(Colors.purple, 'ที่พัก'),
        SizedBox(width: 16.w),
        _legendDot(const Color(0xFFFF6B9D), 'บริการ'),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4.w),
        Text(label, style: styles(fontSize: 10.sp, color: Colors.black54)),
      ],
    );
  }

  Widget _buildMlmSection() {
    if (_earningsLoading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('รายได้แนะนำ (MLM)'),
        SizedBox(height: 12.h),
        _buildMlmCard(),
      ],
    );
  }

  Widget _buildMlmCard() {
    final hasData = _mlmTotalAgg > 0;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: hasData
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _mlmStat(
                      'เดือนนี้ (รอจ่าย)',
                      _mlmPendingThisMonthAgg,
                      Colors.orange,
                    ),
                    _mlmStat('พร้อมถอน', _mlmPendingAgg, Colors.green),
                    _mlmStat('สะสมทั้งหมด', _mlmTotalAgg, Colors.blue),
                  ],
                ),
                if (_mlmBySource.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Divider(color: Colors.grey.shade200, height: 1),
                  SizedBox(height: 12.h),
                  ..._buildMlmSourceRows(),
                ],
              ],
            )
          : Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Text(
                  'ยังไม่มีรายได้แนะนำ',
                  style: styles(fontSize: 13.sp, color: Colors.grey),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildMlmSourceRows() {
    const sources = ['delivery', 'hotel', 'services'];
    const labels = {
      'delivery': 'Delivery',
      'hotel': 'ที่พัก',
      'services': 'บริการ',
    };
    const colorMap = {
      'delivery': Colors.blue,
      'hotel': Colors.purple,
      'services': Color(0xFFFF6B9D),
    };

    return sources
        .where((s) => (_mlmBySource[s] ?? 0) > 0)
        .map((s) {
          final amount = _mlmBySource[s]!;
          final pct = _mlmTotalAgg > 0
              ? '${(amount / _mlmTotalAgg * 100).toStringAsFixed(0)}%'
              : '0%';
          return Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Row(
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: colorMap[s],
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  labels[s] ?? s,
                  style: styles(fontSize: 12.sp, color: Colors.black54),
                ),
                const Spacer(),
                Text(
                  pct,
                  style: styles(fontSize: 11.sp, color: Colors.grey),
                ),
                SizedBox(width: 12.w),
                Text(
                  '฿${_formatNum(amount)}',
                  style: styles(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          );
        })
        .toList();
  }

  Widget _mlmStat(String label, double amount, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '฿${_formatNum(amount)}',
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: styles(fontSize: 10.sp, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'บริหารธุรกิจ',
          style: styles(
            fontSize: 20.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vendors')
            .doc(_uid)
            .snapshots(),
        builder: (context, buyerSnap) {
          final buyerData =
              buyerSnap.data?.data() as Map<String, dynamic>? ?? {};
          final String code = buyerData['referralCode'] as String? ?? '-';

          if (buyerSnap.hasData &&
              (buyerData['referralCode'] as String? ?? '').isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final functions = FirebaseFunctions.instanceFor(
                  region: 'asia-southeast1',
                );
                await functions
                    .httpsCallable('generateReferralCodeForUser')
                    .call({'userId': _uid, 'userType': 'vendor'});
              } catch (e) {
                debugPrint('[REFERRAL] generate code error: $e');
              }
            });
          }
          final int count = (buyerData['referralCount'] as num?)?.toInt() ?? 0;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('referral_transactions')
                .where('toUserId', isEqualTo: _uid)
                .snapshots(),
            builder: (context, txSnap) {
              if (buyerSnap.connectionState == ConnectionState.waiting &&
                  !buyerSnap.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: mainColor),
                );
              }

              double pending = 0;
              double withdrawn = 0;

              if (txSnap.hasData) {
                for (final doc in txSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                  final status = data['status']?.toString() ?? '';
                  if (status == 'pending_payout') {
                    pending += amount;
                  } else if (status == 'paid') {
                    withdrawn += amount;
                  }
                }
              }

              final double total = pending + withdrawn;

              return RefreshIndicator(
                onRefresh: () async {
                  await _loadEarnings();
                  setState(() {});
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── New: aggregate earnings ──────────────────────────
                      _buildEarningsSummary(),
                      SizedBox(height: 20.h),
                      _buildChartSection(),
                      SizedBox(height: 20.h),
                      _buildMlmSection(),
                      SizedBox(height: 20.h),
                      Divider(color: Colors.grey.shade300, thickness: 0.5),
                      SizedBox(height: 20.h),
                      // ── Existing sections ────────────────────────────────
                      _codeCard(code),
                      _qualCard2Monthly(),
                      _downlineChart(count),
                      _earningsCard(pending, total, withdrawn),
                      SizedBox(height: 20.h),
                      _withdrawButton(pending),
                      SizedBox(height: 32.h),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Existing widgets ──────────────────────────────────────────────────────

  Widget _codeCard(String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'รหัสแนะนำ',
              style: styles(
                fontSize: 14.sp,
                color: context.isDark
                    ? Colors.white
                    : Colors.deepPurple.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),

            IconButton(
              icon: Icon(
                Icons.share,
                color: context.isDark ? Colors.white : Colors.grey,
                size: 20.sp,
              ),
              onPressed: () => Share.share(
                'สมัครเปิดร้านขายของกับ Colae ด้วยรหัสแนะนำ: $code',
              ),
            ),
            IconButton(
              icon: Icon(Icons.qr_code_2, color: Colors.purple, size: 22.sp),
              tooltip: 'สร้าง QR Code',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReferralQrPage(referralCode: code),
                  ),
                );
              },
            ),
          ],
        ),
        Text(
          code,
          style: styles(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: context.isDark ? Colors.white : Colors.black54,
            letterSpacing: 2,
          ),
        ),
        SizedBox(height: 12.h),
        Divider(color: Colors.grey.shade300, thickness: 0.5),
      ],
    );
  }

  Widget _earningsCard(double pending, double total, double withdrawn) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ประวัติรายได้',
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: context.isDark ? Colors.white : Colors.deepPurple[900],
            ),
          ),
          SizedBox(height: 12.h),

          FutureBuilder<double>(
            future: _calculatePendingThisMonth(),
            builder: (context, snap) {
              final monthAmount = snap.data ?? 0;
              return Container(
                padding: EdgeInsets.all(12.w),
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event, color: Colors.green, size: 20.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'รายได้เดือนนี้',
                            style: styles(
                              fontSize: 11.sp,
                              color: context.subColor,
                            ),
                          ),
                          Text(
                            '฿${monthAmount.toStringAsFixed(2)}',
                            style: styles(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: context.isDark
                                  ? Colors.indigo
                                  : Colors.green,
                            ),
                          ),
                          Text(
                            'จ่ายวันที่ 5 ของเดือนถัดไป',
                            style: styles(
                              fontSize: 10.sp,
                              color: context.subColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          Row(
            children: [
              _earningsItem(
                'พร้อมถอน',
                pending,
                context.isDark ? Colors.deepOrange : Colors.orange,
              ),
              _earningsItem(
                'ทั้งหมด',
                total,
                context.isDark ? Colors.indigo : Colors.blue,
              ),
              _earningsItem(
                'ถอนแล้ว',
                withdrawn,
                context.isDark ? Colors.green[800]! : Colors.green,
              ),
            ],
          ),
          SizedBox(height: 16.h),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('referral_transactions')
                .where('toUserId', isEqualTo: _uid)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: EdgeInsets.all(12.w),
                  child: Text(
                    'Error: ${snap.error}',
                    style: styles(color: Colors.red, fontSize: 11.sp),
                  ),
                );
              }

              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return Padding(
                  padding: EdgeInsets.all(16.w),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  child: Center(
                    child: Text(
                      'ยังไม่มีรายการ',
                      style: styles(
                        color: context.isDark ? Colors.white : Colors.grey,
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                );
              }

              final monthMap = <String, Map<String, dynamic>>{};

              for (final doc in snap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final month = data['month']?.toString() ?? 'unknown';
                final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                final status = data['status']?.toString() ?? 'pending_payout';

                if (!monthMap.containsKey(month)) {
                  monthMap[month] = {
                    'total': 0.0,
                    'count': 0,
                    'hasPending': false,
                  };
                }

                monthMap[month]!['total'] =
                    (monthMap[month]!['total'] as double) + amount;
                monthMap[month]!['count'] =
                    (monthMap[month]!['count'] as int) + 1;
                if (status == 'pending_payout') {
                  monthMap[month]!['hasPending'] = true;
                }
              }

              final months = monthMap.keys.toList()
                ..sort((a, b) => b.compareTo(a));

              return Column(
                children: months.map((month) {
                  final info = monthMap[month]!;
                  return _monthlyEarningItem(
                    month,
                    info['total'] as double,
                    info['count'] as int,
                    info['hasPending'] as bool,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _earningsItem(String label, double amount, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '฿${amount.toStringAsFixed(2)}',
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: styles(fontSize: 12.sp, color: context.textColor),
          ),
        ],
      ),
    );
  }

  Widget _downlineChart(int count) {
    final bool qualified = count >= 12;
    final levels = ['1', '2', '3', '4', '5'];
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                qualified ? Icons.check_circle : Icons.info_outline,
                color: qualified
                    ? Colors.deepPurple[900]
                    : Colors.deepOrange[900],
                size: 24.sp,
              ),
              SizedBox(width: 8.w),
              Text(
                '${qualified ? 'รับรายได้!' : 'ภารกิจ'} 5 ชั้น ${count > 12 ? '$count' : '$count/12'}',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: qualified
                      ? Colors.deepPurple[900]
                      : Colors.deepOrange[900],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          FutureBuilder<List<int>>(
            future: _getDownlineCounts(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: 220.h,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              final counts = snap.data ?? [0, 0, 0, 0, 0];
              final maxY = counts.fold(0, (a, b) => a > b ? a : b).toDouble();

              return SizedBox(
                height: 220.h,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    backgroundColor: Colors.deepOrange.shade50,
                    maxY: maxY > 0 ? maxY + 5 : 10,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY > 20 ? 10 : 5,
                      getDrawingHorizontalLine: (value) =>
                          FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= levels.length) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: EdgeInsets.only(top: 4.h),
                              child: Text(
                                levels[i],
                                style: styles(
                                  fontSize: 9.sp,
                                  color: context.textColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: maxY > 20 ? 10 : 5,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: styles(
                              fontSize: 9.sp,
                              color: context.subColor,
                            ),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        left: BorderSide(
                          color: Colors.grey.shade300,
                          width: 0.5,
                        ),
                        bottom: BorderSide(
                          color: Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                    ),
                    barGroups: List.generate(5, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: counts[i].toDouble(),
                            color: Colors.deepOrange.shade400,
                            width: 24.w,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ],
                      );
                    }),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.black87,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                            BarTooltipItem(
                              '${counts[groupIndex]} คน',
                              styles(
                                color: Colors.white,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      ),
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent && response?.spot != null) {
                          final levelIdx =
                              response!.spot!.touchedBarGroupIndex;
                          if (levelIdx < 0 || levelIdx >= counts.length) return;
                          if (counts[levelIdx] > 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DownlineDetailPage(
                                  uid: _uid,
                                  level: levelIdx,
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _qualCard2Monthly() {
    return Padding(
      padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ยอดขายของฉัน',
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: Colors.deepPurple[900],
            ),
          ),
          Builder(
            builder: (context) {
              final amount = _revenueThisMonth;
              const threshold = 5000.0;
              final progress = (amount / threshold).clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'เดือนนี้',
                          style: styles(
                            fontSize: 12.sp,
                            color: context.subColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '฿${amount.toStringAsFixed(2)} / ฿5,000',
                          style: styles(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: amount >= threshold
                                ? Colors.green[700]
                                : Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.r),
                      child: LinearProgressIndicator(
                        value: _earningsLoading ? null : progress,
                        minHeight: 8.h,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          amount >= threshold ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(color: Colors.grey.shade200, thickness: 0.5),
          if (_earningsLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: const Center(child: CircularProgressIndicator()),
            )
          else if (_monthlyHistory.isEmpty ||
              _monthlyHistory.every((m) => m.total == 0))
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: Center(
                child: Text(
                  'ยังไม่มีรายการ',
                  style: styles(color: context.subColor, fontSize: 13.sp),
                ),
              ),
            )
          else
            Column(
              children: _monthlyHistory.reversed
                  .map((m) => _vendorSalesMonthItem(m.monthKey, m.total))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _vendorSalesMonthItem(String monthKey, double totalSales) {
    const monthNames = [
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
    final parts = monthKey.split('-');
    String displayMonth = monthKey;
    if (parts.length == 2) {
      final monthIdx = int.tryParse(parts[1]);
      final year = int.tryParse(parts[0]);
      if (monthIdx != null && monthIdx >= 1 && monthIdx <= 12 && year != null) {
        displayMonth = '${monthNames[monthIdx - 1]} ${year + 543}';
      }
    }
    final qualified = totalSales >= 5000;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayMonth,
              style: styles(
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: context.subColor,
              ),
            ),
          ),
          if (qualified)
            Padding(
              padding: EdgeInsets.only(right: 6.w),
              child: Icon(Icons.check_circle, color: Colors.green, size: 14.sp),
            ),
          Text(
            '฿${totalSales.toStringAsFixed(2)}',
            style: styles(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: qualified ? Colors.green[700] : Colors.orange[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyEarningItem(
    String month,
    double total,
    int count,
    bool hasPending,
  ) {
    final parts = month.split('-');
    const monthNames = [
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
    String displayMonth = month;
    if (parts.length == 2) {
      final monthIdx = int.tryParse(parts[1]);
      final year = int.tryParse(parts[0]);
      if (monthIdx != null && monthIdx >= 1 && monthIdx <= 12 && year != null) {
        displayMonth = '${monthNames[monthIdx - 1]} ${year + 543}';
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayMonth,
                  style: styles(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w400,
                    color: context.textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '$count รายการ',
                  style: styles(fontSize: 11.sp, color: context.subColor),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '฿${total.toStringAsFixed(2)}',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
              SizedBox(height: 2.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: hasPending
                      ? Colors.orange.shade50
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  hasPending ? 'รอจ่าย' : 'จ่ายแล้ว',
                  style: styles(
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w600,
                    color: hasPending ? Colors.orange[800] : Colors.green[800],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _withdrawButton(double pending) {
    final bool canWithdraw = pending >= 5000;
    return SizedBox(
      width: double.infinity,
      height: 60.h,
      child: ElevatedButton.icon(
        icon: _isWithdrawing
            ? SizedBox(
                width: 20.w,
                height: 20.h,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 20.sp,
              ),
        label: Text(
          canWithdraw
              ? 'ถอนเงิน ฿${pending.toStringAsFixed(2)}'
              : 'ถอนขั้นต่ำ ฿5,000',
          style: styles(
            fontSize: 15.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canWithdraw ? Colors.amber : Colors.grey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7.r),
          ),
        ),
        onPressed: canWithdraw && !_isWithdrawing
            ? () => _requestWithdrawal(pending)
            : null,
      ),
    );
  }
}
