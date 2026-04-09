// lib/features/reports/pdf_generator_service.dart
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/database/app_database.dart';
import 'package:intl/intl.dart';

class PDFGeneratorService {
  Future<void> generateFinancialReport({
    required BuildContext context,
    required String businessName,
    required String period,
    required double totalRevenue,
    required double totalExpenses,
    required List<Expense> expenses,
  }) async {
    final pdf = pw.Document();
    
    final profit = totalRevenue - totalExpenses;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
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
                      pw.Text(businessName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Reporte Financiero', style: const pw.TextStyle(fontSize: 14)),
                      pw.Text('Período: $period', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text('Generado: ${DateFormat('dd MMM yyyy').format(DateTime.now())}'),
                ],
              ),
              pw.SizedBox(height: 30),
              
              // Summary Metrics
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricBox('INGRESOS', totalRevenue, PdfColors.green700),
                    _buildMetricBox('EGRESOS', totalExpenses, PdfColors.red700),
                    _buildMetricBox('UTILIDAD', profit, profit >= 0 ? PdfColors.blue700 : PdfColors.orange700),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 30),
              
              // Expenses Details Table
              pw.Text('Detalle de Egresos', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              if (expenses.isEmpty)
                pw.Text('No se registraron egresos en este periodo.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic))
              else
                pw.TableHelper.fromTextArray(
                  context: ctx,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6C63FF)),
                  rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
                  data: <List<String>>[
                    <String>['Fecha', 'Categoría', 'Descripción', 'Monto'],
                    ...expenses.map((e) => [
                      DateFormat('dd/MM/yyyy').format(e.date),
                      e.category,
                      e.description,
                      '\$${e.amount.toStringAsFixed(2)}'
                    ]),
                  ],
                ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Reporte_Financiero_${businessName.replaceAll(' ', '_')}.pdf',
    );
  }

  Future<void> generateInvoiceStandard({
    required Invoice invoice,
    required List<InvoiceItem> items,
    BusinessesData? business,
  }) async {
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
              if (invoice.customerTaxId != null)
                pw.Text('RNC/Cédula: ${invoice.customerTaxId}',
                    style: const pw.TextStyle(fontSize: 11)),
              if (invoice.ncf != null)
                pw.Text('NCF: ${invoice.ncf}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
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
              pw.SizedBox(height: 40),
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
      filename: 'factura_${invoice.invoiceNumber}.pdf',
    );
  }

  Future<void> generateInvoiceTicket({
    required Invoice invoice,
    required List<InvoiceItem> items,
    BusinessesData? business,
  }) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('dd/MM/yy HH:mm');
    // POS format (80mm)
    const format = PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(business?.name.toUpperCase() ?? 'VENDEPRO',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
              if (business?.address != null)
                pw.Text(business!.address!, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
              if (business?.phone != null)
                pw.Text('Tel: ${business!.phone!}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 5),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('FACTURA: ${invoice.invoiceNumber}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(dateFmt.format(invoice.createdAt), style: const pw.TextStyle(fontSize: 9)),
              if (invoice.ncf != null)
                pw.Text('NCF: ${invoice.ncf}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 5),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('CLIENTE: ${invoice.customerName ?? 'General'}', style: const pw.TextStyle(fontSize: 9)),
              ),
              if (invoice.customerTaxId != null)
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text('RNC: ${invoice.customerTaxId}', style: const pw.TextStyle(fontSize: 9)),
                ),
              pw.SizedBox(height: 5),
              pw.Text('*** DETALLE ***', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 3),
              ...items.map((item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.productName, style: const pw.TextStyle(fontSize: 9)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('\$${item.subtotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              )),
              pw.SizedBox(height: 5),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 10)),
              _ticketRow('SUBTOTAL:', '\$${invoice.subtotal.toStringAsFixed(2)}'),
              _ticketRow('ITBIS:', '\$${invoice.taxAmount.toStringAsFixed(2)}'),
              _ticketRow('TOTAL:', '\$${invoice.total.toStringAsFixed(2)}', isBold: true),
              pw.SizedBox(height: 10),
              pw.Text('¡GRACIAS POR SU COMPRA!', style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('VendePro v1.0', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ticket_${invoice.invoiceNumber}.pdf',
    );
  }

  pw.Widget _ticketRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : null)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false, bool white = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : null,
          color: white ? PdfColors.white : null,
        ),
      ),
    );
  }

  pw.Widget _buildMetricBox(String title, double value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('\$${value.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }
}

