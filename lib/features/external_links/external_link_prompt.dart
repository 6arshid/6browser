import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/browser_engine.dart';
import '../tabs/url_input.dart';
import 'external_links.dart';

/// Opens links that belong to other apps (mailto:, tel:, sms:, whatsapp:,
/// tg:...) with the app the system has for them, after asking "Open
/// Telegram Desktop?" over the tab, as Chrome does. Without this the engine
/// showed ERR_UNKNOWN_URL_SCHEME.
class ExternalLinkHost extends ConsumerStatefulWidget {
  const ExternalLinkHost({super.key, required this.view, required this.child});

  final BrowserView view;
  final Widget child;

  @override
  ConsumerState<ExternalLinkHost> createState() => _ExternalLinkHostState();
}

typedef _Offer = ({AppLink link, String app, String site});

class _ExternalLinkHostState extends ConsumerState<ExternalLinkHost> {
  StreamSubscription<ExternalLinkRequest>? _sub;
  _Offer? _offer;

  @override
  void initState() {
    super.initState();
    _attach(widget.view);
  }

  @override
  void didUpdateWidget(ExternalLinkHost old) {
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
    _sub = view.externalLinks.listen(_onLink);
    // Like Chrome's dialog, the question goes away when the tab navigates.
    view.url.addListener(_dismiss);
  }

  void _detach(BrowserView view) {
    _sub?.cancel();
    view.url.removeListener(_dismiss);
  }

  void _dismiss() {
    if (_offer != null) setState(() => _offer = null);
  }

  static bool get _phone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _onLink(ExternalLinkRequest request) async {
    final link = AppLink.parse(request.url);
    if (link == null) return;
    final app = await ref.read(externalAppsProvider).appFor(link.scheme);
    if (!mounted) return;
    if (app == null) return _noApp(link);
    if (opensWithoutAsking(link, phone: _phone)) return _open(link);
    final source = request.source;
    setState(
      () => _offer = (
        link: link,
        app: app,
        site: isBookmarkable(source) ? displayHost(source) : '',
      ),
    );
  }

  Future<void> _open(AppLink link) async {
    _dismiss();
    final apps = ref.read(externalAppsProvider);
    if (await apps.open(link.url) || !mounted) return;
    await _noApp(link);
  }

  /// No app took the link: show the page the link offers instead, look for
  /// the app in the store (as Chrome on Android does), or say so.
  Future<void> _noApp(AppLink link) async {
    final fallback = link.fallbackUrl;
    if (fallback != null) {
      await widget.view.load(fallback);
      return;
    }
    final package = link.package;
    if (package != null && _phone) {
      final store = 'market://details?id=${Uri.encodeQueryComponent(package)}';
      if (await ref.read(externalAppsProvider).open(store) || !mounted) return;
    }
    final address = link.address;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('No app on this device opens ${link.target}: links.'),
        action: address == null
            ? null
            : SnackBarAction(
                label: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: address)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (offer != null)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topCenter,
              child: ExternalLinkPrompt(
                key: ObjectKey(offer),
                app: offer.app,
                site: offer.site,
                onOpen: () => _open(offer.link),
                onCancel: _dismiss,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Open Telegram Desktop?" with the site that asked.
class ExternalLinkPrompt extends StatelessWidget {
  const ExternalLinkPrompt({
    super.key,
    required this.app,
    required this.site,
    required this.onOpen,
    required this.onCancel,
  });

  /// Name of the app; empty when the system does not say.
  final String app;

  /// Host of the page that asked; empty when the user typed the link.
  final String site;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // Fits phones too.
        width: min(380, MediaQuery.sizeOf(context).width - 32),
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.arrow_up_right_square, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    app.isEmpty
                        ? 'Open this link in another app?'
                        : 'Open $app?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (site.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '$site wants to open this app.',
                style: TextStyle(color: muted),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onOpen, child: const Text('Open')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
