// lib/core/database/daos/daos.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'daos.g.dart';

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

  Future<void> upsert(ProductsCompanion product) =>
      into(products).insertOnConflictUpdate(product);

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

  Future<String> insertInvoice(InvoicesCompanion invoice) =>
      into(invoices).insertReturning(invoice).then((i) => i.id);

  Future<void> insertItem(InvoiceItemsCompanion item) =>
      into(invoiceItems).insert(item);

  Future<void> updateStatus(String id, String status) =>
      (update(invoices)..where((i) => i.id.equals(id)))
          .write(InvoicesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ));

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

  Future<void> upsert(CustomersCompanion customer) =>
      into(customers).insertOnConflictUpdate(customer);

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

  Future<void> upsert(BusinessesCompanion business) =>
      into(businesses).insertOnConflictUpdate(business);

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(appSettings)
          .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
