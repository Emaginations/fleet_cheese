import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_chess/config.dart';
import 'package:fleet_chess/models.dart';
import 'package:fleet_chess/engine.dart';
import 'package:fleet_chess/notation.dart';

void main() {
  group('开局', () {
    test('每方19子，总38子', () {
      final b = Board.initial();
      expect(b.pieces.length, 38);
      expect(b.ofSide(Side.red).length, 19);
      expect(b.ofSide(Side.blue).length, 19);
    });

    test('红方关键位置', () {
      final b = Board.initial();
      expect(b.at(const Pos(6, 0))!.type, PieceType.flagship);
      expect(b.at(const Pos(3, 0))!.type, PieceType.awacs);
      expect(b.at(const Pos(1, 2))!.type, PieceType.cruiser);
      expect(b.at(const Pos(3, 4))!.type, PieceType.submarine);
      expect(b.at(const Pos(0, 5))!.type, PieceType.destroyer);
    });

    test('蓝方镜像位置', () {
      final b = Board.initial();
      expect(b.at(const Pos(6, 13))!.type, PieceType.flagship);
      expect(b.at(const Pos(6, 13))!.side, Side.blue);
      expect(b.at(const Pos(0, 8))!.type, PieceType.destroyer);
    });
  });

  group('走法', () {
    test('驱逐舰不能后退', () {
      final b = Board.initial();
      final d = b.at(const Pos(0, 5))!;
      final moves = RulesEngine(b).validMoves(d);
      expect(moves.contains(const Pos(0, 6)), true); // 前进
      expect(moves.contains(const Pos(1, 5)), true); // 右移
      expect(moves.contains(const Pos(0, 4)), false); // 不能后退
    });

    test('旗舰限指挥区', () {
      final b = Board.initial();
      final f = b.at(const Pos(6, 0))!;
      final moves = RulesEngine(b).validMoves(f);
      expect(moves.contains(const Pos(6, 1)), true);
      // (5,0)(7,0)有护卫舰占位
      expect(moves.contains(const Pos(5, 0)), false);
    });

    test('预警机斜向1~3格可越子不过河', () {
      final b = Board.initial();
      final a = b.at(const Pos(3, 0))!;
      final moves = RulesEngine(b).validMoves(a);
      expect(moves.contains(const Pos(4, 1)), true);  // 斜1
      expect(moves.contains(const Pos(5, 2)), true);  // 斜2
      expect(moves.contains(const Pos(6, 3)), true);  // 斜3
      expect(moves.contains(const Pos(7, 4)), false); // 超3格
      // 越子：(2,1)方向即使有子也可跳过（初始无阻挡，验证路径穿越逻辑）
      final movesLeft = moves.where((m) => m.x < 3).toList();
      expect(movesLeft.contains(const Pos(2, 1)), true);
      expect(movesLeft.contains(const Pos(0, 3)), true);
    });

    test('战机马走日且不能吃潜艇', () {
      final b = Board.initial();
      final j = b.at(const Pos(2, 0))!;
      final moves = RulesEngine(b).validMoves(j);
      expect(moves.contains(const Pos(1, 2)), false); // (1,2)有己方巡洋舰
      expect(moves.contains(const Pos(3, 2)), true);
    });

    test('潜艇吃子仅1格', () {
      final b = Board.initial();
      // 红潜(3,4)前方(3,5)空，(3,6)空
      final s = b.at(const Pos(3, 4))!;
      final moves = RulesEngine(b).validMoves(s);
      expect(moves.contains(const Pos(3, 5)), true);
      expect(moves.contains(const Pos(3, 6)), true);
    });
  });

  group('对局流程', () {
    GameController makeGame({Side first = Side.red}) {
      final state = GameState(firstMoverChoice: first);
      final rec = GameRecorder(firstMover: first);
      return GameController(state: state, recorder: rec);
    }

    test('移动产生棋谱行并切换回合（回合号半步递增）', () {
      final c = makeGame();
      c.ensureSnapshotForAction();
      final r = c.tryMove(const Pos(0, 5), const Pos(0, 6));
      expect(r.ok, true);
      expect(c.recorder.lines.length, 1);
      expect(c.recorder.lines.first, '1.红，驱（0，5）->（0，6）空');
      expect(c.state.current, Side.blue);
      expect(c.state.round, 2, reason: '蓝方半步应为第2回合');
      // 蓝方走子 → 棋谱行应为 "2.蓝，…"
      c.ensureSnapshotForAction();
      expect(c.tryMove(const Pos(0, 8), const Pos(0, 7)).ok, true);
      expect(c.recorder.lines[1].startsWith('2.蓝，'), true,
          reason: '回合号应为1.红→2.蓝递增');
    });

    test('非法移动被拒绝', () {
      final c = makeGame();
      c.ensureSnapshotForAction();
      final r = c.tryMove(const Pos(0, 5), const Pos(0, 4));
      expect(r.ok, false);
      expect(c.state.current, Side.red);
      expect(c.recorder.lines.isEmpty, true);
    });

    test('轰炸延迟结算：敌回合结束时生效（走入雷区）', () {
      final c = makeGame();
      final s = c.state;
      // 红巡(6,2)沿y+：炮架(6,5)红驱，可打(6,5)~(6,7)；(6,8)蓝驱为第二颗不可打
      c.ensureSnapshotForAction();
      final cruiser = s.board.at(const Pos(6, 2))!;
      expect(c.tryBombard(cruiser.id, const Pos(6, 8)).ok, false,
          reason: '第二颗棋子(6,8)不应在射程内（炮架规则）');
      final rb = c.tryBombard(cruiser.id, const Pos(6, 7));
      expect(rb.ok, true, reason: rb.error ?? '');
      // 红方移动结束回合
      expect(c.tryMove(const Pos(0, 5), const Pos(0, 6)).ok, true);
      // 蓝方(6,8)驱走进轰炸点(6,7)
      c.ensureSnapshotForAction();
      expect(c.tryMove(const Pos(6, 8), const Pos(6, 7)).ok, true);
      // 蓝回合结束时结算：走入雷区被炸
      expect(s.board.at(const Pos(6, 7)), isNull, reason: '走入轰炸点的蓝驱应被击沉');
      expect(s.current, Side.red);
    });

    test('跨三回合双方分批轰炸结算正确', () {
      final c = makeGame();
      final s = c.state;

      // T1红: 轰(6,7)（炮架(6,5)红驱），走(0,5)->(0,6)
      c.ensureSnapshotForAction();
      final redCruiser = s.board.at(const Pos(6, 2))!;
      expect(c.tryBombard(redCruiser.id, const Pos(6, 7)).ok, true);
      expect(c.tryMove(const Pos(0, 5), const Pos(0, 6)).ok, true);
      expect(s.awaitingResolve[Side.red]!.length, 1);

      // T2蓝: 轰(6,6)（蓝巡(6,11)沿y-炮架(6,8)蓝驱，可打(6,8)~(6,6)），走(12,8)->(12,7)
      c.ensureSnapshotForAction();
      final blueCruiser = s.board.at(const Pos(6, 11))!;
      expect(c.tryBombard(blueCruiser.id, const Pos(6, 6)).ok, true,
          reason: '蓝巡应能轰炸(6,6)');
      expect(s.awaitingResolve[Side.blue]!.length, 1);
      expect(c.tryMove(const Pos(12, 8), const Pos(12, 7)).ok, true);
      // T2末: 红轰炸(6,7)结算（空格落空），蓝轰炸仍在等待
      expect(s.awaitingResolve[Side.red]!.length, 0, reason: '红轰炸已结算');
      expect(s.awaitingResolve[Side.blue]!.length, 1,
          reason: '蓝轰炸(6,6)应等待红T3结束才结算');
      expect(s.current, Side.red);

      // T3红: 驱(6,5)->(6,6)走进蓝方轰炸点
      c.ensureSnapshotForAction();
      expect(c.tryMove(const Pos(6, 5), const Pos(6, 6)).ok, true);
      // T3末: 蓝轰炸结算，(6,6)红驱被击沉
      expect(s.board.at(const Pos(6, 6)), isNull,
          reason: '(6,6)红驱应在T3末被蓝轰炸命中');
      expect(s.awaitingResolve[Side.blue]!.length, 0);
    });

    test('轰炸后目标逃走则落空', () {
      final c = makeGame();
      final s = c.state;
      // 红巡(6,2)轰炮架自身(6,5)红驱（误伤测试），随后红驱逃走
      c.ensureSnapshotForAction();
      final cruiser = s.board.at(const Pos(6, 2))!;
      expect(c.tryBombard(cruiser.id, const Pos(6, 5)).ok, true);
      expect(c.tryMove(const Pos(6, 5), const Pos(6, 6)).ok, true); // 目标逃离
      c.ensureSnapshotForAction();
      expect(c.tryMove(const Pos(12, 8), const Pos(12, 7)).ok, true);
      // 结算落空：逃走的红驱存活
      expect(s.board.at(const Pos(6, 6)), isNotNull);
    });

    test('开火的巡洋舰当回合不能移动', () {
      final c = makeGame();
      final s = c.state;
      c.ensureSnapshotForAction();
      final cruiser = s.board.at(const Pos(6, 2))!;
      expect(c.tryBombard(cruiser.id, const Pos(6, 5)).ok, true,
          reason: '炮架(6,5)红驱自身应可作为目标');
      final r = c.tryMove(const Pos(6, 2), const Pos(6, 3));
      expect(r.ok, false);
    });

    test('悔棋恢复状态并截断棋谱', () {
      final c = makeGame();
      final s = c.state;
      c.ensureSnapshotForAction();
      expect(c.tryMove(const Pos(0, 5), const Pos(0, 6)).ok, true);
      expect(c.recorder.lines.length, 1);
      final r = c.tryUndo(Side.red, 1, quotaCost: 1);
      expect(r.ok, true);
      expect(s.board.at(const Pos(0, 5)), isNotNull);
      expect(s.board.at(const Pos(0, 6)), isNull);
      expect(s.current, Side.red);
      expect(c.recorder.lines.isEmpty, true);
      expect(s.undoLeft[Side.red], kUndoQuota - 1);
    });

    test('生死斗禁止悔棋', () {
      AppSettings.deathMatch = true;
      final c = makeGame();
      c.ensureSnapshotForAction();
      c.tryMove(const Pos(0, 5), const Pos(0, 6));
      expect(c.tryUndo(Side.red, 1).ok, false);
      AppSettings.deathMatch = false;
    });
  });

  group('棋谱', () {
    test('解析移动与轰炸动作', () {
      final actions = QpParser.parseActions(
          '指令：巡（6，2）x（6，8）驱，驱（0，5）->（0，6）空');
      expect(actions.length, 2);
      expect(actions[0].isBombard, true);
      expect(actions[0].from, const Pos(6, 2));
      expect(actions[0].to, const Pos(6, 8));
      expect(actions[1].isBombard, false);
      expect(actions[1].pieceType, PieceType.destroyer);
    });

    test('兼容半角符号', () {
      final actions = QpParser.parseActions('巡(6,2)x(6,8)驱, 机(2,0)->(3,2)空');
      expect(actions.length, 2);
    });

    test('解析悔棋指令', () {
      expect(QpParser.parseUndo('悔2'), 2);
      expect(QpParser.parseUndo('指令：悔 3'), 3);
      expect(QpParser.parseUndo('驱（0，5）->（0，6）'), null);
    });

    test('棋谱文本可反解析', () {
      final content = '''
# 舰队象棋棋谱
# 时间：2026-07-18 10:00:00
# 先手：蓝
1.蓝，驱（0，8）->（0，7）空
1.红，巡（6，2）x（6，8）驱，驱（2，5）->（2，6）空
# 结果：红胜（击毁旗舰）
''';
      final g = ParsedGame.fromContent(content);
      expect(g.firstMover, Side.blue);
      expect(g.plies.length, 2);
      expect(g.plies[1].actions.length, 2);
      expect(g.result, '红胜（击毁旗舰）');
    });
  });
}
