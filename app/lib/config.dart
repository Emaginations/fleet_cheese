import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// API 提供商
class ApiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String brandLetter;
  final int brandColor;
  const ApiProvider(this.id, this.name, this.baseUrl, this.brandLetter, this.brandColor);
}

const List<ApiProvider> kApiProviders = [
  ApiProvider('587', '587 (免费试用)', 'https://api.587.lol/v1', '5', 0xFF7C3AED),
  ApiProvider('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'D', 0xFF4D6BFE),
  ApiProvider('doubao', '豆包(火山方舟)', 'https://ark.cn-beijing.volces.com/api/v3', '豆', 0xFF00C8B4),
  ApiProvider('google', '谷歌 Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'G', 0xFF4285F4),
  ApiProvider('grok', 'Grok (xAI)', 'https://api.x.ai/v1', 'X', 0xFF1D1D1F),
  ApiProvider('chatgpt', 'ChatGPT (OpenAI)', 'https://api.openai.com/v1', 'O', 0xFF10A37F),
  ApiProvider('longcat', 'LongCat (美团)', 'https://api.longcat.chat/openai/v1', 'L', 0xFFFFD100),
  ApiProvider('kimi', 'Kimi (月之暗面)', 'https://api.moonshot.cn/v1', 'K', 0xFF16191E),
  ApiProvider('mimo', 'MiMo (小米)', 'https://api.xiaomimimo.com/v1', 'M', 0xFFFF6900),
  ApiProvider('zhipu', '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', '智', 0xFF3B5BDB),
];

ApiProvider providerById(String id) =>
    kApiProviders.firstWhere((p) => p.id == id, orElse: () => kApiProviders.first);

/// 全局设置（内存镜像 + SharedPreferences 持久化）
class AppSettings {
  static SharedPreferences? _prefs;

  static String providerId = 'deepseek';
  static String model = 'deepseek-v4-flash';

  /// 每个 API 服务商独立的 Key
  static final Map<String, String> apiKeys = {};

  static String get apiKey => apiKeys[providerId] ?? '';
  static set apiKey(String v) => apiKeys[providerId] = v;

  /// AI对战中玩家执方
  static Side mySide = Side.red;

  /// 默认先手：null=随机(d2)
  static Side? firstMover;

  static int aiDepth = 4;
  static bool aiDebug = false;
  static bool deathMatch = false;
  static bool showRules = true;
  static bool onboarded = false;

  static const int undoQuota = 4;

  /// 设置版本号（每次save递增，用于驱动所有页面实时刷新）
  static int revision = 0;
  static final ValueNotifier<int> notifier = ValueNotifier(0);

  static String get baseUrl => providerById(providerId).baseUrl;
  static bool get hasKey => apiKey.isNotEmpty;

  static Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      providerId = p.getString('providerId') ?? 'deepseek';
      // 迁移单 Key → 多 Key；优先读取各提供商独立 Key，兼容旧版 apiKey
      final keysJson = p.getString('apiKeys');
      if (keysJson != null) {
        final decoded = jsonDecode(keysJson) as Map<String, dynamic>;
        apiKeys.clear();
        for (final e in decoded.entries) { apiKeys[e.key] = e.value.toString(); }
      }
      final oldKey = p.getString('apiKey') ?? '';
      if (oldKey.isNotEmpty && !apiKeys.containsKey(providerId)) {
        apiKeys[providerId] = oldKey; // 迁移旧 Key 到当前提供商
        await p.remove('apiKey');
      }
      model = p.getString('model') ?? 'deepseek-v4-flash';
      mySide = (p.getString('mySide') ?? 'red') == 'blue' ? Side.blue : Side.red;
      final fm = p.getString('firstMover') ?? 'random';
      firstMover = fm == 'red' ? Side.red : (fm == 'blue' ? Side.blue : null);
      aiDepth = p.getInt('aiDepth') ?? 4;
      aiDebug = p.getBool('aiDebug') ?? false;
      deathMatch = p.getBool('deathMatch') ?? false;
      showRules = p.getBool('showRules') ?? true;
      onboarded = p.getBool('onboarded') ?? false;
    } catch (_) {
      // 存储异常时使用默认值
    }
  }

  static Future<void> save() async {
    revision++;
    notifier.value = revision;
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setString('providerId', providerId);
      await p.setString('apiKeys', jsonEncode(apiKeys));
      await p.setString('model', model);
      await p.setString('mySide', mySide == Side.blue ? 'blue' : 'red');
      await p.setString('firstMover',
          firstMover == null ? 'random' : (firstMover == Side.red ? 'red' : 'blue'));
      await p.setInt('aiDepth', aiDepth);
      await p.setBool('aiDebug', aiDebug);
      await p.setBool('deathMatch', deathMatch);
      await p.setBool('showRules', showRules);
      await p.setBool('onboarded', onboarded);
    } catch (_) {}
  }

  /// 连通性快速测试：返回 (成功, 信息)
  static Future<(bool, String)> testConnection() async {
    if (apiKey.isEmpty) return (false, '请先填写 API Key');
    try {
      final resp = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': '回复"OK"即可'}
              ],
              'max_tokens': 16,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices']?[0]?['message']?['content'] ?? '';
        return (true, '连接成功，模型响应：$content');
      }
      return (false, 'HTTP ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}');
    } catch (e) {
      return (false, '连接失败：$e');
    }
  }
}
