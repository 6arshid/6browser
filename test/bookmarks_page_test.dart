import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/bookmarks/bookmarks_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searches titles and URLs and clears the filter', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.inMemory();
            ref.onDispose(db.close);
            return db;
          }),
          bookmarksProvider.overrideWith(
            (ref) => Stream.value([
              Bookmark(
                id: 1,
                createdAt: DateTime(2026),
                title: 'Flutter docs',
                url: 'https://flutter.dev',
              ),
              Bookmark(
                id: 2,
                createdAt: DateTime(2026),
                title: 'Language guide',
                url: 'https://dart.dev',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: BookmarksPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), '  FLUTTER DOCS  ');
    await tester.pump();
    expect(find.text('Flutter docs'), findsOneWidget);
    expect(find.text('Language guide'), findsNothing);

    await tester.enterText(find.byType(TextField), 'DART.DEV');
    await tester.pump();
    expect(find.text('Language guide'), findsOneWidget);
    expect(find.text('Flutter docs'), findsNothing);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching bookmarks.'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
