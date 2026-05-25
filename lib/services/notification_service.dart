// ignore_for_file: avoid_print

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      final plugin = _localNotif
          .resolvePlatformSpecificImplementation<
            // ← ต้องมี
            AndroidFlutterLocalNotificationsPlugin
          >();

      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'new_order_channel',
          'ออร์เดอร์ใหม่',
          description: 'แจ้งเตือนเมื่อมีออร์เดอร์ใหม่เข้ามา',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('new_order_sound'),
          enableVibration: true,
          showBadge: true,
        ),
      );

      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'order_status_channel',
          'สถานะออร์เดอร์',
          description: 'แจ้งเตือนความคืบหน้าของออร์เดอร์',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('order_ready'),
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        );

    await _localNotif.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );

    FirebaseMessaging.onMessageOpenedApp.listen((message) {});

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {}
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    final type = message.data['type'] ?? '';
    final title =
        message.data['title'] ?? message.notification?.title ?? '🔔 แจ้งเตือน';
    final body = message.data['body'] ?? message.notification?.body ?? '';

    // เลือก channel ตาม type
    final bool isNewOrder = type == 'new_order_vendor' || type == 'order_paid';
    final String channelId = isNewOrder
        ? 'new_order_channel'
        : 'order_status_channel';
    final String channelName = isNewOrder ? 'ออร์เดอร์ใหม่' : 'สถานะออร์เดอร์';
    final sound = isNewOrder
        ? const RawResourceAndroidNotificationSound('new_order_sound')
        : const RawResourceAndroidNotificationSound('order_ready');

    if (Platform.isAndroid) {
      await _localNotif.show(
        id: message.hashCode.abs(),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: sound,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            channelShowBadge: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } else {
      await _localNotif.show(
        id: message.hashCode.abs(),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
  }

  /* static Future<void> showLocalNotification(RemoteMessage message) async {
    final type = message.data['type'] ?? '';
    if (type != 'new_order_vendor' && type != 'order_paid') return;

    final title = message.data['title'] ?? '🛵 มีออร์เดอร์ใหม่!';
    final body =
        message.data['body'] ?? 'มีออร์เดอร์ใหม่เข้ามา กรุณาตรวจสอบด่วน';

    if (Platform.isAndroid) {
      await _localNotif.show(
        id: message.hashCode.abs(),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'new_order_channel',
            'ออร์เดอร์ใหม่', // ชื่อช่อง
            channelDescription: 'แจ้งเตือนเมื่อมีออร์เดอร์ใหม่เข้ามา',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('new_order_sound'),
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            channelShowBadge: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } else {
      await _localNotif.show(
        id: message.hashCode.abs(),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
  }*/
}
