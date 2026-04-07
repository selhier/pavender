// lib/features/platform_admin/platform_admin_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/providers/providers.dart';

class PlatformAdminScreen extends ConsumerWidget {
  const PlatformAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firestore = ref.watch(firestoreProvider);
    final currFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppColors.gradientAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Panel de Plataforma'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        backgroundColor: AppColors.darkBg,
      ),
      backgroundColor: AppColors.darkBg,
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('businesses').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accent));
          }

          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.grey, size: 48),
                  const SizedBox(height: 12),
                  Text('Sin conexión a internet\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final businesses = snap.data?.docs ?? [];

          return FutureBuilder<List<_BusinessStats>>(
            future: _fetchStats(firestore, businesses),
            builder: (context, statsSnap) {
              if (!statsSnap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }

              final stats = statsSnap.data!;
              final grandTotal =
                  stats.fold<double>(0, (s, b) => s + b.totalSales);
              final grandCommission =
                  stats.fold<double>(0, (s, b) => s + b.commission);

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Header banner
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientAccent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🚀 Panel Administrativo',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Resumen de todos los negocios activos',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _AdminStat(
                                    label: 'Total Ventas',
                                    value: currFmt.format(grandTotal),
                                  ),
                                  const SizedBox(width: 20),
                                  _AdminStat(
                                    label: 'Tu Comisión',
                                    value: currFmt.format(grandCommission),
                                  ),
                                  const SizedBox(width: 20),
                                  _AdminStat(
                                    label: 'Negocios',
                                    value: '${businesses.length}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ).animate().fadeIn().slideY(begin: -0.1),
                        const SizedBox(height: 24),

                        Text(
                          'Detalle por Negocio',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 12),

                        ...stats.asMap().entries.map((e) {
                          return _BusinessCard(
                            stats: e.value,
                            index: e.key,
                            currFmt: currFmt,
                          );
                        }),
                      ]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_BusinessStats>> _fetchStats(
      FirebaseFirestore firestore, List<QueryDocumentSnapshot> businesses) async {
    final results = <_BusinessStats>[];

    for (final bDoc in businesses) {
      final invoicesSnap = await firestore
          .collection('businesses')
          .doc(bDoc.id)
          .collection('invoices')
          .where('status', isEqualTo: 'paid')
          .get();

      double totalSales = 0;
      for (final inv in invoicesSnap.docs) {
        totalSales += (inv.data()['total'] as num?)?.toDouble() ?? 0;
      }

      final bData = bDoc.data() as Map<String, dynamic>;
      final commissionRate =
          (bData['commissionRate'] as num?)?.toDouble() ?? 5.0;
      final commission = totalSales * commissionRate / 100;

      results.add(_BusinessStats(
        id: bDoc.id,
        name: bData['name'] as String? ?? 'Negocio sin nombre',
        commissionRate: commissionRate,
        totalSales: totalSales,
        commission: commission,
        invoiceCount: invoicesSnap.docs.length,
      ));
    }

    results.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return results;
  }
}

class _BusinessStats {
  final String id;
  final String name;
  final double commissionRate;
  final double totalSales;
  final double commission;
  final int invoiceCount;

  _BusinessStats({
    required this.id,
    required this.name,
    required this.commissionRate,
    required this.totalSales,
    required this.commission,
    required this.invoiceCount,
  });
}

class _BusinessCard extends StatelessWidget {
  final _BusinessStats stats;
  final int index;
  final NumberFormat currFmt;

  const _BusinessCard({
    required this.stats,
    required this.index,
    required this.currFmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stats.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text('ID: ${stats.id}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${stats.commissionRate}%',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.darkBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatMini(
                  label: 'Ventas Totales',
                  value: currFmt.format(stats.totalSales),
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _StatMini(
                  label: 'Tu Comisión',
                  value: currFmt.format(stats.commission),
                  color: AppColors.accent,
                ),
              ),
              Expanded(
                child: _StatMini(
                  label: 'Facturas',
                  value: '${stats.invoiceCount}',
                  color: AppColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: (index * 80).ms)
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, duration: 400.ms);
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatMini(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AdminStat extends StatelessWidget {
  final String label;
  final String value;
  const _AdminStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18),
        ),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.8), fontSize: 11),
        ),
      ],
    );
  }
}
