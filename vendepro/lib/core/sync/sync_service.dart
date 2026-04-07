// lib/core/sync/sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import 'package:drift/drift.dart' as drift;

class SyncService {
  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  SyncService(this._db, this._firestore);

  void startListening() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInternet = results.any((r) => r != ConnectivityResult.none);
      if (hasInternet) {
        syncPendingChanges();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Upload all pending local changes to Firestore
  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pending = await _db.syncDao.getPending();
      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      final batch = _firestore.batch();
      final processedIds = <String>[];

      for (final item in pending) {
        try {
          final data = jsonDecode(item.data) as Map<String, dynamic>;
          final ref = _firestore
              .collection('businesses')
              .doc(data['businessId'] ?? 'default_business')
              .collection(item.entity)
              .doc(item.entityId);

          if (item.operation == 'delete') {
            batch.delete(ref);
          } else {
            batch.set(ref, data, SetOptions(merge: true));
          }
          processedIds.add(item.id);
        } catch (e) {
          debugPrint('Sync error for ${item.id}: $e');
        }
      }

      await batch.commit();

      for (final id in processedIds) {
        await _db.syncDao.markProcessed(id);
      }
      await _db.syncDao.clearProcessed();

      // After uploading, pull any new data from cloud
      await pullFromCloud();
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Enqueue a local change for later sync
  Future<void> enqueueChange({
    required String entity,
    required String entityId,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    await _db.syncDao.enqueue(SyncQueueCompanion(
      id: drift.Value('${entity}_${entityId}_${DateTime.now().millisecondsSinceEpoch}'),
      entity: drift.Value(entity),
      entityId: drift.Value(entityId),
      operation: drift.Value(operation),
      data: drift.Value(jsonEncode(data)),
    ));

    // Try to sync immediately if online
    if (await isOnline()) {
      syncPendingChanges();
    }
  }

  /// Pull latest data from Firestore and update local DB
  Future<void> pullFromCloud() async {
    try {
      const businessId = 'default_business'; // TODO: from session
      // Pull products
      final productsSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products')
          .get();

      for (final doc in productsSnap.docs) {
        final data = doc.data();
        await _db.productsDao.upsert(ProductsCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          description: drift.Value(data['description']),
          sku: drift.Value(data['sku']),
          price: drift.Value((data['price'] ?? 0).toDouble()),
          cost: drift.Value((data['cost'] ?? 0).toDouble()),
          stock: drift.Value(data['stock'] ?? 0),
          minStock: drift.Value(data['minStock'] ?? 5),
          categoryId: drift.Value(data['categoryId']),
          businessId: drift.Value(businessId),
          isActive: drift.Value(data['isActive'] ?? true),
        ));
      }

      // Pull invoices
      final invoicesSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('invoices')
          .get();

      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        await _db.invoicesDao.markSynced(doc.id);
        // Additional merge logic as needed
      }
    } catch (e) {
      debugPrint('Pull from cloud failed: $e');
    }
  }
}
