// Fictional web pages for the store screenshots (the engine is faked, so
// the page area is drawn here). All sites use reserved example domains.
import 'package:flutter/material.dart';

String mockTitle(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return '';
  return switch (u.host) {
    'news.example.com' when u.path.contains('fastest') =>
      'The fastest browsers of 2026, tested',
    'news.example.com' => 'Example News',
    'travel.example.org' when u.path.contains('kyoto') =>
      'Kyoto in 3 days — Wander',
    'travel.example.org' => 'Wander — Travel guides',
    'recipes.example.net' when u.path.contains('pasta') =>
      'Lemon garlic pasta in 15 minutes',
    'recipes.example.net' => 'Fresh Kitchen Recipes',
    'shop.example.net' => 'Example Shop — Headphones',
    'docs.example.com' => 'Getting started — Example Docs',
    'music.example.com' => 'Example Music',
    _ => u.host,
  };
}

class MockPage extends StatelessWidget {
  const MockPage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = Uri.tryParse(url);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = switch (u?.host) {
      'news.example.com' => const _Article(),
      'travel.example.org' => const _Travel(),
      'recipes.example.net' => const _Recipe(),
      'shop.example.net' => const _Shop(),
      'docs.example.com' => const _Docs(),
      'music.example.com' => const _Music(),
      _ => const SizedBox(),
    };
    final bg = dark ? const Color(0xFF16181D) : Colors.white;
    final fg = dark ? const Color(0xFFE6E6EA) : const Color(0xFF1C1C22);
    return ColoredBox(
      color: bg,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg, fontSize: 15, height: 1.5),
        child: _Palette(
          dark: dark,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: page,
            ),
          ),
        ),
      ),
    );
  }
}

class _Palette extends InheritedWidget {
  const _Palette({required this.dark, required super.child});
  final bool dark;
  static bool of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_Palette>()!.dark;
  @override
  bool updateShouldNotify(_Palette old) => old.dark != dark;
}

Color _muted(BuildContext c) =>
    _Palette.of(c) ? const Color(0xFF9A9CA6) : const Color(0xFF666873);
Color _card(BuildContext c) =>
    _Palette.of(c) ? const Color(0xFF22252C) : const Color(0xFFF3F4F7);

bool _wide(BuildContext c) => MediaQuery.sizeOf(c).width >= 720;

class _Header extends StatelessWidget {
  const _Header(this.brand, this.color, this.links, {this.icon});
  final String brand;
  final Color color;
  final List<String> links;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _muted(context).withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.circle, color: color, size: 26),
          const SizedBox(width: 8),
          Text(
            brand,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          if (wide)
            for (final l in links)
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
              )
          else
            Icon(Icons.menu, color: _muted(context)),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(this.colors, this.icon, {this.height = 220});
  final List<Color> colors;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -30,
          bottom: -40,
          child: Icon(icon, size: height * 0.95, color: Colors.white24),
        ),
        Center(child: Icon(icon, size: height * 0.38, color: Colors.white)),
      ],
    ),
  );
}

