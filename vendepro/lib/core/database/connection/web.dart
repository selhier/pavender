// lib/core/database/connection/web.dart
// Used on Web (dart:html available)
// Drift WebDatabase uses IndexedDB for persistent local storage on web.
import 'package:drift/drift.dart';
import 'package:drift/web.dart';

DatabaseConnection connect() {
  return DatabaseConnection(WebDatabase('vendepro_db', logStatements: false));
}
