import 'dart:math';

/// 阵营
enum Side { red, blue }

extension SideX on Side {
  Side get opponent => this == Side.red ? Side.blue : Side.red;
  String get label => this == Side.red ? '红' : '蓝';
  String get fullLabel => this == Side.red ? '红方' : '蓝方';
  int get forward => this == Side.red ? 1 : -1;
}

/// 棋子类型
enum PieceType { flagship, escort, cruiser, destroyer, aircraft, submarine, awacs }

extension PieceTypeX on PieceType {
  String get label => switch (this) {
        PieceType.flagship => '旗',
        PieceType.escort => '护',
        PieceType.cruiser => '巡',
        PieceType.destroyer => '驱',
        PieceType.aircraft => '机',
        PieceType.submarine => '潜',
        PieceType.awacs => '警',
      };

  String get fullName => switch (this) {
        PieceType.flagship => '旗舰',
        PieceType.escort => '护卫舰',
        PieceType.cruiser => '巡洋舰',
        PieceType.destroyer => '驱逐舰',
        PieceType.aircraft => '战机编队',
        PieceType.submarine => '潜艇',
        PieceType.awacs => '预警机队',
      };

  static PieceType? fromLabel(String s) {
    for (final t in PieceType.values) {
      if (t.label == s) return t;
    }
    return null;
  }
}

/// 坐标，左下角为(0,0)，x横向0~12，y纵向0~13
class Pos {
  final int x, y;
  const Pos(this.x, this.y);

  bool get inBoard => x >= 0 && x < Board.width && y >= 0 && y < Board.height;

  Pos operator +(Pos o) => Pos(x + o.x, y + o.y);

  @override
  bool operator ==(Object other) => other is Pos && other.x == x && other.y == y;
  @override
  int get hashCode => x * 31 + y;
  @override
  String toString() => '($x,$y)';

  /// 全角棋谱格式
  String get qp => '（$x，$y）';
}

class Piece {
  final int id;
  final PieceType type;
  final Side side;
  Pos pos;
  bool firedThisTurn = false;

  Piece(this.id, this.type, this.side, this.pos);

  Piece clone() {
    final p = Piece(id, type, side, pos);
    p.firedThisTurn = firedThisTurn;
    return p;
  }
}

/// 一步移动
class Move {
  final Pos from, to;
  const Move(this.from, this.to);

  @override
  bool operator ==(Object other) => other is Move && other.from == from && other.to == to;
  @override
  int get hashCode => from.hashCode * 131 + to.hashCode;
}

/// 巡洋舰轰炸指令（延迟结算，目标对敌隐藏）
class BombardOrder {
  final int cruiserId;
  final Side side;
  final Pos cruiserPos;
  final Pos target;
  const BombardOrder(this.cruiserId, this.side, this.cruiserPos, this.target);
}

/// 结算后的轰炸结果
class BombardResult {
  final BombardOrder order;
  final bool hit;
  final bool intercepted;
  final bool immune;
  final String? victimName;
  const BombardResult(this.order,
      {required this.hit, required this.intercepted, required this.immune, this.victimName});
}

class Board {
  static const int width = 13;
  static const int height = 14;

  static bool inRedHalf(Pos p) => p.y <= 6;

  static bool inCommandZone(Pos p, Side s) {
    if (p.x < 4 || p.x > 8) return false;
    return s == Side.red ? (p.y >= 0 && p.y <= 4) : (p.y >= 9 && p.y <= 13);
  }

  static int promotionRow(Side s) => s == Side.red ? height - 1 : 0;

  final List<Piece> pieces = [];
  int _nextId = 0;

  Board.initial() {
    void add(PieceType t, Side s, int x, int y) =>
        pieces.add(Piece(_nextId++, t, s, Pos(x, y)));

    add(PieceType.aircraft, Side.red, 2, 0);
    add(PieceType.awacs, Side.red, 3, 0);
    add(PieceType.escort, Side.red, 5, 0);
    add(PieceType.flagship, Side.red, 6, 0);
    add(PieceType.escort, Side.red, 7, 0);
    add(PieceType.awacs, Side.red, 9, 0);
    add(PieceType.aircraft, Side.red, 10, 0);
    for (final x in [0, 6, 12]) {
      add(PieceType.cruiser, Side.red, x, 2);
    }
    add(PieceType.submarine, Side.red, 3, 4);
    add(PieceType.submarine, Side.red, 9, 4);
    for (int x = 0; x <= 12; x += 2) {
      add(PieceType.destroyer, Side.red, x, 5);
    }

    final redSnapshot = pieces.toList();
    for (final p in redSnapshot) {
      add(p.type, Side.blue, p.pos.x, height - 1 - p.pos.y);
    }
  }

