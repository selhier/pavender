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
  final String _businessId;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  SyncService(this._db, this._firestore, this._businessId);

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
              .doc(data['businessId'] ?? _businessId)
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
      final businessId = _businessId;
      // 1. Pull products
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
          unit: drift.Value(data['unit'] ?? 'unidad'),
          taxRate: drift.Value((data['taxRate'] ?? 0.18).toDouble()),
          brand: drift.Value(data['brand']),
          subCategory: drift.Value(data['subCategory']),
          businessId: drift.Value(businessId),
          isActive: drift.Value(data['isActive'] ?? true),
          updatedAt: drift.Value(DateTime.tryParse(data['updatedAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // 2. Pull Customers
      final customersSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('customers')
          .get();
      for (final doc in customersSnap.docs) {
        final data = doc.data();
        await _db.customersDao.upsert(CustomersCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          phone: drift.Value(data['phone']),
          email: drift.Value(data['email']),
          address: drift.Value(data['address']),
          taxId: drift.Value(data['taxId']),
          businessId: drift.Value(businessId),
          updatedAt: drift.Value(DateTime.tryParse(data['updatedAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // 3. Pull Suppliers
      final suppliersSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('suppliers')
          .get();
      for (final doc in suppliersSnap.docs) {
        final data = doc.data();
        await _db.suppliersDao.upsert(SuppliersCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          phone: drift.Value(data['phone']),
          email: drift.Value(data['email']),
          address: drift.Value(data['address']),
          rnc: drift.Value(data['rnc'] ?? data['taxId']),
          businessId: drift.Value(businessId),
        ));
      }

      // 4. Pull invoices
      final invoicesSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('invoices')
          .get();

      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        await _db.invoicesDao.upsert(InvoicesCompanion(
          id: drift.Value(doc.id),
          invoiceNumber: drift.Value(data['invoiceNumber'] ?? ''),
          ncf: drift.Value(data['ncf']),
          ncfType: drift.Value(data['ncfType']),
          customerName: drift.Value(data['customerName'] ?? 'Cliente general'),
          status: drift.Value(data['status'] ?? 'paid'),
          subtotal: drift.Value((data['subtotal'] ?? 0).toDouble()),
          taxAmount: drift.Value((data['taxAmount'] ?? 0).toDouble()),
          total: drift.Value((data['total'] ?? 0).toDouble()),
          paymentMethod: drift.Value(data['paymentMethod'] ?? 'cash'),
          currency: drift.Value(data['currency'] ?? 'DOP'),
          exchangeRate: drift.Value((data['exchangeRate'] ?? 1.0).toDouble()),
          businessId: drift.Value(businessId),
          createdAt: drift.Value(DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now()),
        ));

        // Pull Invoice Items
        final itemsSnap = await doc.reference.collection('invoice_items').get();
        for (final itemDoc in itemsSnap.docs) {
          final itemData = itemDoc.data();
          await _db.invoicesDao.upsertItem(InvoiceItemsCompanion(
            id: drift.Value(itemDoc.id),
            invoiceId: drift.Value(doc.id),
            productId: drift.Value(itemData['productId'] ?? ''),
            productName: drift.Value(itemData['productName'] ?? ''),
            unitPrice: drift.Value((itemData['unitPrice'] ?? 0).toDouble()),
            quantity: drift.Value(itemData['quantity'] ?? 1),
            taxAmount: drift.Value((itemData['taxAmount'] ?? 0).toDouble()),
            subtotal: drift.Value((itemData['subtotal'] ?? 0).toDouble()),
          ));
        }
      }

      // 5. Pull expenses
      final expensesSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('expenses')
          .get();

      for (final doc in expensesSnap.docs) {
        final data = doc.data();
        await _db.expensesDao.upsert(ExpensesCompanion(
          id: drift.Value(doc.id),
          amount: drift.Value((data['amount'] ?? 0).toDouble()),
          description: drift.Value(data['description'] ?? ''),
          category: drift.Value(data['category'] ?? ''),
          date: drift.Value(DateTime.tryParse(data['date'] ?? '') ?? DateTime.now()),
          businessId: drift.Value(businessId),
          status: drift.Value(data['status'] ?? 'paid'),
          synced: const drift.Value(true),
        ));
      }

      // 6. Pull Quotes
      final quotesSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('quotes')
          .get();
      for (final doc in quotesSnap.docs) {
        final data = doc.data();
        await _db.quotesDao.upsert(QuotesCompanion(
          id: drift.Value(doc.id),
          quoteNumber: drift.Value(data['quoteNumber'] ?? ''),
          customerName: drift.Value(data['customerName'] ?? 'Cliente general'),
          status: drift.Value(data['status'] ?? 'pending'),
          total: drift.Value((data['total'] ?? 0).toDouble()),
          businessId: drift.Value(businessId),
          createdAt: drift.Value(DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now()),
        ));

        // Pull Quote Items
        final itemsSnap = await doc.reference.collection('quote_items').get();
        for (final itemDoc in itemsSnap.docs) {
          final itemData = itemDoc.data();
          await _db.quotesDao.upsertItem(QuoteItemsCompanion(
            id: drift.Value(itemDoc.id),
            quoteId: drift.Value(doc.id),
            productId: drift.Value(itemData['productId'] ?? ''),
            productName: drift.Value(itemData['productName'] ?? ''),
            unitPrice: drift.Value((itemData['unitPrice'] ?? 0).toDouble()),
            quantity: drift.Value(itemData['quantity'] ?? 1),
            taxAmount: drift.Value((itemData['taxAmount'] ?? 0).toDouble()),
            subtotal: drift.Value((itemData['subtotal'] ?? 0).toDouble()),
          ));
        }
      }

      // 7. Pull NCF Sequences
      final ncfSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('ncf_sequences')
          .get();
      for (final doc in ncfSnap.docs) {
        final data = doc.data();
        await _db.ncfDao.upsert(NcfSequencesCompanion(
          id: drift.Value(doc.id),
          type: drift.Value(data['type'] ?? ''),
          prefix: drift.Value(data['prefix'] ?? 'B'),
          from: drift.Value(data['from'] ?? 1),
          to: drift.Value(data['to'] ?? 9999),
          lastUsed: drift.Value(data['lastUsed'] ?? 0),
          businessId: drift.Value(businessId),
          isActive: drift.Value(data['isActive'] ?? true),
        ));
      }

      // 8. Pull Users (Admin created)
      final usersSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('users')
          .get();
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        await _db.authDao.upsert(AppUsersCompanion(
          id: drift.Value(doc.id),
          email: drift.Value(data['email'] ?? ''),
          passwordHash: drift.Value(data['passwordHash'] ?? ''),
          role: drift.Value(data['role'] ?? 'cashier'),
          businessId: drift.Value(businessId),
        ));
      }
    } catch (e) {
      debugPrint('Pull from cloud failed: $e');
    }
  }
}
