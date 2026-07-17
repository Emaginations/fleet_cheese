import 'dart:io';

import 'package:flutter/material.dart';
import '../config.dart';
import '../models.dart';
import '../notation.dart';
import 'game_screen.dart';
import 'replay_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AppSettings.notifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettings.notifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _enterMode(BuildContext context, GameMode mode) {
    if ((mode == GameMode.vsAI || mode == GameMode.aiVsAi) && !AppSettings.hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先在设置中配置 API Key'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(mode: mode),
    ));
  }

  Future<void> _chooseReplayFile(BuildContext context) async {
    final files = await GameRecorder.listQpFiles();
    if (!context.mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有棋谱文件，先下一局吧')));
      return;
    }
    final file = await showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: Colors.white,
        title: const Text('选择棋谱'),
        children: [
          for (final f in files.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f),
              child: Text(
                f.path.split(Platform.pathSeparator).last,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
    if (file != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReplayScreen(qpFile: file)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeFromSettings = AppSettings.mySide == Side.blue ? '执蓝' : '执红';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F9),
      appBar: AppBar(
        title: const Text('舰队象棋', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF92CDDB),
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.crisis_alert, size: 48, color: Color(0xFF2F76C6)),
              const SizedBox(height: 8),
              Text('AI对战 · $modeFromSettings',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              _MenuButton(
                icon: Icons.smart_toy,
                label: 'AI对战',
                subtitle: '你$modeFromSettings vs AI（${AppSettings.hasKey ? AppSettings.model : '未配置API'}）',
                onTap: () => _enterMode(context, GameMode.vsAI),
              ),
              _MenuButton(
                icon: Icons.psychology,
                label: '自行推演',
                subtitle: '一人操控红蓝双方',
                onTap: () => _enterMode(context, GameMode.sandbox),
              ),
              _MenuButton(
                icon: Icons.people,
                label: '线下对战',
                subtitle: '面对面同屏对战，蓝方反向显示',
                onTap: () => _enterMode(context, GameMode.faceToFace),
              ),
              _MenuButton(
                icon: Icons.theaters,
                label: '对局再现',
                subtitle: '读取棋谱(.qp)回放，支持自动播放',
                onTap: () => _chooseReplayFile(context),
              ),
              _MenuButton(
                icon: Icons.smart_display,
                label: '观AI战',
                subtitle: 'AI自对弈，参考上局棋谱变换策略',
                onTap: () => _enterMode(context, GameMode.aiVsAi),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: 340,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF2F76C6), size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
