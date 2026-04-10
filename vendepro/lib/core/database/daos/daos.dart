import 'dart:convert';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'daos.g.dart';

Map<String, dynamic> _mapCompanion(UpdateCompanion companion) {
  return companion.toColumns(true).map((key, value) {
    if (value is Variable) {
      final val = value.value;
      if (val is DateTime) {
        return MapEntry(key, val.toIso8601String());
      }
      return MapEntry(key, val);
    }
    return MapEntry(key, null);
  });
}

@DriftAccessor(tables: [Products, Categories])
class ProductsDao extends DatabaseAccessor<AppDatabase> with _$ProductsDaoMixin {
  ProductsDao(super.db);

  Stream<List<Product>> watchAll(String businessId) =>
      (select(products)
            ..where((p) => p.businessId.equals(businessId) & p.isActive.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();

  Future<List<Product>> getLowStock(String businessId) =>
      (select(products)
            ..where((p) =>
                p.businessId.equals(businessId) &
                p.isActive.equals(true))
            ..orderBy([(p) => OrderingTerm.asc(p.stock)]))
          .get()
          .then((rows) => rows.where((p) => p.stock <= p.minStock).toList());

  Future<Product?> getById(String id) =>
      (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ProductsCompanion product) async {
    await into(products).insertOnConflictUpdate(product);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'prod_${product.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'products',
      entityId: product.id.value,
      operation: 'upsert',
      data: jsonEncode(_mapCompanion(product)),
    ));
  }

  Future<List<Category>> getCategories(String businessId) =>
      (select(categories)..where((c) => c.businessId.equals(businessId))).get();

