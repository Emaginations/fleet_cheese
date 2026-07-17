import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 单个动作（移动或轰炸）
class QpAction {
  final PieceType pieceType;
  final Pos from;
  final Pos to;
  final bool isBombard; // true=x攻击，false=->移动
  final String targetDesc; // 目标格描述：棋子简称或"空"

  const QpAction({
    required this.pieceType,
    required this.from,
    required this.to,
    required this.isBombard,
    required this.targetDesc,
  });

  String serialize() =>
      '${pieceType.label}${from.qp}${isBombard ? 'x' : '->'}${to.qp}$targetDesc';
}

/// 悔棋动作
class QpUndo {
  final int steps;
  const QpUndo(this.steps);
}

/// 棋谱解析器：从文本提取动作（兼容全角/半角括号逗号）
class QpParser {
  /// 动作正则：棋子（x，y）->/x（x，y）[目标]
  static final _actionRe = RegExp(
      r'(旗|护|巡|驱|机|潜|警)\s*[（(]\s*(\d+)\s*[，,]\s*(\d+)\s*[）)]\s*(->|→|x|X|×)\s*[（(]\s*(\d+)\s*[，,]\s*(\d+)\s*[）)]\s*(旗|护|巡|驱|机|潜|警|空)?');

  static final _undoRe = RegExp(r'悔\s*(\d+)');

  /// 从文本解析所有动作
  static List<QpAction> parseActions(String text) {
    final result = <QpAction>[];
    for (final m in _actionRe.allMatches(text)) {
      final type = PieceTypeX.fromLabel(m.group(1)!)!;
      final from = Pos(int.parse(m.group(2)!), int.parse(m.group(3)!));
      final op = m.group(4)!;
      final to = Pos(int.parse(m.group(5)!), int.parse(m.group(6)!));
      final isBombard = op == 'x' || op == 'X' || op == '×';
      result.add(QpAction(
        pieceType: type,
        from: from,
        to: to,
        isBombard: isBombard,
        targetDesc: m.group(7) ?? '空',
      ));
    }
    return result;
  }

  /// 解析悔棋指令，返回悔棋半步数（无则null）
  static int? parseUndo(String text) {
    final m = _undoRe.firstMatch(text);
    return m != null ? int.parse(m.group(1)!) : null;
  }
}

/// 对局棋谱记录器：维护行列表+落盘
class GameRecorder {
  final List<String> lines = [];
  String? _filePath;
  final DateTime startTime;
  Side firstMover;

  GameRecorder({required this.firstMover}) : startTime = DateTime.now();

  String get _header {
    final ts = startTime;
    final t =
        '${ts.year}-${_p(ts.month)}-${_p(ts.day)} ${_p(ts.hour)}:${_p(ts.minute)}:${_p(ts.second)}';
    return '# 舰队象棋棋谱\n# 时间：$t\n# 先手：${firstMover.label}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  /// 记录一个半步（该方本回合所有动作，逗号分隔）
  void recordPly(int round, Side side, List<String> actions) {
    if (actions.isEmpty) return;
    lines.add('$round.${side.label}，${actions.join('，')}');
    _save();
  }

  /// 悔棋：截断到指定行数
  void truncate(int lineCount) {
    if (lineCount < lines.length) {
      lines.removeRange(lineCount, lines.length);
      _save();
    }
  }

  /// 终局标注
  void recordResult(String result) {
    lines.add('# 结果：$result');
    _save();
  }

  String get content => '$_header\n${lines.join('\n')}\n';

  Future<String> get filePath async {
    if (_filePath != null) return _filePath!;
    if (kIsWeb) return 'web://qp/memory.qp';
    final dir = await qpDirectory();
    final ts = startTime;
    final name =
        'fleet_${ts.year}${_p(ts.month)}${_p(ts.day)}_${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}.qp';
    _filePath = '${dir.path}${Platform.pathSeparator}$name';
    return _filePath!;
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    try {
      final path = await filePath;
      await File(path).writeAsString(content);
    } catch (_) {
      // 存盘失败不影响对局
    }
  }

  /// 棋谱目录
  static Future<Directory> qpDirectory() async {
    if (kIsWeb) throw UnsupportedError('web not supported');
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}FleetChess${Platform.pathSeparator}qp');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 列出全部棋谱文件（新→旧）
  static Future<List<File>> listQpFiles() async {
    if (kIsWeb) return [];
    try {
      final dir = await qpDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.qp'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// 读取最近一局棋谱内容（排除当前对局文件）
  static Future<String?> latestQpContent({String? excludePath}) async {
    try {
      final files = await listQpFiles();
      for (final f in files) {
        if (excludePath != null && f.path == excludePath) continue;
        return await f.readAsString();
      }
    } catch (_) {}
    return null;
  }
}

/// 已解析的棋谱（回放用）
class ParsedGame {
  final Side firstMover;
  final List<ParsedPly> plies;
  final String? result;

  ParsedGame({required this.firstMover, required this.plies, this.result});

  static ParsedGame fromContent(String content) {
    Side first = Side.red;
    String? result;
    final plies = <ParsedPly>[];

    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        if (line.contains('先手：红')) first = Side.red;
        if (line.contains('先手：蓝')) first = Side.blue;
        final rm = RegExp(r'结果：(.+)').firstMatch(line);
        if (rm != null) result = rm.group(1);
        continue;
      }
      // 解析 "N.方，动作串"
      final m = RegExp(r'^(\d+)\.(红|蓝)[，,](.+)$').firstMatch(line);
      if (m == null) continue;
      final side = m.group(2) == '红' ? Side.red : Side.blue;
      final actions = QpParser.parseActions(m.group(3)!);
      if (actions.isEmpty) continue;
      plies.add(ParsedPly(
        round: int.parse(m.group(1)!),
        side: side,
        actions: actions,
      ));
    }
    return ParsedGame(firstMover: first, plies: plies, result: result);
  }
}

class ParsedPly {
  final int round;
  final Side side;
  final List<QpAction> actions;
  ParsedPly({required this.round, required this.side, required this.actions});
}
