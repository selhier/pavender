// lib/core/database/connection/connection.dart
// This file uses conditional imports to pick the right DB connection
// for web vs mobile/desktop.
import 'package:drift/drift.dart';

export 'unsupported.dart'
    if (dart.library.ffi) 'native.dart'
    if (dart.library.html) 'web.dart';