  Future<void> updateStock(String productId, int newStock) =>
      (update(products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(
        stock: Value(newStock),
        updatedAt: Value(DateTime.now()),
      ));

  Stream<List<Product>> searchProducts(String businessId, String query) =>
      (select(products)
            ..where((p) =>
                p.businessId.equals(businessId) &
                p.isActive.equals(true) &
                (p.name.like('%$query%') | p.sku.like('%$query%'))))
          .watch();
}

@DriftAccessor(tables: [Invoices, InvoiceItems, Products])
class InvoicesDao extends DatabaseAccessor<AppDatabase>
    with _$InvoicesDaoMixin {
  InvoicesDao(super.db);

  Stream<List<Invoice>> watchAll(String businessId) =>
      (select(invoices)
            ..where((i) => i.businessId.equals(businessId))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .watch();

  Future<List<InvoiceItem>> getItems(String invoiceId) =>
      (select(invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();

  Future<Invoice?> getById(String id) =>
      (select(invoices)..where((i) => i.id.equals(id))).getSingleOrNull();

  Future<String> insertInvoice(InvoicesCompanion invoice) async {
    final id = await into(invoices).insertReturning(invoice).then((i) => i.id);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'inv_${id}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'invoices',
      entityId: id,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(invoice)..['id'] = id),
    ));
    return id;
  }

  Future<void> upsert(InvoicesCompanion invoice) async {
    await into(invoices).insertOnConflictUpdate(invoice);
  }

  Future<void> upsertItem(InvoiceItemsCompanion item) async {
    await into(invoiceItems).insertOnConflictUpdate(item);
  }

  Future<void> insertItem(InvoiceItemsCompanion item) async {
    await into(invoiceItems).insert(item);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'inv_item_${item.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'invoice_items',
      entityId: item.id.value,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(item)),
    ));
  }

  Future<void> updateStatus(String id, String status) async {
    await (update(invoices)..where((i) => i.id.equals(id)))
          .write(InvoicesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ));
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'inv_status_${id}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'invoices',
      entityId: id,
      operation: 'update',
      data: jsonEncode({'id': id, 'status': status, 'updatedAt': DateTime.now().toIso8601String()}),
    ));
  }

  Future<double> getTotalSales(String businessId,
      {DateTime? from, DateTime? to}) async {
    final query = select(invoices)
      ..where((i) =>
          i.businessId.equals(businessId) &
          i.status.equals('paid'));
    if (from != null) {
      query.where((i) => i.createdAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((i) => i.createdAt.isSmallerOrEqualValue(to));
    }
    final result = await query.get();
    double total = 0.0;
    for (final i in result) { total += i.total; }
    return total;
  }

  Future<List<Invoice>> getByStatus(String businessId, String status) =>
      (select(invoices)
            ..where((i) => i.businessId.equals(businessId) & i.status.equals(status))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .get();

  Future<List<Invoice>> getAll(String businessId) =>
      (select(invoices)
            ..where((i) => i.businessId.equals(businessId))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .get();

  Future<List<Invoice>> getByCustomer(String customerId) =>
      (select(invoices)
            ..where((i) => i.customerId.equals(customerId))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .get();

  Future<List<Invoice>> getByDateRange(String businessId, DateTime start, DateTime end) =>
      (select(invoices)
            ..where((i) => i.businessId.equals(businessId))
            ..where((i) => i.createdAt.isBetweenValues(start, end))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .get();

  Future<void> markSynced(String id) =>
      (update(invoices)..where((i) => i.id.equals(id)))
          .write(const InvoicesCompanion(synced: Value(true)));
}

@DriftAccessor(tables: [Customers])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  Stream<List<Customer>> watchAll(String businessId) =>
      (select(customers)
            ..where((c) => c.businessId.equals(businessId))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<Customer?> getById(String id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> upsert(CustomersCompanion customer) async {
    await into(customers).insertOnConflictUpdate(customer);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'cust_${customer.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'customers',
      entityId: customer.id.value,
      operation: 'upsert',
      data: jsonEncode(_mapCompanion(customer)),
    ));
  }

  Future<List<Customer>> search(String businessId, String query) =>
      (select(customers)
            ..where((c) =>
                c.businessId.equals(businessId) &
                (c.name.like('%$query%') | c.phone.like('%$query%'))))
          .get();
}

@DriftAccessor(tables: [SyncQueue])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<List<SyncQueueData>> getPending() =>
      (select(syncQueue)..where((s) => s.processed.equals(false))).get();

  Future<void> enqueue(SyncQueueCompanion entry) =>
      into(syncQueue).insert(entry);

  Future<void> markProcessed(String id) =>
      (update(syncQueue)..where((s) => s.id.equals(id)))
          .write(const SyncQueueCompanion(processed: Value(true)));

  Future<void> clearProcessed() =>
      (delete(syncQueue)..where((s) => s.processed.equals(true))).go();
}

@DriftAccessor(tables: [Businesses, AppSettings])
class BusinessDao extends DatabaseAccessor<AppDatabase> with _$BusinessDaoMixin {
  BusinessDao(super.db);

  Future<BusinessesData?> getBusiness(String id) =>
      (select(businesses)..where((b) => b.id.equals(id))).getSingleOrNull();

  Stream<BusinessesData?> watchBusiness(String id) =>
      (select(businesses)..where((b) => b.id.equals(id))).watchSingleOrNull();

  Future<List<BusinessesData>> getAllBranches() =>
      select(businesses).get();

  Future<void> upsert(BusinessesCompanion business) async {
    await into(businesses).insertOnConflictUpdate(business);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'biz_${business.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'businesses',
      entityId: business.id.value,
      operation: 'upsert',
      data: jsonEncode(_mapCompanion(business)),
    ));
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(appSettings)
          .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}

@DriftAccessor(tables: [Expenses])
class ExpensesDao extends DatabaseAccessor<AppDatabase> with _$ExpensesDaoMixin {
  ExpensesDao(super.db);

  Stream<List<Expense>> watchAllByBusiness(String businessId) {
    return (select(expenses)
          ..where((e) => e.businessId.equals(businessId))
          ..orderBy([(e) => OrderingTerm(expression: e.date, mode: OrderingMode.desc)]))
        .watch();
  }
  
  Future<List<Expense>> getByDateRange(String businessId, DateTime start, DateTime end) {
    return (select(expenses)
          ..where((e) => e.businessId.equals(businessId))
          ..where((e) => e.date.isBetweenValues(start, end))
          ..orderBy([(e) => OrderingTerm(expression: e.date, mode: OrderingMode.asc)]))
        .get();
  }

  Future<void> upsert(ExpensesCompanion expense) async {
    await into(expenses).insertOnConflictUpdate(expense);
    // Note: Manual enqueuing is NOT done here if we are pulling from cloud 
    // to avoid cycles. DAOs should handle local-to-cloud sync elsewhere 
    // or take a flag. For now, pullFromCloud will use this.
  }

  Future<void> insertExpense(ExpensesCompanion expense) async {
    await into(expenses).insert(expense);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'exp_${expense.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'expenses',
      entityId: expense.id.value,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(expense)),
    ));
  }

  Future<void> updateExpense(ExpensesCompanion expense) async {
    await update(expenses).replace(expense);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'exp_upd_${expense.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'expenses',
      entityId: expense.id.value,
      operation: 'update',
      data: jsonEncode(_mapCompanion(expense)),
    ));
  }

  Future<void> deleteExpense(String id) async {
    await (delete(expenses)..where((e) => e.id.equals(id))).go();
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'exp_del_${id}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'expenses',
      entityId: id,
      operation: 'delete',
      data: jsonEncode({'id': id}),
    ));
  }
}
@DriftAccessor(tables: [NcfSequences])
class NcfDao extends DatabaseAccessor<AppDatabase> with _$NcfDaoMixin {
  NcfDao(super.db);

