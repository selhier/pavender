// lib/core/providers/providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../sync/sync_service.dart';

// Database
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// Firestore
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// Sync Service
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final firestore = ref.watch(firestoreProvider);
  final service = SyncService(db, firestore);
  service.startListening();
  ref.onDispose(service.dispose);
  return service;
});

// Current business ID (could come from auth/login in real app)
final currentBusinessIdProvider = StateProvider<String>((ref) => 'default_business');

// Products stream
final productsStreamProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  return db.productsDao.watchAll(bId);
});

// Low stock products
final lowStockProvider = FutureProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  return db.productsDao.getLowStock(bId);
});

// Invoices stream
final invoicesStreamProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  return db.invoicesDao.watchAll(bId);
});

// Customers stream
final customersStreamProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  return db.customersDao.watchAll(bId);
});

// Business info
final businessProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  return db.businessDao.watchBusiness(bId);
});

// Total sales today
final salesTodayProvider = FutureProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);
  return db.invoicesDao.getTotalSales(bId, from: startOfDay);
});

// Total sales this month
final salesMonthProvider = FutureProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final bId = ref.watch(currentBusinessIdProvider);
  final today = DateTime.now();
  final startOfMonth = DateTime(today.year, today.month, 1);
  return db.invoicesDao.getTotalSales(bId, from: startOfMonth);
});

// Theme mode preference
final themeModeProvider = StateProvider<bool>((ref) => true); // true = dark
