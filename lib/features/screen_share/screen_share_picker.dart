import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/browser_engine.dart';
import '../site_permissions/site_permissions.dart';
import 'capture_sources.dart';

/// Shows the screen and window picker over the tab when its page wants to
/// share the screen (Chrome's "Choose what to share").
class ScreenShareHost extends StatefulWidget {
  const ScreenShareHost({
    super.key,
    required this.view,
    required this.child,
    this.sources = listCaptureSources,
  });

  final BrowserView view;
  final Widget child;

  /// Where the screens and windows come from (a fake in tests).
  final Future<List<CaptureSource>> Function() sources;

  @override
  State<ScreenShareHost> createState() => _ScreenShareHostState();
}

class _ScreenShareHostState extends State<ScreenShareHost> {
  StreamSubscription<ScreenShareRequest>? _sub;
  ScreenShareRequest? _request;

  @override
  void initState() {
    super.initState();
    _sub = widget.view.screenShareRequests.listen(_onRequest);
  }

  @override
  void didUpdateWidget(ScreenShareHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.view, widget.view)) {
      _sub?.cancel();
      _request?.cancel();
      _request = null;
      _sub = widget.view.screenShareRequests.listen(_onRequest);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _request?.cancel();
    super.dispose();
  }

  void _onRequest(ScreenShareRequest request) {
    _request?.cancel();
    setState(() => _request = request);
    request.withdrawn.then((_) {
      if (mounted && identical(_request, request)) {
        setState(() => _request = null);
      }
    });
  }

  void _close() => setState(() => _request = null);

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (request != null)
          Positioned.fill(
            child: ScreenSharePicker(
              key: ObjectKey(request),
              request: request,
              sources: widget.sources,
              onClosed: _close,
            ),
          ),
      ],
    );
  }
}

/// "Choose what to share": the entire screen (each display) or a window,
/// with live thumbnails, and "Also share system audio" when the page asked
/// for sound.
class ScreenSharePicker extends StatefulWidget {
  const ScreenSharePicker({
    super.key,
    required this.request,
    required this.onClosed,
    this.sources = listCaptureSources,
  });

  final ScreenShareRequest request;
  final VoidCallback onClosed;
  final Future<List<CaptureSource>> Function() sources;

  @override
  State<ScreenSharePicker> createState() => _ScreenSharePickerState();
}

class _ScreenSharePickerState extends State<ScreenSharePicker> {
  /// How often the thumbnails and the window list are refreshed.
  static const _refresh = Duration(seconds: 3);

  List<CaptureSource>? _sources;
  CaptureKind _kind = CaptureKind.screen;
  String? _selected;
  late bool _audio = widget.request.audioOffered;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final sources = await widget.sources();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        // A window that closed can no longer be chosen.
        if (_selected != null && !sources.any((s) => s.id == _selected)) {
          _selected = null;
        }
        _selected ??= _ofKind(sources, _kind).firstOrNull?.id;
      });
    } finally {
      _loading = false;
    }
  }

  static List<CaptureSource> _ofKind(
    List<CaptureSource> sources,
    CaptureKind kind,
  ) => [
    for (final s in sources)
      if (s.kind == kind) s,
  ];

  void _pickKind(CaptureKind kind) {
    setState(() {
      _kind = kind;
      final shown = _ofKind(_sources ?? const [], kind);
      if (!shown.any((s) => s.id == _selected)) {
        _selected = shown.length == 1 ? shown.single.id : null;
      }
    });
  }

  void _share([String? id]) {
    final source = id ?? _selected;
    if (source == null) return;
    widget.request.share(source, audio: _audio);
    widget.onClosed();
  }

  void _cancel() {
    widget.request.cancel();
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final size = MediaQuery.sizeOf(context);
    final sources = _sources;
    final shown = sources == null ? null : _ofKind(sources, _kind);
    final site = siteName(widget.request.origin);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        const SingleActivator(LogicalKeyboardKey.enter): _share,
      },
      child: FocusScope(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ModalBarrier(dismissible: false, color: Colors.black38),
            Center(
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: min(760, size.width - 32),
                  height: min(580, size.height - 32),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose what to share',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$site will be able to see the contents of what '
                          'you share.',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SegmentedButton<CaptureKind>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: CaptureKind.screen,
                                icon: Icon(Icons.desktop_windows_outlined),
                                label: Text('Entire screen'),
                              ),
                              ButtonSegment(
                                value: CaptureKind.window,
                                icon: Icon(Icons.web_asset),
                                label: Text('Window'),
                              ),
                            ],
                            selected: {_kind},
                            onSelectionChanged: (s) => _pickKind(s.single),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _grid(shown, muted)),
                        if (widget.request.audioOffered)
                          CheckboxListTile(
                            key: const ValueKey('share-audio'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _audio,
                            onChanged: (v) => setState(() => _audio = v!),
                            title: const Text('Also share system audio'),
                            subtitle: const Text(
                              "Sound from the computer. 6browser's own sound "
                              'is left out, so people in the call do not hear '
                              'themselves.',
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _cancel,
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _selected == null ? null : _share,
                              child: const Text('Share'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<CaptureSource>? shown, Color muted) {
    if (shown == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shown.isEmpty) {
      return Center(
        child: Text(
          _kind == CaptureKind.window
              ? 'No windows to share.'
              : 'Screen sharing is not available on this computer.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final source = shown[i];
        return _SourceTile(
          key: ValueKey(source.id),
          source: source,
          selected: source.id == _selected,
          onTap: () => setState(() => _selected = source.id),
          onDoubleTap: () => _share(source.id),
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final CaptureSource source;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnail = source.thumbnail;
    return Semantics(
      selected: selected,
      button: true,
      label: source.title,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? scheme.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: thumbnail == null
                          ? Icon(
                              source.kind == CaptureKind.window
                                  ? Icons.web_asset
                                  : Icons.desktop_windows_outlined,
                              size: 40,
                              color: scheme.onSurfaceVariant,
                            )
                          : Image.memory(
                              thumbnail,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  source.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
