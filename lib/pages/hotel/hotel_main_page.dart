import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:colae_shop/pages/hotel/tabs/hotel_info_tab.dart';
import 'package:colae_shop/pages/hotel/tabs/rooms_tab.dart';
import 'package:colae_shop/pages/hotel/tabs/bookings_tab.dart';
import 'package:colae_shop/pages/hotel/tabs/hotel_earnings_tab.dart';
import 'package:colae_shop/services/sevice.dart';

class HotelMainPage extends StatefulWidget {
  const HotelMainPage({super.key});

  @override
  State<HotelMainPage> createState() => _HotelMainPageState();
}

class _HotelMainPageState extends State<HotelMainPage> {
  int _currentTab = 0;

  final List<Widget> _tabs = const [
    BookingsTab(),
    HotelEarningsTab(),
    RoomsTab(),
    HotelInfoTab(),
  ];

  Widget _bookingTabIcon() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Icon(_currentTab == 0 ? IconlyBold.home : IconlyLight.home);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hotel_bookings')
          .where('hotelId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        final baseIcon = Icon(
          _currentTab == 0 ? IconlyBold.home : IconlyLight.home,
        );
        if (count == 0) return baseIcon;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            baseIcon,
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentTab],
      bottomNavigationBar: SafeArea(
        child: BottomNavigationBar(
          backgroundColor: mainColor,
          currentIndex: _currentTab,
          selectedItemColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          unselectedItemColor: Colors.white70,
          selectedIconTheme: IconThemeData(size: 26.spMax),
          selectedLabelStyle: GoogleFonts.righteous(fontSize: 14.spMax),
          onTap: (index) => setState(() => _currentTab = index),
          items: [
            BottomNavigationBarItem(icon: _bookingTabIcon(), label: 'การจอง'),
            BottomNavigationBarItem(
              icon: Icon(
                _currentTab == 1 ? IconlyBold.wallet : IconlyLight.wallet,
              ),
              label: 'รายได้',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentTab == 2 ? IconlyBold.calendar : IconlyLight.calendar,
              ),
              label: 'ที่พัก',
            ),
            BottomNavigationBarItem(
              icon: Icon(_currentTab == 3 ? Icons.bed : Icons.bed_outlined),
              label: 'ห้องพัก',
            ),
          ],
        ),
      ),
    );
  }
}
