import 'config.dart';
import 'models.dart';
import 'notation.dart';

/// 走法生成 + 合法性检查
class RulesEngine {
  final Board board;

  RulesEngine(this.board);

  List<Pos> _flagshipMoves(Piece p) {
    final moves = <Pos>[];
    for (final d in [Pos(0, 1), Pos(0, -1), Pos(1, 0), Pos(-1, 0)]) {
      final to = p.pos + d;
      if (!to.inBoard) continue;
      if (!Board.inCommandZone(to, p.side)) continue;
      final target = board.at(to);
      if (target != null && target.side == p.side) continue;
      moves.add(to);
    }
    return moves;
  }

  List<Pos> _escortMoves(Piece p) {
    final moves = <Pos>[];
    for (final d in [Pos(1, 1), Pos(-1, 1), Pos(1, -1), Pos(-1, -1)]) {
      final to = p.pos + d;
      if (!to.inBoard) continue;
      final target = board.at(to);
      if (target != null && target.side == p.side) continue;

      final inZone = Board.inCommandZone(to, p.side);
      final adjacentToAlly = _adjacentToAlly(to, p.side, exclude: p);
      if (inZone || adjacentToAlly) {
        moves.add(to);
      }
    }
    return moves;
  }

  bool _adjacentToAlly(Pos pos, Side side, {Piece? exclude}) {
    for (final d in [Pos(0, 1), Pos(0, -1), Pos(1, 0), Pos(-1, 0),
                     Pos(1, 1), Pos(-1, -1), Pos(1, -1), Pos(-1, 1)]) {
      final adj = pos + d;
      final pc = board.at(adj);
      if (pc != null && pc.side == side && pc != exclude) return true;
    }
    return false;
  }

  List<Pos> _cruiserMoves(Piece p) {
    final moves = <Pos>[];
    for (final d in [Pos(0, 1), Pos(0, -1), Pos(1, 0), Pos(-1, 0)]) {
      for (int dist = 1; dist <= 2; dist++) {
        final to = p.pos + Pos(d.x * dist, d.y * dist);
        if (!to.inBoard) continue;
        final target = board.at(to);
        if (target != null && target.side == p.side) break;
        if (dist == 2 && board.at(p.pos + d) != null) break;
        moves.add(to);
        if (target != null) break;
      }
    }
    return moves;
  }

  List<Pos> _destroyerMoves(Piece p) {
    final moves = <Pos>[];
    final fwd = p.side.forward;
    for (final d in [Pos(0, fwd), Pos(1, 0), Pos(-1, 0)]) {
      final to = p.pos + d;
      if (!to.inBoard) continue;
      final target = board.at(to);
      if (target != null && target.side == p.side) continue;
      moves.add(to);
    }
    return moves;
  }

  List<Pos> _aircraftMoves(Piece p) {
    final moves = <Pos>[];
    final steps = <List<Pos>>[
      [Pos(0, 1), Pos(1, 1)],
      [Pos(0, 1), Pos(-1, 1)],
      [Pos(0, -1), Pos(1, -1)],
      [Pos(0, -1), Pos(-1, -1)],
      [Pos(1, 0), Pos(1, 1)],
      [Pos(1, 0), Pos(1, -1)],
      [Pos(-1, 0), Pos(-1, 1)],
      [Pos(-1, 0), Pos(-1, -1)],
    ];
    for (final s in steps) {
      final leg1 = p.pos + s[0];
      final leg2 = p.pos + s[0] + s[1];
      if (!leg2.inBoard) continue;
      final blocker = board.at(leg1);
      if (blocker != null && blocker.side != p.side) continue;
      final target = board.at(leg2);
      if (target != null && target.side == p.side) continue;
      if (target != null && target.type == PieceType.submarine) continue;
      moves.add(leg2);
    }
    return moves;
  }

  List<Pos> _submarineMoves(Piece p) {
    final moves = <Pos>[];
    for (final d in [Pos(0, 1), Pos(0, -1), Pos(1, 0), Pos(-1, 0)]) {
      for (int dist = 1; dist <= 2; dist++) {
        final to = p.pos + Pos(d.x * dist, d.y * dist);
        if (!to.inBoard) continue;
        final target = board.at(to);
        if (target != null && target.side == p.side) break;
        if (target != null && target.side != p.side && dist > 1) break;
        moves.add(to);
        if (target != null) break;
      }
    }
    return moves;
  }

