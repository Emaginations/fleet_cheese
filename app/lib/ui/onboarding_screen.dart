import 'package:flutter/material.dart';

import '../config.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 第二界面：初次引导设置（API + 推演步数）
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  void _finish() {
    AppSettings.onboarded = true;
    AppSettings.save();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F9),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.rocket_launch, size: 48, color: Color(0xFF2F76C6)),
                const SizedBox(height: 12),
                const Text(
                  '欢迎使用舰队象棋',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '首次使用请配置大模型 API（用于AI对战），并测试连通性。\n所有设置之后都可以在「设置」中随时修改。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: ApiSettingsCard(),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('AI推演步数', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: AppSettings.aiDepth.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '${AppSettings.aiDepth}',
                            onChanged: (v) {
                              setState(() => AppSettings.aiDepth = v.round());
                              AppSettings.save();
                            },
                          ),
                        ),
                        Text('${AppSettings.aiDepth}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F76C6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('完成，进入游戏', style: TextStyle(fontSize: 15)),
                ),
                TextButton(
                  onPressed: _finish,
                  child: Text('跳过（稍后在设置中配置）',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
