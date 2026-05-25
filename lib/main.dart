// ignore_for_file: avoid_print, deprecated_member_use
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:thai_address_picker/thai_address_picker.dart'
    hide ChangeNotifierProvider;
import 'package:colae_shop/auth/landing_page.dart';
import 'package:colae_shop/auth/login_page.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/providers/vendor_order_provider.dart';
import 'package:colae_shop/services/notification_service.dart';

Future<void> _saveFcmToken() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null) await _saveFcmToken();
      });
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance.collection('vendors').doc(uid).update({
      'fcmToken': token,
    });
  } catch (e) {
    print("Failed to save FCM token: ${e.toString()}");
  }
}

Future<void> _updateFcmToken(String newToken) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('vendors').doc(uid).update({
      'fcmToken': newToken,
    });
  } catch (e) {
    print("Failed to update FCM token: ${e.toString()}");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    print("Firebase init error: ${e.toString()}");
  }

  FlutterError.onError = (FlutterErrorDetails details) {};

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.dark,
    ),
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode
        ? AndroidProvider.playIntegrity
        : AndroidProvider.debug,
  );

  await NotificationService.init();
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: true,
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    await _saveFcmToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFcmToken);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('=== FOREGROUND MESSAGE ===');
      print('type: ${message.data['type']}');
      print('title: ${message.notification?.title}');
      print('data: ${message.data}');
      NotificationService.showLocalNotification(message);
    });
  });
  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => VendorOrderProvider()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSub;
  User? _currentUser;
  Timer? _firestoreKeepAliveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _currentUser = user;
    });
    _firestoreKeepAliveTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _firestoreKeepAliveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentUser != null) {
      _currentUser!.getIdToken(true).then((_) {}).catchError((e) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 815),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Vendor Box',
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black26),
            primarySwatch: Colors.blue,
            textTheme: Typography.englishLike2018.apply(
              fontSizeFactor: 1.sp,
              bodyColor: Colors.black,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey,
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.white),
              bodyMedium: TextStyle(color: Colors.white70),
              headlineSmall: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
          ),
          themeMode: ThemeMode.system,
          home: SplashView(),
          builder: EasyLoading.init(),
        );
      },
    );
  }
}

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  Timer? _timer;

  @override
  void initState() {
    _timer = Timer(const Duration(seconds: 7), () {
      _navigateToNextScreen();
    });
    super.initState();
  }

  @override
  void dispose() {
    _timer!.cancel();
    super.dispose();
  }

  void _navigateToNextScreen() async {
    final User? user = await FirebaseAuth.instance.authStateChanges().first;
    if (user != null) {
      Get.offAll(() => const LandingPage());
    } else {
      Get.offAll(() => const LoginPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 150.h),
          Center(child: Image.asset('images/colae2.png', fit: BoxFit.contain)),
        ],
      ),
    );
  }
}
