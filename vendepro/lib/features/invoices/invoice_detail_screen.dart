// lib/features/invoices/invoice_detail_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final bId = ref.watch(currentBusinessIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Factura'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded,
                color: AppColors.accent),
            onPressed: () => _generatePdf(context, ref),
            tooltip: 'Generar PDF',
          ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([
          db.invoicesDao.getById(invoiceId),
          db.invoicesDao.getItems(invoiceId),
          db.businessDao.getBusiness(bId),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final invoice = snap.data![0] as Invoice?;
          final items = snap.data![1] as List<InvoiceItem>;
          final business = snap.data![2] as BusinessesData?;

          if (invoice == null) {
            return const Center(child: Text('Factura no encontrada'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                _InvoiceHeader(invoice: invoice, business: business),
                const SizedBox(height: 20),
                // Items
                _ItemsSection(items: items),
                const SizedBox(height: 20),
                // Totals
                _TotalsSection(invoice: invoice),
                const SizedBox(height: 20),
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        label: 'Generar PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        gradient: AppColors.gradientAccent,
                        onTap: () => _generatePdf(context, ref),
                      ),
                    ),
                    if (invoice.status == 'issued') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: 'Marcar Pagado',
                          icon: Icons.check_circle_rounded,
                          gradient: AppColors.gradientSuccess,
                          onTap: () async {
                            await db.invoicesDao
                                .updateStatus(invoiceId, 'paid');
                            if (context.mounted) context.pop();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _generatePdf(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final invoice = await db.invoicesDao.getById(invoiceId);
    final items = await db.invoicesDao.getItems(invoiceId);
    final business = await db.businessDao.getBusiness(bId);

    if (invoice == null) return;

    final pdf = pw.Document();
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(business?.name ?? 'Mi Negocio',
                          style: pw.TextStyle(
                              fontSize: 22, fontWeight: pw.FontWeight.bold)),
                      if (business?.address != null)
                        pw.Text(business!.address!,
                            style: const pw.TextStyle(fontSize: 11)),
                      if (business?.phone != null)
                        pw.Text('Tel: ${business!.phone!}',
                            style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('FACTURA',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#6C63FF'))),
                      pw.Text(invoice.invoiceNumber,
                          style: const pw.TextStyle(fontSize: 13)),
                      pw.Text(dateFmt.format(invoice.createdAt),
                          style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 12),
              // Customer
              pw.Text('FACTURADO A:',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10,
                      color: PdfColors.grey700)),
              pw.Text(invoice.customerName ?? 'Cliente general',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              // Items table
              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6C63FF)),
                    children: [
                      _pdfCell('PRODUCTO', bold: true, white: true),
                      _pdfCell('CANT.', bold: true, white: true),
                      _pdfCell('PRECIO', bold: true, white: true),
                      _pdfCell('SUBTOTAL', bold: true, white: true),
                    ],
                  ),
                  ...items.map((item) => pw.TableRow(
                    children: [
                      _pdfCell(item.productName),
                      _pdfCell('${item.quantity}'),
                      _pdfCell('\$${item.unitPrice.toStringAsFixed(2)}'),
                      _pdfCell('\$${item.subtotal.toStringAsFixed(2)}'),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 12),
              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          'Subtotal: \$${invoice.subtotal.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 12)),
                      pw.Text(
                          'Impuesto: \$${invoice.taxAmount.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 12)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'TOTAL: \$${invoice.total.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#6C63FF'))),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Center(
                child: pw.Text('Gracias por su compra • VendePro',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  static pw.Widget _pdfCell(String text, {bool bold = false, bool white = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: bold ? pw.FontWeight.bold : null,
          color: white ? PdfColors.white : null,
        ),
      ),
    );
  }
}

class _InvoiceHeader extends StatelessWidget {
  final dynamic invoice;
  final dynamic business;
  const _InvoiceHeader({required this.invoice, this.business});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.invoiceNumber ?? '---',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22),
                  ),
                  Text(
                    business?.name ?? 'Mi Negocio',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                ],
              ),
              StatusBadge(status: invoice.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                invoice.customerName ?? 'Cliente general',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.payment_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                _paymentLabel(invoice.paymentMethod),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String? method) {
    switch (method) {
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return 'Efectivo';
    }
  }
}

class _ItemsSection extends StatelessWidget {
  final List items;
  const _ItemsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Productos',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const Divider(height: 1),
          ...items.map((item) => ListTile(
                title: Text(item.productName,
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                    '${item.quantity} × \$${item.unitPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: Text(
                  '\$${item.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              )),
        ],
      ),
    );
  }
}

class _TotalsSection extends StatelessWidget {
  final dynamic invoice;
  const _TotalsSection({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          _TotalRow('Subtotal', '\$${invoice.subtotal.toStringAsFixed(2)}'),
          _TotalRow('Impuesto', '\$${invoice.taxAmount.toStringAsFixed(2)}'),
          if ((invoice.discountAmount as double) > 0)
            _TotalRow('Descuento',
                '-\$${invoice.discountAmount.toStringAsFixed(2)}',
                color: AppColors.success),
          const Divider(),
          _TotalRow('TOTAL', '\$${invoice.total.toStringAsFixed(2)}',
              isTotal: true),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? color;
  const _TotalRow(this.label, this.value, {this.isTotal = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight:
                      isTotal ? FontWeight.w800 : FontWeight.w500,
                  color: isTotal
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurface)),
          Text(value,
              style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight:
                      isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: color ??
                      (isTotal ? AppColors.primary : null))),
        ],
      ),
    );
  }
}
