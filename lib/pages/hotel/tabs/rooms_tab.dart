// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/pages/hotel/tabs/room_edit_page.dart';
import 'package:colae_shop/pages/hotel/tabs/room_calendar_page.dart';
import 'package:colae_shop/services/sevice.dart';

class RoomsTab extends StatelessWidget {
  const RoomsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ห้องพัก',
          style: styles(color: Colors.white, fontSize: 20.sp),
        ),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: width - 40.w,
        child: FloatingActionButton.extended(
          backgroundColor: mainColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7.r),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            'เพิ่มห้อง',
            style: styles(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoomEditPage()),
            );
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('hotels')
            .doc(uid)
            .collection('rooms')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: mainColor));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bed, size: 80.sp, color: Colors.grey),
                  SizedBox(height: 16.h),
                  Text(
                    'ยังไม่มีห้องพัก',
                    style: styles(fontSize: 16.sp, color: Colors.grey),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'กดปุ่ม + เพื่อเพิ่มห้อง',
                    style: styles(fontSize: 13.sp, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(12.w),
            itemCount: docs.length,
            itemBuilder: (context, i) => _roomCard(context, docs[i], uid),
          );
        },
      ),
    );
  }

  Widget _roomCard(
    BuildContext context,
    QueryDocumentSnapshot doc,
    String uid,
  ) {
    final d = doc.data() as Map<String, dynamic>;
    final images = List<String>.from(d['images'] ?? []);
    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: images.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: images.first,
                          width: 80.w,
                          height: 80.w,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (_, __) => Container(
                            width: 80.w,
                            height: 80.w,
                            color: Colors.grey.shade200,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 80.w,
                            height: 80.w,
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : Container(
                          width: 80.w,
                          height: 80.w,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.bed, color: Colors.grey),
                        ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            d['name'] ?? '-',
                            style: styles(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.deepPurple[900],
                            ),
                          ),
                          Spacer(),
                          SizedBox(width: 8.w),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.orange,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('ยืนยันการลบ'),
                                  content: Text(
                                    'ลบห้อง "${d['name']}" ใช่หรือไม่?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(
                                        'ยกเลิก',
                                        style: styles(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                      ),
                                      child: const Text(
                                        'ลบ',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await FirebaseFirestore.instance
                                    .collection('hotels')
                                    .doc(uid)
                                    .collection('rooms')
                                    .doc(doc.id)
                                    .delete();
                              }
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${d['roomType'] ?? ''} / ${d['totalRooms'] ?? 0} ห้อง / พัก ${d['maxGuests'] ?? 0} คน',
                        style: styles(fontSize: 12.sp, color: Colors.grey[700]),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '฿${(d['basePrice'] as num?)?.toStringAsFixed(0) ?? '0'} / คืน',
                        style: styles(
                          fontSize: 14.sp,
                          color: Colors.deepPurple[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      Icons.edit,
                      size: 16.sp,
                      color: Colors.deepOrange,
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide.none,

                      shape: RoundedRectangleBorder(side: BorderSide.none),
                    ),
                    label: Text(
                      'แก้ไข',
                      style: styles(
                        fontSize: 12.sp,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RoomEditPage(roomId: doc.id, initialData: d),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(side: BorderSide.none),
                    ),
                    icon: Icon(
                      Icons.calendar_month,
                      size: 16.sp,
                      color: Colors.blue,
                    ),
                    label: Text(
                      'ราคาพิเศษ',
                      style: styles(
                        fontSize: 12.sp,
                        color: Colors.blue,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RoomCalendarPage(
                            roomId: doc.id,
                            roomName: d['name'] ?? '',
                            basePrice:
                                (d['basePrice'] as num?)?.toDouble() ?? 0,
                          ),
                        ),
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
  }
}