  Board._();

  Piece? at(Pos p) {
    for (final pc in pieces) {
      if (pc.pos == p) return pc;
    }
    return null;
  }

  Piece? byId(int id) {
    for (final pc in pieces) {
      if (pc.id == id) return pc;
    }
    return null;
  }

  List<Piece> ofSide(Side s) => pieces.where((p) => p.side == s).toList();

  bool hasAwacs(Side s) =>
      pieces.any((p) => p.side == s && p.type == PieceType.awacs);

  Piece? flagship(Side s) {
    for (final p in pieces) {
      if (p.side == s && p.type == PieceType.flagship) return p;
    }
    return null;
  }

  void remove(Piece p) {
    pieces.remove(p);
    captured.add(p);
  }

  /// 战损（被吃/被轰沉）棋子
  final List<Piece> captured = [];

  Board clone() {
    final b = Board._();
    b._nextId = _nextId;
    for (final p in pieces) {
      b.pieces.add(p.clone());
    }
    for (final p in captured) {
      b.captured.add(p.clone());
    }
    return b;
  }
}

/// 每局悔棋配额
const int kUndoQuota = 4;

/// 对局日志条目
class GameLogEntry {
  final int round;
  final Side side;
  final String text;
  const GameLogEntry(this.round, this.side, this.text);
}

/// 半步快照（悔棋用，存于每个半步开始前）
class Snapshot {
  final Board board;
  final Side current;
  final int ply;
  final Map<Side, List<BombardOrder>> awaitingResolve;
  final int notationLines;

  Snapshot({
    required this.board,
    required this.current,
    required this.ply,
    required this.awaitingResolve,
    required this.notationLines,
  });
}

class GameState {
  Board board = Board.initial();

  /// 先手方
  Side firstMover = Side.red;

  /// 当前行动方
  Side current = Side.red;

  /// 半步计数（0起）：大回合号 = ply ~/ 2 + 1
  int ply = 0;

  int get round => ply + 1;

  Side? winner;
  String? winReason;

  /// 各方已下达、等待结算的轰炸
  final Map<Side, List<BombardOrder>> awaitingResolve = {
    Side.red: [],
    Side.blue: [],
  };

  /// 当前半步内已下达的轰炸（用于棋谱行合并）
  final List<String> currentPlyActions = [];

  /// 悔棋配额
  final Map<Side, int> undoLeft = {
    Side.red: kUndoQuota,
    Side.blue: kUndoQuota,
  };

  /// 快照栈
  final List<Snapshot> snapshots = [];

  final List<GameLogEntry> log = [];
  List<BombardResult> lastResults = [];

  final Random rng = Random();

  GameState({Side? firstMoverChoice}) {
    firstMover = firstMoverChoice ?? (rng.nextBool() ? Side.red : Side.blue);
    current = firstMover;
  }

  void addLog(String text, {Side? side}) {
    log.add(GameLogEntry(round, side ?? current, text));
  }

  /// 半步开始前拍快照
  void takeSnapshot(int notationLines) {
    snapshots.add(Snapshot(
      board: board.clone(),
      current: current,
      ply: ply,
      awaitingResolve: {
        Side.red: List.of(awaitingResolve[Side.red]!),
        Side.blue: List.of(awaitingResolve[Side.blue]!),
      },
      notationLines: notationLines,
    ));
  }

  /// 回退n个半步，返回恢复到的快照（null=无法回退）
  Snapshot? undo(int halfSteps) {
    if (snapshots.length < halfSteps || halfSteps < 1) return null;
    Snapshot? target;
    for (int i = 0; i < halfSteps; i++) {
      target = snapshots.removeLast();
    }
    if (target == null) return null;
    board = target.board.clone();
    current = target.current;
    ply = target.ply;
    awaitingResolve[Side.red] = List.of(target.awaitingResolve[Side.red]!);
    awaitingResolve[Side.blue] = List.of(target.awaitingResolve[Side.blue]!);
    winner = null;
    winReason = null;
    currentPlyActions.clear();
    lastResults = [];
    return target;
  }
}
