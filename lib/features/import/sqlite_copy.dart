import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Opens [sourcePath] as a read-only SQLite database and runs [fn].
///
/// Browsers keep their SQLite files locked while running, so we copy the file
/// (and its `-wal`/`-shm` sidecars, if present) to a temp directory first, open
/// the copy, and delete it afterwards.
T withSqliteCopy<T>(String sourcePath, T Function(Database db) fn) {
  final tmpDir = Directory.systemTemp.createTempSync('6b_import_');
  final target = p.join(tmpDir.path, p.basename(sourcePath));
  Database? db;
  try {
    File(sourcePath).copySync(target);
    for (final suffix in const ['-wal', '-shm']) {
      final side = File('$sourcePath$suffix');
      if (side.existsSync()) side.copySync('$target$suffix');
    }
    db = sqlite3.open(target, mode: OpenMode.readOnly);
    return fn(db);
  } finally {
    db?.close();
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
