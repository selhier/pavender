// lib/features/invoices/invoice_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  String _filterStatus = 'all';
  String _search = '';

  static const _statuses = [
    ('all', 'Todas'),
    ('paid', 'Pagadas'),
    ('issued', 'Emitidas'),
    ('draft', 'Borradores'),
    ('cancelled', 'Canceladas'),
  ];

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded),
            color: AppColors.primary,
            onPressed: () => context.push('/invoices/new'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _statuses
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(s.$2),
                          selected: _filterStatus == s.$1,
                          onSelected: (v) =>
                              setState(() => _filterStatus = s.$1),
                          selectedColor:
                              AppColors.primary.withOpacity(0.2),
                          checkmarkColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _filterStatus == s.$1
                                ? AppColors.primary
                                : Colors.grey,
                            fontWeight: _filterStatus == s.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppSearchBar(
              hint: 'Buscar por número o cliente...',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: invoicesAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (invoices) {
                var filtered = invoices;
                if (_filterStatus != 'all') {
                  filtered = filtered
                      .where((i) => i.status == _filterStatus)
                      .toList();
                }
                if (_search.isNotEmpty) {
                  final q = _search.toLowerCase();
                  filtered = filtered
                      .where((i) =>
                          (i.invoiceNumber?.toLowerCase().contains(q) ??
                              false) ||
                          (i.customerName?.toLowerCase().contains(q) ??
                              false))
                      .toList();
                }

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Sin facturas',
                    subtitle: 'Crea tu primera factura',
                    actionLabel: 'Crear Factura',
                    onAction: () => context.push('/invoices/new'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final inv = filtered[i];
                    return _InvoiceCard(invoice: inv)
                        .animate(delay: (i * 40).ms)
                        .fadeIn()
                        .slideX(begin: 0.05);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final dynamic invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    return Card(
      child: InkWell(
        onTap: () => context.push('/invoices/${invoice.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Number badge
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          invoice.invoiceNumber ?? 'FAC-000',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          '\$${invoice.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            invoice.customerName ?? 'Cliente general',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: invoice.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFmt.format(invoice.createdAt),
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
