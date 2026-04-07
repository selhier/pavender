// lib/features/expenses/expense_form_screen.dart
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Suministros';
  bool _isLoading = false;

  final List<String> _categories = [
    'Suministros',
    'Servicios Públicos',
    'Alquiler',
    'Salarios',
    'Mantenimiento',
    'Transporte',
    'Impuestos',
    'Otros'
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final syncService = ref.read(syncServiceProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final id = const Uuid().v4();
      final now = DateTime.now();

      await db.expensesDao.insertExpense(ExpensesCompanion(
        id: drift.Value(id),
        amount: drift.Value(double.tryParse(_amountCtrl.text) ?? 0.0),
        description: drift.Value(_descCtrl.text.trim()),
        category: drift.Value(_category),
        date: drift.Value(now),
        businessId: drift.Value(bId),
      ));

      await syncService.enqueueChange(
        entity: 'expenses',
        entityId: id,
        operation: 'create',
        data: {
          'amount': double.tryParse(_amountCtrl.text) ?? 0.0,
          'description': _descCtrl.text.trim(),
          'category': _category,
          'businessId': bId,
          'status': 'paid',
          'date': now.toIso8601String(),
        },
      );

      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nuevo Gasto'),
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.money_off_rounded, size: 40, color: AppColors.error),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.error),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$ ',
                        border: InputBorder.none,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
                        if (double.tryParse(v) == null) return 'Número inválido';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción del gasto',
                  prefixIcon: Icon(Icons.description_rounded),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.category_rounded),
                ),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: GradientButton(
                  label: 'Registrar Gasto',
                  icon: Icons.check_circle_outline_rounded,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
