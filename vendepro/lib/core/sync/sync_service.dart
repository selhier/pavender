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
  StreamSubscription? _queueSub;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  SyncService(this._db, this._firestore, this._businessId);

  void startListening() {
    // 1. Listen to connectivity changes: when internet returns, sync immediately
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInternet = results.any((r) => r != ConnectivityResult.none);
      if (hasInternet) {
        debugPrint('[SyncService] Connectivity restored -> syncing pending changes');
        syncPendingChanges();
      }
    });

    // 2. Automatically sync when local changes are enqueued (reactive outbox)
    _queueSub = _db.syncDao.watchPendingCount().listen((pendingCount) {
      if (pendingCount > 0) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
          if (await isOnline()) {
            syncPendingChanges();
          }
        });
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _queueSub?.cancel();
    _debounceTimer?.cancel();
  }

  Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Upload all pending local changes to Firestore with versioning
  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;
    if (!await isOnline()) return;

    _isSyncing = true;
    try {
      final pending = await _db.syncDao.getPending();
      if (pending.isEmpty) {
        _isSyncing = false;
        // Even with no pending uploads, pull any cloud changes
        await pullFromCloud();
        return;
      }

      debugPrint('[SyncService] Uploading ${pending.length} pending local changes...');

      // Process in chunks of 400 (Firestore batch limit is 500)
      const chunkSize = 400;
      for (var i = 0; i < pending.length; i += chunkSize) {
        final chunk = pending.skip(i).take(chunkSize).toList();
        final batch = _firestore.batch();
        final processedIds = <String>[];

        for (final item in chunk) {
          try {
            final data = jsonDecode(item.data) as Map<String, dynamic>;
            final targetBusinessId =
                data['businessId'] ?? data['business_id'] ?? _businessId;
            final businessDoc =
                _firestore.collection('businesses').doc(targetBusinessId);

            // Route sub-collection entities to the correct nested path
            DocumentReference ref;
            if (item.entity == 'invoice_items') {
              final parentId = data['invoiceId'] ?? data['invoice_id'];
              if (parentId == null || parentId.toString().isEmpty) {
                processedIds.add(item.id);
                continue;
              }
              ref = businessDoc
                  .collection('invoices')
                  .doc(parentId.toString())
                  .collection('invoice_items')
                  .doc(item.entityId);
            } else if (item.entity == 'quote_items') {
              final parentId = data['quoteId'] ?? data['quote_id'];
              if (parentId == null || parentId.toString().isEmpty) {
                processedIds.add(item.id);
                continue;
              }
              ref = businessDoc
                  .collection('quotes')
                  .doc(parentId.toString())
                  .collection('quote_items')
                  .doc(item.entityId);
            } else if (item.entity == 'purchase_order_items') {
              final parentId = data['orderId'] ?? data['order_id'];
              if (parentId == null || parentId.toString().isEmpty) {
                processedIds.add(item.id);
                continue;
              }
              ref = businessDoc
                  .collection('purchase_orders')
                  .doc(parentId.toString())
                  .collection('purchase_order_items')
                  .doc(item.entityId);
            } else {
              ref = businessDoc.collection(item.entity).doc(item.entityId);
            }

            if (item.operation == 'delete') {
              batch.delete(ref);
            } else {
              // Ensure updatedAt timestamp is attached to Firestore document for version comparisons
              if (!data.containsKey('updatedAt') || data['updatedAt'] == null) {
                data['updatedAt'] = DateTime.now().toIso8601String();
              }
              batch.set(ref, data, SetOptions(merge: true));
            }
            processedIds.add(item.id);
          } catch (e) {
            debugPrint('[SyncService] Error prepping item ${item.id}: $e');
          }
        }

        await batch.commit();

        for (final id in processedIds) {
          await _db.syncDao.markProcessed(id);
        }
      }

      await _db.syncDao.clearProcessed();
      debugPrint('[SyncService] Pending changes uploaded successfully.');

      // After uploading our local changes, pull latest data from cloud
      await pullFromCloud();
    } catch (e) {
      debugPrint('[SyncService] syncPendingChanges failed: $e');
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
    // Attach current timestamp if not present
    if (!data.containsKey('updatedAt') || data['updatedAt'] == null) {
      data['updatedAt'] = DateTime.now().toIso8601String();
    }
    if (!data.containsKey('businessId') || data['businessId'] == null) {
      data['businessId'] = _businessId;
    }

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

  /// Pull latest data from Firestore and update local DB.
  /// Compares local offline versions with cloud versions:
  /// - If local has pending offline modifications -> Local wins (don't overwrite).
  /// - If local updatedAt > cloud updatedAt -> Local wins (enqueue local to cloud).
  /// - If cloud updatedAt > local updatedAt -> Cloud wins (update local SQLite).
  /// - If new in cloud -> Insert into local SQLite.
  Future<void> pullFromCloud() async {
    try {
      if (!await isOnline()) return;

      final businessId = _businessId;
      final businessRef = _firestore.collection('businesses').doc(businessId);

      debugPrint('[SyncService] Pulling latest data from cloud for business: $businessId');

      // Get all pending change entity IDs so we never overwrite uncommitted offline work
      final pendingProducts = await _db.syncDao.getPendingEntityIds('products');
      final pendingCategories = await _db.syncDao.getPendingEntityIds('categories');
      final pendingCustomers = await _db.syncDao.getPendingEntityIds('customers');
      final pendingSuppliers = await _db.syncDao.getPendingEntityIds('suppliers');
      final pendingExpenses = await _db.syncDao.getPendingEntityIds('expenses');
      final pendingQuotes = await _db.syncDao.getPendingEntityIds('quotes');
      final pendingNcf = await _db.syncDao.getPendingEntityIds('ncf_sequences');
      final pendingSessions = await _db.syncDao.getPendingEntityIds('cash_sessions');
      final pendingPOs = await _db.syncDao.getPendingEntityIds('purchase_orders');

      // 0. Pull Business info
      final businessDocSnap = await businessRef.get();
      if (businessDocSnap.exists) {
        final data = businessDocSnap.data()!;
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final localBiz = await _db.businessDao.getBusiness(businessId);

        if (localBiz == null || cloudUpdated.isAfter(localBiz.updatedAt)) {
          await _db.businessDao.upsert(BusinessesCompanion(
            id: drift.Value(businessId),
            name: drift.Value(data['name'] ?? ''),
            logoPath: drift.Value(data['logoPath']),
            currency: drift.Value(data['currency'] ?? 'USD'),
            currencySymbol: drift.Value(data['currencySymbol'] ?? '\$'),
            taxRate: drift.Value((data['taxRate'] ?? 0.0).toDouble()),
            commissionRate: drift.Value((data['commissionRate'] ?? 5.0).toDouble()),
            address: drift.Value(data['address']),
            phone: drift.Value(data['phone']),
            email: drift.Value(data['email']),
            updatedAt: drift.Value(cloudUpdated),
          ), syncToCloud: false);
        }
      }

      // 0b. Pull Categories (with version comparison)
      final categoriesSnap = await businessRef.collection('categories').get();
      for (final doc in categoriesSnap.docs) {
        final data = doc.data();
        final localCat = await _db.productsDao.getCategoryById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingCategories.contains(doc.id);

        if (localCat != null) {
          if (isPending || localCat.updatedAt.isAfter(cloudUpdated)) {
            // Local is newer or pending -> local wins
            continue;
          }
        }

        await _db.into(_db.categories).insertOnConflictUpdate(CategoriesCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          icon: drift.Value(data['icon'] ?? '📦'),
          color: drift.Value(data['color'] ?? '#6C63FF'),
          businessId: drift.Value(businessId),
          updatedAt: drift.Value(cloudUpdated),
        ));
      }

      // 1. Pull Products (Core Inventory with Version & Conflict Comparison)
      final productsSnap = await businessRef.collection('products').get();
      for (final doc in productsSnap.docs) {
        final data = doc.data();
        final localProduct = await _db.productsDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingProducts.contains(doc.id);

        if (localProduct != null) {
          if (isPending) {
            // Local product has pending offline modifications -> local wins!
            continue;
          }
          if (localProduct.updatedAt.isAfter(cloudUpdated)) {
            // Local product is newer than cloud version -> local wins!
            // Re-enqueue local product so cloud gets the newer data
            await _db.productsDao.upsert(ProductsCompanion(
              id: drift.Value(localProduct.id),
              name: drift.Value(localProduct.name),
              description: drift.Value(localProduct.description),
              sku: drift.Value(localProduct.sku),
              price: drift.Value(localProduct.price),
              cost: drift.Value(localProduct.cost),
              stock: drift.Value(localProduct.stock),
              minStock: drift.Value(localProduct.minStock),
              categoryId: drift.Value(localProduct.categoryId),
              unit: drift.Value(localProduct.unit),
              taxRate: drift.Value(localProduct.taxRate),
              brand: drift.Value(localProduct.brand),
              subCategory: drift.Value(localProduct.subCategory),
              businessId: drift.Value(businessId),
              isActive: drift.Value(localProduct.isActive),
              updatedAt: drift.Value(localProduct.updatedAt),
            ), syncToCloud: true);
            continue;
          }
        }

        // Cloud is newer or new: update local database cleanly
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
          updatedAt: drift.Value(cloudUpdated),
        ), syncToCloud: false);
      }

      // 2. Pull Customers (with version comparison)
      final customersSnap = await businessRef.collection('customers').get();
      for (final doc in customersSnap.docs) {
        final data = doc.data();
        final localCustomer = await _db.customersDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingCustomers.contains(doc.id);

        if (localCustomer != null) {
          if (isPending || localCustomer.updatedAt.isAfter(cloudUpdated)) {
            continue; // Local wins
          }
        }

        await _db.customersDao.upsert(CustomersCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          phone: drift.Value(data['phone']),
          email: drift.Value(data['email']),
          address: drift.Value(data['address']),
          taxId: drift.Value(data['taxId']),
          businessId: drift.Value(businessId),
          updatedAt: drift.Value(cloudUpdated),
        ), syncToCloud: false);
      }

      // 3. Pull Suppliers (with version comparison)
      final suppliersSnap = await businessRef.collection('suppliers').get();
      for (final doc in suppliersSnap.docs) {
        final data = doc.data();
        final localSupplier = await _db.suppliersDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingSuppliers.contains(doc.id);

        if (localSupplier != null) {
          if (isPending || localSupplier.updatedAt.isAfter(cloudUpdated)) {
            continue; // Local wins
          }
        }

        await _db.suppliersDao.upsert(SuppliersCompanion(
          id: drift.Value(doc.id),
          name: drift.Value(data['name'] ?? ''),
          phone: drift.Value(data['phone']),
          email: drift.Value(data['email']),
          address: drift.Value(data['address']),
          rnc: drift.Value(data['rnc'] ?? data['taxId']),
          businessId: drift.Value(businessId),
          updatedAt: drift.Value(cloudUpdated),
        ), syncToCloud: false);
      }

      // 4. Pull Invoices (with version comparison)
      final invoicesSnap = await businessRef.collection('invoices').get();
      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        final localInv = await _db.invoicesDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (localInv != null && localInv.updatedAt.isAfter(cloudUpdated)) {
          continue; // Local invoice is newer
        }

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
          createdAt: drift.Value(DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now()),
          updatedAt: drift.Value(cloudUpdated),
          synced: const drift.Value(true),
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

      // 5. Pull Expenses (with version comparison)
      final expensesSnap = await businessRef.collection('expenses').get();
      for (final doc in expensesSnap.docs) {
        final data = doc.data();
        final localExp = await _db.expensesDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingExpenses.contains(doc.id);

        if (localExp != null) {
          if (isPending || localExp.updatedAt.isAfter(cloudUpdated)) {
            continue; // Local wins
          }
        }

        await _db.expensesDao.upsert(ExpensesCompanion(
          id: drift.Value(doc.id),
          amount: drift.Value((data['amount'] ?? 0).toDouble()),
          description: drift.Value(data['description'] ?? ''),
          category: drift.Value(data['category'] ?? ''),
          date: drift.Value(DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now()),
          businessId: drift.Value(businessId),
          status: drift.Value(data['status'] ?? 'paid'),
          synced: const drift.Value(true),
          updatedAt: drift.Value(cloudUpdated),
        ));
      }

      // 6. Pull Quotes (with version comparison)
      final quotesSnap = await businessRef.collection('quotes').get();
      for (final doc in quotesSnap.docs) {
        final data = doc.data();
        final localQuote = await _db.quotesDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingQuotes.contains(doc.id);

        if (localQuote != null) {
          if (isPending || localQuote.updatedAt.isAfter(cloudUpdated)) {
            continue; // Local wins
          }
        }

        await _db.quotesDao.upsert(QuotesCompanion(
          id: drift.Value(doc.id),
          quoteNumber: drift.Value(data['quoteNumber'] ?? ''),
          customerName: drift.Value(data['customerName'] ?? 'Cliente general'),
          status: drift.Value(data['status'] ?? 'pending'),
          total: drift.Value((data['total'] ?? 0).toDouble()),
          businessId: drift.Value(businessId),
          createdAt: drift.Value(DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now()),
          updatedAt: drift.Value(cloudUpdated),
        ));

        final qItemsSnap = await doc.reference.collection('quote_items').get();
        for (final itemDoc in qItemsSnap.docs) {
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

      // 7. Pull NCF Sequences (coordinated high-water mark for lastUsed)
      final ncfSnap = await businessRef.collection('ncf_sequences').get();
      for (final doc in ncfSnap.docs) {
        final data = doc.data();
        final localNcf = await _db.ncfDao.getById(doc.id);
        final cloudLastUsed = (data['lastUsed'] ?? 0) as int;
        final isPending = pendingNcf.contains(doc.id);

        int finalLastUsed = cloudLastUsed;
        if (localNcf != null) {
          // Never roll back lastUsed to avoid duplicate invoice tax numbers
          if (localNcf.lastUsed > finalLastUsed) {
            finalLastUsed = localNcf.lastUsed;
          }
          if (isPending && localNcf.lastUsed >= cloudLastUsed) {
            continue;
          }
        }

        await _db.ncfDao.upsert(NcfSequencesCompanion(
          id: drift.Value(doc.id),
          type: drift.Value(data['type'] ?? ''),
          prefix: drift.Value(data['prefix'] ?? 'B'),
          from: drift.Value(data['from'] ?? 1),
          to: drift.Value(data['to'] ?? 9999),
          lastUsed: drift.Value(finalLastUsed),
          businessId: drift.Value(businessId),
          isActive: drift.Value(data['isActive'] ?? true),
          updatedAt: drift.Value(DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now()),
        ), syncToCloud: false);
      }

      // 8. Pull Users
      final usersSnap = await businessRef.collection('users').get();
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

      // 9. Pull Cash Sessions (with version comparison)
      final cashSessionsSnap = await businessRef.collection('cash_sessions').get();
      for (final doc in cashSessionsSnap.docs) {
        final data = doc.data();
        final localSession = await _db.cashSessionsDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['openedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingSessions.contains(doc.id);

        if (localSession != null) {
          if (isPending || localSession.updatedAt.isAfter(cloudUpdated)) {
            continue;
          }
        }

        await _db.into(_db.cashSessions).insertOnConflictUpdate(CashSessionsCompanion(
          id: drift.Value(doc.id),
          businessId: drift.Value(businessId),
          cashierId: drift.Value(data['cashierId'] ?? ''),
          openedAt: drift.Value(DateTime.tryParse(data['openedAt']?.toString() ?? '') ?? DateTime.now()),
          closedAt: drift.Value(data['closedAt'] != null ? DateTime.tryParse(data['closedAt'].toString()) : null),
          startingCash: drift.Value((data['startingCash'] ?? 0).toDouble()),
          calculatedEndingCash: drift.Value(data['calculatedEndingCash'] != null ? (data['calculatedEndingCash'] as num).toDouble() : null),
          actualEndingCash: drift.Value(data['actualEndingCash'] != null ? (data['actualEndingCash'] as num).toDouble() : null),
          difference: drift.Value(data['difference'] != null ? (data['difference'] as num).toDouble() : null),
          notes: drift.Value(data['notes']),
          status: drift.Value(data['status'] ?? 'open'),
          updatedAt: drift.Value(cloudUpdated),
        ));
      }

      // 10. Pull Invoice Payments
      final paymentsSnap = await businessRef.collection('invoice_payments').get();
      for (final doc in paymentsSnap.docs) {
        final data = doc.data();
        await _db.into(_db.invoicePayments).insertOnConflictUpdate(InvoicePaymentsCompanion(
          id: drift.Value(doc.id),
          invoiceId: drift.Value(data['invoiceId'] ?? ''),
          businessId: drift.Value(businessId),
          amount: drift.Value((data['amount'] ?? 0).toDouble()),
          method: drift.Value(data['method'] ?? 'cash'),
          notes: drift.Value(data['notes']),
          paidAt: drift.Value(DateTime.tryParse(data['paidAt']?.toString() ?? '') ?? DateTime.now()),
        ));
      }

      // 11. Pull Purchase Orders (with version comparison)
      final poSnap = await businessRef.collection('purchase_orders').get();
      for (final doc in poSnap.docs) {
        final data = doc.data();
        final localPO = await _db.purchaseOrdersDao.getById(doc.id);
        final cloudUpdated = DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final isPending = pendingPOs.contains(doc.id);

        if (localPO != null) {
          if (isPending || localPO.updatedAt.isAfter(cloudUpdated)) {
            continue;
          }
        }

        await _db.into(_db.purchaseOrders).insertOnConflictUpdate(PurchaseOrdersCompanion(
          id: drift.Value(doc.id),
          businessId: drift.Value(businessId),
          supplierId: drift.Value(data['supplierId']),
          supplierName: drift.Value(data['supplierName'] ?? ''),
          status: drift.Value(data['status'] ?? 'draft'),
          total: drift.Value((data['total'] ?? 0).toDouble()),
          notes: drift.Value(data['notes']),
          expectedDate: drift.Value(data['expectedDate'] != null ? DateTime.tryParse(data['expectedDate'].toString()) : null),
          createdAt: drift.Value(DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now()),
          updatedAt: drift.Value(cloudUpdated),
        ));

        final poItemsSnap = await doc.reference.collection('purchase_order_items').get();
        for (final itemDoc in poItemsSnap.docs) {
          final itemData = itemDoc.data();
          await _db.into(_db.purchaseOrderItems).insertOnConflictUpdate(PurchaseOrderItemsCompanion(
            id: drift.Value(itemDoc.id),
            orderId: drift.Value(doc.id),
            productId: drift.Value(itemData['productId']),
            productName: drift.Value(itemData['productName'] ?? ''),
            quantity: drift.Value(itemData['quantity'] ?? 1),
            unitCost: drift.Value((itemData['unitCost'] ?? 0).toDouble()),
            subtotal: drift.Value((itemData['subtotal'] ?? 0).toDouble()),
          ));
        }
      }

      debugPrint('[SyncService] Pull completed successfully for $businessId');
    } catch (e) {
      debugPrint('[SyncService] Pull from cloud failed: $e');
    }
  }
}