  /// 预警机队：斜向1~3格，可越子，不能过河
  List<Pos> _awacsMoves(Piece p) {
    final moves = <Pos>[];
    for (final d in [Pos(1, 1), Pos(-1, 1), Pos(1, -1), Pos(-1, -1)]) {
      for (int dist = 1; dist <= 3; dist++) {
        final to = p.pos + Pos(d.x * dist, d.y * dist);
        if (!to.inBoard) continue;
        final redSide = p.side == Side.red;
        if (redSide && to.y > 6) continue;
        if (!redSide && to.y < 7) continue;
        final target = board.at(to);
        if (target != null && target.side == p.side) continue;
        moves.add(to);
        // 可越子：不因路径棋子中断，但落点是敌子时该方向更远处仍可走（穿越）
      }
    }
    return moves;
  }

  List<Pos> _bombardTargetsOnLine(Pos origin, Pos dir, Side side) {
    // 第一颗棋子为炮架（不可打），炮架后方所有点（空格+第二颗棋子）为有效目标
    final targets = <Pos>[];
    bool foundScreen = false;
    Pos cur = origin + dir;
    while (cur.inBoard) {
      final pc = board.at(cur);
      if (pc != null) {
        if (!foundScreen) {
          foundScreen = true; // 第一颗棋子 = 炮架，自身跳过
          cur = cur + dir;
          continue;
        } else {
          targets.add(cur); // 第二颗棋子含在目标内
          break;
        }
      }
      if (foundScreen) targets.add(cur); // 炮架后方空格
      cur = cur + dir;
    }
    return targets;
  }

  List<Pos> getBombardTargets(Piece cruiser) {
    if (cruiser.firedThisTurn) return [];
    final targets = <Pos>[];
    for (final d in [Pos(0, 1), Pos(0, -1), Pos(1, 0), Pos(-1, 0)]) {
      targets.addAll(_bombardTargetsOnLine(cruiser.pos, d, cruiser.side));
    }
    return targets;
  }

  bool canBombard(Side side) => board.hasAwacs(side);

  List<Pos> validMoves(Piece p) {
    return switch (p.type) {
      PieceType.flagship => _flagshipMoves(p),
      PieceType.escort => _escortMoves(p),
      PieceType.cruiser => _cruiserMoves(p),
      PieceType.destroyer => _destroyerMoves(p),
      PieceType.aircraft => _aircraftMoves(p),
      PieceType.submarine => _submarineMoves(p),
      PieceType.awacs => _awacsMoves(p),
    };
  }
}

/// 行动结果
class ActionResult {
  final bool ok;
  final String? error;
  const ActionResult.success() : ok = true, error = null;
  const ActionResult.fail(this.error) : ok = false;
}

/// 统一对局控制器：验证→执行→棋谱→快照→回合推进
class GameController {
  final GameState state;
  final GameRecorder recorder;

  GameController({required this.state, required this.recorder});

  Board get board => state.board;

  /// 下达巡洋舰轰炸（不结束回合）
  ActionResult tryBombard(int cruiserId, Pos target) {
    if (state.winner != null) return const ActionResult.fail('对局已结束');
    final cruiser = board.byId(cruiserId);
    if (cruiser == null) return const ActionResult.fail('巡洋舰不存在');
    if (cruiser.side != state.current) return const ActionResult.fail('不是你的巡洋舰');
    if (cruiser.type != PieceType.cruiser) return const ActionResult.fail('该棋子不是巡洋舰');
    if (cruiser.firedThisTurn) return const ActionResult.fail('该巡洋舰本回合已开火');

    final rules = RulesEngine(board);
    if (!rules.canBombard(state.current)) {
      return const ActionResult.fail('预警机全部损失，无法远程打击');
    }
    if (!rules.getBombardTargets(cruiser).contains(target)) {
      return ActionResult.fail('目标${target.qp}不在射程内');
    }

    cruiser.firedThisTurn = true;
    state.awaitingResolve[state.current]!
        .add(BombardOrder(cruiserId, state.current, cruiser.pos, target));

    final victim = board.at(target);
    final targetDesc = victim != null ? victim.type.label : '空';
    state.currentPlyActions
        .add('巡${cruiser.pos.qp}x${target.qp}$targetDesc');
    state.addLog('巡洋舰${cruiser.pos.qp}锁定攻击${target.qp}');
    return const ActionResult.success();
  }

