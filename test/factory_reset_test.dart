import 'dart:io';

import 'package:browser6/features/settings/factory_reset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late FactoryResetStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('6browser-reset-test-');
    store = FactoryResetStore(root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('does not change data without a pending reset', () async {
    final db = await File(p.join(root.path, '6browser.sqlite'))
        .writeAsString('data');
    await store.applyPending();
    expect(await db.readAsString(), 'data');
  });

  test(
    'removes the complete owned profile and retains downloaded files',
    () async {
      for (final name in [
        '6browser.sqlite',
        '6browser.sqlite-wal',
        '6browser.sqlite-shm',
        '6browser.sqlite-journal',
        'themes/old/theme.json',
        'cef_profile/Default/Cookies',
        'cef_profile/Default/Local Storage/site',
      ]) {
        await File(p.join(root.path, name)).create(recursive: true);
      }
      final download = await File(p.join(root.path, 'report.pdf'))
          .writeAsString('keep');
      await store.schedule();
      expect(await store.marker.exists(), isTrue);
      await store.applyPending();
      expect((await root.list().toList()).map((e) => p.basename(e.path)), [
        'report.pdf',
      ]);
      expect(await download.readAsString(), 'keep');
      await store.applyPending();
      expect(await download.exists(), isTrue);
    },
  );
}
