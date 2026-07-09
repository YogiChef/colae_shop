// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/auth/login_page.dart';
import 'package:colae_shop/pages/provider/provider_booking_detail_page.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

class ProviderHomePage extends StatefulWidget {
  final String shopId;
  final String providerId;
  final String providerName;
  final String shopName;

  const ProviderHomePage({
    super.key,
    required this.shopId,
    required this.providerId,
    required this.providerName,
    required this.shopName,
  });

  @override
  State<ProviderHomePage> createState() => _ProviderHomePageState();
}

class _ProviderHomePageState extends State<ProviderHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _providerName = '';
  String _shopName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _providerName = widget.providerName;
    _shopName = widget.shopName;
    _loadProviderInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProviderInfo() async {
    try {
      final provDoc = await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .collection('providers')
          .doc(widget.providerId)
          .get();
      final shopDoc = await FirebaseFirestore.instance
          .collection('service_shops')
          .doc(widget.shopId)
          .get();
      if (mounted) {
        setState(() {
          _providerName = provDoc.data()?['name'] as String? ?? _providerName;
          _shopName = shopDoc.data()?['shopName'] as String? ?? _shopName;
        });
      }
    } catch (_) {}
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ออกจากระบบ',
          style: styles(fontSize: 15.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ต้องการออกจากระบบหรือไม่?',
          style: styles(fontSize: 13.sp, color: context.subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: styles(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ออกจากระบบ',
              style: styles(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    Get.offAll(() => const LoginPage());
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> get _todayStream {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return FirebaseFirestore.instance
        .collection('service_bookings')
        .where('shopId', isEqualTo: widget.shopId)
        .where('providerId', isEqualTo: widget.providerId)
        .where('bookingDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('bookingDate')
        .snapshots();
  }

  Stream<QuerySnapshot> get _inServiceStream =>
      FirebaseFirestore.instance
          .collection('service_bookings')
          .where('shopId', isEqualTo: widget.shopId)
          .where('providerId', isEqualTo: widget.providerId)
          .where('status', isEqualTo: 'in_service')
          .orderBy('bookingDate')
          .snapshots();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          context.isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _providerName.isNotEmpty ? _providerName : 'พนักงาน',
              style: styles(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (_shopName.isNotEmpty)
              Text(
                _shopName,
                style: styles(fontSize: 11.sp, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'ออกจากระบบ',
            onPressed: _signOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(child: Text('คิววันนี้', style: styles(fontSize: 13.sp))),
            Tab(child: Text('กำลังบริการ', style: styles(fontSize: 13.sp))),
            Tab(child: Text('เสร็จแล้ว', style: styles(fontSize: 13.sp))),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _QueueTab(
            stream: _todayStream,
            filterStatuses: const ['pending', 'confirmed'],
            emptyMessage: 'ไม่มีคิวที่รอในวันนี้',
            shopId: widget.shopId,
            providerId: widget.providerId,
          ),
          _QueueTab(
            stream: _inServiceStream,
            filterStatuses: const ['in_service'],
            emptyMessage: 'ไม่มีลูกค้าที่กำลังรับบริการ',
            shopId: widget.shopId,
            providerId: widget.providerId,
          ),
          _QueueTab(
            stream: _todayStream,
            filterStatuses: const ['completed'],
            emptyMessage: 'ยังไม่มีงานที่เสร็จในวันนี้',
            shopId: widget.shopId,
            providerId: widget.providerId,
          ),
        ],
      ),
    );
  }
}

// ── Queue Tab Widget ────────────────────────────────────────────────────────

class _QueueTab extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final List<String> filterStatuses;
  final String emptyMessage;
  final String shopId;
  final String providerId;

  const _QueueTab({
    required this.stream,
    required this.filterStatuses,
    required this.emptyMessage,
    required this.shopId,
    required this.providerId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: mainColor));
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'เกิดข้อผิดพลาด: ${snap.error}',
              style: styles(fontSize: 13.sp, color: context.subColor),
            ),
          );
        }

        final docs = (snap.data?.docs ?? [])
            .where((d) =>
                filterStatuses.contains((d.data() as Map)['status'] as String?))
            .toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 52.r,
                  color: Colors.grey[300],
                ),
                SizedBox(height: 12.h),
                Text(
                  emptyMessage,
                  style: styles(fontSize: 14.sp, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data =
                docs[i].data() as Map<String, dynamic>;
            return _BookingCard(
              bookingId: docs[i].id,
              data: data,
            );
          },
        );
      },
    );
  }
}

// ── Booking Card ───────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic> data;

  const _BookingCard({required this.bookingId, required this.data});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'in_service':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'รอยืนยัน';
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'in_service':
        return 'กำลังบริการ';
      case 'completed':
        return 'เสร็จแล้ว';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? '';
    final customerName = data['customerName'] as String? ?? 'ลูกค้า';
    final serviceName = data['serviceName'] as String? ?? '';
    final bookingDate = (data['bookingDate'] as Timestamp?)?.toDate();
    final isWalkIn = data['isWalkIn'] as bool? ?? false;
    final fmt = DateFormat('HH:mm');

    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderBookingDetailPage(
              bookingId: bookingId,
              data: data,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.r),
          child: Row(
            children: [
              // Time column
              Container(
                width: 52.w,
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Text(
                      bookingDate != null ? fmt.format(bookingDate) : '--:--',
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: mainColor,
                      ),
                    ),
                    if (isWalkIn)
                      Container(
                        margin: EdgeInsets.only(top: 3.h),
                        padding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          'walk-in',
                          style: styles(
                              fontSize: 9.sp, color: Colors.orange[700]),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: context.purpleColor,
                      ),
                    ),
                    if (serviceName.isNotEmpty)
                      Text(
                        serviceName,
                        style: styles(
                            fontSize: 12.sp, color: context.subColor),
                      ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  _statusLabel(status),
                  style: styles(
                    fontSize: 11.sp,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Icon(
                Icons.chevron_right_rounded,
                size: 20.r,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
