import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// 第一界面：开屏
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await AppSettings.load();
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;
    // 渐变过渡到第二屏
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (_, __, ___) =>
          AppSettings.onboarded ? const HomeScreen() : const OnboardingScreen(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF92CDDB),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.anchor, size: 72, color: Colors.white),
            SizedBox(height: 24),
            Text(
              '1maginations Studio',
              style: TextStyle(
                fontFamily: 'SimSun',
                fontFamilyFallback: ['Noto Serif SC', 'serif'],
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '舰 队 象 棋',
              style: TextStyle(
                fontFamily: 'SimSun',
                fontFamilyFallback: ['Noto Serif SC', 'serif'],
                fontSize: 16,
                color: Colors.white70,
                letterSpacing: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
