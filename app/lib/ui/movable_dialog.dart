import 'package:flutter/material.dart';

/// 可拖动的弹窗（标题栏按住拖动，内容可滚动）
class MovableDialog extends StatefulWidget {
  final String title;
  final Widget content;
  final double width;
  final double height;
  final Color bgColor;
  final Color titleBg;
  final Color titleFg;

  const MovableDialog({
    super.key,
    required this.title,
    required this.content,
    this.width = 520,
    this.height = 560,
    this.bgColor = Colors.white,
    this.titleBg = const Color(0xFF92CDDB),
    this.titleFg = Colors.black87,
  });

  static Future<void> show(BuildContext context, {
    required String title,
    required Widget content,
    double width = 520,
    double height = 560,
    Color bgColor = Colors.white,
    Color titleBg = const Color(0xFF92CDDB),
    Color titleFg = Colors.black87,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black38,
      pageBuilder: (ctx, _, __) {
        return MovableDialog(
          title: title,
          content: content,
          width: width,
          height: height,
          bgColor: bgColor,
          titleBg: titleBg,
          titleFg: titleFg,
        );
      },
    );
  }

  @override
  State<MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<MovableDialog> {
  Offset _pos = Offset.zero;
  bool _init = false;
  Offset? _dragStart;

  @override
  Widget build(BuildContext context) {
    if (!_init) {
      _init = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = MediaQuery.of(context).size;
        setState(() => _pos = Offset(
          (size.width - widget.width) / 2,
          (size.height - widget.height) / 2,
        ));
      });
    }

    return Stack(
      children: [
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: widget.bgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  // 标题栏：使用 Listener 原始指针事件实现跨平台拖动
                  Listener(
                    onPointerDown: (e) => _dragStart = e.position,
                    onPointerMove: (e) {
                      if (_dragStart != null) {
                        setState(() {
                          _pos += e.position - _dragStart!;
                          _dragStart = e.position;
                        });
                      }
                    },
                    onPointerUp: (_) => _dragStart = null,
                    onPointerCancel: (_) => _dragStart = null,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.titleBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(widget.title,
                                style: TextStyle(color: widget.titleFg, fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: widget.titleFg, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  // 内容滚动区
                  Expanded(child: widget.content),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
