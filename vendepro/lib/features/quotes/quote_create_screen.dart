// lib/features/quotes/quote_create_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';

class QuoteCreateScreen extends ConsumerStatefulWidget {
  const QuoteCreateScreen({super.key});

  @override
  ConsumerState<QuoteCreateScreen> createState() => _QuoteCreateScreenState();
}

class _QuoteCreateScreenState extends ConsumerState<QuoteCreateScreen> {
  final List<_CartItem> _cart = [];
  Customer? _selectedCustomer;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.subtotal);
  double get _taxAmount => _cart.fold(0, (sum, item) => sum + (item.subtotal * item.taxRate));
  double get _total => _subtotal + _taxAmount;

  void _addToCart(Product p) {
    setState(() {
      final idx = _cart.indexWhere((item) => item.productId == p.id);
      if (idx >= 0) {
        _cart[idx].quantity++;
      } else {
        _cart.add(_CartItem(
          productId: p.id,
          name: p.name,
          unitPrice: p.price,
          taxRate: p.taxRate,
          quantity: 1,
        ));
      }
    });
  }

  Future<void> _saveQuote() async {
    if (_cart.isEmpty) return;
    setState(() => _isSaving = true);
    
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final quoteId = const Uuid().v4();
    final quoteNum = 'COT-${DateFormat('Hm').format(DateTime.now())}${_cart.length}';

    try {
      await db.quotesDao.insertQuote(QuotesCompanion(
        id: drift.Value(quoteId),
        quoteNumber: drift.Value(quoteNum),
        customerId: drift.Value(_selectedCustomer?.id),
        customerName: drift.Value(_selectedCustomer?.name ?? 'Cliente general'),
        subtotal: drift.Value(_subtotal),
        taxAmount: drift.Value(_taxAmount),
        total: drift.Value(_total),
        notes: drift.Value(_notesCtrl.text),
        businessId: drift.Value(bId),
        createdAt: drift.Value(DateTime.now()),
      ));

      for (final item in _cart) {
        await db.quotesDao.insertItem(QuoteItemsCompanion(
          id: drift.Value(const Uuid().v4()),
          quoteId: drift.Value(quoteId),
          productId: drift.Value(item.productId),
          productName: drift.Value(item.name),
          unitPrice: drift.Value(item.unitPrice),
          quantity: drift.Value(item.quantity),
          taxAmount: drift.Value(item.subtotal * item.taxRate),
          subtotal: drift.Value(item.subtotal),
        ));
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final customersAsync = ref.watch(customersStreamProvider);
    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Cotización')),
      body: Row(
        children: [
          // Left: Product Selection
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppSearchBar(
                    hint: 'Buscar producto...',
                    onChanged: (v) { /* Implement search in providers if needed */ },
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                      onPressed: () async {
                        final products = productsAsync.value ?? [];
                        var res = await SimpleBarcodeScanner.scanBarcode(
                          context,
                          barcodeAppBar: const BarcodeAppBar(
                            appBarTitle: 'Escanear Producto',
                            centerTitle: false,
                            enableBackButton: true,
                            backButtonIcon: Icon(Icons.arrow_back_ios),
                          ),
                          isShowFlashIcon: true,
                          delayMillis: 500,
                        );
                        if (res is String && res != '-1') {
                          final p = products.where((p) => p.sku == res).firstOrNull;
                          if (p != null) {
                            _addToCart(p);
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Producto no encontrado'), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: productsAsync.when(
                    data: (products) => GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final p = products[i];
                        return ProductGridCard(
                          product: p,
                          onTap: () => _addToCart(p),
                        );
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          ),
          // Right: Cart & Summary
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Column(
                children: [
                  _CartHeader(
                    selectedCustomer: _selectedCustomer,
                    onSelectCustomer: (c) => setState(() => _selectedCustomer = c),
                    customers: customersAsync.value ?? [],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _cart.length,
                      itemBuilder: (context, i) {
                        final item = _cart[i];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text('${item.quantity} x ${currencyFmt.format(item.unitPrice)}'),
                          trailing: Text(currencyFmt.format(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                          onLongPress: () => setState(() => _cart.removeAt(i)),
                        );
                      },
                    ),
                  ),
                  _SummaryPanel(
                    subtotal: _subtotal,
                    tax: _taxAmount,
                    total: _total,
                    isSaving: _isSaving,
                    onSave: _saveQuote,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItem {
  final String productId;
  final String name;
  final double unitPrice;
  final double taxRate;
  int quantity;

  _CartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.taxRate,
    required this.quantity,
  });

  double get subtotal => unitPrice * quantity;
}

class _CartHeader extends StatelessWidget {
  final Customer? selectedCustomer;
  final Function(Customer?) onSelectCustomer;
  final List<Customer> customers;

  const _CartHeader({
    required this.selectedCustomer,
    required this.onSelectCustomer,
    required this.customers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<Customer?>(
            initialValue: selectedCustomer,
            decoration: const InputDecoration(hintText: 'Seleccionar cliente'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Cliente General')),
              ...customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))),
            ],
            onChanged: onSelectCustomer,
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  final double subtotal;
  final double tax;
  final double total;
  final bool isSaving;
  final VoidCallback onSave;

  const _SummaryPanel({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _Row('Subtotal', currencyFmt.format(subtotal)),
          _Row('Taxes', currencyFmt.format(tax)),
          const Divider(),
          _Row('TOTAL', currencyFmt.format(total), isBold: true, color: AppColors.primary),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: GradientButton(
              label: 'Guardar Cotización',
              onTap: onSave,
              isLoading: isSaving,
            ),
          ),
        ],
      ),
    );
  }

  Widget _Row(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null, color: color)),
        ],
      ),
    );
  }
}
