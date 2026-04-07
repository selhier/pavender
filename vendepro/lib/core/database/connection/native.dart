// lib/core/database/connection/native.dart
// Used on Android, iOS, Desktop (dart:ffi available)
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqlite3/sqlite3.dart';

DatabaseConnection connect() {
  return DatabaseConnection.delayed(Future(() async {
    // Apply recommended SQLite options on Android
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      final cachebase = (await getTemporaryDirectory()).path;
      sqlite3.tempDirectory = cachebase;
    }

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vendepro.db'));
    return DatabaseConnection(NativeDatabase.createInBackground(file));
  }));
}
