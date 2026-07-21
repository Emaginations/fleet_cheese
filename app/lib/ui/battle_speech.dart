import 'package:flutter/material.dart';
import '../models.dart';
import '../notation.dart';

/// 根据半步动作生成简短作战总结
String generateSpeech(Side side, List<QpAction>? actions) {
  if (actions == null || actions.isEmpty) return '${side.label}方完成战术部署';
  final bombards = actions.where((a) => a.isBombard).toList();
  final moves = actions.where((a) => !a.isBombard).toList();
  final parts = <String>[];
  if (bombards.isNotEmpty) {
    final hitEnemy = bombards.where((b) => b.targetDesc != '空' && b.targetDesc.isNotEmpty).toList();
    if (hitEnemy.isNotEmpty) parts.add('火力锁定敌${hitEnemy.map((b) => b.targetDesc).join("、")}');
    if (hitEnemy.length < bombards.length) parts.add('远程打击封锁海域');
  }
  if (moves.isNotEmpty) {
    final mv = moves.first;
    final dir = mv.to.y > mv.from.y ? '推进' : (mv.to.y < mv.from.y ? '后撤' : '机动');
    parts.add('${mv.pieceType.fullName}$dir至${mv.to.qp}');
  }
  return parts.isEmpty ? '${side.label}方完成战术部署' : parts.join('，');
}

/// 弹出作战指令气泡 Overlay
void showBattleSpeech(BuildContext context, String text, Side side) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _SpeechBubble(text: text, side: side, onDone: () {
    try { entry.remove(); } catch (_) {}
  }));
  overlay.insert(entry);
}

class _SpeechBubble extends StatefulWidget {
  final String text;
  final Side side;
  final VoidCallback onDone;
  const _SpeechBubble({required this.text, required this.side, required this.onDone});

  @override
  State<_SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<_SpeechBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) { _ctrl.reverse().then((_) => widget.onDone()); }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isBlue = widget.side == Side.blue;
    return Positioned(
      left: 40, right: 40,
      top: isBlue ? MediaQuery.of(context).padding.top + 48 : null,
      bottom: isBlue ? null : 120,
      child: FadeTransition(
        opacity: _ctrl,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (isBlue ? const Color(0xFF2F76C6) : const Color(0xFFE63946)).withAlpha(220),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 6)],
            ),
            child: Text('⚡ ${widget.side.label} · ${widget.text}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}
