import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/browser_engine.dart';
import 'browser_theme.dart';

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
    final light = scheme.brightness == Brightness.light;
    Widget step(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          iconSize: 14,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          icon: Icon(icon),
          onPressed: onPressed,
        );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: light ? Colors.white : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(Ui.radiusLarge),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: Ui.shadow(scheme.brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        child: SizedBox(
          width: 340,
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
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'Find in page',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      prefixIcon: Icon(CupertinoIcons.search, size: 15),
                      prefixIconConstraints: BoxConstraints(minWidth: 26),
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
              const SizedBox(width: 6),
              step('Previous (Shift+Enter)', CupertinoIcons.chevron_up, () {
                _step(false);
              }),
              step('Next (Enter)', CupertinoIcons.chevron_down, () {
                _step(true);
              }),
              const SizedBox(width: 2),
              step('Close (Esc)', CupertinoIcons.xmark, onClose),
            ],
          ),
        ),
      ),
    );
  }
}