Widget _body(BuildContext context, List<Widget> children) {
  final wide = _wide(context);
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, wide ? 32 : 18, wide ? 32 : 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

class _Article extends StatelessWidget {
  const _Article();

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    return Column(
      children: [
        const _Header('Example News', Color(0xFFD32F2F), [
          'World', 'Tech', 'Science', 'Culture', 'Sports',
        ], icon: Icons.newspaper),
        _body(context, [
          const Text(
            'TECHNOLOGY',
            style: TextStyle(
              color: Color(0xFFD32F2F),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The fastest browsers of 2026, tested',
            style: TextStyle(
              fontSize: wide ? 40 : 27,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We loaded 500 popular pages on five devices. Lean browsers that '
            'skip the bloat came out on top.',
            style: TextStyle(fontSize: wide ? 19 : 16, color: _muted(context)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFFFCDD2),
                child: Text('AL', style: TextStyle(fontSize: 11, color: Color(0xFFB71C1C))),
              ),
              const SizedBox(width: 10),
              Text(
                'Alex Lane · 6 min read',
                style: TextStyle(fontSize: 13, color: _muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Hero(
            const [Color(0xFFFF7043), Color(0xFFD32F2F)],
            Icons.speed_rounded,
            height: wide ? 300 : 190,
          ),
          const SizedBox(height: 20),
          const Text(
            'Speed is the feature people notice first. A browser that opens '
            'instantly, renders pages without stutter and stays out of the way '
            'makes the whole web feel faster. In our tests, the browsers that '
            'did best were the ones that did less: no extra toolbars, no '
            'background services, just a modern engine and a clean interface.',
          ),
          const SizedBox(height: 14),
          const Text(
            'Startup time, memory use and page load time were measured on '
            'every device. Tabs, history and bookmarks were kept the same.',
          ),
        ]),
      ],
    );
  }
}

class _Travel extends StatelessWidget {
  const _Travel();

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    Widget card(String t, String s, List<Color> c, IconData i) => Container(
      decoration: BoxDecoration(
        color: _card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(c, i, height: wide ? 150 : 110),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(s, style: TextStyle(fontSize: 13, color: _muted(context))),
              ],
            ),
          ),
        ],
      ),
    );
    final cards = [
      card('Fushimi Inari', 'Day 1 · Sunrise hike', const [Color(0xFFFF8A65), Color(0xFFE53935)], Icons.temple_buddhist),
      card('Arashiyama', 'Day 2 · Bamboo grove', const [Color(0xFF81C784), Color(0xFF2E7D32)], Icons.forest),
      card('Gion at night', 'Day 3 · Old town', const [Color(0xFF7986CB), Color(0xFF283593)], Icons.nightlife),
    ];
    return Column(
      children: [
        const _Header('Wander', Color(0xFF00897B), [
          'Destinations', 'Guides', 'Deals', 'Sign in',
        ], icon: Icons.explore),
        _body(context, [
          _Hero(
            const [Color(0xFF4DB6AC), Color(0xFF00695C)],
            Icons.landscape_rounded,
            height: wide ? 260 : 180,
          ),
          const SizedBox(height: 18),
          Text(
            'Kyoto in 3 days',
            style: TextStyle(
              fontSize: wide ? 38 : 28,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Temples, tea houses and quiet gardens: a relaxed plan for your first visit.',
            style: TextStyle(color: _muted(context)),
          ),
          const SizedBox(height: 18),
          if (wide)
            Row(
              children: [
                for (final c in cards) ...[
                  Expanded(child: c),
                  if (c != cards.last) const SizedBox(width: 16),
                ],
              ],
            )
          else ...[
            cards[0],
            const SizedBox(height: 12),
            cards[1],
          ],
        ]),
      ],
    );
  }
}

class _Recipe extends StatelessWidget {
  const _Recipe();

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    Widget chip(IconData i, String s) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _card(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 16, color: const Color(0xFFF9A825)),
          const SizedBox(width: 6),
          Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    final ingredients = [
      '250 g spaghetti',
      '3 cloves garlic, sliced',
      '1 lemon, zest and juice',
      '40 g parmesan, grated',
      'Fresh parsley and black pepper',
    ];
    return Column(
      children: [
        const _Header('Fresh Kitchen', Color(0xFFF9A825), [
          'Recipes', 'Quick meals', 'Vegetarian', 'Saved',
        ], icon: Icons.restaurant),
        _body(context, [
          _Hero(
            const [Color(0xFFFFD54F), Color(0xFFF57F17)],
            Icons.ramen_dining,
            height: wide ? 260 : 180,
          ),
          const SizedBox(height: 18),
          Text(
            'Lemon garlic pasta in 15 minutes',
            style: TextStyle(
              fontSize: wide ? 36 : 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(Icons.timer_outlined, '15 min'),
              chip(Icons.people_outline, '2 servings'),
              chip(Icons.star_rounded, '4.9'),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Ingredients', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final i in ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFFF9A825)),
                  const SizedBox(width: 10),
                  Text(i),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

class _Shop extends StatelessWidget {
  const _Shop();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('Example Shop', Color(0xFF6A1B9A), ['Deals', 'Audio', 'Cart'], icon: Icons.shopping_bag),
      _body(context, [
        const _Hero([Color(0xFFBA68C8), Color(0xFF4A148C)], Icons.headphones, height: 220),
        const SizedBox(height: 16),
        const Text('Studio Wireless Headphones', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const Text('\$129', style: TextStyle(fontSize: 22, color: Color(0xFF6A1B9A), fontWeight: FontWeight.w700)),
      ]),
    ],
  );
}

class _Docs extends StatelessWidget {
  const _Docs();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('Example Docs', Color(0xFF1565C0), ['Guides', 'API', 'Blog'], icon: Icons.menu_book),
      _body(context, [
        const Text('Getting started', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('Install the toolkit and create your first project in a few minutes.'),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF1E2230), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            '\$ example init my-app\n\$ cd my-app && example run',
            style: TextStyle(fontFamily: 'monospace', color: Color(0xFF9CDCFE)),
          ),
        ),
      ]),
    ],
  );
}

class _Music extends StatelessWidget {
  const _Music();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _Header('Example Music', Color(0xFF2E7D32), ['Home', 'Library'], icon: Icons.music_note),
      _body(context, [
        const _Hero([Color(0xFF66BB6A), Color(0xFF1B5E20)], Icons.album, height: 220),
        const SizedBox(height: 16),
        const Text('Morning Focus', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      ]),
    ],
  );
}
