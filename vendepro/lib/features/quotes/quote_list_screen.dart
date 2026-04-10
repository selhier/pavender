// lib/features/quotes/quote_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class QuoteListScreen extends ConsumerWidget {
  const QuoteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(quotesStreamProvider);
    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Cotizaciones')),
      body: quotesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (quotes) {
          if (quotes.isEmpty) {
            return IllustrationEmptyState(
              primaryIcon: Icons.description_outlined,
              secondaryIcon: Icons.add_rounded,
              title: 'Sin Cotizaciones',
              subtitle: 'Crea presupuestos para tus clientes y conviértelos en facturas después.',
              actionLabel: 'Nueva Cotización',
              onAction: () => context.push('/quotes/new'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: quotes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final q = quotes[i];
              return Card(
                child: ListTile(
                  title: Row(
                    children: [
                      Text(q.quoteNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      _StatusChip(status: q.status),
                    ],
                  ),
                  subtitle: Text(q.customerName ?? 'Cliente general'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(currencyFmt.format(q.total), 
                           style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      Text(DateFormat('dd/MM/yy').format(q.createdAt), 
                           style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  onTap: () => context.push('/quotes/${q.id}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/quotes/new'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = 'Pendiente';
        break;
      case 'converted':
        color = Colors.green;
        label = 'Facturada';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
