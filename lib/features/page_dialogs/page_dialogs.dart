import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/browser_engine.dart';
import '../site_permissions/site_permissions.dart';

/// Draws the tab's alert(), confirm(), prompt() and "Leave site?" dialogs
/// over its page, one at a time. The page waits for the answer; the rest
/// of the browser does not.
class PageDialogHost extends StatefulWidget {
  const PageDialogHost({super.key, required this.view, required this.child});

  final BrowserView view;
  final Widget child;

  @override
  State<PageDialogHost> createState() => _PageDialogHostState();
}

class _PageDialogHostState extends State<PageDialogHost> {
  StreamSubscription<PageDialogRequest>? _sub;
  final _queue = <PageDialogRequest>[];

  @override
  void initState() {
    super.initState();
    _sub = widget.view.pageDialogs.listen(_onDialog);
  }

  @override
  void didUpdateWidget(PageDialogHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.view, widget.view)) {
      _sub?.cancel();
      _cancelAll();
      _sub = widget.view.pageDialogs.listen(_onDialog);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelAll();
    super.dispose();
  }

  void _cancelAll() {
    for (final dialog in _queue) {
      dialog.respond(false);
    }
    _queue.clear();
  }

  void _onDialog(PageDialogRequest request) {
    setState(() => _queue.add(request));
    request.withdrawn.then((_) {
      if (mounted && _queue.contains(request)) {
        setState(() => _queue.remove(request));
      }
    });
  }

  void _answer(PageDialogRequest request, bool ok, [String text = '']) {
    setState(() => _queue.remove(request));
    request.respond(ok, text);
    // Give the page its keyboard back.
    if (_queue.isEmpty) widget.view.focus();
  }

  @override
  Widget build(BuildContext context) {
    final request = _queue.firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (request != null) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Colors.black26),
          ),
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topCenter,
              child: PageDialog(
                key: ObjectKey(request),
                request: request,
                onAnswer: (ok, [text = '']) => _answer(request, ok, text),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "example.com says" with the page's message, as Chrome shows it.
class PageDialog extends StatefulWidget {
  const PageDialog({super.key, required this.request, required this.onAnswer});

  final PageDialogRequest request;
  final void Function(bool ok, [String text]) onAnswer;

  @override
  State<PageDialog> createState() => _PageDialogState();
}

class _PageDialogState extends State<PageDialog> {
  late final _text = TextEditingController(text: widget.request.defaultText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ok() => widget.onAnswer(true, _text.text);
  void _cancel() => widget.onAnswer(false);

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final leave = request.type == PageDialogType.leave;
    final site = request.origin.isEmpty ? '' : siteName(request.origin);
    final title = switch (request.type) {
      PageDialogType.leave => request.isReload ? 'Reload site?' : 'Leave site?',
      _ => site.isEmpty ? 'This page says' : '$site says',
    };
    final okLabel = switch (request.type) {
      PageDialogType.leave => request.isReload ? 'Reload' : 'Leave',
      _ => 'OK',
    };
    final hasCancel = request.type != PageDialogType.alert;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): hasCancel
            ? _cancel
            : _ok,
      },
      child: FocusScope(
        autofocus: true,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: min(460, MediaQuery.sizeOf(context).width - 32),
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: SelectableText(
                      leave
                          ? 'Changes that you made may not be saved.'
                          : request.message,
                      style: leave ? TextStyle(color: muted) : null,
                    ),
                  ),
                ),
                if (request.type == PageDialogType.prompt) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: TextField(
                      key: const ValueKey('page-dialog-text'),
                      controller: _text,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _ok(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasCancel) ...[
                      TextButton(
                        autofocus: leave,
                        onPressed: _cancel,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton(
                      autofocus:
                          !leave && request.type != PageDialogType.prompt,
                      onPressed: _ok,
                      child: Text(okLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
