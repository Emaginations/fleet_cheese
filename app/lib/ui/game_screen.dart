import 'dart:async';

import 'package:flutter/material.dart';
import '../config.dart';
import '../models.dart';
import '../engine.dart';
import '../notation.dart';
import '../save_game.dart';
import '../ai/ai_client.dart';
import '../rules_text.dart';
import 'board_widget.dart';
import 'movable_dialog.dart';

enum GameMode { vsAI, sandbox, faceToFace, aiVsAi }

extension GameModeX on GameMode {
  String get label => switch (this) {
        GameMode.vsAI => 'AI对战',
        GameMode.sandbox => '自行推演',
        GameMode.faceToFace => '线下对战',
        GameMode.aiVsAi => '观AI战',
      };
}

class GameScreen extends StatefulWidget {
  final GameMode mode;
  const GameScreen({super.key, required this.mode});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameState _state;
  late GameRecorder _recorder;
  late GameController _controller;
  AIClient? _aiRed;
  AIClient? _aiBlue;

  bool _aiThinking = false;
  bool _stopped = false;
  String? _lastAIDebugContent;
  SelectionInfo? _selectionInfo;
  double? _lastAIElapsed; // 最近一次AI调用耗时秒数

  @override
  void initState() {
    super.initState();
    _startNewGame();
    AppSettings.notifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _stopped = true;
    AppSettings.notifier.removeListener(_onSettingsChanged);
    if (_state.winner == null && _state.ply > 0) {
      SaveGame.save(widget.mode.name, _state, List.of(_recorder.lines));
    } else {
      SaveGame.clear(widget.mode.name);
    }
    AIClient.flushAll();
    super.dispose();
  }

  void _onSettingsChanged() { if (mounted) setState(() {}); }

  Future<void> _startNewGame({bool forceNew = false}) async {
    _stopped = false; _aiThinking = false; _lastAIDebugContent = null;
    _selectionInfo = null; _aiRed = null; _aiBlue = null; _lastAIElapsed = null;

    bool restored = false;
    if (!forceNew) {
      final saved = await SaveGame.load(widget.mode.name);
      if (saved != null) {
        final (savedState, qpLines) = saved;
        _state = savedState;
        _recorder = GameRecorder(firstMover: _state.firstMover, modeLabel: widget.mode.label);
        _recorder.lines.addAll(qpLines);
        _controller = GameController(state: _state, recorder: _recorder);
        _state.addLog('已恢复未完成的对局（第${_state.round}回合）', side: _state.current);
        restored = true;
      }
    } else { await SaveGame.clear(widget.mode.name); }

    if (!restored) {
      final chosen = AppSettings.firstMover;
      _state = GameState(firstMoverChoice: chosen);
      _recorder = GameRecorder(firstMover: _state.firstMover, modeLabel: widget.mode.label);
      _controller = GameController(state: _state, recorder: _recorder);
      final way = chosen == null ? 'd2投掷' : '指定';
      _state.addLog('$way决定先手：${_state.firstMover.fullLabel}', side: _state.firstMover);
    }

    if (widget.mode == GameMode.vsAI) {
      final aiSide = AppSettings.mySide.opponent;
      final ai = AIClient(side: aiSide);
      if (aiSide == Side.red) { _aiRed = ai; } else { _aiBlue = ai; }
    } else if (widget.mode == GameMode.aiVsAi) {
      _aiRed = AIClient(side: Side.red);
      _aiBlue = AIClient.forAI2(side: Side.blue);
      final myPath = await _recorder.filePath;
      final prev = await GameRecorder.latestQpContent(excludePath: myPath);
      _aiRed!.previousGameQp = prev;
      _aiBlue!.previousGameQp = prev;
    }

    if (mounted) setState(() {});
    _maybeTriggerAI();
  }

  // --- AI 逻辑 ---
  bool get _isHumanTurn {
    if (_state.winner != null || _aiThinking) return false;
    return switch (widget.mode) {
      GameMode.vsAI => _state.current == AppSettings.mySide,
      GameMode.sandbox || GameMode.faceToFace => true,
      GameMode.aiVsAi => false,
    };
  }

