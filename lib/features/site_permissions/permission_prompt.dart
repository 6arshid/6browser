import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/browser_engine.dart';
import 'site_permissions.dart';

/// Answers the tab's permission requests from the user's saved choice, or
/// shows "meet.google.com wants to use your microphone" over the page and
/// remembers the answer.
class SitePermissionHost extends ConsumerStatefulWidget {
  const SitePermissionHost({
    super.key,
    required this.view,
    required this.child,
  });

  final BrowserView view;
  final Widget child;

  @override
  ConsumerState<SitePermissionHost> createState() => _SitePermissionHostState();
}

class _SitePermissionHostState extends ConsumerState<SitePermissionHost> {
  StreamSubscription<PermissionRequest>? _sub;
  final _queue = <PermissionRequest>[];
  String _pageOrigin = '';

  @override
  void initState() {
    super.initState();
    _attach(widget.view);
  }

  @override
  void didUpdateWidget(SitePermissionHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.view, widget.view)) {
      _detach(old.view);
      _attach(widget.view);
    }
  }

  @override
  void dispose() {
    _detach(widget.view);
    super.dispose();
  }

  void _attach(BrowserView view) {
    _pageOrigin = _originOf(view.url.value);
    _sub = view.permissionRequests.listen(_onRequest);
    view.url.addListener(_onUrl);
  }

  void _detach(BrowserView view) {
    _sub?.cancel();
    view.url.removeListener(_onUrl);
    for (final request in _queue) {
      request.respond(PermissionAnswer.dismiss);
    }
    _queue.clear();
  }

  static String _originOf(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasAuthority ? uri.origin : url;
  }

  /// Like Chrome, an unanswered prompt goes away with the page that asked.
  void _onUrl() {
    final origin = _originOf(widget.view.url.value);
    if (origin == _pageOrigin) return;
    _pageOrigin = origin;
    if (_queue.isEmpty) return;
    final open = [..._queue];
    setState(_queue.clear);
    for (final request in open) {
      request.respond(PermissionAnswer.dismiss);
    }
  }

  Future<void> _onRequest(PermissionRequest request) async {
    final saved = await ref
        .read(sitePermissionStoreProvider)
        .decisionFor(
          request.origin,
          request.permissions,
          incognito: widget.view.incognito,
        );
    if (!mounted) return request.respond(PermissionAnswer.dismiss);
    if (saved != null) return request.respond(saved);
    if (!request.isOpen) return;
    setState(() => _queue.add(request));
    unawaited(
      request.withdrawn.then((_) {
        if (mounted && _queue.contains(request)) {
          setState(() => _queue.remove(request));
        }
      }),
    );
  }

  Future<void> _answer(
    PermissionRequest request,
    PermissionAnswer answer,
  ) async {
    setState(() => _queue.remove(request));
    final store = ref.read(sitePermissionStoreProvider);
    final incognito = widget.view.incognito;
    // Saved before answering: the engine may ask again for the same thing
    // right away (Chromium's prompt, then the device request).
    if (answer != PermissionAnswer.dismiss) {
      await store.remember(
        request.origin,
        request.permissions,
        allowed: answer == PermissionAnswer.allow,
        incognito: incognito,
      );
    }
    request.respond(answer);
    // Requests waiting behind this one may be answered now.
    for (final next in [..._queue]) {
      final saved = await store.decisionFor(
        next.origin,
        next.permissions,
        incognito: incognito,
      );
      if (saved == null) continue;
      next.respond(saved);
      if (mounted) setState(() => _queue.remove(next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _queue.firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (request != null)
          PositionedDirectional(
            top: 8,
            start: 16,
            child: PermissionPrompt(
              key: ObjectKey(request),
              origin: request.origin,
              permissions: request.permissions,
              incognito: widget.view.incognito,
              onAnswer: (answer) => _answer(request, answer),
            ),
          ),
      ],
    );
  }
}

/// "meet.google.com wants to: Use your microphone, Use your camera" with
/// Block and Allow.
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    super.key,
    required this.origin,
    required this.permissions,
    required this.onAnswer,
    this.incognito = false,
  });

  final String origin;
  final Set<SitePermission> permissions;
  final bool incognito;
  final ValueChanged<PermissionAnswer> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final sorted = permissions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // Fits phones too.
        width: min(380, MediaQuery.sizeOf(context).width - 32),
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${siteName(origin)} wants to',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => onAnswer(PermissionAnswer.dismiss),
                ),
              ],
            ),
            for (final permission in sorted)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4, end: 12),
                child: Row(
                  children: [
                    Icon(permission.icon, size: 20, color: muted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(permission.request)),
                  ],
                ),
              ),
            if (incognito) ...[
              const SizedBox(height: 8),
              Text(
                'In this private window your choice is kept until 6browser '
                'closes.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => onAnswer(PermissionAnswer.block),
                    child: const Text('Block'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onAnswer(PermissionAnswer.allow),
                    child: const Text('Allow'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
