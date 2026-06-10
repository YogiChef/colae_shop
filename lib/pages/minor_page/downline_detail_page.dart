import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:url_launcher/url_launcher.dart';

class DownlineDetailPage extends StatelessWidget {
  final String uid;
  final int level;

  const DownlineDetailPage({super.key, required this.uid, required this.level});

  Future<List<Map<String, dynamic>>> _loadDownlines() async {
    final db = FirebaseFirestore.instance;
    final List<Map<String, dynamic>> result = [];

    for (final col in ['buyers', 'vendors', 'riders']) {
      final snap = await db
          .collection(col)
          .where('uplineIds', arrayContains: uid)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final uplines = List<String>.from(data['uplineIds'] ?? []);

        if (uplines.length > level && uplines[level] == uid) {
          result.add({
            'uid': doc.id,
            'collection': col,
            'name': (data['fullName'] as String?)?.trim().isNotEmpty == true
                ? data['fullName']
                : (data['bussinessName'] as String?)?.trim().isNotEmpty == true
                ? data['bussinessName']
                : (data['name'] as String?)?.trim().isNotEmpty == true
                ? data['name']
                : '(ไม่มีชื่อ)',
            'phone': (data['phone'] as String?)?.trim().isNotEmpty == true
                ? data['phone']
                : (data['custphone'] as String?)?.trim().isNotEmpty == true
                ? data['custphone']
                : '-',
            'createdAt': data['createdAt'] as Timestamp?,
          });
        }
      }
    }

    result.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadDownlines(),
          builder: (context, snap) {
            final count = snap.data?.length ?? 0;
            if (count > 0) {
              return Text(
                'Level ${level + 1}, $count คน',
                style: styles(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              );
            }
            return Text('Level ${level + 1}');
          },
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadDownlines(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Text(
                  'Error: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final list = snap.data ?? [];

          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_off_outlined,
                    size: 48.sp,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'ยังไม่มีสมาชิกในชั้นนี้',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: list.length,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey.shade300),
            itemBuilder: (context, index) => _downlineItem(list[index]),
          );
        },
      ),
    );
  }

  Widget _downlineItem(Map<String, dynamic> item) {
    final name = item['name'] as String;
    final phone = item['phone'] as String;
    final collection = item['collection'] as String;
    final createdAt = item['createdAt'] as Timestamp?;

    const typeLabels = {'buyers': '🛒', 'vendors': '🏪', 'riders': '🛵'};

    final typeLabel = typeLabels[collection] ?? collection;

    String dateStr = '-';
    if (createdAt != null) {
      final d = createdAt.toDate();
      const months = [
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
      dateStr = '${d.day} ${months[d.month - 1]} ${d.year + 543}';
    }

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),

      title: Text(
        '$typeLabel $name',
        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                launchUrl(Uri.parse('tel:$phone'));
              },
              child: Row(
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone, size: 16.sp, color: Colors.green[600]),
                      SizedBox(width: 6.w),
                      Text(
                        phone,
                        style: styles(
                          fontSize: 12.sp,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Spacer(),
                  Row(
                    children: [
                      Icon(Icons.event, size: 16.sp, color: Colors.amber[500]),
                      SizedBox(width: 6.w),
                      Text(
                        dateStr,
                        style: styles(
                          fontSize: 11.sp,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
          ],
        ),
      ),
    );
  }
}
