import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../engine/browser_engine.dart';
import '../../ui/browser_theme.dart';
import '../settings/app_settings.dart';
import '../settings/appearance_settings.dart';
import '../tabs/tabs_controller.dart';
import '../tabs/url_input.dart';
import 'new_tab_tiles.dart';

const _tileWidth = 96.0;
const _tileSpacing = 10.0;
const _iconTile = 64.0;

/// The built-in New Tab page: a search box and a grid of shortcuts and
/// most visited sites that can be added, edited, removed and dragged.
class NewTabPage extends ConsumerWidget {
  const NewTabPage({super.key, required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = view.incognito
        ? BrowserColors.incognito
        : BrowserColors.of(context);
    final image = view.incognito ? null : colors.ntpImage;
    final page = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.ntpBackground,
        image: image == null
            ? null
            : DecorationImage(
                image: image,
                alignment: colors.ntpAlignment,
                repeat: colors.ntpRepeat,
                fit: colors.ntpRepeat == ImageRepeat.noRepeat
                    ? BoxFit.cover
                    : BoxFit.none,
              ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: colors.ntpText,
          shadows: image == null
              ? null
              : const [Shadow(blurRadius: 4, color: Colors.black54)],
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: colors.ntpText),
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: Column(
                      children: [
                        SizedBox(height: (box.maxHeight * 0.14).clamp(24, 140)),
                        if (view.incognito)
                          const _IncognitoHeader()
                        else
                          const _Logo(),
                        _SearchBox(view: view),
                        const SizedBox(height: 44),
                        if (!view.incognito) _TileGrid(view: view),
                        const SizedBox(height: 72),
                      ],
                    ),
                  ),
                ),
              ),
              if (!view.incognito)
                PositionedDirectional(
                  end: 16,
                  bottom: 16,
                  child: _CustomizeButton(
                    color: colors.ntpText,
                    onPressed: () => showCustomizePanel(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // Private tabs are dark like their toolbar, so text and the search box
    // must not take light-theme colors.
    return view.incognito
        ? Theme(
            data: buildTheme(
              brightness: Brightness.dark,
              colors: BrowserColors.incognito,
            ),
            child: page,
          )
        : page;
  }
}

/// The app's mark, small and quiet like Safari's Start Page.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      children: [
        Image.asset('assets/logo.png', width: 56, height: 56),
        const SizedBox(height: 12),
        Text(
          '6browser',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 26,
            color: DefaultTextStyle.of(context).style.color,
            shadows: DefaultTextStyle.of(context).style.shadows,
          ),
        ),
      ],
    ),
  );
}

/// "Customize" in the corner of the page: a glyph and a word on a faint
/// fill.
class _CustomizeButton extends StatelessWidget {
  const _CustomizeButton({required this.color, required this.onPressed});

  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: color.withValues(alpha: 0.75),
      backgroundColor: color.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
    ),
    icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 16),
    label: const Text('Customize'),
    onPressed: onPressed,
  );
}

