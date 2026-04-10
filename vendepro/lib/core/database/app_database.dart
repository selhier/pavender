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
    NcfSequences,
    Quotes,
    QuoteItems,
    Suppliers,
    AppUsers,
  ],
  daos: [
    ProductsDao,
    InvoicesDao,
    CustomersDao,
    SyncDao,
    BusinessDao,
    ExpensesDao,
    NcfDao,
    QuotesDao,
    SuppliersDao,
    AuthDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connect());

  @override
  int get schemaVersion => 6;

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
            taxRate: const Value(18.0),
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
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Add expenses table created in version 2
            await m.createTable(expenses);
          }
          if (from < 3) {
            // Add NCF support columns and sequences table
            await m.addColumn(invoices, invoices.ncf);
            await m.addColumn(invoices, invoices.ncfType);
            await m.createTable(ncfSequences);
          }
          if (from < 4) {
            // Add customer tax ID column for invoices
            await m.addColumn(invoices, invoices.customerTaxId);
          }
          if (from < 5) {
            // Add taxRate to products and taxAmount to invoiceItems
            await m.addColumn(products, products.taxRate);
            await m.addColumn(invoiceItems, invoiceItems.taxAmount);
          }
          if (from < 6) {
            // New tables for Quotes, Suppliers, Users
            await m.createTable(quotes);
            await m.createTable(quoteItems);
            await m.createTable(suppliers);
            await m.createTable(appUsers);
            // New columns in Products (brand, subcategory) and Invoices (currency, rate)
            await m.addColumn(products, products.brand);
            await m.addColumn(products, products.subCategory);
            await m.addColumn(invoices, invoices.currency);
            await m.addColumn(invoices, invoices.exchangeRate);
            await m.addColumn(expenses, expenses.supplierId);
          }
        },
      );
}
