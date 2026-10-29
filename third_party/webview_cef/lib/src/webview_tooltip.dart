import 'dart:async';

import 'package:flutter/material.dart';

class WebviewTooltip {
  WebviewTooltip(BuildContext context) {
    _overlayState = Overlay.of(context);
    _box = context.findRenderObject() as RenderBox;
  }
  late OverlayState _overlayState;
  OverlayEntry? _overlayEntry;
  Timer? _timer;
  TooltipStatus _eStatus = TooltipStatus.hide;
  String _text = '';
  Offset cursorOffset = Offset.zero;
  late RenderBox _box;
  final TextStyle _textStyle =
      const TextStyle(color: Colors.black, fontSize: 14);

  void _buildOverlayEntry() {
    //往Overlay中插入插入OverlayEntry
    _timer = Timer(const Duration(milliseconds: 500), () {
      if (!_box.attached) return;
      _overlayEntry = OverlayEntry(builder: (context) {
        final text = _text;
        double height = _box.size.height;
        double width = _box.size.width;
        TextPainter textPainter = TextPainter(
          locale: Localizations.localeOf(context),
          textDirection: TextDirection.ltr,
          text: TextSpan(text: text, style: _textStyle),
          maxLines: 5,
          ellipsis: '...',
        )..layout(maxWidth: width - 16);
        if (cursorOffset.dy + textPainter.height + 25 > height) {
          cursorOffset =
              Offset(cursorOffset.dx, height - textPainter.height - 10);
          if (cursorOffset.dy < 0) {
            cursorOffset = Offset(cursorOffset.dx, 0);
          }
        } else {
          cursorOffset = Offset(cursorOffset.dx, cursorOffset.dy + 15);
        }

        if (cursorOffset.dx + textPainter.width + 40 > width) {
          cursorOffset =
              Offset(width - textPainter.width - 25, cursorOffset.dy);
          if (cursorOffset.dx < 0) {
            cursorOffset = Offset(0, cursorOffset.dy);
          }
        } else {
          cursorOffset = Offset(cursorOffset.dx + 15, cursorOffset.dy);
        }
        // 6browser patch: never takes the pointer, or the page under it
        // would stop getting hover and wheel events.
        return Positioned(
          top: cursorOffset.dy,
          left: cursorOffset.dx,
          child: IgnorePointer(
              child: Material(
            color: Colors.transparent,
            child: Container(
              width: textPainter.width + 16,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                boxShadow: [
                  BoxShadow(
                      blurRadius: 2, color: Colors.black.withValues(alpha: .2))
                ],
              ),
              child: RichText(
                text: TextSpan(text: text, style: _textStyle),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )),
        );
      });
      _overlayState.insert(_overlayEntry!);
      _eStatus = TooltipStatus.shown;
    });
  }

  void showToolTip(String text) {
    _text = text;
    if (text.isEmpty) {
      hide();
    } else if (_eStatus == TooltipStatus.hide) {
      _eStatus = TooltipStatus.prepare;
      _buildOverlayEntry();
    } else {
      // 6browser patch: another element's tooltip replaces the shown one.
      _overlayEntry?.markNeedsBuild();
    }
  }

  /// 6browser patch: also used when the view goes away.
  void hide() {
    _timer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _eStatus = TooltipStatus.hide;
  }
}

enum TooltipStatus {
  //Tooltip is prepare to show, Timer is running
  prepare,
  //Tooltip is alreay shown
  shown,
  //Tooltip is hide or uninitialized
  hide
}
