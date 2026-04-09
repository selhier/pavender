// lib/features/invoices/invoice_create_screen.dart
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/utils/dr_utils.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';

class _CartItem {
  final dynamic product;
  int quantity;
  double discount;
  final double taxRate;
  
  _CartItem({
    required this.product, 
    this.quantity = 1, 
    this.discount = 0,
    required this.taxRate,
  });

  double get subtotal =>
      (product.price as double) * quantity * (1 - discount / 100);
      
  double get itemTaxAmount => subtotal * taxRate;
}

class InvoiceCreateScreen extends ConsumerStatefulWidget {
  const InvoiceCreateScreen({super.key});
  @override
  ConsumerState<InvoiceCreateScreen> createState() =>
      _InvoiceCreateScreenState();
}

class _InvoiceCreateScreenState extends ConsumerState<InvoiceCreateScreen> {
  final List<_CartItem> _cart = [];
  dynamic _selectedCustomer;
  String _paymentMethod = 'cash';
  final _notesCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isValidatingRnc = false;
  String _productSearch = '';
  String? _ncfType; // DR Localization

  double get _subtotal => _cart.fold(0, (s, i) => s + i.subtotal);
  // _tax and _total computed in build()

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider).value ?? [];
    final cardFeePct = ref.watch(cardFeeProvider).value ?? 0.0;
    double totalTaxAmount = _cart.fold(0, (s, i) => s + i.itemTaxAmount);
    double fee = _paymentMethod == 'card' ? (_subtotal + totalTaxAmount) * (cardFeePct / 100.0) : 0.0;
    double finalTotal = _subtotal + totalTaxAmount + fee;
    final isMobile = MediaQuery.of(context).size.width < 768;

    Widget cartPanel = Container(
      width: isMobile ? double.infinity : 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _CustomerSelector(
              selected: _selectedCustomer,
              onSelect: (c) => setState(() => _selectedCustomer = c),
            ),
          ),
          const Divider(height: 1),
          // Cart items
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text('Selecciona productos',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _cart.length,
                    itemBuilder: (_, i) => _CartItemTile(
                      item: _cart[i],
                      onRemove: () => setState(() => _cart.removeAt(i)),
                      onQuantityChange: (q) =>
                          setState(() => _cart[i].quantity = q),
                    ),
                  ),
          ),
          const Divider(height: 1),
          // Scrollable summary / actions section
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SummaryRow('Subtotal', '\$${_subtotal.toStringAsFixed(2)}'),
                  _SummaryRow('Impuesto', '\$${totalTaxAmount.toStringAsFixed(2)}'),
                  if (_paymentMethod == 'card' && fee > 0)
                    _SummaryRow('Comisión Tarjeta', '\$${fee.toStringAsFixed(2)}'),
                  const Divider(),
                  _SummaryRow('TOTAL', '\$${finalTotal.toStringAsFixed(2)}', isTotal: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Método de pago',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('💵 Efectivo')),
                      DropdownMenuItem(value: 'card', child: Text('💳 Tarjeta')),
                      DropdownMenuItem(
                          value: 'transfer', child: Text('🏦 Transferencia')),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: _ncfType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Tipo de Comprobante (RD)',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin Comprobante')),
                      ...DRUtils.ncfTypes.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          )),
                    ],
                    onChanged: (v) => setState(() => _ncfType = v),
                  ),
                  const SizedBox(height: 12),
                  if (_ncfType != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _taxIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'RNC / Cédula',
                              hintText: 'Ej. 131996035',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _isValidatingRnc ? null : _lookupRNC,
                          icon: _isValidatingRnc
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.search_rounded),
                          tooltip: 'Validar RNC en DGII',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      label: 'Emitir Factura',
                      icon: Icons.receipt_rounded,
                      onTap: _cart.isEmpty ? null : () => _save(finalTotal, totalTaxAmount, fee),
                      isLoading: _isLoading,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Widget bodyContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: AppSearchBar(
            hint: 'Buscar producto...',
            onChanged: (v) => setState(() => _productSearch = v),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded,
                  color: AppColors.primary),
              onPressed: () async {
                var res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SimpleBarcodeScannerPage(),
                  ),
                );
                if (res is String && res != '-1') {
                  final p =
                      products.where((p) => p.sku == res).firstOrNull;
                  if (p != null) {
                    _addToCart(p);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Agregado: ${p.name}'),
                          backgroundColor: AppColors.success),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Producto no encontrado'),
                          backgroundColor: AppColors.error),
                    );
                  }
                }
              },
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 110,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _filteredProducts(products).length,
            itemBuilder: (_, i) {
              final p = _filteredProducts(products)[i];
              final inCart = _cart.any((c) => c.product.id == p.id);
              return GestureDetector(
                onTap: () => _addToCart(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: inCart
                        ? AppColors.primary.withOpacity(0.15)
                        : Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: inCart
                          ? AppColors.primary
                          : Theme.of(context).dividerColor,
                      width: inCart ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(Icons.inventory_2_rounded,
                              color: AppColors.primary, size: 20),
                          if (inCart)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 12),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        p.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '\$${p.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      endDrawer: isMobile ? Drawer(child: cartPanel) : null,
      appBar: AppBar(
        title: const Text('Nueva Factura'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isMobile)
            Builder(
              builder: (context) => IconButton(
                icon: Badge(
                  label: Text(_cart.length.toString()),
                  isLabelVisible: _cart.isNotEmpty,
                  child: const Icon(Icons.shopping_cart_rounded),
                ),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          if (!isMobile && _cart.isNotEmpty)
            TextButton.icon(
              onPressed: () => _save(finalTotal, totalTaxAmount, fee),
              icon: const Icon(Icons.check_rounded, color: AppColors.success),
              label: const Text('Emitir',
                  style: TextStyle(
                      color: AppColors.success, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: isMobile 
            ? bodyContent 
            : Row(
                children: [
                  Expanded(child: bodyContent),
                  cartPanel,
                ],
              ),
      ),
    );
  }

  List _filteredProducts(List products) {
    if (_productSearch.isEmpty) return products;
    final q = _productSearch.toLowerCase();
    return products
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  void _addToCart(dynamic product) {
    setState(() {
      final idx = _cart.indexWhere((c) => c.product.id == product.id);
      if (idx >= 0) {
        _cart[idx].quantity++;
      } else {
        _cart.add(_CartItem(
          product: product,
          taxRate: product.taxRate as double,
        ));
      }
    });
  }

  Future<void> _lookupRNC() async {
    if (_taxIdCtrl.text.isEmpty) return;
    setState(() => _isValidatingRnc = true);
    try {
      final res = await ref.read(taxServiceProvider).lookupRNC(_taxIdCtrl.text);
      if (res != null) {
        setState(() {
          _taxIdCtrl.text = res['rnc'] ?? _taxIdCtrl.text;
          if (_selectedCustomer == null) {
            // For general customer, we update the name display for this invoice
            _selectedCustomer = (name: res['name'] ?? 'Cliente general', id: null);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('RNC Validado: ${res['name']}'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se encontró información para este RNC'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isValidatingRnc = false);
    }
  }

  Future<void> _save(double total, double taxAmount, double feeAmount) async {
    if (_cart.isEmpty) return;
    if (_ncfType != null && _taxIdCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El RNC/Cédula es obligatorio para facturas con NCF'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final syncService = ref.read(syncServiceProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final id = const Uuid().v4();
      final invoiceNum =
          'FAC-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      String? ncf;
      if (_ncfType != null) {
        ncf = await db.ncfDao.getNextNCF(bId, _ncfType!);
        if (ncf == null) {
          setState(() => _isLoading = false);
          // Auto-init dialog
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Secuencia no encontrada'),
              content: Text(
                  'No tienes una secuencia activa para ${DRUtils.ncfTypes[_ncfType]}. ¿Deseas iniciar una automática desde el número 1 hasta el 10,000?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Configurar Manual')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Iniciar Automática')),
              ],
            ),
          );

          if (confirm == true) {
            setState(() => _isLoading = true);
            await db.ncfDao.upsert(NcfSequencesCompanion(
              id: drift.Value(const Uuid().v4()),
              type: drift.Value(_ncfType!),
              prefix: const drift.Value('B'),
              from: const drift.Value(1),
              to: const drift.Value(10000),
              lastUsed: const drift.Value(0),
              businessId: drift.Value(bId),
              isActive: const drift.Value(true),
            ));
            // Retry getNextNCF
            ncf = await db.ncfDao.getNextNCF(bId, _ncfType!);
          }

          if (ncf == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('No hay secuencias de NCF disponibles.')),
              );
            }
            return;
          }
        }
      }

      final String status = _paymentMethod == 'credit' ? 'issued' : 'paid';

      await db.invoicesDao.insertInvoice(InvoicesCompanion(
        id: drift.Value(id),
        invoiceNumber: drift.Value(invoiceNum),
        ncf: drift.Value(ncf),
        ncfType: drift.Value(_ncfType),
        customerId: drift.Value(_selectedCustomer?.id),
        customerName:
            drift.Value(_selectedCustomer?.name ?? 'Cliente general'),
        customerTaxId: drift.Value(_taxIdCtrl.text.isEmpty ? null : _taxIdCtrl.text),
        status: drift.Value(status),
        subtotal: drift.Value(_subtotal),
        taxAmount: drift.Value(taxAmount),
        total: drift.Value(total),
        paymentMethod: drift.Value(_paymentMethod),
        businessId: drift.Value(bId),
        notes: drift.Value(_notesCtrl.text.isEmpty ? null : _notesCtrl.text),
      ));

      for (final item in _cart) {
        await db.invoicesDao.insertItem(InvoiceItemsCompanion(
          id: drift.Value(const Uuid().v4()),
          invoiceId: drift.Value(id),
          productId: drift.Value(item.product.id as String),
          productName: drift.Value(item.product.name as String),
          unitPrice: drift.Value(item.product.price as double),
          quantity: drift.Value(item.quantity),
          taxAmount: drift.Value(item.itemTaxAmount),
          subtotal: drift.Value(item.subtotal),
        ));
        // Decrease stock
        final newStock = (item.product.stock as int) - item.quantity;
        await db.productsDao.updateStock(item.product.id as String,
            newStock < 0 ? 0 : newStock);
      }

      await syncService.enqueueChange(
        entity: 'invoices',
        entityId: id,
        operation: 'create',
        data: {
          'invoiceNumber': invoiceNum,
          'customerName': _selectedCustomer?.name ?? 'Cliente general',
          'status': status,
          'subtotal': _subtotal,
          'taxAmount': taxAmount,
          'cardFee': feeAmount,
          'total': total,
          'paymentMethod': _paymentMethod,
          'businessId': bId,
          'createdAt': DateTime.now().toIso8601String(),
        },
      );

      if (mounted) {
        context.pop();
        context.push('/invoices/$id');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al emitir factura: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _taxIdCtrl.dispose();
    super.dispose();
  }
}

class _CartItemTile extends StatelessWidget {
  final _CartItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChange;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onQuantityChange,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.product.name as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: AppColors.error),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints()),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _QuantityBtn(
                        icon: Icons.remove_rounded,
                        onTap: () {
                          if (item.quantity > 1) {
                            onQuantityChange(item.quantity - 1);
                          }
                        }),
                    const SizedBox(width: 10),
                    Text('${item.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    _QuantityBtn(
                        icon: Icons.add_rounded,
                        onTap: () => onQuantityChange(item.quantity + 1)),
                  ],
                ),
                Text(
                  '\$${item.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QuantityBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  const _SummaryRow(this.label, this.value, {this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: isTotal ? 16 : 13,
                  fontWeight:
                      isTotal ? FontWeight.w800 : FontWeight.w400,
                  color: isTotal 
                      ? AppColors.primary 
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
          Text(value,
              style: TextStyle(
                  fontSize: isTotal ? 16 : 13,
                  fontWeight:
                      isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: isTotal
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _CustomerSelector extends ConsumerWidget {
  final dynamic selected;
  final ValueChanged<dynamic> onSelect;
  const _CustomerSelector({this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersStreamProvider).value ?? [];
    return GestureDetector(
      onTap: () => _showPicker(context, customers),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected?.name ?? 'Cliente general',
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, List customers) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Cliente general'),
            onTap: () {
              onSelect(null);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: customers.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.person_rounded,
                    color: AppColors.primary),
                title: Text(customers[i].name),
                subtitle: Text(customers[i].phone ?? ''),
                onTap: () {
                  onSelect(customers[i]);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
