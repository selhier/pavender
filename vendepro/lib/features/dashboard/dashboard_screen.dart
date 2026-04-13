import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider);
    final salesToday = ref.watch(salesTodayProvider);
    final salesMonth = ref.watch(salesMonthProvider);
    final invoices = ref.watch(invoicesStreamProvider);
    final lowStock = ref.watch(lowStockProvider);
    final ncfSequences = ref.watch(ncfSequencesProvider);
    final totalReceivable = ref.watch(totalReceivableProvider);
    final totalPayable = ref.watch(totalPayableProvider);

    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            snap: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
                padding:
                    const EdgeInsets.fromLTRB(20, 50, 20, 16),
                child: business.when(
                  data: (b) => Row(
                    children: [
                      if (b?.logoPath != null)
                        Container(
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: MemoryImage(base64Decode(b!.logoPath!)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '¡Hola, ${b?.name ?? "Mi Negocio"}! 👋',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              DateFormat('EEEE, d MMMM yyyy', 'es')
                                  .format(DateTime.now()),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (err, _) => Text('Error: $err'),
                ),
              ),
            ),
            actions: [
              _SyncIndicatorButton(),
              const SizedBox(width: 8),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // KPI Cards Row
                _KpiRow(
                  salesToday: salesToday.value ?? 0.0,
                  salesMonth: salesMonth.value ?? 0.0,
                  receivable: totalReceivable.value ?? 0.0,
                  payable: totalPayable.value ?? 0.0,
                  invoices: invoices.value ?? [],
                  currencyFmt: currencyFmt,
                ),
                const SizedBox(height: 24),

                // Quick actions
                _QuickActions(),
                const SizedBox(height: 24),

                // Sales chart
                _SalesChart(invoices: invoices.value ?? []),
                const SizedBox(height: 24),

                // Recent invoices
                Text(
                  'Facturas Recientes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (invoices.isLoading)
                  ...List.generate(4, (_) => const _SkeletonInvoiceTile())
                else if (invoices.hasError)
                   Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Error al cargar facturas: ${invoices.error}', style: const TextStyle(color: Colors.red)),
                    ),
                  )
                else if (invoices.value?.isEmpty ?? true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Aún no tienes facturas', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ...((invoices.value ?? []).take(5).map(
                        (inv) => _InvoiceTile(invoice: inv),
                      )),

                // Low stock alert
                if ((lowStock.value ?? []).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _LowStockAlert(products: lowStock.value!),
                ],

                // Fiscal alert (NCF running out)
                if (ncfSequences.value != null) ...[
                  _FiscalAlert(sequences: ncfSequences.value!),
                ],
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/invoices/new'),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Nueva Factura',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final double salesToday;
  final double salesMonth;
  final double receivable;
  final double payable;
  final List invoices;
  final NumberFormat currencyFmt;

  const _KpiRow({
    required this.salesToday,
    required this.salesMonth,
    required this.receivable,
    required this.payable,
    required this.invoices,
    required this.currencyFmt,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final paidCount = invoices.where((i) => i.status == 'paid').length;

    final cards = [
      StatCard(
        title: 'Ventas Hoy',
        value: currencyFmt.format(salesToday),
        icon: Icons.trending_up_rounded,
        gradient: AppColors.gradient,
        index: 0,
      ),
      StatCard(
        title: 'Ventas del Mes',
        value: currencyFmt.format(salesMonth),
        icon: Icons.calendar_month_rounded,
        gradient: AppColors.gradientAccent,
        index: 1,
      ),
      StatCard(
        title: 'Por Cobrar',
        value: currencyFmt.format(receivable),
        icon: Icons.pending_actions_rounded,
        gradient: AppColors.gradientWarning,
        index: 2,
      ),
      StatCard(
        title: 'Por Pagar',
        value: currencyFmt.format(payable),
        icon: Icons.outbox_rounded,
        gradient: const LinearGradient(colors: [Colors.blueGrey, Colors.grey]),
        index: 3,
      ),
      StatCard(
        title: 'Pagadas',
        value: '$paidCount',
        subtitle: 'total: ${invoices.length}',
        icon: Icons.receipt_rounded,
        gradient: AppColors.gradientSuccess,
        index: 4,
      ),
    ];

    if (isWide) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 180,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: cards.length,
        itemBuilder: (context, index) => cards[index],
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 200, child: cards[i]),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
          icon: Icons.add_circle_rounded,
          label: 'Nueva\nFactura',
          color: AppColors.primary,
          onTap: () => context.push('/invoices/new')),
      _QuickAction(
          icon: Icons.inventory_2_rounded,
          label: 'Agregar\nProducto',
          color: AppColors.accent,
          onTap: () => context.push('/inventory/new')),
      _QuickAction(
          icon: Icons.person_add_rounded,
          label: 'Nuevo\nCliente',
          color: AppColors.success,
          onTap: () => context.push('/customers/new')),
      _QuickAction(
          icon: Icons.point_of_sale_rounded,
          label: 'Turno\nde Caja',
          color: AppColors.secondary,
          onTap: () => context.push('/dashboard/shift')),
    ];

    final isWide = MediaQuery.of(context).size.width >= 768;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acciones Rápidas',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: actions.asMap().entries.map((e) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: e.key < actions.length - 1 ? (isWide ? 24 : 8) : 0,
                ),
                child: e.value,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.2),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.9, 0.9)),
    );
  }
}

