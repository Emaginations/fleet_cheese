import 'package:flutter/material.dart';
import 'config.dart';
import 'ui/settings_screen.dart';
import 'ui/splash_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const FleetChessApp());
}

class FleetChessApp extends StatelessWidget {
  const FleetChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '舰队象棋',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF2F76C6),
        scaffoldBackgroundColor: const Color(0xFFF2F7F9),
        fontFamily: 'SimSun',
        fontFamilyFallback: const ['Noto Serif SC', 'serif'],
      ),
      home: const SplashScreen(),
      // 全局设置悬浮球：所有页面右下角可见
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const _SettingsFloatingBall(),
          ],
        );
      },
    );
  }
}

/// 全局设置悬浮球（可拖动，点击进入设置，返回后所有页面实时更新）
class _SettingsFloatingBall extends StatefulWidget {
  const _SettingsFloatingBall();

  @override
  State<_SettingsFloatingBall> createState() => _SettingsFloatingBallState();
}

class _SettingsFloatingBallState extends State<_SettingsFloatingBall> {
  Offset? _pos;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // 开屏/引导阶段不显示悬浮球，进入主界面后由 AppSettings.onboarded 驱动
    AppSettings.notifier.addListener(_onSettingsChanged);
    // 延迟到开屏结束后显示
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    AppSettings.notifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _openSettings() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    // 返回时 SettingsScreen 内的每次修改已通过 AppSettings.save() → notifier 广播，
    // 各页面用 ValueListenableBuilder 监听后实时重建。
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final size = MediaQuery.of(context).size;
    final pos = _pos ?? Offset(size.width - 64, size.height * 0.72);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            final nx = (pos.dx + d.delta.dx).clamp(4.0, size.width - 52);
            final ny = (pos.dy + d.delta.dy).clamp(4.0, size.height - 52);
            _pos = Offset(nx, ny);
          });
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openSettings,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2F76C6).withAlpha(225),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(70),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.white.withAlpha(160), width: 1.5),
              ),
              child: const Icon(Icons.settings, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
