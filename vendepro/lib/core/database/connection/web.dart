// lib/core/database/connection/web.dart
// Used on Web (dart:js_interop / dart:html available)
// Uses WasmDatabase with sqlite3.wasm bundled in the web/ folder.
// No separate drift worker needed — WasmDatabase auto-detects the best
// available storage backend (OPFS → IndexedDB → in-memory fallback).
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

DatabaseConnection connect() {
  return DatabaseConnection.delayed(Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'vendepro_db',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );

    if (result.missingFeatures.isNotEmpty) {
      // Log which features are unavailable (e.g. OPFS requires a secure context)
      // The database still works using IndexedDB as fallback.
    }

    return result.resolvedExecutor;
  }));
}
