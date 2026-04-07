// lib/core/database/connection/unsupported.dart
// Fallback stub for unsupported platforms
import 'package:drift/drift.dart';

DatabaseConnection connect() {
  throw UnsupportedError('Unsupported platform for database connection');
}
