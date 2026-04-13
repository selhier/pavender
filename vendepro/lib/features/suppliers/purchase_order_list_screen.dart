// lib/features/suppliers/purchase_order_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class PurchaseOrderListScreen extends ConsumerWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(purchaseOrdersStreamProvider);
    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes de Compra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.refresh(purchaseOrdersStreamProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return IllustrationEmptyState(
              primaryIcon: Icons.local_shipping_outlined,
              secondaryIcon: Icons.add_business_rounded,
              title: 'Sin Órdenes de Compra',
              subtitle: 'Gestiona tus pedidos a proveedores y controla la entrada de mercancía al almacén.',
              actionLabel: 'Crear Primera Orden',
              onAction: () => context.push('/suppliers/orders/new'),
            );
          }

          final pendingCount = orders.where((o) => o.status == 'pending').length;
          final totalAmount = orders.fold<double>(0, (sum, o) => sum + o.total);

          return Column(
            children: [
              _KPIRow(
                pendingCount: pendingCount,
                totalAmount: totalAmount,
                currencyFmt: currencyFmt,
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return _OrderCard(
                      order: order,
                      currencyFmt: currencyFmt,
                      onReceive: () => _showReceiveDialog(context, ref, order),
                    ).animate(delay: (i * 50).ms).fadeIn().slideX(begin: 0.1, end: 0);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/suppliers/orders/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva Orden'),
      ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
    );
  }

  Future<void> _showReceiveDialog(BuildContext context, WidgetRef ref, dynamic order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recibir Mercancía'),
        content: Text('¿Deseas confirmar la recepción de la orden ${order.id.substring(0, 8).toUpperCase()}? Esto incrementará automáticamente el stock de los productos vinculados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar Recepción')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(databaseProvider).purchaseOrdersDao.receiveOrder(order.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Orden recibida. Stock actualizado.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }
}

class _KPIRow extends StatelessWidget {
  final int pendingCount;
  final double totalAmount;
  final NumberFormat currencyFmt;

  const _KPIRow({
    required this.pendingCount,
    required this.totalAmount,
    required this.currencyFmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: _MiniStatCard(
              label: 'Pendientes',
              value: '$pendingCount',
              icon: Icons.pending_actions_rounded,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MiniStatCard(
              label: 'Inversión Total',
              value: currencyFmt.format(totalAmount),
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final dynamic order;
  final NumberFormat currencyFmt;
  final VoidCallback onReceive;

  const _OrderCard({
    required this.order,
    required this.currencyFmt,
    required this.onReceive,
  });

  @override
  Widget build(BuildContext context) {
    final isReceived = order.status == 'received';
    final dateStr = DateFormat('dd MMM yyyy').format(order.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.supplierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('OC-${order.id.substring(0, 5).toUpperCase()} • $dateStr', 
                           style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                _StatusChip(status: order.status),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monto Total', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                    Text(currencyFmt.format(order.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
                  ],
                ),
                if (!isReceived)
                  ElevatedButton.icon(
                    onPressed: onReceive,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Recibir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Completado', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isReceived = status == 'received';
    final color = isReceived ? Colors.green : Colors.orange;
    final label = isReceived ? 'Recibida' : 'Pendiente';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