  Side? get _activeSide {
    if (_state.winner != null || _aiThinking) return null;
    return switch (widget.mode) {
      GameMode.vsAI => _state.current == AppSettings.mySide ? AppSettings.mySide : null,
      GameMode.sandbox || GameMode.faceToFace => _state.current,
      GameMode.aiVsAi => null,
    };
  }

  void _maybeTriggerAI() {
    if (_stopped || _state.winner != null) return;
    final ai = _state.current == Side.red ? _aiRed : _aiBlue;
    if (ai == null) return;
    _runAITurn(ai);
  }

  Future<void> _runAITurn(AIClient ai) async {
    setState(() => _aiThinking = true);
    _lastAIElapsed = null;

    String? errorFeedback;
    for (int attempt = 0; attempt < 3; attempt++) {
      if (_stopped) return;
      try {
        final opponentBombards = _state.awaitingResolve[ai.side.opponent]!;
        String extraHint = '';
        if (opponentBombards.isNotEmpty) {
          extraHint = '\n【对方已锁定的轰炸（红色四角框），将在本回合结束时结算】\n';
          for (final b in opponentBombards) { extraHint += '${b.side.label}方轰${b.target.qp}\n'; }
        }

        final decision = await ai.requestDecision(
          board: _state.board, state: _state,
          qpContent: _recorder.content + extraHint,
          canUndo: !AppSettings.deathMatch && _state.undoLeft[ai.side]! > 0,
          undoLeft: _state.undoLeft[ai.side]!,
          errorFeedback: errorFeedback,
        );
        if (_stopped) return;
        _lastAIDebugContent = AppSettings.aiDebug ? decision.rawContent : null;
        _lastAIElapsed = decision.elapsedSec;

        if (decision.undoSteps != null && decision.actions.isEmpty) {
          final r = _controller.tryUndo(ai.side, decision.undoSteps!, quotaCost: decision.undoSteps!);
          if (r.ok) { setState(() => _aiThinking = false); _maybeTriggerAI(); return; }
          errorFeedback = r.error; continue;
        }

        final err = _applyAIActions(ai.side, decision.actions);
        if (err == null) { setState(() => _aiThinking = false); _afterPlyAdvanced(); return; }
        errorFeedback = err;
      } catch (e) {
        errorFeedback = '请求或解析失败：$e';
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    if (!_stopped) {
      _fallbackAIMove(ai.side);
      setState(() => _aiThinking = false);
      _afterPlyAdvanced();
    }
  }

  String? _applyAIActions(Side aiSide, List<QpAction> actions) {
    if (actions.isEmpty) return '未解析到任何动作指令';
    final moveActions = actions.where((a) => !a.isBombard).toList();
    if (moveActions.length != 1) return '每回合须恰好1个移动指令';
    _controller.ensureSnapshotForAction();
    for (final a in actions.where((a) => a.isBombard)) {
      final cruiser = _state.board.at(a.from);
      if (cruiser == null || cruiser.type != PieceType.cruiser) { _rollbackCurrentPly(); return '轰炸位置不是巡洋舰'; }
      final r = _controller.tryBombard(cruiser.id, a.to);
      if (!r.ok) { _rollbackCurrentPly(); return r.error; }
    }
    final mv = moveActions.first;
    final r = _controller.tryMove(mv.from, mv.to);
    if (!r.ok) { _rollbackCurrentPly(); return r.error; }
    return null;
  }

  void _rollbackCurrentPly() {
    if (_state.snapshots.isEmpty) return;
    final snap = _state.snapshots.removeLast();
    _state.board = snap.board.clone(); _state.current = snap.current; _state.ply = snap.ply;
    _state.awaitingResolve[Side.red] = List.of(snap.awaitingResolve[Side.red]!);
    _state.awaitingResolve[Side.blue] = List.of(snap.awaitingResolve[Side.blue]!);
    _state.currentPlyActions.clear();
    _controller.resetSnapshotFlag();
  }

  void _fallbackAIMove(Side aiSide) {
    final rules = RulesEngine(_state.board);
    final myPieces = _state.board.ofSide(aiSide)..shuffle(_state.rng);
    for (final p in myPieces) {
      if (p.firedThisTurn) continue;
      final moves = rules.validMoves(p);
      if (moves.isEmpty) continue;
      moves.shuffle(_state.rng);
      moves.sort((a,b) => ((_state.board.at(b)!=null)?1:0).compareTo((_state.board.at(a)!=null)?1:0));
      _controller.ensureSnapshotForAction();
      _controller.tryMove(p.pos, moves.first);
      _state.addLog('AI降级随机走子', side: aiSide);
      return;
    }
  }

  void _afterPlyAdvanced() {
    if (!mounted) return;
    setState(() {});
    if (_state.winner == null && !_stopped) {
      if (widget.mode == GameMode.aiVsAi) {
        Future.delayed(const Duration(seconds: 2), () { if (!_stopped && mounted) _maybeTriggerAI(); });
      } else { _maybeTriggerAI(); }
    }
  }

  void _handleMove(Move m) {
    if (!_isHumanTurn) return;
    _controller.ensureSnapshotForAction();
    final r = _controller.tryMove(m.from, m.to);
    if (!r.ok) { _toast(r.error!); return; }
    _afterPlyAdvanced();
  }

  void _handleBombard(int cruiserId, Pos target) {
    if (!_isHumanTurn) return;
    _controller.ensureSnapshotForAction();
    final r = _controller.tryBombard(cruiserId, target);
    if (!r.ok) _toast(r.error!);
    setState(() {});
  }

  void _handleUndo() {
    if (AppSettings.deathMatch) { _toast('生死斗不可悔棋'); return; }
    final undoBy = widget.mode == GameMode.vsAI ? AppSettings.mySide : _state.current;
    final halfSteps = widget.mode == GameMode.vsAI ? 2 : 1;
    if (_aiThinking) { _toast('AI思考中'); return; }
    final r = _controller.tryUndo(undoBy, halfSteps, quotaCost: 1);
    if (!r.ok) { _toast(r.error!); return; }
    setState(() {}); _maybeTriggerAI();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2), backgroundColor: Colors.red.shade900));
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF92CDDB),
      appBar: AppBar(
        title: Text('舰队象棋 · ${widget.mode.label}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        backgroundColor: const Color(0xFF92CDDB), foregroundColor: Colors.black87, elevation: 0,
        actions: [
          if (!AppSettings.deathMatch && widget.mode != GameMode.aiVsAi)
            IconButton(icon: const Icon(Icons.undo), tooltip: '悔棋', onPressed: _handleUndo),
          IconButton(icon: const Icon(Icons.replay), tooltip: '快速重开', onPressed: () { _stopped = true; _startNewGame(forceNew: true); }),
          if (AppSettings.aiDebug && _lastAIDebugContent != null)
            IconButton(icon: const Icon(Icons.bug_report), tooltip: 'AI完整推演', onPressed: _showDebugDialog),
        ],
      ),
      body: Column(children: [
        _buildInfoBar(),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(2), child: BoardWidget(
          board: _state.board, state: _state, activeSide: _activeSide,
          rotateBlue: widget.mode == GameMode.faceToFace,
          onMove: _handleMove, onBombard: _handleBombard,
          onSelectionChanged: (sel) => setState(() => _selectionInfo = sel),
        )))),
        // 共享面板：选中棋子时显示规则，否则显示棋谱日志
        _buildBottomPanel(),
        if (AppSettings.aiDebug && _lastAIDebugContent != null) _buildDebugMini(),
      ]),
    );
  }

  /// 底部共享面板：显示规则（选中棋子时）或日志
  Widget _buildBottomPanel() {
    if (_selectionInfo != null && AppSettings.showRules) {
      return _buildRulePanel(_selectionInfo!);
    }
    return _buildLogPanel();
  }

  Widget _buildRulePanel(SelectionInfo s) {
    final textColor = s.piece.side == Side.red ? kRedPieceText : kBluePieceText;
    return InkWell(
      onTap: _showLogDialog,
      child: Container(
        width: double.infinity, height: 54,
        color: Colors.white.withAlpha(240),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(s.piece.type.fullName, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 12)),
            const SizedBox(width: 8),
            if (s.bombardMode) const Text('·攻击模式', style: TextStyle(color: Color(0xFFE05500), fontSize: 11)),
            const Spacer(),
            const Text('点击查看完整棋谱 ▸', style: TextStyle(fontSize: 10, color: Colors.black38)),
          ]),
          Expanded(child: SingleChildScrollView(child: SelectableText(pieceRuleText(s.piece.type), style: const TextStyle(fontSize: 10.5, color: Colors.black87)))),
        ]),
      ),
    );
  }

  void _showLogDialog() {
    MovableDialog.show(context, title: '棋谱与对局记录', width: 520, height: 560, content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('— 棋谱 —', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      SelectableText(_recorder.content, style: const TextStyle(fontSize: 12, height: 1.5)),
      const Divider(height: 20),
      const Text('— 日志 —', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      for (final e in _state.log) SelectableText('[${e.round}] ${e.side.label}·${e.text}', style: TextStyle(color: e.side==Side.red?const Color(0xFFC62828):const Color(0xFF1565C0), fontSize: 11.5)),
    ])));
  }

  void _showDebugDialog() {
    MovableDialog.show(context, title: 'AI完整推演', width: 520, height: 560,
      bgColor: const Color(0xFF0D1B2E), titleBg: const Color(0xFF1A3A5C), titleFg: const Color(0xFF90CAF9),
      content: SingleChildScrollView(child: SelectableText(_lastAIDebugContent ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
    );
  }

  Widget _buildDebugMini() {
    return InkWell(
      onTap: _showDebugDialog,
      child: Container(width: double.infinity, height: 50, color: const Color(0xFF0D1B2E), padding: const EdgeInsets.all(6),
        child: SingleChildScrollView(child: SelectableText(_lastAIDebugContent ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF90CAF9))))),
    );
  }

  Widget _buildInfoBar() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), color: Colors.white.withAlpha(185), child: Row(children: [
      _pills(Side.red), const SizedBox(width: 8), _pills(Side.blue), const Spacer(),
      if (_state.winner != null) Text('${_state.winner!.fullLabel}胜！', style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
      if (_state.winner == null) ...[
        Text('第${_state.round}回合', style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 6),
        if (_aiThinking) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
      const SizedBox(width: 6),
      if (!AppSettings.deathMatch) Text('悔:红${_state.undoLeft[Side.red]} 蓝${_state.undoLeft[Side.blue]}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
      const SizedBox(width: 4),
      Text('轰:红${_state.awaitingResolve[Side.red]!.length} 蓝${_state.awaitingResolve[Side.blue]!.length}', style: const TextStyle(fontSize: 10, color: Color(0xFFB71C1C))),
      if (_lastAIElapsed != null) ...[
        const SizedBox(width: 6),
        Text('${_lastAIElapsed!.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: Color(0xFF2F76C6), fontWeight: FontWeight.bold)),
      ],
    ]));
  }

  Widget _pills(Side side) {
    final isActive = _state.current == side && _state.winner == null;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(
      color: isActive ? (side==Side.red?const Color(0xFFE63946):const Color(0xFF2F76C6)) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: isActive?Colors.white:Colors.grey, width: isActive?1.8:0.5),
    ), child: Text(side.label, style: TextStyle(color: isActive?Colors.white:Colors.black54, fontSize: 12)));
  }

  Widget _buildLogPanel() {
    final recent = _state.log.reversed.take(3).toList();
    return InkWell(
      onTap: _showLogDialog,
      child: Container(width: double.infinity, height: 54, color: Colors.white.withAlpha(205), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in recent)
            SelectableText('[${e.round}] ${e.side.label}·${e.text}', style: TextStyle(color: e.side==Side.red?const Color(0xFFC62828):const Color(0xFF1565C0), fontSize: 10)),
        ])),
    );
  }
}
