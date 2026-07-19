import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';
import '../engine.dart';
import '../notation.dart';

/// AI 回复解析结果
class AIDecision {
  final List<QpAction> actions;
  final int? undoSteps;
  final String rawContent;
  AIDecision({required this.actions, this.undoSteps, required this.rawContent});
}

class AIClient {
  final Side side;

  /// 观AI战模式：上一局棋谱（要求采用不同策略）
  String? previousGameQp;

  AIClient({required this.side});

  static const String rulesText = '''
## 舰队象棋规则
棋盘13列×14行（x∈[0,12]，y∈[0,13]），海域分界在y=6与y=7之间（白色区域），红方y≤6，蓝方y≥7。双方指挥区（黑虚框）：x∈[4,8]，红y∈[0,4]，蓝y∈[9,13]。

### 棋子每方
- **旗舰**(旗)×1：正交1格，限指挥区。被吃则全局败。同列无遮挡=对脸，主动方判负。
- **护卫舰**(护)×2：斜1格，区内或邻己方可出区。站敌巡射击线上可拦截该线轰炸。
- **巡洋舰**(巡)×3：移动=正交直线1~2格（不可跳越），移动与攻击互斥。
  攻击：沿正交直线锁定一格。射击线须恰好越过1颗棋子（任意阵营）作为炮架——炮架自身不可攻击，炮架后方所有空格（至下一颗棋子前）均为有效目标。
  锁定位置双方公开可见（红色四角框），攻击必定在敌方下回合结束时结算：目标格有舰船则击沉（潜艇免疫；敌护卫舰站射击线则拦截）。每回合可多艘各开火一次；开火者当回合不能移动。
- **驱逐舰**(驱)×7：前进/左右各1格，不退。到底线升变为巡洋舰。
- **战机编队**(机)×2：马走日，敌方别腿。不能攻击潜艇。
- **潜艇**(潜)×2：正交直线1~2格可穿行，吃子1格。免疫轰炸与战机。
- **预警机**(警)×2：斜向1~3格可越子，不过河。全灭后巡洋舰无法轰炸。

### 回合流程
先令巡洋舰开火（0个或多个，不结束回合），然后移动一个棋子（结束回合）。
棋谱中 `# 结算：` 行记录每轮轰炸结果，参考它可判断目标是否存活。
''';

  static String boardToMap(Board board) {
    final buf = StringBuffer();
    for (int y = Board.height - 1; y >= 0; y--) {
      buf.write('${y.toString().padLeft(2)}|');
      for (int x = 0; x < Board.width; x++) {
        final p = board.at(Pos(x, y));
        if (p == null) {
          buf.write(' ..');
        } else {
          buf.write(' ${p.side == Side.red ? 'R' : 'B'}${p.type.label}');
        }
      }
      buf.writeln();
    }
    buf.write('    ');
    for (int x = 0; x < Board.width; x++) {
      buf.write('${x.toString().padLeft(2)} ');
    }
    return buf.toString();
  }

  static String legalMovesText(Board board, RulesEngine rules, Side s) {
    final buf = StringBuffer();
    for (final p in board.pieces.where((p) => p.side == s)) {
      final moves = rules.validMoves(p);
      if (moves.isEmpty) continue;
      buf.writeln(
          '${p.type.label}${p.pos.qp} 可移动至: ${moves.map((e) => e.qp).join(' ')}');
    }
    return buf.toString();
  }

  static String bombardOptionsText(Board board, RulesEngine rules, Side s) {
    if (!rules.canBombard(s)) return '（预警机全灭，无法轰炸）';
    final buf = StringBuffer();
    for (final p
        in board.pieces.where((p) => p.side == s && p.type == PieceType.cruiser)) {
      final targets = rules.getBombardTargets(p);
      if (targets.isNotEmpty) {
        buf.writeln('巡${p.pos.qp} 可轰炸: ${targets.map((e) => e.qp).join(' ')}');
      }
    }
    return buf.isEmpty ? '（无可用巡洋舰）' : buf.toString();
  }