  Stream<List<NcfSequence>> watchAll(String businessId) =>
      (select(ncfSequences)..where((s) => s.businessId.equals(businessId))).watch();

  Future<void> upsert(NcfSequencesCompanion sequence) async {
    await into(ncfSequences).insertOnConflictUpdate(sequence);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'ncf_${sequence.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'ncf_sequences',
      entityId: sequence.id.value,
      operation: 'upsert',
      data: jsonEncode(_mapCompanion(sequence)),
    ));
  }

  Future<void> deleteSequence(String id) =>
      (delete(ncfSequences)..where((s) => s.id.equals(id))).go();

  Future<String?> getNextNCF(String businessId, String type) async {
    final seq = await (select(ncfSequences)
          ..where((s) =>
              s.businessId.equals(businessId) &
              s.type.equals(type) &
              s.isActive.equals(true)))
        .getSingleOrNull();

    if (seq == null) return null;

    final nextVal = seq.lastUsed + 1;
    if (nextVal > seq.to) return null;

    // Update last used
    await (update(ncfSequences)..where((s) => s.id.equals(seq.id)))
        .write(NcfSequencesCompanion(lastUsed: Value(nextVal)));

    // Format B0100000001
    return '${seq.prefix}${seq.type}${nextVal.toString().padLeft(8, '0')}';
  }
}

@DriftAccessor(tables: [Quotes, QuoteItems])
class QuotesDao extends DatabaseAccessor<AppDatabase> with _$QuotesDaoMixin {
  QuotesDao(super.db);

  Stream<List<Quote>> watchAll(String businessId) =>
      (select(quotes)
            ..where((q) => q.businessId.equals(businessId))
            ..orderBy([(q) => OrderingTerm.desc(q.createdAt)]))
          .watch();

  Future<List<QuoteItem>> getItems(String quoteId) =>
      (select(quoteItems)..where((i) => i.quoteId.equals(quoteId))).get();

  Future<Quote?> getById(String id) =>
      (select(quotes)..where((q) => q.id.equals(id))).getSingleOrNull();

  Future<String> insertQuote(QuotesCompanion quote) async {
    final id = await into(quotes).insertReturning(quote).then((q) => q.id);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'quo_${id}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'quotes',
      entityId: id,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(quote)..['id'] = id),
    ));
    return id;
  }

  Future<void> upsert(QuotesCompanion quote) async {
    await into(quotes).insertOnConflictUpdate(quote);
  }

  Future<void> upsertItem(QuoteItemsCompanion item) async {
    await into(quoteItems).insertOnConflictUpdate(item);
  }

  Future<void> insertItem(QuoteItemsCompanion item) async {
    await into(quoteItems).insert(item);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'quo_item_${item.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'quote_items',
      entityId: item.id.value,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(item)),
    ));
  }

  Future<void> updateStatus(String id, String status) async {
    await (update(quotes)..where((q) => q.id.equals(id)))
          .write(QuotesCompanion(status: Value(status)));
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'quo_status_${id}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'quotes',
      entityId: id,
      operation: 'update',
      data: jsonEncode({'id': id, 'status': status, 'updatedAt': DateTime.now().toIso8601String()}),
    ));
  }
}

@DriftAccessor(tables: [Suppliers])
class SuppliersDao extends DatabaseAccessor<AppDatabase> with _$SuppliersDaoMixin {
  SuppliersDao(super.db);

  Stream<List<Supplier>> watchAll(String businessId) =>
      (select(suppliers)
            ..where((s) => s.businessId.equals(businessId))
            ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .watch();

  Future<void> upsert(SuppliersCompanion supplier) async {
    await into(suppliers).insertOnConflictUpdate(supplier);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'sup_${supplier.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'suppliers',
      entityId: supplier.id.value,
      operation: 'upsert',
      data: jsonEncode(_mapCompanion(supplier)),
    ));
  }

  Future<Supplier?> getById(String id) =>
      (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();
}

@DriftAccessor(tables: [AppUsers])
class AuthDao extends DatabaseAccessor<AppDatabase> with _$AuthDaoMixin {
  AuthDao(super.db);

  Future<AppUser?> login(String email, String passwordHash) =>
      (select(appUsers)
            ..where((u) => u.email.equals(email) & u.passwordHash.equals(passwordHash)))
          .getSingleOrNull();

  Future<void> upsert(AppUsersCompanion user) async {
    await into(appUsers).insertOnConflictUpdate(user);
  }

  Future<void> register(AppUsersCompanion user) async {
    await into(appUsers).insert(user);
    await db.syncDao.enqueue(SyncQueueCompanion.insert(
      id: 'user_${user.id.value}_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'users',
      entityId: user.id.value,
      operation: 'insert',
      data: jsonEncode(_mapCompanion(user)),
    ));
  }
}
