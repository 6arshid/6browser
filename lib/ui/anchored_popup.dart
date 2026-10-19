import 'package:flutter/material.dart';

/// Shows [builder]'s content in a card under [anchor] (a toolbar button),
/// right-aligned with it, like Chrome's bubbles; in the middle on phones.
/// Tapping outside closes it.
Future<T?> showAnchoredPopup<T>(
  BuildContext anchor, {
  required WidgetBuilder builder,
  double width = 340,
}) {
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final box = anchor.findRenderObject() as RenderBox?;
  final rect = box == null || !box.hasSize
      ? null
      : MatrixUtils.transformRect(
          box.getTransformTo(overlay),
          Offset.zero & box.size,
        );
  return showDialog<T>(
    context: anchor,
    barrierColor: Colors.transparent,
    useSafeArea: false,
    builder: (context) {
      final screen = overlay.size;
      Widget card(double maxHeight) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(child: builder(context)),
        ),
      );
      if (rect == null || screen.width < 500) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: card(screen.height - 32),
          ),
        );
      }
      final top = rect.bottom + 6;
      return Stack(
        children: [
          Positioned(
            top: top,
            right: (screen.width - rect.right).clamp(8.0, screen.width),
            width: width,
            child: card(screen.height - top - 16),
          ),
        ],
      );
    },
  );
}