  String buildPrompt({
    required Board board,
    required GameState state,
    required String qpContent,
    required bool canUndo,
    required int undoLeft,
  }) {
    final rules = RulesEngine(board);
    final debug = AppSettings.aiDebug;
    final depth = AppSettings.aiDepth;

    final differentStrategy = previousGameQp != null
        ? '''
## 上一局棋谱（请尽量采用与上局不同的策略）
$previousGameQp
'''
        : '';

    return '''
你是舰队象棋${side.fullLabel}AI。
$rulesText
$differentStrategy
## 本局棋谱（至今）
$qpContent

## 当前局面（R=红 B=蓝）
${boardToMap(board)}

## 你的合法移动
${legalMovesText(board, rules, side)}

## 你的轰炸选项（本回合可多艘各开火一次，开火者不能再移动）
${bombardOptionsText(board, rules, side)}

## 任务
${debug ? '先分析局势（每行以"分析："开头），最后一行以"指令："输出行动。推演深度$depth步，注意棋谱#结算行中哪些位置已被清空。' : '决定本回合轰炸（0或多个）与移动（必须1个）。注意棋谱#结算行中哪些位置已被清空。'}
${canUndo ? '如需悔棋可回复"悔x"（x为回退半步数，消耗x次配额，你剩余$undoLeft次）。' : ''}

## 输出格式
只回复最终指令行，以"指令："开头。${debug ? '\n指令前每行加"分析："前缀输出推演过程。' : ''}
指令格式：巡（x，y）x（x，y）目标，棋子（x，y）->（x，y）目标
目标=棋子简称或"空"。移动指令必须恰好1个且放最后。
示例：指令：巡（6，2）x（6，8）驱，驱（0，5）->（0，6）空''';
  }

  Future<AIDecision> requestDecision({
    required Board board,
    required GameState state,
    required String qpContent,
    required bool canUndo,
    required int undoLeft,
    String? errorFeedback,
  }) async {
    final prompt = buildPrompt(
      board: board,
      state: state,
      qpContent: qpContent,
      canUndo: canUndo,
      undoLeft: undoLeft,
    );

    final messages = [
      {'role': 'system', 'content': '你是严谨的舰队象棋棋手，只按要求格式输出。'},
      {'role': 'user', 'content': prompt},
      if (errorFeedback != null)
        {'role': 'user', 'content': '你上次的指令违规：$errorFeedback。请重新给出合法指令，注意必须从合法移动列表中选择。'},
    ];

    final requestBody = jsonEncode({
      'model': AppSettings.model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 4096,
      'thinking': {'type': 'disabled'},
    });

    final response = await http
        .post(
          Uri.parse('${AppSettings.baseUrl}/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppSettings.apiKey}',
          },
          body: requestBody,
        )
        .timeout(const Duration(seconds: 180));

    _logAI(side.label, messages, requestBody, response.body);

    if (response.statusCode != 200) {
      throw Exception('API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data.containsKey('error')) throw Exception('API Error: ${data["error"]}');

    final message = (data['choices'] as List).first['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';

    if (content.trim().isEmpty) {
      throw Exception('模型未输出内容（finish_reason=${(data['choices'] as List).first['finish_reason']}）');
    }

    final decision = parseDecision(content);
    return AIDecision(
      actions: decision.actions,
      undoSteps: decision.undoSteps,
      rawContent: content,
    );
  }

  static final List<String> _buf = [];

  /// 写 AI 通信日志到文件
  static void _logAI(String side, List<Map<String, dynamic>> msgs, String reqBody, String respBody) async {
    try {
      if (kIsWeb) return;
      _buf.add('=== ${DateTime.now()} === $side ===\n'
          '--- 发送 Prompt ---\n${msgs.last['content']}\n'
          '--- 收到 Response ---\n$respBody\n\n');
      if (_buf.length >= 3 || _buf.fold<int>(0, (s, e) => s + e.length) > 50000) {
        await _flushLog();
      }
    } catch (_) {}
  }

  static Future<void> _flushLog() async {
    if (_buf.isEmpty) return;
    try {
      final dir = Directory('${Directory.current.path}${Platform.pathSeparator}ai_logs');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}ai_trace_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(_buf.join());
      _buf.clear();
    } catch (_) {}
  }

  /// 强制刷盘（对局结束时调用）
  static Future<void> flushAll() => _flushLog();

  /// 从AI回复中解析指令（优先取"指令："之后的部分）
  static AIDecision parseDecision(String content) {
    String directive = content;
    final idx = content.lastIndexOf('指令：');
    if (idx >= 0) {
      directive = content.substring(idx);
    } else {
      final idx2 = content.lastIndexOf('指令:');
      if (idx2 >= 0) directive = content.substring(idx2);
    }

    final undo = QpParser.parseUndo(directive);
    final actions = QpParser.parseActions(directive);
    return AIDecision(actions: actions, undoSteps: undo, rawContent: content);
  }
}
