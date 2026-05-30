import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:colae_shop/pages/mode_selector_page.dart';
import 'package:colae_shop/services/sevice.dart';

class HotelSettingsTab extends StatelessWidget {
  const HotelSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ตั้งค่า Hotel', style: styles(color: Colors.white, fontSize: 18.sp)),
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.all(12.w),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.blue),
              title: Text('เปลี่ยนบริการ', style: styles(fontSize: 16.sp)),
              subtitle: Text('กลับไปเลือกโหมดบริการอื่น', style: styles(fontSize: 12.sp, color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('vendor_last_mode');
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const ModeSelectorPage()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
