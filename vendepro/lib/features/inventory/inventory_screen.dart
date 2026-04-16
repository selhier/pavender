// lib/features/inventory/inventory_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/database/app_database.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _search = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'import') _importInventory();
              if (value == 'export') _exportCSV();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text('Importar Inventario (Excel/CSV)'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_rounded),
                  title: Text('Exportar CSV'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Productos'),
            Tab(text: 'Categorías'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppSearchBar(
              hint: 'Buscar producto, código...',
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Products tab
                productsAsync.when(
                  loading: () => ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: 5,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, __) => const SkeletonProductCard(),
                  ),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (products) {
                    final filtered = _search.isEmpty
                        ? products
                        : products.where((p) {
                            final q = _search.toLowerCase();
                            return p.name.toLowerCase().contains(q) ||
                                (p.sku?.toLowerCase().contains(q) ?? false);
                          }).toList();

                    if (filtered.isEmpty) {
                      return IllustrationEmptyState(
                        primaryIcon: Icons.inventory_2_rounded,
                        secondaryIcon: Icons.add_box_rounded,
                        title: 'Sin productos',
                        subtitle: 'Agrega tu primer producto al inventario y comienza a vender.',
                        actionLabel: 'Agregar Producto',
                        onAction: () => context.push('/inventory/new'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final p = filtered[i];
                        return _ProductCard(product: p, index: i)
                            .animate(delay: (i * 40).ms)
                            .fadeIn()
                            .slideX(begin: 0.1);
                      },
                    );
                  },
                ),
                // Categories tab (simple placeholder)
                _CategoriesList(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            context.push('/inventory/new');
          } else {
            _showCategoryDialog(context);
          }
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _showCategoryDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Categoría'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nombre de categoría',
            hintText: 'Ej. Postres',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final db = ref.read(databaseProvider);
              final bId = ref.read(currentBusinessIdProvider);
              final uuid = DateTime.now().millisecondsSinceEpoch.toString();
              await db.into(db.categories).insert(
                CategoriesCompanion.insert(
                  id: uuid,
                  name: ctrl.text.trim(),
                  businessId: bId,
                  icon: const drift.Value('🏷️'),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('Crear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _importInventory() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final fileData = file.bytes;
      if (fileData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al leer archivo.')),
          );
        }
        return;
      }
      
      List<List<dynamic>> rows = [];

      if (file.extension == 'csv') {
        final csvString = utf8.decode(fileData);
        rows = const CsvToListConverter().convert(csvString);
      } else if (file.extension == 'xlsx' || file.extension == 'xls') {
        final excel = Excel.decodeBytes(fileData);
        for (var table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet == null) continue;
          for (var row in sheet.rows) {
            rows.add(row.map((cell) => cell?.value).toList());
          }
          break; // Only import the first sheet
        }
      }

      if (rows.isEmpty || rows.length <= 1) return; 

      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      
      int imported = 0;
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row[0] == null || row[0].toString().trim().isEmpty) {
          continue;
        }
        
        final name = row[0].toString();
        final sku = row.length > 1 ? row[1]?.toString() ?? '' : '';
        final price = row.length > 2 ? double.tryParse(row[2].toString()) ?? 0.0 : 0.0;
        final cost = row.length > 3 ? double.tryParse(row[3].toString()) ?? 0.0 : 0.0;
        final stock = row.length > 4 ? int.tryParse(row[4].toString()) ?? 0 : 0;
        
        final uuid = const Uuid().v4();
        await db.productsDao.upsert(ProductsCompanion(
          id: drift.Value(uuid),
          name: drift.Value(name),
          sku: drift.Value(sku.isEmpty ? null : sku),
          price: drift.Value(price),
          cost: drift.Value(cost),
          stock: drift.Value(stock),
          businessId: drift.Value(bId),
          isActive: const drift.Value(true),
        ));
        imported++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$imported productos importados', 
              style: const TextStyle(color: Colors.white)), 
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', 
              style: const TextStyle(color: Colors.white)), 
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _exportCSV() async {
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final products = await db.productsDao.watchAll(bId).first;
    
    List<List<dynamic>> rows = [
      ["Nombre", "SKU", "Precio", "Costo", "Stock"]
    ];
    
    for(var p in products) {
      rows.add([p.name, p.sku ?? '', p.price, p.cost, p.stock]);
    }
    
    String csv = const ListToCsvConverter().convert(rows);
    await Share.share(csv, subject: 'Inventario.csv');
  }
}

class _ProductCard extends StatelessWidget {
  final dynamic product;
  final int index;
  const _ProductCard({required this.product, required this.index});

  @override
  Widget build(BuildContext context) {
    final isLowStock = product.stock <= product.minStock;

    return Card(
      child: InkWell(
        onTap: () => context.push('/inventory/edit/${product.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product icon/image
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (product.sku != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SKU: ${product.sku}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isLowStock
                                ? AppColors.warning.withValues(alpha: 0.15)
                                : AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Stock: ${product.stock} ${product.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isLowStock
                                  ? AppColors.warning
                                  : AppColors.success,
                            ),
                          ),
                        ),
                        if (isLowStock) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.warning, size: 14),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${product.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Costo: \$${product.cost.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriesList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final bId = ref.watch(currentBusinessIdProvider);

    return FutureBuilder(
      future: db.productsDao.getCategories(bId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final cats = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: cats.length,
          itemBuilder: (_, i) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Text(cats[i].icon,
                  style: const TextStyle(fontSize: 24)),
              title: Text(cats[i].name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing:
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ),
          ),
        );
      },
    );
  }
}
