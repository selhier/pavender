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