class _SalesChart extends StatelessWidget {
  final List invoices;
  const _SalesChart({required this.invoices});

  @override
  Widget build(BuildContext context) {
    // Group paid invoices by day (last 7 days)
    final now = DateTime.now();
    
    // Current week spots
    final currentWeekSpots = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final total = invoices
          .where((inv) =>
              inv != null &&
              inv.status == 'paid' &&
              inv.createdAt != null &&
              inv.createdAt.year == day.year &&
              inv.createdAt.month == day.month &&
              inv.createdAt.day == day.day)
          .fold<double>(0.0, (sum, inv) => sum + (inv.total as double));
      return FlSpot(i.toDouble(), total);
    });

    // Previous week spots for comparison
    final previousWeekSpots = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 13 - i));
      final total = invoices
          .where((inv) =>
              inv != null &&
              inv.status == 'paid' &&
              inv.createdAt != null &&
              inv.createdAt.year == day.year &&
              inv.createdAt.month == day.month &&
              inv.createdAt.day == day.day)
          .fold<double>(0.0, (sum, inv) => sum + (inv.total as double));
      return FlSpot(i.toDouble(), total);
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Comparativa Ventas Semanales', style: Theme.of(context).textTheme.titleSmall),
              Row(
                children: [
                   _ChartLegend(label: 'Hoy', color: AppColors.primary),
                   const SizedBox(width: 12),
                   _ChartLegend(label: 'Prev.', color: Colors.grey.withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final day = now.subtract(
                            Duration(days: 6 - value.toInt()));
                        return Text(
                          DateFormat('dd/MM').format(day),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: previousWeekSpots,
                    isCurved: true,
                    color: Colors.grey.withValues(alpha: 0.3),
                    barWidth: 2,
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: currentWeekSpots,
                    isCurved: true,
                    gradient: AppColors.gradient,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.2),
                          AppColors.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final String label;
  final Color color;
  const _ChartLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final dynamic invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_rounded,
                color: AppColors.primary, size: 22),
          ),
          title: Text(
            invoice.invoiceNumber ?? '---',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            invoice.customerName ?? 'Cliente general',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${invoice.total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
              StatusBadge(status: invoice.status),
            ],
          ),
          onTap: () => context.push('/invoices/${invoice.id}'),
        ),
      ),
    );
  }
}

class _FiscalAlert extends StatelessWidget {
  final List sequences;
  const _FiscalAlert({required this.sequences});

  @override
  Widget build(BuildContext context) {
    final criticalSequences = sequences.where((s) {
      final remaining = (s.to as int) - (s.lastUsed as int);
      return remaining <= 10 && remaining > 0;
    }).toList();

    if (criticalSequences.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Alerta Fiscal: NCF Agotándose',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...criticalSequences.map((s) {
            final remaining = (s.to as int) - (s.lastUsed as int);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tipo ${s.type}', style: const TextStyle(fontSize: 13)),
                  Text('Quedan: $remaining',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _LowStockAlert extends StatelessWidget {
  final List products;
  const _LowStockAlert({required this.products});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Text(
                'Stock Bajo (${products.length} productos)',
                style: const TextStyle(
                    color: AppColors.warning, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...products.take(3).map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(p.name,
                        style: const TextStyle(fontSize: 13)),
                    Text('Stock: ${p.stock}',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SyncIndicatorButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncService = ref.watch(syncServiceProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: IconButton(
        icon: const Icon(Icons.sync_rounded),
        tooltip: 'Sincronizar',
        onPressed: () async {
          await syncService.syncPendingChanges();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sincronización completada'),
                backgroundColor: AppColors.success,
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }
}

class _SkeletonInvoiceTile extends StatelessWidget {
  const _SkeletonInvoiceTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.transparent,
      elevation: 0,
      child: Shimmer.fromColors(
        baseColor: AppColors.darkBorder,
        highlightColor: AppColors.darkCard,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          title: Container(
            width: 100,
            height: 14,
            color: Colors.white,
          ),
          subtitle: Container(
            width: 80,
            height: 12,
            margin: const EdgeInsets.only(top: 8),
            color: Colors.white,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 60,
                height: 14,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Container(
                width: 70,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
