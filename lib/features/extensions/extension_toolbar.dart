import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/browser_engine.dart';
import '../../ui/anchored_popup.dart';
import '../../ui/browser_theme.dart';
import '../../ui/toolbar.dart' show openPage;
import '../tabs/tabs_controller.dart';
import 'extension_service.dart';
import 'extensions_page.dart';

/// Pinned extension icons and the extensions (puzzle) button, as in
/// Chrome's toolbar. Nothing is shown when no extension is installed.
class ExtensionsToolbar extends ConsumerWidget {
  const ExtensionsToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(extensionsProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = BrowserColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final x in items)
          if (x.pinned && x.running)
            Builder(
              builder: (context) => IconButton(
                tooltip: x.name,
                icon: Opacity(
                  opacity: x.popupUrl == null ? 0.5 : 1,
                  child: ExtensionIcon(x, size: 18),
                ),
                onPressed: x.popupUrl == null
                    ? null
                    : () => showExtensionPopup(context, ref, x),
              ),
            ),
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Extensions',
            icon: Icon(Icons.extension_outlined, color: colors.icon, size: 20),
            onPressed: () => _showMenu(context, ref),
          ),
        ),
      ],
    );
  }

  void _showMenu(BuildContext anchor, WidgetRef ref) {
    showAnchoredPopup<void>(
      anchor,
      width: 320,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final items = ref.watch(extensionsProvider);
          final controller = ref.read(extensionsProvider.notifier);
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Extensions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final x in items.where((x) => x.running))
                ListTile(
                  dense: true,
                  leading: ExtensionIcon(x),
                  title: Text(x.name, overflow: TextOverflow.ellipsis),
                  subtitle: x.popupUrl == null
                      ? Text(
                          'No popup',
                          style: TextStyle(color: muted, fontSize: 12),
                        )
                      : null,
                  onTap: x.popupUrl == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          showExtensionPopup(anchor, ref, x);
                        },
                  trailing: IconButton(
                    tooltip: x.pinned ? 'Unpin' : 'Pin',
                    icon: Icon(
                      x.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 18,
                    ),
                    onPressed: () => controller.setPinned(x.id, !x.pinned),
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_outlined, size: 20),
                title: const Text('Manage extensions'),
                onTap: () {
                  Navigator.pop(context);
                  openPage(anchor, const ExtensionsPage());
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Opens the extension's toolbar popup page under [anchor].
Future<void> showExtensionPopup(
  BuildContext anchor,
  WidgetRef ref,
  InstalledExtension x,
) async {
  final url = x.popupUrl;
  if (url == null) return;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final box = anchor.findRenderObject() as RenderBox?;
  final rect = box == null || !box.hasSize
      ? Rect.fromLTWH(overlay.size.width - 8, 48, 0, 0)
      : MatrixUtils.transformRect(
          box.getTransformTo(overlay),
          Offset.zero & box.size,
        );
  await showDialog<void>(
    context: anchor,
    barrierColor: Colors.transparent,
    useSafeArea: false,
    builder: (context) => Stack(
      children: [
        Positioned(
          top: rect.bottom + 4,
          right: (overlay.size.width - rect.right).clamp(
            8.0,
            overlay.size.width,
          ),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ExtensionPopupView(
              engine: ref.read(engineProvider),
              url: url,
              maxHeight: overlay.size.height - rect.bottom - 16,
            ),
          ),
        ),
      ],
    ),
  );
}

/// An extension popup page that sizes itself to its content, like Chrome's
/// (25x25 up to 800x600). `window.close()` in the page closes it.
class ExtensionPopupView extends StatefulWidget {
  const ExtensionPopupView({
    super.key,
    required this.engine,
    required this.url,
    this.maxHeight = 600,
  });

  final BrowserEngine engine;
  final String url;
  final double maxHeight;

  @override
  State<ExtensionPopupView> createState() => _ExtensionPopupViewState();
}

class _ExtensionPopupViewState extends State<ExtensionPopupView> {
  /// Size used when the page cannot report its own.
  static const _fallback = Size(360, 480);

  late final BrowserView _view;
  StreamSubscription<String>? _messages;
  Timer? _fallbackTimer;
  Size? _size;

  @override
  void initState() {
    super.initState();
    _view = widget.engine.createView(initialUrl: widget.url);
    _view.isLoading.addListener(_onLoading);
    _messages = _view.scriptMessages.listen(_onMessage);
    if (_view.scriptPostFunction == null) _size = _fallback;
  }

  void _onLoading() {
    if (_view.isLoading.value) return;
    final post = _view.scriptPostFunction;
    if (post == null) return;
    // Reports the page's preferred size and turns window.close() into a
    // request to close this popup.
    _view.runScript('''
(function (post) {
  window.close = function () { post(JSON.stringify({extensionPopup: 'close'})); };
  var last = '';
  function report() {
    var d = document.documentElement, b = document.body;
    var w = Math.max(d.scrollWidth, b ? b.scrollWidth : 0);
    var h = Math.max(d.scrollHeight, b ? b.scrollHeight : 0);
    if (w + 'x' + h === last) return;
    last = w + 'x' + h;
    post(JSON.stringify({extensionPopup: 'size', width: w, height: h}));
  }
  report();
  var o = new ResizeObserver(report);
  o.observe(document.documentElement);
  if (document.body) o.observe(document.body);
})($post);''');
    _fallbackTimer ??= Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _size == null) setState(() => _size = _fallback);
    });
  }

  void _onMessage(String text) {
    final Object? m;
    try {
      m = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (m is! Map || !mounted) return;
    switch (m['extensionPopup']) {
      case 'close':
        Navigator.of(context).maybePop();
      case 'size':
        final w = (m['width'] as num?)?.toDouble() ?? 0;
        final h = (m['height'] as num?)?.toDouble() ?? 0;
        setState(() => _size = Size(w.clamp(25, 800), h.clamp(25, 600)));
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _messages?.cancel();
    _view.isLoading.removeListener(_onLoading);
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    // Until the page reports its size it is laid out small (so it can
    // report its preferred width) and kept invisible.
    return AnimatedSize(
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: size?.width ?? 25,
        height: (size?.height ?? 25).clamp(25, widget.maxHeight.clamp(25, 600)),
        child: Opacity(opacity: size == null ? 0 : 1, child: _view.widget),
      ),
    );
  }
}
