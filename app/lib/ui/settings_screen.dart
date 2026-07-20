import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';

/// API 设置卡片（引导页与设置页共用）
class ApiSettingsCard extends StatefulWidget {
  const ApiSettingsCard({super.key});

  @override
  State<ApiSettingsCard> createState() => _ApiSettingsCardState();
}

class _ApiSettingsCardState extends State<ApiSettingsCard> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  bool _keyVisible = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: AppSettings.apiKey);
    _modelCtrl = TextEditingController(text: AppSettings.model);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    AppSettings.apiKey = _keyCtrl.text.trim();
    AppSettings.model = _modelCtrl.text.trim();
    await AppSettings.save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final (ok, msg) = await AppSettings.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = msg;
    });
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 提供商下拉
        DropdownButtonFormField<String>(
          initialValue: AppSettings.providerId,
          decoration: _dec('API 服务商'),
          items: [
            for (final p in kApiProviders)
              DropdownMenuItem(
                value: p.id,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: Color(p.brandColor),
                      child: Text(p.brandLetter,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(p.name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() {
                AppSettings.providerId = v;
                _keyCtrl.text = AppSettings.apiKey; // 切换时加载该提供商的Key
              });
              AppSettings.save();
            }
          },
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            AppSettings.baseUrl,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        // API Key
        TextField(
          controller: _keyCtrl,
          obscureText: !_keyVisible,
          style: const TextStyle(fontSize: 13),
          decoration: _dec('API Key').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility,
                  size: 18),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
          ),
          onChanged: (v) {
            AppSettings.apiKey = v.trim();
            AppSettings.save();
          },
        ),
        const SizedBox(height: 12),
        // 模型名
        TextField(
          controller: _modelCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: _dec('模型名称（默认 deepseek-v4-flash）'),
          onChanged: (v) {
            AppSettings.model = v.trim();
            AppSettings.save();
          },
        ),
        const SizedBox(height: 12),
        // 测试按钮
        FilledButton.icon(
          onPressed: _testing ? null : _test,
          icon: _testing
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering, size: 18),
          label: Text(_testing ? '测试中...' : '连通性快速测试'),
        ),
        if (_testResult != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _testOk ? const Color(0xFFE3F5E5) : const Color(0xFFFDE7E7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _testResult!,
              style: TextStyle(
                  fontSize: 12,
                  color: _testOk ? const Color(0xFF1B7C2C) : const Color(0xFFB3261E)),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// 对局偏好设置卡片（先手/推演步数/Debug/生死斗/规则说明）
class GamePrefsCard extends StatefulWidget {
  final bool showMySide;
  const GamePrefsCard({super.key, this.showMySide = true});

  @override
  State<GamePrefsCard> createState() => _GamePrefsCardState();
}

class _GamePrefsCardState extends State<GamePrefsCard> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showMySide) ...[
          _rowLabel('AI对战我的执方', SegmentedButton<Side>(
            segments: const [
              ButtonSegment(value: Side.red, label: Text('红', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: Side.blue, label: Text('蓝', style: TextStyle(fontSize: 12))),
            ],
            selected: {AppSettings.mySide},
            onSelectionChanged: (s) {
              setState(() => AppSettings.mySide = s.first);
              AppSettings.save();
            },
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          )),
          const SizedBox(height: 8),
        ],
        _rowLabel('默认先手', SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'random', label: Text('随机', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'red', label: Text('红', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'blue', label: Text('蓝', style: TextStyle(fontSize: 12))),
          ],
          selected: {
            AppSettings.firstMover == null
                ? 'random'
                : (AppSettings.firstMover == Side.red ? 'red' : 'blue')
          },
          onSelectionChanged: (s) {
            setState(() {
              AppSettings.firstMover = switch (s.first) {
                'red' => Side.red,
                'blue' => Side.blue,
                _ => null,
              };
            });
            AppSettings.save();
          },
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        )),
        const SizedBox(height: 4),
        Row(
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        _switchRow('Debug模式（显示AI完整返回）', AppSettings.aiDebug, (v) {
          setState(() => AppSettings.aiDebug = v);
          AppSettings.save();
        }),
        _switchRow('生死斗（禁止悔棋）', AppSettings.deathMatch, (v) {
          setState(() => AppSettings.deathMatch = v);
          AppSettings.save();
        }),
        _switchRow('显示规则', AppSettings.showRules, (v) {
          setState(() => AppSettings.showRules = v);
          AppSettings.save();
        }),
      ],
    );
  }

  Widget _rowLabel(String label, Widget control) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        control,
      ],
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 独立设置页（随时可进）
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F9),
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: const Color(0xFF92CDDB),
        foregroundColor: Colors.black87,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('AI-1 设置', const ApiSettingsCard()),
          const SizedBox(height: 16),
          _card('AI-2 设置（观AI战专用）', const Api2SettingsCard()),
          const SizedBox(height: 16),
          _card('对局偏好', const GamePrefsCard()),
          const SizedBox(height: 16),
          _card('开发者名单', const _CreditsCard()),
        ],
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// AI-2 设置卡片（观AI战专用）
class Api2SettingsCard extends StatefulWidget {
  const Api2SettingsCard({super.key});