class _IncognitoHeader extends StatelessWidget {
  const _IncognitoHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      children: [
        const Icon(CupertinoIcons.eye_slash, size: 44),
        const SizedBox(height: 14),
        Text(
          'You are browsing privately',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text(
          'History, cookies and downloads from this tab are not saved.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _SearchBox extends ConsumerWidget {
  const _SearchBox({required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final engine = searchEngines
        .where((e) => e.template == settings.searchTemplate)
        .firstOrNull;
    final colors = BrowserColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fill = view.incognito
        ? BrowserColors.incognito.omnibox
        : colors.omnibox;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        borderRadius: BorderRadius.circular(Ui.radiusLarge),
        color: fill,
        child: TextField(
          key: const ValueKey('newtab-search'),
          style: TextStyle(
            fontSize: 15,
            color: view.incognito
                ? BrowserColors.incognito.omniboxText
                : colors.omniboxText,
            shadows: const [],
          ),
          decoration: InputDecoration(
            filled: false,
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Icon(
                CupertinoIcons.search,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
            hintText: engine == null
                ? 'Search or type a URL'
                : 'Search ${engine.name} or type a URL',
            hintStyle: TextStyle(
              color: scheme.onSurfaceVariant,
              shadows: const [],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Ui.radiusLarge),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Ui.radiusLarge),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Ui.radiusLarge),
              borderSide: BorderSide(
                color: scheme.primary.withValues(alpha: 0.6),
                width: 3,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onSubmitted: (text) {
            if (text.trim().isEmpty) return;
            view.load(
              resolveInput(text, searchTemplate: settings.searchTemplate),
            );
          },
        ),
      ),
    );
  }
}

class _TileGrid extends ConsumerWidget {
  const _TileGrid({required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(newTabTilesProvider);
    if (tiles == null) return const SizedBox.shrink();
    final actions = NewTabActions(ref.read(databaseProvider), tiles);
    final customCount = tiles.where((t) => t.custom).length;

    Future<void> remove(int i) async {
      final messenger = ScaffoldMessenger.of(context);
      final undo = await actions.remove(i);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Shortcut removed'),
            action: SnackBarAction(label: 'Undo', onPressed: undo),
          ),
        );
    }

    Future<void> edit(int i) async {
      final r = await showShortcutDialog(context, initial: tiles[i]);
      if (r != null) await actions.edit(i, r.$1, r.$2);
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Two rows at most, like Chrome: as many tiles as fit side by side
        // (up to eight), the add button taking the last slot.
        final perRow =
            ((box.maxWidth + _tileSpacing) / (_tileWidth + _tileSpacing))
                .floor()
                .clamp(1, 8);
        final slots = perRow * 2;
        final canAdd = customCount < math.min(maxTiles, slots - 1);
        final shown = tiles.take(canAdd ? slots - 1 : slots);
        final width = perRow * (_tileWidth + _tileSpacing) - _tileSpacing;
        return SizedBox(
          width: math.min(width, box.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 14),
                child: Text(
                  'Favorites',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    color: DefaultTextStyle.of(context).style.color,
                    shadows: DefaultTextStyle.of(context).style.shadows,
                  ),
                ),
              ),
              Wrap(
                spacing: _tileSpacing,
                runSpacing: 14,
                children: [
                  for (final (i, t) in shown.indexed)
                    _DraggableTile(
                      key: ValueKey(t.url),
                      index: i,
                      tile: t,
                      onOpen: () => view.load(t.url),
                      onOpenInBackground: () => ref
                          .read(tabsProvider.notifier)
                          .newTab(url: t.url, activate: false),
                      onEdit: () => edit(i),
                      onRemove: () => remove(i),
                      onMove: actions.move,
                    ),
                  if (canAdd)
                    _AddTile(
                      onTap: () async {
                        final r = await showShortcutDialog(context);
                        if (r != null) await actions.add(r.$1, r.$2);
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A tile that can be dragged onto another tile to take its place.
class _DraggableTile extends StatelessWidget {
  const _DraggableTile({
    super.key,
    required this.index,
    required this.tile,
    required this.onOpen,
    required this.onOpenInBackground,
    required this.onEdit,
    required this.onRemove,
    required this.onMove,
  });

  final int index;
  final NewTabTile tile;
  final VoidCallback onOpen;
  final VoidCallback onOpenInBackground;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final Future<void> Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final body = _Tile(
      tile: tile,
      onOpen: onOpen,
      onOpenInBackground: onOpenInBackground,
      onEdit: onEdit,
      onRemove: onRemove,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onMove(d.data, index),
      builder: (context, candidates, _) => Draggable<int>(
        data: index,
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(opacity: 0.85, child: _TileFace(tile: tile)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: body),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: 2,
              color: candidates.isEmpty
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.tile,
    required this.onOpen,
    required this.onOpenInBackground,
    required this.onEdit,
    required this.onRemove,
  });

  final NewTabTile tile;
  final VoidCallback onOpen;
  final VoidCallback onOpenInBackground;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  Future<void> _menu(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'background', child: Text('Open in new tab')),
        PopupMenuItem(value: 'edit', child: Text('Edit shortcut')),
        PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    switch (choice) {
      case 'background':
        widget.onOpenInBackground();
      case 'edit':
        widget.onEdit();
      case 'remove':
        widget.onRemove();
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Listener(
      // Middle-click opens the site in a background tab.
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) widget.onOpenInBackground();
      },
      child: GestureDetector(
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        child: Tooltip(
          message: widget.tile.title,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            hoverColor: Colors.transparent,
            onTap: widget.onOpen,
            child: Stack(
              children: [
                _TileFace(tile: widget.tile, hover: _hover),
                if (_hover)
                  Positioned(
                    top: 0,
                    right: 2,
                    child: Builder(
                      builder: (context) => IconButton(
                        tooltip: 'More actions',
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        style: IconButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        icon: const Icon(CupertinoIcons.ellipsis),
                        onPressed: () {
                          final box = context.findRenderObject() as RenderBox;
                          _menu(
                            box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Icon and label of a tile.
class _TileFace extends StatelessWidget {
  const _TileFace({required this.tile, this.hover = false});

  final NewTabTile tile;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final colors = BrowserColors.of(context);
    final light = colors.brightness == Brightness.light;
    return SizedBox(
      width: _tileWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Ui.fast,
            curve: Ui.curve,
            width: _iconTile,
            height: _iconTile,
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, hover ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: light ? Colors.white : colors.omnibox,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.separator.withValues(alpha: 0.06),
              ),
              boxShadow: Ui.shadow(
                colors.brightness,
                strength: hover ? 0.9 : 0.45,
              ),
            ),
            child: SiteIcon(url: tile.url, title: tile.title),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: Text(
              tile.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: colors.ntpText.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Site icon: the site's touch icon, then its favicon, then a letter.
class SiteIcon extends StatelessWidget {
  const SiteIcon({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final letter = _LetterIcon(host: uri?.host ?? '', title: title);
    if (uri == null || uri.host.isEmpty) return letter;
    final origin = uri.origin;
    Widget image(String src, Widget fallback) => Image.network(
      src,
      width: 32,
      height: 32,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => fallback,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: image(
        '$origin/apple-touch-icon.png',
        image('$origin/favicon.ico', letter),
      ),
    );
  }
}

class _LetterIcon extends StatelessWidget {
  const _LetterIcon({required this.host, required this.title});

  final String host;
  final String title;

  @override
  Widget build(BuildContext context) {
    final name = host.startsWith('www.') ? host.substring(4) : host;
    final source = name.isNotEmpty ? name : title;
    final letter = source.isEmpty ? '?' : source.characters.first.toUpperCase();
    final color =
        Colors.primaries[source.hashCode.abs() % Colors.primaries.length];
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.shade400, color.shade600],
        ),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BrowserColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      hoverColor: Colors.transparent,
      onTap: onTap,
      child: SizedBox(
        width: _tileWidth,
        child: Column(
          children: [
            Container(
              width: _iconTile,
              height: _iconTile,
              decoration: BoxDecoration(
                color: colors.ntpText.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.ntpText.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                CupertinoIcons.add,
                size: 22,
                color: colors.ntpText.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: Text(
                'Add shortcut',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.ntpText.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a shortcut's title and URL. Returns (url, title) or null.
Future<(String, String)?> showShortcutDialog(
  BuildContext context, {
  NewTabTile? initial,
}) => showDialog<(String, String)>(
  context: context,
  builder: (_) => _ShortcutDialog(initial: initial),
);

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({this.initial});

  final NewTabTile? initial;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _url = TextEditingController(text: widget.initial?.url);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = normalizeShortcutUrl(_url.text);
    if (url == null) {
      setState(() => _error = 'Enter a valid web address');
      return;
    }
    final title = _title.text.trim();
    Navigator.of(context)
        .pop((url, title.isEmpty ? Uri.parse(url).host : title));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit shortcut' : 'New shortcut'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('shortcut-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('shortcut-url'),
              controller: _url,
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: 'Type or paste a URL',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }
}
