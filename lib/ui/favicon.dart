import 'package:flutter/material.dart';

import '../features/tabs/url_input.dart';

/// Small site icon for tabs, menus and the bookmarks bar: the site's
/// `/favicon.ico`, a globe when it has none, the app logo on New Tab.
class Favicon extends StatelessWidget {
  const Favicon({super.key, required this.url, this.size = 16, this.color});

  final String url;
  final double size;

  /// Color of the fallback globe.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (isNewTabUrl(url)) {
      return Image.asset('assets/logo.png', width: size, height: size);
    }
    final globe = Icon(Icons.public, size: size, color: color);
    final uri = Uri.tryParse(url);
    if (uri == null || !isBookmarkable(url) || uri.host.isEmpty) return globe;
    return Image.network(
      '${uri.origin}/favicon.ico',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => globe,
      frameBuilder: (_, child, frame, sync) =>
          frame == null && !sync ? globe : child,
    );
  }
}
