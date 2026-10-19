import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/browser_engine.dart';

/// Chrome's find-in-page box (Ctrl+F): typing searches as you go, Enter /
/// Shift+Enter (or F3 / Shift+F3) step through matches, Esc closes.
class FindBar extends StatelessWidget {
  const FindBar({
    super.key,
    required this.view,
    required this.controller,
    required this.focusNode,
    required this.onClose,
  });

  final BrowserView view;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;

  void _step(bool forward) {
    if (controller.text.isEmpty) return;
    view.find(controller.text, forward: forward, findNext: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: SizedBox(
          width: 360,
          child: Row(
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () =>
                        _step(true),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): () =>
                        _step(false),
                    const SingleActivator(LogicalKeyboardKey.escape): onClose,
                  },
                  child: TextField(
                    key: const ValueKey('find-field'),
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Find in page',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (t) => view.find(t),
                  ),
                ),
              ),
              ValueListenableBuilder<FindResult>(
                valueListenable: view.findResult,
                builder: (_, r, _) => Text(
                  controller.text.isEmpty ? '' : '${r.active}/${r.count}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const SizedBox(height: 24, child: VerticalDivider()),
              IconButton(
                tooltip: 'Previous (Shift+Enter)',
                iconSize: 20,
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _step(false),
              ),
              IconButton(
                tooltip: 'Next (Enter)',
                iconSize: 20,
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _step(true),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                iconSize: 20,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
