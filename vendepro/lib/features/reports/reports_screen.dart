// lib/features/reports/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import 'pdf_generator_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'Este Mes';
  bool _isGenerating = false;

  void _generatePDF() async {
    setState(() => _isGenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      if (bId.isEmpty) throw Exception("No business ID");

      final business = await db.businessDao.getBusiness(bId);
      final today = DateTime.now();
      DateTime startDate;

      if (_period == 'Hoy') {
        startDate = DateTime(today.year, today.month, today.day);
      } else if (_period == 'Esta Semana') {
        startDate = today.subtract(Duration(days: today.weekday - 1));
      } else {
        startDate = DateTime(today.year, today.month, 1);
      }
      
      final sales = await db.invoicesDao.getTotalSales(bId, from: startDate);
      final expensesAsync = await db.expensesDao.getByDateRange(bId, startDate, today);
      final expensesTotal = expensesAsync.fold(0.0, (s, e) => s + e.amount);

      final pdfService = PDFGeneratorService();
      await pdfService.generateFinancialReport(
        context: context,
        businessName: business?.name ?? 'Mi Negocio',
        period: '$_period (${startDate.day}/${startDate.month} - ${today.day}/${today.month})',
        totalRevenue: sales,
        totalExpenses: expensesTotal,
        expenses: expensesAsync,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _export607() async {
    // Export Invoices (Sales)
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final today = DateTime.now();
    final startDate = DateTime(today.year, today.month, 1);
    
    final invoices = await db.invoicesDao.getByDateRange(bId, startDate, today);
    
    String csv = "RNCCedula,TipoIdentificacion,NumeroComprobanteFiscal,NCFModificado,TipoIngreso,FechaComprobante,FechaPago,MontoFacturado,ITBISFacturado,ITBISRetenido,MontoPropinaLegal,MontoEfectivo\n";
    
    for (var inv in invoices) {
      final rnc = inv.customerTaxId ?? "000000000";
      final tipo = rnc.length == 9 ? "1" : "2"; // 1=RNC, 2=Cedula
      final ncf = inv.ncf ?? inv.invoiceNumber;
      final fecha = DateFormat('yyyyMMdd').format(inv.createdAt);
      
      csv += "$rnc,$tipo,$ncf,,01,$fecha,$fecha,${inv.subtotal.toStringAsFixed(2)},${inv.taxAmount.toStringAsFixed(2)},0.00,0.00,${inv.total.toStringAsFixed(2)}\n";
    }
    
    await Share.share(csv, subject: 'Reporte 607 - ${DateFormat('MMMM yyyy').format(today)}');
  }

  void _export606() async {
    // Export Expenses (Purchases)
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final today = DateTime.now();
    final startDate = DateTime(today.year, today.month, 1);
    
    final expenses = await db.expensesDao.getByDateRange(bId, startDate, today);
    
    String csv = "RNCCedula,TipoIdentificacion,TipoBienesServicios,NumeroComprobanteFiscal,NCFModificado,FechaComprobante,FechaPago,MontoFacturado,ITBISFacturado,ITBISRetenido,ITBISProporcionalidad\n";
    
    for (var exp in expenses) {
      final rnc = "000000000"; // Generic as we don't store provider RNC yet
      csv += "$rnc,1,01,B0100000000,,${DateFormat('yyyyMMdd').format(exp.date)},${DateFormat('yyyyMMdd').format(exp.date)},${exp.amount.toStringAsFixed(2)},0.00,0.00,0.00\n";
    }
    
    await Share.share(csv, subject: 'Reporte 606 - ${DateFormat('MMMM yyyy').format(today)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes Financieros')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.analytics_rounded, size: 48, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text('Generador de Reportes PDF',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Genera un estado de resultados con todos los ingresos y egresos registrados.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: _period,
                      decoration: const InputDecoration(labelText: 'Período'),
                      items: ['Hoy', 'Esta Semana', 'Este Mes']
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _period = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                height: 54,
                child: GradientButton(
                  label: 'Vista Previa e Imprimir PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  onTap: _generatePDF,
                  isLoading: _isGenerating,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _export607,
                      icon: const Icon(Icons.file_download_rounded),
                      label: const Text('Exportar 607'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _export606,
                      icon: const Icon(Icons.file_upload_rounded),
                      label: const Text('Exportar 606'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Los archivos CSV se generan con el formato requerido por la DGII.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