  /// 执行移动（结束当前半步）
  ActionResult tryMove(Pos from, Pos to) {
    if (state.winner != null) return const ActionResult.fail('对局已结束');
    final piece = board.at(from);
    if (piece == null) return ActionResult.fail('${from.qp}处无棋子');
    if (piece.side != state.current) return const ActionResult.fail('不是你的棋子');
    if (piece.firedThisTurn) return const ActionResult.fail('开火的巡洋舰本回合不能移动');

    final rules = RulesEngine(board);
    if (!rules.validMoves(piece).contains(to)) {
      return ActionResult.fail('${piece.type.fullName}${from.qp}不能走到${to.qp}');
    }

    // 快照（半步开始前状态在轰炸下达前就该拍——因此在回合首个动作前由 caller 保证）
    _ensureSnapshot();

    final victim = board.at(to);
    if (victim != null) board.remove(victim);
    piece.pos = to;

    final targetDesc = victim != null ? victim.type.label : '空';
    state.currentPlyActions.add('${piece.type.label}${from.qp}->${to.qp}$targetDesc');

    if (victim != null) {
      state.addLog('${piece.type.fullName}${from.qp}吃${victim.type.fullName}${to.qp}');
      if (victim.type == PieceType.flagship) {
        state.winner = state.current;
        state.winReason = '${state.current.fullLabel}击毁敌方旗舰';
      }
    } else {
      state.addLog('${piece.type.fullName}${from.qp}→${to.qp}');
    }

    // 驱逐舰升变
    if (piece.type == PieceType.destroyer &&
        to.y == Board.promotionRow(piece.side)) {
      board.pieces.remove(piece); // 升变非战损，不走remove()
      board.pieces.add(Piece(piece.id, PieceType.cruiser, piece.side, piece.pos));
      state.addLog('驱逐舰${to.qp}升变为巡洋舰');
    }

    // 旗舰对脸检查（走完后形成对脸，当前方违规）
    if (state.winner == null) _checkFaceoff();

    // 写棋谱行
    recorder.recordPly(state.round, state.current, List.of(state.currentPlyActions));
    state.currentPlyActions.clear();

    // 结算对方轰炸（对方下达的轰炸在我方回合结束时生效）
    if (state.winner == null) {
      final opponent = state.current.opponent;
      state.lastResults = _resolveBombards(opponent);
      // 结算结果写入棋谱（#注释行，AI与回放可参考）
      if (state.lastResults.isNotEmpty) {
        final parts = state.lastResults.map((r) {
          final t = r.order.target.qp;
          if (r.intercepted) return '轰$t被拦截';
          if (r.immune) return '轰$t潜艇免疫';
          if (r.hit) return '轰$t击沉${r.victimName ?? ''}';
          return '轰$t落空';
        }).join('；');
        recorder.recordComment('结算：${opponent.label}方$parts');
      }
    }

    // 终局落盘
    if (state.winner != null) {
      recorder.recordResult('${state.winner!.label}胜（${state.winReason ?? ''}）');
    }

    // 推进回合
    if (state.winner == null) {
      state.current = state.current.opponent;
      state.ply++;
      for (final p in board.pieces) {
        if (p.side == state.current) p.firedThisTurn = false;
      }
    }
    _snapshotTaken = false;
    return const ActionResult.success();
  }

  bool _snapshotTaken = false;

  /// 在半步的首个动作前调用（含轰炸），保证快照存在
  void ensureSnapshotForAction() => _ensureSnapshot();

  /// AI指令回滚后重置快照标记
  void resetSnapshotFlag() => _snapshotTaken = false;

