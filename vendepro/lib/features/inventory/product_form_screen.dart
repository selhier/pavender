// lib/features/inventory/product_form_screen.dart
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController();
  final _minStock = TextEditingController();
  final _description = TextEditingController();
  String _unit = 'unidad';
  String? _categoryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) _loadProduct();
  }

  Future<void> _loadProduct() async {
    final db = ref.read(databaseProvider);
    final p = await db.productsDao.getById(widget.productId!);
    if (p != null && mounted) {
      setState(() {
        _name.text = p.name;
        _sku.text = p.sku ?? '';
        _price.text = p.price.toString();
        _cost.text = p.cost.toString();
        _stock.text = p.stock.toString();
        _minStock.text = p.minStock.toString();
        _description.text = p.description ?? '';
        _unit = p.unit;
        _categoryId = p.categoryId;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final syncService = ref.read(syncServiceProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final id = widget.productId ?? const Uuid().v4();

      final companion = ProductsCompanion(
        id: drift.Value(id),
        name: drift.Value(_name.text.trim()),
        sku: drift.Value(_sku.text.trim().isEmpty ? null : _sku.text.trim()),
        price: drift.Value(double.tryParse(_price.text) ?? 0),
        cost: drift.Value(double.tryParse(_cost.text) ?? 0),
        stock: drift.Value(int.tryParse(_stock.text) ?? 0),
        minStock: drift.Value(int.tryParse(_minStock.text) ?? 5),
        description: drift.Value(_description.text.isEmpty
            ? null
            : _description.text),
        unit: drift.Value(_unit),
        categoryId: drift.Value(_categoryId),
        businessId: drift.Value(bId),
        updatedAt: drift.Value(DateTime.now()),
      );
      await db.productsDao.upsert(companion);
      await syncService.enqueueChange(
        entity: 'products',
        entityId: id,
        operation: widget.productId == null ? 'create' : 'update',
        data: {
          'name': _name.text,
          'sku': _sku.text,
          'price': double.tryParse(_price.text) ?? 0,
          'cost': double.tryParse(_cost.text) ?? 0,
          'stock': int.tryParse(_stock.text) ?? 0,
          'minStock': int.tryParse(_minStock.text) ?? 5,
          'businessId': bId,
          'isActive': true,
        },
      );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.productId != null;
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'Editar Producto' : 'Nuevo Producto'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSection('Información Básica', [
                _buildField('Nombre del producto *', _name,
                    validator: (v) =>
                        v!.isEmpty ? 'Requerido' : null),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: _buildField('Código SKU', _sku)),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () async {
                        var res = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SimpleBarcodeScannerPage(),
                          ),
                        );
                        if (res is String && res != '-1') {
                          setState(() => _sku.text = res);
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 28),
                      tooltip: 'Escanear Código',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField('Descripción', _description, maxLines: 3),
              ]),
              const SizedBox(height: 20),
              _buildSection('Precios', [
                Row(children: [
                  Expanded(
                    child: _buildField('Precio de Venta *', _price,
                        prefix: '\$',
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? 'Requerido' : null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField('Costo', _cost,
                        prefix: '\$',
                        keyboardType: TextInputType.number),
                  ),
                ]),
              ]),
              const SizedBox(height: 20),
              _buildSection('Inventario', [
                Row(children: [
                  Expanded(
                    child: _buildField('Stock actual *', _stock,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? 'Requerido' : null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField('Stock mínimo', _minStock,
                        keyboardType: TextInputType.number),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _unit,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: ['unidad', 'kg', 'g', 'lt', 'ml', 'caja', 'paquete']
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _unit = v!),
                ),
              ]),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: GradientButton(
                  label: isEdit ? 'Guardar Cambios' : 'Crear Producto',
                  icon: isEdit ? Icons.save_rounded : Icons.add_rounded,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.primary)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    String? prefix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    _description.dispose();
    super.dispose();
  }
}
