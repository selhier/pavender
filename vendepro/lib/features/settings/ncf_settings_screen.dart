// lib/features/settings/ncf_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/utils/dr_utils.dart';

class NcfSettingsScreen extends ConsumerWidget {
  const NcfSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bId = ref.watch(currentBusinessIdProvider);
    final db = ref.watch(databaseProvider);
    final sequencesAsync = ref.watch(ncfSequencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Secuencias NCF')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref, bId),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Añadir Rango'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: sequencesAsync.when(
        data: (sequences) => sequences.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No hay secuencias configuradas',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sequences.length,
                itemBuilder: (_, i) => _NcfSequenceCard(
                  sequence: sequences[i],
                  onDelete: () => _delete(context, db, sequences[i].id),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, String bId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddNcfForm(businessId: bId),
    );
  }

  Future<void> _delete(BuildContext context, AppDatabase db, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar secuencia?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(_, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );

    if (confirm == true) {
      await db.ncfDao.deleteSequence(id);
    }
  }
}

class _NcfSequenceCard extends StatelessWidget {
  final NcfSequence sequence;
  final VoidCallback onDelete;

  const _NcfSequenceCard({required this.sequence, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final typeName = DRUtils.ncfTypes[sequence.type] ?? 'Desconocido';
    final progress = (sequence.lastUsed - sequence.from + 1) /
        (sequence.to - sequence.from + 1);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                          'Prefijo: ${sequence.prefix} | Tipo: ${sequence.type}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error),
                  onPressed: onDelete,
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoBlock('Desde', sequence.from.toString().padLeft(8, '0')),
                _InfoBlock('Hasta', sequence.to.toString().padLeft(8, '0')),
                _InfoBlock(
                    'Último', sequence.lastUsed.toString().padLeft(8, '0'),
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              color: progress > 0.9 ? AppColors.error : AppColors.primary,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _InfoBlock(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: color)),
      ],
    );
  }
}

class _AddNcfForm extends ConsumerStatefulWidget {
  final String businessId;
  const _AddNcfForm({required this.businessId});

  @override
  ConsumerState<_AddNcfForm> createState() => _AddNcfFormState();
}

class _AddNcfFormState extends ConsumerState<_AddNcfForm> {
  String _type = '01';
  final _prefixCtrl = TextEditingController(text: 'B');
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nueva Secuencia NCF',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Tipo de Comprobante'),
            items: DRUtils.ncfTypes.entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _prefixCtrl,
            decoration: const InputDecoration(labelText: 'Prefijo (Ej. B)'),
            maxLength: 1,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _fromCtrl,
                  decoration: const InputDecoration(labelText: 'Desde (Ej. 1)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _toCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Hasta (Ej. 100)'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: GradientButton(
              label: 'Guardar Rango',
              icon: Icons.save_rounded,
              isLoading: _isLoading,
              onTap: _save,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_fromCtrl.text.isEmpty || _toCtrl.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final from = int.parse(_fromCtrl.text);
      final to = int.parse(_toCtrl.text);

      await db.ncfDao.upsert(NcfSequencesCompanion(
        id: drift.Value(const Uuid().v4()),
        type: drift.Value(_type),
        prefix: drift.Value(_prefixCtrl.text.isEmpty ? 'B' : _prefixCtrl.text),
        from: drift.Value(from),
        to: drift.Value(to),
        lastUsed: drift.Value(from - 1),
        businessId: drift.Value(widget.businessId),
        isActive: const drift.Value(true),
      ));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
