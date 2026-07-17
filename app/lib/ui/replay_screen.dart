import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../models.dart';
import '../notation.dart';
import 'board_widget.dart';

/// 对局再现：读取.qp棋谱回放
class ReplayScreen extends StatefulWidget {
  final File qpFile;
  const ReplayScreen({super.key, required this.qpFile});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  ParsedGame? _game;
  String? _error;

  /// 已应用的半步数（0=初始局面）
  int _cursor = 0;

  /// 每个半步应用后的棋盘快照（懒构建）
  final List<Board> _boards = [];

  Timer? _autoTimer;
  int _speed = 1; // 1x=4s, 2x=2s, 4x=1s

  GameState _dummyState = GameState(firstMoverChoice: Side.red);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await widget.qpFile.readAsString();
      final game = ParsedGame.fromContent(content);
      // 预构建所有局面
      final boards = <Board>[Board.initial()];
      var cur = boards.first;
      for (final ply in game.plies) {
        cur = _applyPly(cur.clone(), ply);
        boards.add(cur);
      }
      setState(() {
        _game = game;
        _boards
          ..clear()
          ..addAll(boards);
        _cursor = 0;
      });
    } catch (e) {
      setState(() => _error = '棋谱解析失败：$e');
    }
  }

  /// 回放引擎：按棋谱行应用动作（信任棋谱，宽松执行）
  Board _applyPly(Board board, ParsedPly ply) {
    for (final a in ply.actions) {
      if (a.isBombard) {
        // 轰炸延迟结算：回放中直接在敌方行动后结算过于复杂，
        // 采用简化：若目标描述非"空"，在对方下一半步应用后移除目标格棋子。
        // 这里先记录，由 _applyPendingBombard 处理。
        _pendingBombards.add(_PendingBombard(a, ply.side));
      } else {
        final piece = board.at(a.from);
        if (piece != null) {
          final victim = board.at(a.to);
          if (victim != null) board.remove(victim);
          piece.pos = a.to;
          // 驱逐舰升变
          if (piece.type == PieceType.destroyer &&
              a.to.y == Board.promotionRow(piece.side)) {
            board.pieces.remove(piece);
            board.pieces.add(Piece(piece.id, PieceType.cruiser, piece.side, a.to));
          }
        }
      }
    }
    // 结算敌方（对方）在上一半步下达的轰炸：
    // 本半步是side行动，行动结束时结算对方(side.opponent)之前下达的轰炸
    final toResolve =
        _pendingBombards.where((b) => b.side == ply.side.opponent).toList();
    for (final b in toResolve) {
      final victim = board.at(b.action.to);
      if (victim != null && victim.type != PieceType.submarine) {
        // 护卫舰拦截判定（简化：射击线上有敌方护卫舰则无效）
        bool intercepted = false;
        final dx = (b.action.to.x - b.action.from.x).sign;
        final dy = (b.action.to.y - b.action.from.y).sign;
        if (dx == 0 || dy == 0) {
          var cur = b.action.from + Pos(dx, dy);
          while (cur != b.action.to && cur.inBoard) {
            final pc = board.at(cur);
            if (pc != null &&
                pc.type == PieceType.escort &&
                pc.side != b.side) {
              intercepted = true;
              break;
            }
            cur = cur + Pos(dx, dy);
          }
        }
        if (!intercepted) board.remove(victim);
      }
      _pendingBombards.remove(b);
    }
    return board;
  }

  final List<_PendingBombard> _pendingBombards = [];

  void _next() {
    if (_game == null) return;
    setState(() {
      _cursor = (_cursor + 1).clamp(0, _boards.length - 1);
    });
  }

  void _prev() {
    if (_game == null) return;
    setState(() {
      _cursor = (_cursor - 1).clamp(0, _boards.length - 1);
    });
  }

  void _toggleAuto() {
    if (_autoTimer != null) {
      _autoTimer!.cancel();
      _autoTimer = null;
      setState(() {});
      return;
    }
    _startAutoTimer();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    final interval = Duration(milliseconds: 4000 ~/ _speed);
    _autoTimer = Timer.periodic(interval, (_) {
      if (_cursor >= _boards.length - 1) {
        _autoTimer?.cancel();
        _autoTimer = null;
        setState(() {});
        return;
      }
      _next();
    });
    setState(() {});
  }

  void _cycleSpeed() {
    setState(() {
      _speed = _speed == 1 ? 2 : (_speed == 2 ? 4 : 1);
    });
    if (_autoTimer != null) _startAutoTimer();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.qpFile.path.split(Platform.pathSeparator).last;
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: Text('对局再现 · $name',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D2137),
        foregroundColor: Colors.cyanAccent,
      ),
      body: _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
          : _game == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildInfo(),
                    Expanded(
                      child: Center(
                        child: BoardWidget(
                          board: _boards[_cursor],
                          state: _dummyState,
                          activeSide: null,
                          onMove: (_) {},
                          onBombard: (_, __) {},
                        ),
                      ),
                    ),
                    _buildControls(),
                  ],
                ),
    );
  }

  Widget _buildInfo() {
    final g = _game!;
    String stepDesc = '初始局面';
    if (_cursor > 0 && _cursor <= g.plies.length) {
      final ply = g.plies[_cursor - 1];
      stepDesc =
          '${ply.round}.${ply.side.label}：${ply.actions.map((a) => a.serialize()).join('，')}';
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF0D2137),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('先手：${g.firstMover.fullLabel}${g.result != null ? '  结果：${g.result}' : ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(stepDesc,
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final playing = _autoTimer != null;
    return Container(
      color: const Color(0xFF0D2137),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.cyanAccent),
            tooltip: '上一回合',
            onPressed: _cursor > 0 ? _prev : null,
          ),
          const SizedBox(width: 8),
          IconButton(
            iconSize: 36,
            icon: Icon(playing ? Icons.pause_circle : Icons.play_circle,
                color: Colors.cyanAccent),
            tooltip: playing ? '暂停' : '自动播放',
            onPressed: _toggleAuto,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.cyanAccent),
            tooltip: '下一回合',
            onPressed: _cursor < _boards.length - 1 ? _next : null,
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: _cycleSpeed,
            child: Text('${_speed}x',
                style: const TextStyle(color: Colors.amber, fontSize: 16)),
          ),
          const SizedBox(width: 16),
          Text('$_cursor / ${_boards.length - 1}',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _PendingBombard {
  final QpAction action;
  final Side side;
  _PendingBombard(this.action, this.side);
}