  @override
  State<Api2SettingsCard> createState() => _Api2SettingsCardState();
}

class _Api2SettingsCardState extends State<Api2SettingsCard> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  bool _keyVisible = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: AppSettings.ai2ApiKey);
    _modelCtrl = TextEditingController(text: AppSettings.ai2Model);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    AppSettings.ai2ApiKey = _keyCtrl.text.trim();
    AppSettings.ai2Model = _modelCtrl.text.trim();
    await AppSettings.save();
    setState(() { _testing = true; _testResult = null; });
    final (ok, msg) = await AppSettings.testConnection(url: AppSettings.ai2BaseUrl, key: AppSettings.ai2ApiKey, mdl: AppSettings.ai2Model);
    if (!mounted) return;
    setState(() { _testing = false; _testOk = ok; _testResult = msg; });
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 13), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: AppSettings.ai2ProviderId,
        decoration: _dec('API 服务商'),
        items: [
          for (final p in kApiProviders)
            DropdownMenuItem(value: p.id, child: Row(children: [
              CircleAvatar(radius: 10, backgroundColor: Color(p.brandColor), child: Text(p.brandLetter, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Flexible(child: Text(p.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            ])),
        ],
        onChanged: (v) {
          if (v != null) { setState(() { AppSettings.ai2ProviderId = v; _keyCtrl.text = AppSettings.ai2ApiKey; }); AppSettings.save(); }
        },
      ),
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(AppSettings.ai2BaseUrl, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
      TextField(controller: _keyCtrl, obscureText: !_keyVisible, style: const TextStyle(fontSize: 13), decoration: _dec('API Key').copyWith(suffixIcon: IconButton(icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _keyVisible = !_keyVisible))), onChanged: (v) { AppSettings.ai2ApiKey = v.trim(); AppSettings.save(); }),
      const SizedBox(height: 12),
      TextField(controller: _modelCtrl, style: const TextStyle(fontSize: 13), decoration: _dec('模型名称'), onChanged: (v) { AppSettings.ai2Model = v.trim(); AppSettings.save(); }),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _testing ? null : _test, icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering, size: 18), label: Text(_testing ? '测试中...' : '连通性快速测试')),
      if (_testResult != null) Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _testOk ? const Color(0xFFE3F5E5) : const Color(0xFFFDE7E7), borderRadius: BorderRadius.circular(8)), child: Text(_testResult!, style: TextStyle(fontSize: 12, color: _testOk ? const Color(0xFF1B7C2C) : const Color(0xFFB3261E)), maxLines: 4, overflow: TextOverflow.ellipsis)),
    ]);
  }
}

/// 开发者名单
class _CreditsCard extends StatelessWidget {
  const _CreditsCard();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, height: 1.9);
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('程序：DeepSeek-v4-pro', style: style),
        Text('规则：AAA🚀火箭批发零售', style: style),
        Text('构建：1maginations', style: style),
      ],
    );
  }
}
