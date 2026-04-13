// lib/features/suppliers/suppliers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/utils/dr_utils.dart';
import '../../core/theme/app_theme.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Proveedores')),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return IllustrationEmptyState(
              primaryIcon: Icons.local_shipping_outlined,
              secondaryIcon: Icons.add_business_rounded,
              title: 'No hay proveedores',
              subtitle: 'Registra a tus suplidores para gestionar compras y cuentas por pagar.',
              actionLabel: 'Agregar Proveedor',
              onAction: () => _showSupplierForm(context, ref),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: suppliers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = suppliers[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(s.rnc ?? 'Sin RNC'),
                  trailing: const Icon(Icons.edit_rounded, size: 20),
                  onTap: () => _showSupplierForm(context, ref, supplier: s),
                ),
              ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.1);
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'order',
            onPressed: () => context.push('/suppliers/orders'),
            tooltip: 'Órdenes de Compra',
            child: const Icon(Icons.receipt_long_rounded),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'supplier',
            onPressed: () => _showSupplierForm(context, ref),
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  void _showSupplierForm(BuildContext context, WidgetRef ref, {Supplier? supplier}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SupplierForm(supplier: supplier),
    );
  }
}

class _SupplierForm extends ConsumerStatefulWidget {
  final Supplier? supplier;
  const _SupplierForm({this.supplier});

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      _nameCtrl.text = widget.supplier!.name;
      _rncCtrl.text = widget.supplier!.rnc ?? '';
      _phoneCtrl.text = widget.supplier!.phone ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.supplier == null ? 'Nuevo Proveedor' : 'Editar Proveedor', 
                 style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl, 
              decoration: const InputDecoration(labelText: 'Nombre Comercial *'),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _rncCtrl, 
              decoration: const InputDecoration(
                labelText: 'RNC / Cédula',
                helperText: 'Opcional (Validación RD)',
              ),
              inputFormatters: [DRTaxIdFormatter()],
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final clean = v.replaceAll('-', '');
                if (clean.length != 9 && clean.length != 11) return '9 o 11 dígitos';
                if (!DRUtils.isValidTaxId(clean)) return 'ID inválido para RD';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl, 
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Guardar'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      await db.suppliersDao.upsert(SuppliersCompanion(
        id: drift.Value(widget.supplier?.id ?? const Uuid().v4()),
        name: drift.Value(_nameCtrl.text.trim()),
        rnc: drift.Value(_rncCtrl.text.trim().isEmpty ? null : _rncCtrl.text.trim()),
        phone: drift.Value(_phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
        businessId: drift.Value(bId),
      ));
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
