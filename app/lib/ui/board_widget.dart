import 'package:flutter/material.dart';
import '../models.dart';
import '../engine.dart';

/// 棋盘配色
const kBoardBg = Color(0xFF92CDDB);
const kGridLine = Color(0xFFFFFFFF);
const kRedPieceText = Color(0xFFE63946);
const kBluePieceText = Color(0xFF2F76C6);
const kPieceBg = Color(0xFFFFFFFF);
const kBombardMark = Color(0xFFD32F2F);

/// 选中信息（回调给上层展示规则说明，棋盘自身不改变尺寸）
class SelectionInfo {
  final Piece piece;
  final bool bombardMode;
  const SelectionInfo(this.piece, this.bombardMode);
}

/// 交叉点制棋盘：13条竖线(x:0~12) × 14条横线(y:0~13)，棋子落在交叉点。
/// 左右两侧内置战损区（原大小、不透明）。
class BoardWidget extends StatefulWidget {
  final Board board;
  final GameState state;
  final Side? activeSide;
  final bool rotateBlue;
  final void Function(Move move) onMove;
  final void Function(int cruiserId, Pos target) onBombard;
  final void Function(SelectionInfo? sel)? onSelectionChanged;

  const BoardWidget({
    super.key,
    required this.board,
    required this.state,
    required this.activeSide,
    this.rotateBlue = false,
    required this.onMove,
    required this.onBombard,
    this.onSelectionChanged,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

/// 布局常量（以格距cell为单位）
const double _kMarginCells = 0.7; // 棋盘四周边距
const double _kSideCells = 1.3; // 单侧战损区宽

/// 总宽（cell数）= 战损区×2 + 边距×2 + 12格距
const double _kTotalWCells = _kSideCells * 2 + _kMarginCells * 2 + 12;
const double _kTotalHCells = _kMarginCells * 2 + 13;

class _BoardWidgetState extends State<BoardWidget> {
  int? selectedId;
  List<Pos> legalMoves = [];
  List<Pos> bombardTargets = [];
  bool bombardMode = false;

  Piece? get selectedPiece =>
      selectedId != null ? widget.board.byId(selectedId!) : null;

  void _clearSelection({bool notify = true}) {
    selectedId = null;
    legalMoves = [];
    bombardTargets = [];
    bombardMode = false;
    if (notify) widget.onSelectionChanged?.call(null);
  }

  @override
  void didUpdateWidget(BoardWidget old) {
    super.didUpdateWidget(old);
    if (widget.activeSide == null && selectedId != null) {
      _clearSelection(notify: false);
    }
  }

  void _notifySelection() {
    final p = selectedPiece;
    widget.onSelectionChanged?.call(p == null ? null : SelectionInfo(p, bombardMode));
  }

  void _onTapCross(Pos pos) {
    if (widget.activeSide == null) return;
    final piece = widget.board.at(pos);
    final rules = RulesEngine(widget.board);
    final sel = selectedPiece;

    if (sel != null) {
      if (sel.pos == pos && sel.type == PieceType.cruiser) {
        if (!bombardMode) {
          final targets = rules.canBombard(widget.activeSide!)
              ? rules.getBombardTargets(sel)
              : <Pos>[];
          if (targets.isNotEmpty) {
            setState(() {
              bombardMode = true;
              bombardTargets = targets;
              legalMoves = [];
            });
            _notifySelection();
            return;
          }
        } else {
          setState(() {
            bombardMode = false;
            bombardTargets = [];
            legalMoves = sel.firedThisTurn ? [] : rules.validMoves(sel);
          });
          _notifySelection();
          return;
        }
      }

      if (bombardMode && bombardTargets.contains(pos)) {
        widget.onBombard(sel.id, pos);
        setState(_clearSelection);
        return;
      }

      if (!bombardMode && legalMoves.contains(pos)) {
        widget.onMove(Move(sel.pos, pos));
        setState(_clearSelection);
        return;
      }
    }

    if (piece != null && piece.side == widget.activeSide) {
      setState(() {
        selectedId = piece.id;
        bombardMode = false;
        bombardTargets = [];
        legalMoves = piece.firedThisTurn ? [] : rules.validMoves(piece);
      });
      _notifySelection();
    } else {
      setState(_clearSelection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kTotalWCells / _kTotalHCells,
      child: LayoutBuilder(builder: (ctx, constraints) {
        final cell = constraints.maxWidth / _kTotalWCells;
        final originX = (_kSideCells + _kMarginCells) * cell; // 交叉点(0,·)的px
        final originYTop = _kMarginCells * cell; // 交叉点(·,13)的px

        double px(num x) => originX + x * cell;
        double py(num y) => originYTop + (13 - y) * cell;

        final pieceSize = cell * 0.84;
        final allBombards = [
          ...widget.state.awaitingResolve[Side.red]!,
          ...widget.state.awaitingResolve[Side.blue]!,
        ];

        final capturedBlue =
            widget.board.captured.where((p) => p.side == Side.blue).toList();
        final capturedRed =
            widget.board.captured.where((p) => p.side == Side.red).toList();

        return Container(
          color: kBoardBg,
          child: Stack(
            children: [
              // 网格与标记层
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    cell: cell,
                    originX: originX,
                    originYTop: originYTop,
                    selectedPos: selectedPiece?.pos,
                    legalMoves: legalMoves,
                    bombardTargets: bombardTargets,
                    bombardMode: bombardMode,
                    board: widget.board,
                    allBombards: allBombards,
                  ),
                ),
              ),
              // 左侧战损（蓝方）——原大小、不透明
              ..._capturedPieces(capturedBlue, cell, pieceSize, true, constraints),
              // 右侧战损（红方）
              ..._capturedPieces(capturedRed, cell, pieceSize, false, constraints),
              // 棋子层（交叉点圆心定位 + 移动动画）
              for (final p in widget.board.pieces)
                AnimatedPositioned(
                  key: ValueKey('piece-${p.id}'),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: px(p.pos.x) - pieceSize / 2,
                  top: py(p.pos.y) - pieceSize / 2,
                  width: pieceSize,
                  height: pieceSize,
                  child: PieceCircle(
                    piece: p,
                    selected: selectedId == p.id,
                    rotate: widget.rotateBlue && p.side == Side.blue,
                  ),
                ),
              // 点击层：最近交叉点
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) {
                    final gx = ((d.localPosition.dx - originX) / cell).round();
                    final gy = 13 - ((d.localPosition.dy - originYTop) / cell).round();
                    final pos = Pos(gx, gy);
                    if (pos.inBoard) _onTapCross(pos);
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// 战损棋子在侧区伪随机散布（按id稳定）
  List<Widget> _capturedPieces(List<Piece> pieces, double cell, double size,
      bool leftSide, BoxConstraints c) {
    final areaW = _kSideCells * cell;
    final baseX = leftSide ? 0.0 : c.maxWidth - areaW;
    final h = c.maxHeight;
    return [
      for (int i = 0; i < pieces.length; i++)
        Positioned(
          left: baseX +
              (areaW - size) * ((pieces[i].id * 37 % 89) / 89.0),
          top: (12.0 + i * (h - size - 20) / (pieces.length.clamp(1, 99))) +
              (pieces[i].id * 53 % 13),
          width: size,
          height: size,
          child: PieceCircle(piece: pieces[i], selected: false, rotate: false),
        ),
    ];
  }
}

/// 圆形棋子（白底描边、宋体单字居中）
class PieceCircle extends StatelessWidget {
  final Piece piece;
  final bool selected;
  final bool rotate;

  const PieceCircle(
      {super.key, required this.piece, required this.selected, required this.rotate});

  @override
  Widget build(BuildContext context) {
    final textColor = piece.side == Side.red ? kRedPieceText : kBluePieceText;
    Widget child = Container(
      decoration: BoxDecoration(
        color: kPieceBg,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Colors.amber.shade700
              : (piece.firedThisTurn ? Colors.orange : textColor),
          width: selected ? 3 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 3,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: LayoutBuilder(builder: (ctx, c) {
        return Text(
          piece.type.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: c.maxHeight * 0.52,
            fontWeight: FontWeight.bold,
            fontFamily: 'SimSun',
            fontFamilyFallback: const ['Noto Serif SC', 'serif'],
            height: 1.0,
          ),
        );
      }),
    );
    if (rotate) {
      child = Transform.rotate(angle: 3.141592653589793, child: child);
    }
    return child;
  }
}

class _GridPainter extends CustomPainter {
  final double cell;
  final double originX;
  final double originYTop;
  final Pos? selectedPos;
  final List<Pos> legalMoves;
  final List<Pos> bombardTargets;
  final bool bombardMode;
  final Board board;
  final List<BombardOrder> allBombards;

  _GridPainter({
    required this.cell,
    required this.originX,
    required this.originYTop,
    this.selectedPos,
    required this.legalMoves,
    required this.bombardTargets,
    required this.bombardMode,
    required this.board,
    required this.allBombards,
  });

  double _px(num x) => originX + x * cell;
  double _py(num y) => originYTop + (13 - y) * cell;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = kGridLine
      ..strokeWidth = 1.2;

    // 竖线13条(x=0..12)，横线14条(y=0..13) —— 交叉点制
    for (int x = 0; x <= 12; x++) {
      canvas.drawLine(
          Offset(_px(x), _py(13)), Offset(_px(x), _py(0)), gridPaint);
    }
    for (int y = 0; y <= 13; y++) {
      canvas.drawLine(
          Offset(_px(0), _py(y)), Offset(_px(12), _py(y)), gridPaint);
    }

    // 海域分界：y=6与y=7两条线之间的中线，加粗
    final seaPaint = Paint()
      ..color = kGridLine
      ..strokeWidth = 3.0;
    final seaY = (_py(6) + _py(7)) / 2;
    canvas.drawLine(Offset(_px(0), seaY), Offset(_px(12), seaY), seaPaint);
    _drawText(canvas, '· 海 域 分 界 ·', Offset(_px(6), seaY),
        color: Colors.black45, fontSize: cell * 0.4, centerV: true);

    // 指挥区（虚线黑框）：交叉点x∈[4,8] y∈[0,4]/[9,13]
    final dashPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    _drawDashedRect(
        canvas, Rect.fromLTRB(_px(4), _py(4), _px(8), _py(0)), dashPaint);
    _drawDashedRect(
        canvas, Rect.fromLTRB(_px(4), _py(13), _px(8), _py(9)), dashPaint);

    // 走法/轰炸目标提示
    if (bombardMode) {
      for (final p in bombardTargets) {
        final cx = _px(p.x), cy = _py(p.y);
        final cross = Paint()
          ..color = const Color(0xFFE05500)
          ..strokeWidth = 2;
        canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), cross);
        canvas.drawLine(Offset(cx, cy - 5), Offset(cx, cy + 5), cross);
      }
    } else {
      for (final p in legalMoves) {
        final target = board.at(p);
        final cx = _px(p.x), cy = _py(p.y);
        if (target != null) {
          canvas.drawCircle(
              Offset(cx, cy),
              cell / 2 - 2,
              Paint()
                ..color = const Color(0xFFD32F2F).withAlpha(210)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.6);
        } else {
          canvas.drawCircle(Offset(cx, cy), cell / 7,
              Paint()..color = Colors.black.withAlpha(95));
        }
      }
    }

    // 选中交叉点高亮
    if (selectedPos != null) {
      canvas.drawCircle(
        Offset(_px(selectedPos!.x), _py(selectedPos!.y)),
        cell * 0.52,
        Paint()..color = Colors.amber.withAlpha(80),
      );
    }

    // 双方已锁定的轰炸位置：红色四角围框（公开可见）
    for (final order in allBombards) {
      _drawCornerFrame(canvas, Offset(_px(order.target.x), _py(order.target.y)),
          cell * 0.46);
    }
  }

  /// 红色四角围框
  void _drawCornerFrame(Canvas canvas, Offset center, double half) {
    final paint = Paint()
      ..color = kBombardMark
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final len = half * 0.55;
    final l = center.dx - half, r = center.dx + half;
    final t = center.dy - half, b = center.dy + half;
    // 左上
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    // 右上
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // 左下
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    // 右下
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0, gap = 4.0;
    void dashedLine(Offset a, Offset b) {
      final total = (b - a).distance;
      if (total <= 0) return;
      final dir = (b - a) / total;
      double t = 0;
      while (t < total) {
        final end = (t + dash).clamp(0, total).toDouble();
        canvas.drawLine(a + dir * t, a + dir * end, paint);
        t += dash + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawText(Canvas canvas, String text, Offset center,
      {required Color color, required double fontSize, bool centerV = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontFamily: 'SimSun',
              fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2,
            centerV ? center.dy - tp.height / 2 : center.dy));
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => true;
}
