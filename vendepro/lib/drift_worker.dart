// lib/drift_worker.dart
// This file is compiled to drift_worker.dart.js by Flutter's web build.
// It enables Drift's WasmDatabase to use a dedicated web worker for SQLite,
// which allows better storage backend support (OPFS with shared-access mode).
import 'package:drift/wasm.dart';

void main() {
  WasmDatabase.workerMainForOpen();
}
