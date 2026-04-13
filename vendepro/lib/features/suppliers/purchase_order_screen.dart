// lib/features/suppliers/purchase_order_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../reports/pdf_generator_service.dart';

class PurchaseOrderScreen extends ConsumerStatefulWidget {
  const PurchaseOrderScreen({super.key});

  @override
  ConsumerState<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

class _OrderLine {
  String productId;
  String productName;
  int quantity;
  double unitCost;
  _OrderLine({required this.productId, required this.productName, this.quantity = 1, required this.unitCost});
  double get subtotal => quantity * unitCost;
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  final _notesCtrl = TextEditingController();
  dynamic _selectedSupplier;
  final List<_OrderLine> _lines = [];
  bool _isSaving = false;
  DateTime? _expectedDate;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + l.subtotal);

  void _addProduct(Product product) {
    final existing = _lines.indexWhere((l) => l.productId == product.id);
    if (existing >= 0) {
      setState(() => _lines[existing].quantity++);
    } else {
      setState(() => _lines.add(_OrderLine(
        productId: product.id,
        productName: product.name,
        quantity: 1,
        unitCost: product.cost,
      )));
    }
  }

  Future<void> _save() async {
    if (_selectedSupplier == null && _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccione proveedor y agregue productos')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final orderId = const Uuid().v4();

      await db.into(db.purchaseOrders).insert(PurchaseOrdersCompanion.insert(
        id: orderId,
        businessId: bId,
        supplierId: drift.Value(_selectedSupplier?.id),
        supplierName: _selectedSupplier?.name ?? 'Proveedor General',
        total: drift.Value(_total),
        notes: drift.Value(_notesCtrl.text.isEmpty ? null : _notesCtrl.text),
        expectedDate: drift.Value(_expectedDate),
      ));

      for (var line in _lines) {
        await db.into(db.purchaseOrderItems).insert(PurchaseOrderItemsCompanion.insert(
          id: const Uuid().v4(),
          orderId: orderId,
          productId: drift.Value(line.productId),
          productName: line.productName,
          quantity: line.quantity,
          unitCost: line.unitCost,
          subtotal: line.subtotal,
        ));
      }

      if (mounted) {
        final biz = ref.read(businessProvider).valueOrNull;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Orden Creada'),
            content: const Text('¿Desea imprimir o guardar la orden de compra ahora?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No, solo salir')),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final db = ref.read(databaseProvider);
                  final order = await (db.select(db.purchaseOrders)..where((o) => o.id.equals(orderId))).getSingle();
                  final items = await (db.select(db.purchaseOrderItems)..where((i) => i.orderId.equals(orderId))).get();
                  if (mounted) {
                    await PDFGeneratorService().generatePurchaseOrder(
                      context: context,
                      businessName: biz?.name ?? 'VendePro',
                      order: order,
                      items: items,
                    );
                  }
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('Imprimir'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final moneyFmt = NumberFormat.currency(symbol: '\$');
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Orden de Compra'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: product browser
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar producto...',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: productsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (products) => ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (ctx, i) {
                        final p = products[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text('Costo: \$${p.cost.toStringAsFixed(2)}  •  Stock: ${p.stock}', style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                            onPressed: () => _addProduct(p),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right: order
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Supplier dropdown
                  suppliersAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => const SizedBox(),
                    data: (suppliers) => DropdownButtonFormField(
                      decoration: const InputDecoration(labelText: 'Proveedor', prefixIcon: Icon(Icons.local_shipping_rounded), border: OutlineInputBorder()),
                      initialValue: _selectedSupplier,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Proveedor General')),
                        ...suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))),
                      ],
                      onChanged: (v) => setState(() => _selectedSupplier = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Expected date
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                    title: Text(_expectedDate == null ? 'Fecha esperada de entrega' : 'Entrega: ${dateFmt.format(_expectedDate!)}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
                      if (d != null) setState(() => _expectedDate = d);
                    },
                  ),
                  const Divider(),
                  // Order lines
                  if (_lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Agrega productos desde el panel izquierdo', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ..._lines.map((line) => Card(
                      child: ListTile(
                        title: Text(line.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('\$${line.unitCost.toStringAsFixed(2)} c/u'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: () => setState(() { if (line.quantity > 1) line.quantity--; else _lines.remove(line); })),
                            Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => setState(() => line.quantity++)),
                            const SizedBox(width: 8),
                            Text(moneyFmt.format(line.subtotal), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    )),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('TOTAL: ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text(moneyFmt.format(_total), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notas para el proveedor', prefixIcon: Icon(Icons.note_alt_rounded), border: OutlineInputBorder()),
                    maxLines: 2,
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
