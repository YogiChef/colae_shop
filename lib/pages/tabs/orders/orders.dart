import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/pages/tabs/orders/delivered_tab.dart';
import 'package:colae_shop/pages/tabs/orders/prepar_tab.dart';
import 'package:colae_shop/services/sevice.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        automaticallyImplyLeading: false,
        title: Text(
          'ออร์เดอร์',
          style: styles(
            fontSize: 20.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelColor: Colors.white,
          labelStyle: styles(fontSize: 14.sp, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(child: Text('กำลังจัดทำ')),
            Tab(child: Text('ประวัติการซื้อ')),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) => IndexedStack(
          index: _tabController.index,
          children: const [PreparTab(), Delivered()],
        ),
      ),
    );
  }
}
