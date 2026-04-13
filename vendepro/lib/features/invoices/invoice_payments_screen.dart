// lib/features/invoices/invoice_payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';

class InvoicePaymentsScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const InvoicePaymentsScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoicePaymentsScreen> createState() => _InvoicePaymentsScreenState();
}

class _InvoicePaymentsScreenState extends ConsumerState<InvoicePaymentsScreen> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _isSaving = false;

  static const _methods = [
    ('cash', 'Efectivo', Icons.money_rounded),
    ('card', 'Tarjeta', Icons.credit_card_rounded),
    ('transfer', 'Transferencia', Icons.account_balance_rounded),
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _registerPayment(Invoice invoice, List<InvoicePayment> existing) async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese un monto válido')));
      return;
    }

    final alreadyPaid = existing.fold(0.0, (s, p) => s + p.amount);
    final remaining = invoice.total - alreadyPaid;
    if (amount > remaining + 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('El monto supera el saldo pendiente: \$${remaining.toStringAsFixed(2)}'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      await db.into(db.invoicePayments).insert(InvoicePaymentsCompanion.insert(
        id: const Uuid().v4(),
        invoiceId: widget.invoiceId,
        businessId: bId,
        amount: amount,
        method: drift.Value(_method),
        notes: drift.Value(_notesCtrl.text.isEmpty ? null : _notesCtrl.text),
      ));

      // If fully paid, update invoice status
      final newTotal = alreadyPaid + amount;
      if (newTotal >= invoice.total - 0.01) {
        await db.invoicesDao.upsert(invoice.toCompanion(true).copyWith(
          status: const drift.Value('paid'),
        ));
      }

      _amountCtrl.clear();
      _notesCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abono registrado'), backgroundColor: AppColors.success),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final moneyFmt = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas por Cobrar')),
      body: FutureBuilder<Invoice?>(
        future: db.invoicesDao.getById(widget.invoiceId),
        builder: (context, invoiceSnap) {
          if (!invoiceSnap.hasData) return const Center(child: CircularProgressIndicator());
          final invoice = invoiceSnap.data!;

          return FutureBuilder<List<InvoicePayment>>(
            future: (db.select(db.invoicePayments)..where((p) => p.invoiceId.equals(widget.invoiceId))).get(),
            builder: (context, paymentsSnap) {
              final payments = paymentsSnap.data ?? [];
              final paid = payments.fold(0.0, (s, p) => s + p.amount);
              final total = invoice.total;
              final remaining = (total - paid).clamp(0, double.infinity);
              final paidPct = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice summary card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.gradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(invoice.invoiceNumber ?? 'Factura', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(invoice.customerName ?? 'Cliente General', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _SummaryCell('Total', moneyFmt.format(total)),
                              _SummaryCell('Pagado', moneyFmt.format(paid)),
                              _SummaryCell('Pendiente', moneyFmt.format(remaining), highlight: remaining > 0),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: paidPct,
                              minHeight: 10,
                              backgroundColor: Colors.white.withValues(alpha: 0.3),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${(paidPct * 100).toStringAsFixed(0)}% pagado', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),

                    if (remaining > 0.01) ...[
                      const SizedBox(height: 24),
                      Text('Registrar Abono', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      // Method selector
                      Row(
                        children: _methods.map((m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _method = m.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _method == m.$1 ? AppColors.primary.withValues(alpha: 0.1) : null,
                                  border: Border.all(color: _method == m.$1 ? AppColors.primary : Colors.grey.shade300, width: _method == m.$1 ? 2 : 1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(m.$3, color: _method == m.$1 ? AppColors.primary : Colors.grey, size: 20),
                                    const SizedBox(height: 4),
                                    Text(m.$2, style: TextStyle(fontSize: 11, color: _method == m.$1 ? AppColors.primary : Colors.grey, fontWeight: _method == m.$1 ? FontWeight.bold : FontWeight.normal)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Monto del abono',
                          hintText: 'Pendiente: \$${remaining.toStringAsFixed(2)}',
                          prefixIcon: const Icon(Icons.attach_money_rounded),
                          border: const OutlineInputBorder(),
                          suffixText: 'máx. \$${remaining.toStringAsFixed(2)}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                          prefixIcon: Icon(Icons.note_alt_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : () => _registerPayment(invoice, payments),
                        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                        icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded),
                        label: const Text('Registrar Abono', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ] else
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Row(children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.success),
                          SizedBox(width: 12),
                          Text('Factura totalmente pagada', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                        ]),
                      ),

                    const SizedBox(height: 24),
                    if (payments.isNotEmpty) ...[
                      Text('Historial de Abonos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...payments.map((p) {
                        final methodIcon = _methods.firstWhere((m) => m.$1 == p.method, orElse: () => _methods.first).$3;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: AppColors.success.withValues(alpha: 0.15), child: Icon(methodIcon, color: AppColors.success, size: 20)),
                            title: Text(moneyFmt.format(p.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(dateFmt.format(p.paidAt) + (p.notes != null ? '\n${p.notes}' : '')),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(p.method.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _SummaryCell(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: highlight ? Colors.yellow.shade200 : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
