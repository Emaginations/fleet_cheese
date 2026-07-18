import 'dart:convert';

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
棋盘13列×14行，坐标（x，y），左下角（0，0）。x∈[0,12]，y∈[0,13]。y=6与y=7之间为海域分界。红方半场y≤6，蓝方半场y≥7。指挥区：x∈[4,8]，红方y∈[0,4]，蓝方y∈[9,13]。
棋子（每方）：
- 旗舰(旗)×1：正交1格，限指挥区内。被吃/被轰沉则败。两旗舰同列且中间无棋子=对脸，走出该局面的一方判负。
- 护卫舰(护)×2：斜行1格。目标格须在指挥区内，或紧邻任一己方棋子（可出区）。当其位于敌巡洋舰的射击线上时，该线轰炸无效（拦截）。
- 巡洋舰(巡)×3：移动=正交直线1~2格，不可跳越，移动与攻击互斥。攻击（不消耗回合）：沿正交直线锁定一个位置（空格或棋子皆可），射击线可越过任意个我方棋子和至多1个敌方棋子；锁定位置双方公开可见（红色四角框）。攻击必定在敌方下回合结束时结算：该格有舰船则击沉（潜艇免疫；敌护卫舰站上射击线则拦截）。每回合可令多艘巡洋舰各开火一次；开火的巡洋舰当回合不能移动。
- 驱逐舰(驱)×7：前进1格或左右1格，不能后退。到达对方底线升变为巡洋舰。
- 战机编队(机)×2：马走日。敌方棋子可别马腿（己方不别）。不能攻击潜艇。
- 潜艇(潜)×2：正交直线1~2格且可穿越棋子，吃子时只能走1格。免疫巡洋舰轰炸与战机攻击。
- 预警机队(警)×2：斜向1~3格，可越子，不能过河。全部损失后己方巡洋舰无法轰炸、旗舰无法远程打击。
回合：一方回合内可先令任意艘巡洋舰开火（不结束回合），然后移动一个棋子（结束回合）。棋谱中"# 结算："行记录了每轮轰炸的实际结果（击沉/落空/拦截）。
开局（红方，蓝方以海域分界镜像）：y0行：机(2,0)警(3,0)护(5,0)旗(6,0)护(7,0)警(9,0)机(10,0)；y2行：巡(1,2)(6,2)(11,2)；y4行：潜(3,4)(9,4)；y5行：驱(0,5)(2,5)(4,5)(6,5)(8,5)(10,5)(12,5)。
轰炸要点：目标在结算前对方可见并可躲避——轰炸空格仅在预判敌方走位时有价值，优先锁定敌方舰船所在位置或封锁其唯一退路，勿反复轰炸无人空格。
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
1. 局势分析：向前推演$depth步，评估双方威胁与机会。
2. 行动布置：决定本回合轰炸（0个或多个）与移动（必须1个）。
${canUndo ? '如需悔棋可回复"悔x"（x为回退半步数，消耗x次配额，你剩余$undoLeft次）。' : ''}

## 输出格式
${debug ? '先输出完整推演分析，最后一行以"指令："开头给出最终指令。' : '只回复一行最终指令，以"指令："开头。'}
指令格式：巡（x，y）x（x，y）目标，巡（x，y）x（x，y）目标，棋子（x，y）->（x，y）目标
目标为该格棋子简称或"空"。移动指令必须恰好1个且放在最后。
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

    final response = await http
        .post(
          Uri.parse('${AppSettings.baseUrl}/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppSettings.apiKey}',
          },
          body: jsonEncode({
            'model': AppSettings.model,
            'messages': messages,
            'temperature': 0.7,
            'max_tokens': 16384,
            // 推理模型关闭思考防止耗尽tokens致content为空（仅对支持thinking字段的服务商发送）
            if (const {'deepseek', 'doubao', 'longcat', 'mimo', 'zhipu'}
                .contains(AppSettings.providerId))
              'thinking': {'type': AppSettings.aiDebug ? 'enabled' : 'disabled'},
          }),
        )
        .timeout(const Duration(seconds: 300));

    if (response.statusCode != 200) {
      throw Exception('API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data.containsKey('error')) throw Exception('API Error: ${data["error"]}');

    final message = (data['choices'] as List).first['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    // 推理模型的思考内容（debug展示用）
    final reasoning = (message['reasoning_content'] as String?) ?? '';

    if (content.trim().isEmpty) {
      throw Exception(
          '模型未输出最终内容（finish_reason=${(data['choices'] as List).first['finish_reason']}，思考${reasoning.length}字被截断），请尝试非推理模型或增大max_tokens');
    }

    final decision = parseDecision(content);
    return AIDecision(
      actions: decision.actions,
      undoSteps: decision.undoSteps,
      rawContent: reasoning.isNotEmpty
          ? '【思考过程】\n$reasoning\n\n【最终输出】\n$content'
          : content,
    );
  }

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
