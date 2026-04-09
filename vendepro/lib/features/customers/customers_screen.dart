// lib/features/customers/customers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppSearchBar(
              hint: 'Buscar por nombre o teléfono...',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: customersAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (customers) {
                final filtered = _search.isEmpty
                    ? customers
                    : customers
                        .where((c) {
                          final q = _search.toLowerCase();
                          return c.name.toLowerCase().contains(q) ||
                              (c.phone?.contains(q) ?? false);
                        })
                        .toList();

                if (filtered.isEmpty) {
                  return IllustrationEmptyState(
                    primaryIcon: Icons.people_alt_rounded,
                    secondaryIcon: Icons.person_add_alt_1_rounded,
                    title: 'Aún no tienes clientes',
                    subtitle: 'Registra a tus compradores para un mejor seguimiento de ventas.',
                    actionLabel: 'Agregar Cliente',
                    onAction: () => context.push('/customers/new'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withOpacity(0.15),
                          child: Text(
                            c.name[0].toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18),
                          ),
                        ),
                        title: Text(c.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c.phone != null)
                              Text(c.phone!,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            if (c.email != null)
                              Text(c.email!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            _CustomerBalanceWidget(customerId: c.id),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              color: AppColors.primary, size: 20),
                          onPressed: () =>
                              context.push('/customers/edit/${c.id}'),
                        ),
                        isThreeLine:
                            c.email != null && c.phone != null,
                      ),
                    )
                        .animate(delay: (i * 40).ms)
                        .fadeIn()
                        .slideX(begin: 0.1);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/customers/new'),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }
}

class _CustomerBalanceWidget extends ConsumerWidget {
  final String customerId;
  const _CustomerBalanceWidget({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(customerBalanceProvider(customerId));
    
    return balance.when(
      data: (val) => val > 0 
        ? Text(
            'Debe: \$${val.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13, 
              color: AppColors.error, 
              fontWeight: FontWeight.w700
            ),
          )
        : const SizedBox.shrink(),
      loading: () => const SizedBox(
        width: 10, 
        height: 10, 
        child: CircularProgressIndicator(strokeWidth: 1, color: AppColors.primary)
      ),
      error: (_, __) => const Text('Error', style: TextStyle(fontSize: 10, color: Colors.red)),
    );
  }
}
