// lib/core/database/app_database.dart
import 'package:drift/drift.dart';
import 'tables/tables.dart';
import 'daos/daos.dart';
import 'connection/connection.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Businesses,
    Categories,
    Products,
    Customers,
    Invoices,
    InvoiceItems,
    SyncQueue,
    AppSettings,
    Expenses,
  ],
  daos: [
    ProductsDao,
    InvoicesDao,
    CustomersDao,
    SyncDao,
    BusinessDao,
    ExpensesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connect());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Insert default business (required fields first, optional use Value)
          await into(businesses).insertOnConflictUpdate(BusinessesCompanion(
            id: const Value('default_business'),
            name: const Value('Mi Negocio'),
            currency: const Value('USD'),
            currencySymbol: const Value('\$'),
            taxRate: const Value(0.0),
            commissionRate: const Value(5.0),
          ));
          // Insert default categories
          const cats = ['General', 'Bebidas', 'Alimentos', 'Electrónica', 'Ropa'];
          for (final cat in cats) {
            await into(categories).insertOnConflictUpdate(CategoriesCompanion(
              id: Value(cat.toLowerCase().replaceAll('é', 'e').replaceAll('ó', 'o')),
              name: Value(cat),
              businessId: const Value('default_business'),
            ));
          }
        },
      );
}
