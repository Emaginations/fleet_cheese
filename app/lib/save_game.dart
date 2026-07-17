import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 未完成对局的持久化（按模式独立存档）
class SaveGame {
  static String _key(String mode) => 'savegame_$mode';

  /// 保存进行中的对局
  static Future<void> save(String mode, GameState state, List<String> qpLines) async {
    try {
      final data = {
        'firstMover': state.firstMover.name,
        'current': state.current.name,
        'ply': state.ply,
        'pieces': [
          for (final p in state.board.pieces)
            {
              'id': p.id,
              't': p.type.name,
              's': p.side.name,
              'x': p.pos.x,
              'y': p.pos.y,
              'f': p.firedThisTurn,
            }
        ],
        'captured': [
          for (final p in state.board.captured)
            {'id': p.id, 't': p.type.name, 's': p.side.name, 'x': p.pos.x, 'y': p.pos.y}
        ],
        'awaitRed': [
          for (final b in state.awaitingResolve[Side.red]!)
            {'cid': b.cruiserId, 'cx': b.cruiserPos.x, 'cy': b.cruiserPos.y, 'tx': b.target.x, 'ty': b.target.y}
        ],
        'awaitBlue': [
          for (final b in state.awaitingResolve[Side.blue]!)
            {'cid': b.cruiserId, 'cx': b.cruiserPos.x, 'cy': b.cruiserPos.y, 'tx': b.target.x, 'ty': b.target.y}
        ],
        'undoRed': state.undoLeft[Side.red],
        'undoBlue': state.undoLeft[Side.blue],
        'qpLines': qpLines,
        'log': [
          for (final e in state.log.take(200)) {'r': e.round, 's': e.side.name, 't': e.text}
        ],
      };
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(mode), jsonEncode(data));
    } catch (_) {}
  }

  /// 恢复对局，无存档返回null
  static Future<(GameState, List<String>)?> load(String mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(mode));
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final first = Side.values.byName(data['firstMover'] as String);
      final state = GameState(firstMoverChoice: first);
      state.current = Side.values.byName(data['current'] as String);
      state.ply = data['ply'] as int;

      state.board.pieces.clear();
      for (final m in (data['pieces'] as List).cast<Map<String, dynamic>>()) {
        final piece = Piece(
          m['id'] as int,
          PieceType.values.byName(m['t'] as String),
          Side.values.byName(m['s'] as String),
          Pos(m['x'] as int, m['y'] as int),
        );
        piece.firedThisTurn = (m['f'] as bool?) ?? false;
        state.board.pieces.add(piece);
      }
      state.board.captured.clear();
      for (final m in (data['captured'] as List).cast<Map<String, dynamic>>()) {
        state.board.captured.add(Piece(
          m['id'] as int,
          PieceType.values.byName(m['t'] as String),
          Side.values.byName(m['s'] as String),
          Pos(m['x'] as int, m['y'] as int),
        ));
      }

      List<BombardOrder> orders(String key, Side side) => [
            for (final m in (data[key] as List).cast<Map<String, dynamic>>())
              BombardOrder(m['cid'] as int, side,
                  Pos(m['cx'] as int, m['cy'] as int), Pos(m['tx'] as int, m['ty'] as int))
          ];
      state.awaitingResolve[Side.red] = orders('awaitRed', Side.red);
      state.awaitingResolve[Side.blue] = orders('awaitBlue', Side.blue);

      state.undoLeft[Side.red] = data['undoRed'] as int? ?? 4;
      state.undoLeft[Side.blue] = data['undoBlue'] as int? ?? 4;

      for (final m in ((data['log'] as List?) ?? []).cast<Map<String, dynamic>>()) {
        state.log.add(GameLogEntry(
            m['r'] as int, Side.values.byName(m['s'] as String), m['t'] as String));
      }

      final qpLines = (data['qpLines'] as List).cast<String>();
      return (state, qpLines);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(mode));
    } catch (_) {}
  }
}
