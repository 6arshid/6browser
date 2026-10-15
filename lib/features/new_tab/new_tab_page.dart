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

const _tileWidth = 104.0;

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
    return DecoratedBox(
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
                        SizedBox(height: (box.maxHeight * 0.12).clamp(24, 120)),
                        if (view.incognito)
                          const _IncognitoHeader()
                        else
                          const _Logo(),
                        _SearchBox(view: view),
                        const SizedBox(height: 36),
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
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Customize'),
                    onPressed: () => showCustomizePanel(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      children: [
        Image.asset('assets/logo.png', width: 72, height: 72),
        const SizedBox(height: 10),
        Text(
          '6browser',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: DefaultTextStyle.of(context).style.color,
            shadows: DefaultTextStyle.of(context).style.shadows,
          ),
        ),
      ],
    ),
  );
}

class _IncognitoHeader extends StatelessWidget {
  const _IncognitoHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      children: [
        const Icon(Icons.visibility_off, size: 48),
        const SizedBox(height: 12),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Material(
        elevation: 2,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(28),
        color: view.incognito
            ? BrowserColors.incognito.omnibox
            : colors.toolbar,
        child: TextField(
          key: const ValueKey('newtab-search'),
          style: TextStyle(
            fontSize: 16,
            color: view.incognito
                ? BrowserColors.incognito.omniboxText
                : colors.omniboxText,
            shadows: const [],
          ),
          decoration: InputDecoration(
            filled: false,
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Icon(Icons.search, color: scheme.onSurfaceVariant),
            ),
            hintText: engine == null
                ? 'Search or type a URL'
                : 'Search ${engine.name} or type a URL',
            hintStyle: TextStyle(
              color: scheme.onSurfaceVariant,
              shadows: const [],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: (_tileWidth + 8) * 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final (i, t) in tiles.indexed)
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
          if (customCount < maxTiles)
            _AddTile(
              onTap: () async {
                final r = await showShortcutDialog(context);
                if (r != null) await actions.add(r.$1, r.$2);
              },
            ),
        ],
      ),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onOpen,
            child: Stack(
              children: [
                _TileFace(tile: widget.tile, hover: _hover),
                if (_hover)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Builder(
                      builder: (context) => IconButton(
                        tooltip: 'More actions',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert),
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
    return Container(
      width: _tileWidth,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: hover ? colors.ntpText.withValues(alpha: 0.08) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.omnibox,
              shape: BoxShape.circle,
            ),
            child: SiteIcon(url: tile.url, title: tile.title),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Text(
              tile.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.4),
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
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.shade600,
      child: Text(
        letter,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: _tileWidth,
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.add, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            const SizedBox(
              height: 34,
              child: Text('Add shortcut', style: TextStyle(fontSize: 12)),
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
