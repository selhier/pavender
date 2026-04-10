// lib/features/settings/branch_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class BranchManagementScreen extends ConsumerWidget {
  const BranchManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final activeBranchId = ref.watch(activeBranchIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Sucursales')),
      body: FutureBuilder<List<BusinessesData>>(
        future: db.businessDao.getAllBranches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final branches = snapshot.data!;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: branches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final b = branches[i];
              final isActive = b.id == activeBranchId;

              return Card(
                elevation: isActive ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isActive 
                      ? const BorderSide(color: AppColors.primary, width: 2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? AppColors.primary : Colors.grey.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.store_rounded, 
                      color: isActive ? Colors.white : Colors.grey,
                    ),
                  ),
                  title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(b.address ?? 'Sin dirección'),
                  trailing: isActive 
                      ? const Badge(label: Text('ACTIVA'), backgroundColor: AppColors.success)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    if (!isActive) {
                      ref.read(activeBranchIdProvider.notifier).state = b.id;
                      final prefs = ref.read(sharedPreferencesProvider);
                      await prefs.setString('active_branch_id', b.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Cambiado a: ${b.name}')),
                        );
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBranchDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva Sucursal'),
      ),
    );
  }

  void _showAddBranchDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Sucursal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre de la Sucursal'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(labelText: 'Dirección (Opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              
              final db = ref.read(databaseProvider);
              final newId = const Uuid().v4();
              
              await db.businessDao.upsert(BusinessesCompanion(
                id: drift.Value(newId),
                name: drift.Value(nameCtrl.text),
                address: drift.Value(addressCtrl.text),
                currency: const drift.Value('DOP'),
                currencySymbol: const drift.Value('RD\$'),
              ));

              if (context.mounted) {
                Navigator.pop(context);
                // Trigger refresh by the caller or use a provider for branches
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}
