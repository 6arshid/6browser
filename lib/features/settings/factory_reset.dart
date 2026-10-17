import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';

final factoryResetProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    if (Platform.isAndroid) {
      await const MethodChannel('6browser/app')
          .invokeMethod<void>('factoryReset');
      return;
    }
    final support = await getApplicationSupportDirectory();
    await FactoryResetStore(support).schedule();
    await ref.read(databaseProvider).close();
    // End the process to release every CEF profile handle. Calling CefShutdown
    // while browser views are still alive is unsafe. Startup removes the profile
    // before CEF can read it again.
    exit(0);
  };
});

/// Only application-owned data is removed. The marker survives partial failures
/// so startup retries before opening either SQLite or the browser engine.
class FactoryResetStore {
  FactoryResetStore(this.support);

  final Directory support;
  File get marker => File(p.join(support.path, 'factory-reset.pending'));

  Future<void> schedule() async {
    await support.create(recursive: true);
    await marker.writeAsString('1', flush: true);
  }

  Future<void> applyPending() async {
    if (!await marker.exists()) return;
    for (final name in [
      '6browser.sqlite',
      '6browser.sqlite-wal',
      '6browser.sqlite-shm',
      '6browser.sqlite-journal',
      'themes',
      'cef_profile',
    ]) {
      final target = p.join(support.path, name);
      final type = await FileSystemEntity.type(target, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          await Directory(target).delete(recursive: true);
        case FileSystemEntityType.link:
          await Link(target).delete();
        case FileSystemEntityType.file:
          await File(target).delete();
        default:
          break;
      }
    }
    await marker.delete();
  }
}
