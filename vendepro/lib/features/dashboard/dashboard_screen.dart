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
  final List invoices;
  final NumberFormat currencyFmt;

  const _KpiRow({
    required this.salesToday,
    required this.salesMonth,
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
        title: 'Facturas Pagadas',
        value: '$paidCount',
        subtitle: 'total: ${invoices.length}',
        icon: Icons.receipt_rounded,
        gradient: AppColors.gradientSuccess,
        index: 2,
      ),
    ];

    if (isWide) {
      return SizedBox(
        height: 160,
        child: Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: c,
                    ),
                  ))
              .toList(),
        ),
      );
    }

    return SizedBox(
      height: 160,
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
          icon: Icons.bar_chart_rounded,
          label: 'Reportes',
          color: AppColors.secondary,
          onTap: () => context.go('/invoices')),
    ];

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
                padding: EdgeInsets.only(right: e.key < actions.length - 1 ? 8 : 0),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
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
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.9, 0.9));
  }
}

class _SalesChart extends StatelessWidget {
  final List invoices;
  const _SalesChart({required this.invoices});

  @override
  Widget build(BuildContext context) {
    // Group paid invoices by day (last 7 days)
    final now = DateTime.now();
    final spots = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final total = invoices
          .where((inv) =>
              inv != null &&
              inv.status == 'paid' &&
              inv.createdAt != null &&
              inv.createdAt.day == day.day &&
              inv.createdAt.month == day.month)
          .fold<double>(0, (sum, inv) => sum + ((inv.total ?? 0.0) as double));
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
          Text('Ventas Últimos 7 Días',
              style: Theme.of(context).textTheme.titleSmall),
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
                    spots: spots,
                    isCurved: true,
                    gradient: AppColors.gradient,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withOpacity(0.3),
                          AppColors.primary.withOpacity(0.0),
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

class _InvoiceTile extends StatelessWidget {
  final dynamic invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
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
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
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
    return IconButton(
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
