// lib/features/expenses/expenses_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos y Egresos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/expenses/new'),
            tooltip: 'Nuevo Gasto',
          ),
        ],
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('Error: $err', style: const TextStyle(color: AppColors.error)),
        ),
        data: (expenses) {
          if (expenses.isEmpty) {
            return Center(
              child: IllustrationEmptyState(
                primaryIcon: Icons.account_balance_wallet_outlined,
                secondaryIcon: Icons.money_off_rounded,
                title: 'No hay gastos registrados',
                subtitle: 'Registra tus primeros egresos para mantener un control financiero.',
                actionLabel: 'Crear Gasto',
                onAction: () => context.push('/expenses/new'),
              ),
            );
          }

          final total = expenses.fold(0.0, (s, e) => s + e.amount);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Gastos:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.error),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.money_off_rounded, color: AppColors.error, size: 20),
                        ),
                        title: Text(expense.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${expense.category} • ${DateFormat('dd MMM yyyy, HH:mm').format(expense.date)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        trailing: Text(
                          '-\$${expense.amount.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo Gasto'),
      ),
    );
  }
}