  void _ensureSnapshot() {
    if (!_snapshotTaken) {
      state.takeSnapshot(recorder.lines.length);
      _snapshotTaken = true;
    }
  }

  void _checkFaceoff() {
    final rFlag = board.flagship(Side.red);
    final bFlag = board.flagship(Side.blue);
    if (rFlag == null || bFlag == null) return;
    if (rFlag.pos.x != bFlag.pos.x) return;
    final minY = rFlag.pos.y < bFlag.pos.y ? rFlag.pos.y : bFlag.pos.y;
    final maxY = rFlag.pos.y > bFlag.pos.y ? rFlag.pos.y : bFlag.pos.y;
    for (int y = minY + 1; y < maxY; y++) {
      if (board.at(Pos(rFlag.pos.x, y)) != null) return;
    }
    state.winner = state.current.opponent;
    state.winReason = '旗舰对脸，${state.current.fullLabel}违规';
  }

  List<BombardResult> _resolveBombards(Side attacker) {
    final orders = state.awaitingResolve[attacker]!;
    if (orders.isEmpty) return [];

    final results = <BombardResult>[];
    for (final order in orders) {
      bool hit = false, intercepted = false, immune = false;
      String? victimName;

      // 一旦设定必定结算（不再检查巡洋舰存活/预警机），仅护卫舰可拦截、潜艇免疫
      final line = _buildLine(order.cruiserPos, order.target);
      for (final step in line) {
        final pc = board.at(step);
        if (pc != null &&
            pc.type == PieceType.escort &&
            pc.side == attacker.opponent) {
          intercepted = true;
          break;
        }
      }

      if (!intercepted) {
        final victim = board.at(order.target);
        if (victim != null) {
          if (victim.type == PieceType.submarine) {
            immune = true;
          } else {
            hit = true;
            victimName = victim.type.fullName;
            board.remove(victim);
            if (victim.type == PieceType.flagship) {
              state.winner = attacker;
              state.winReason = '${attacker.fullLabel}远程火力击毁旗舰';
            }
          }
        }
      }

      results.add(BombardResult(order,
          hit: hit, intercepted: intercepted, immune: immune, victimName: victimName));

      if (intercepted) {
        state.addLog('${attacker.label}方轰炸${order.target.qp}被护卫舰拦截', side: attacker);
      } else if (immune) {
        state.addLog('${attacker.label}方轰炸${order.target.qp}——潜艇免疫', side: attacker);
      } else if (hit) {
        state.addLog('${attacker.label}方轰炸${order.target.qp}摧毁$victimName', side: attacker);
      } else {
        state.addLog('${attacker.label}方轰炸${order.target.qp}落空', side: attacker);
      }
    }

    state.awaitingResolve[attacker]!.clear();
    return results;
  }

  /// 悔棋：回退halfSteps个半步，消耗undoBy方配额quotaCost次
  ActionResult tryUndo(Side undoBy, int halfSteps, {int? quotaCost}) {
    if (AppSettings.deathMatch) return const ActionResult.fail('生死斗模式不可悔棋');
    if (state.winner != null) return const ActionResult.fail('对局已结束');
    final cost = quotaCost ?? halfSteps;
    if (state.undoLeft[undoBy]! < cost) {
      return ActionResult.fail('悔棋配额不足（剩${state.undoLeft[undoBy]}次）');
    }
    final snap = state.undo(halfSteps);
    if (snap == null) return const ActionResult.fail('没有可回退的步数');
    state.undoLeft[undoBy] = state.undoLeft[undoBy]! - cost;
    recorder.truncate(snap.notationLines);
    _snapshotTaken = false;
    state.addLog('${undoBy.fullLabel}悔棋$halfSteps步（剩余配额${state.undoLeft[undoBy]}）', side: undoBy);
    return const ActionResult.success();
  }
}

List<Pos> _buildLine(Pos a, Pos b) {
  final result = <Pos>[];
  final dx = (b.x - a.x).sign;
  final dy = (b.y - a.y).sign;
  if (dx != 0 && dy != 0) return result;
  Pos cur = a + Pos(dx, dy);
  while (cur != b) {
    result.add(cur);
    cur = cur + Pos(dx, dy);
  }
  return result;
}
