// lib/features/quotes/quote_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class QuoteDetailScreen extends ConsumerWidget {
  final String quoteId;
  const QuoteDetailScreen({super.key, required this.quoteId});

  Future<void> _convertToInvoice(BuildContext context, WidgetRef ref, Quote quote) async {
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final items = await db.quotesDao.getItems(quote.id);
    
    final invId = const Uuid().v4();
    final today = DateTime.now();
    final invNum = 'F-${DateFormat('Hm').format(today)}';

    try {
      // 1. Create Invoice
      await db.invoicesDao.insertInvoice(InvoicesCompanion(
        id: drift.Value(invId),
        invoiceNumber: drift.Value(invNum),
        customerId: drift.Value(quote.customerId),
        customerName: drift.Value(quote.customerName),
        subtotal: drift.Value(quote.subtotal),
        taxAmount: drift.Value(quote.taxAmount),
        total: drift.Value(quote.total),
        status: const drift.Value('issued'),
        paymentMethod: const drift.Value('cash'),
        businessId: drift.Value(bId),
        createdAt: drift.Value(today),
      ));

      // 2. Create Items & Update Stock
      for (final item in items) {
        await db.invoicesDao.insertItem(InvoiceItemsCompanion(
          id: drift.Value(const Uuid().v4()),
          invoiceId: drift.Value(invId),
          productId: drift.Value(item.productId),
          productName: drift.Value(item.productName),
          unitPrice: drift.Value(item.unitPrice),
          quantity: drift.Value(item.quantity),
          taxAmount: drift.Value(item.taxAmount),
          subtotal: drift.Value(item.subtotal),
        ));

        // Update Stock
        final p = await db.productsDao.getById(item.productId);
        if (p != null) {
          await db.productsDao.updateStock(p.id, p.stock - item.quantity);
        }
      }

      // 3. Mark Quote as Converted
      await db.quotesDao.updateStatus(quote.id, 'converted');

      if (context.mounted) {
        context.push('/invoices/$invId');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de Cotización')),
      body: FutureBuilder(
        future: Future.wait([
          db.quotesDao.getById(quoteId),
          db.quotesDao.getItems(quoteId),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final quote = snapshot.data![0] as Quote;
          final items = snapshot.data![1] as List<QuoteItem>;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(quote.quoteNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('Creado el ${DateFormat('dd/MM/yyyy').format(quote.createdAt)}'),
                      ],
                    ),
                    _StatusChip(status: quote.status),
                  ],
                ),
                const SizedBox(height: 32),
                Text('CLIENTE: ${quote.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(height: 48),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return ListTile(
                        title: Text(item.productName),
                        trailing: Text(currencyFmt.format(item.subtotal)),
                        subtitle: Text('${item.quantity} x ${currencyFmt.format(item.unitPrice)}'),
                      );
                    },
                  ),
                ),
                const Divider(),
                _SummaryRow('Total', currencyFmt.format(quote.total), isBold: true),
                const SizedBox(height: 32),
                if (quote.status == 'pending')
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: GradientButton(
                      label: 'Convertir en Factura',
                      icon: Icons.receipt_long_rounded,
                      onTap: () => _convertToInvoice(context, ref, quote),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _SummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null, fontSize: isBold ? 18 : null)),
        Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null, fontSize: isBold ? 18 : null, color: AppColors.primary)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = status == 'pending' ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
