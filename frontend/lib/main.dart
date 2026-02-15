import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data/wardrobe_store.dart';

import 'screens/home_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'widgets/glass_nav_bar.dart';
import 'theme/app_theme.dart';

late final List<CameraDescription> cameras;

const Color kAppBg = Color(0xFFFDFCF9);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,

      systemNavigationBarColor: kAppBg,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: kAppBg,

      // Some devices apply auto-contrast/tint. This helps keep it looking “normal”.
      systemNavigationBarContrastEnforced: true,
    ),
  );

  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();

  await Hive.initFlutter();
  await WardrobeStore.init();
  await WardrobeStore.seedIfNeeded();


  runApp(const AIWardrobeApp());
}

class AIWardrobeApp extends StatelessWidget {
  const AIWardrobeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const HomeScreen(),
    CameraScreen(cameras: cameras),
    const WardrobeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      extendBody: true,

      bottomNavigationBar: SafeArea(
        top: false,
        child: GlassNavBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
        ),
      ),
    );
  }
}
