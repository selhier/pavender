import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/database/app_database.dart';

class CashShiftScreen extends ConsumerStatefulWidget {
  const CashShiftScreen({super.key});

  @override
  ConsumerState<CashShiftScreen> createState() => _CashShiftScreenState();
}

class _CashShiftScreenState extends ConsumerState<CashShiftScreen> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _processSession(bool isOpenSession, CashSession? currentSession) async {
    final amountText = _amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(amountText) ?? 0.0;
    
    if (amount <= 0 && !isOpenSession) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese el monto contado')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final fUser = ref.read(authStateProvider).valueOrNull;
      final lUser = ref.read(localUserProvider);
      final userId = lUser?.id ?? fUser?.uid;
      if (userId == null) throw Exception("Usuario no autenticado");

      if (isOpenSession) {
        // OPEN SHIFT
        final uuid = const Uuid().v4();
        await db.cashSessionsDao.openSession(CashSessionsCompanion.insert(
          id: uuid,
          businessId: bId,
          cashierId: userId,
          startingCash: drift.Value(amount),
          notes: drift.Value(_notesCtrl.text),
        ));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turno de caja abierto exitosamente.'), backgroundColor: AppColors.success));
      } else {
        // CLOSE SHIFT
        if (currentSession == null) return;
        
        // Calculate theoretical cash
        final salesSinceOpen = await db.invoicesDao.getTotalSales(bId, from: currentSession.openedAt);
        // Note: For real world we should filter by PaymentMethod == Cash
        
        final expected = currentSession.startingCash + salesSinceOpen;
        final difference = amount - expected;
        
        await db.cashSessionsDao.closeSession(
          currentSession.toCompanion(true).copyWith(
            status: const drift.Value('closed'),
            closedAt: drift.Value(DateTime.now()),
            actualEndingCash: drift.Value(amount),
            calculatedEndingCash: drift.Value(expected),
            difference: drift.Value(difference),
            notes: drift.Value(_notesCtrl.text),
          )
        );
        if (mounted) {
           showDialog(
             context: context,
             builder: (ctx) => AlertDialog(
               title: const Text('Corte Z Completado'),
               content: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text('Efectivo Esperado: \$${expected.toStringAsFixed(2)}'),
                   Text('Efectivo Real: \$${amount.toStringAsFixed(2)}'),
                   Divider(),
                   Text('Diferencia: \$${difference.toStringAsFixed(2)}', 
                     style: TextStyle(color: difference < 0 ? AppColors.error : AppColors.success, fontWeight: FontWeight.bold)),
                 ],
               ),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))
               ],
             )
           );
        }
      }
      _amountCtrl.clear();
      _notesCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final bId = ref.watch(currentBusinessIdProvider);
    final fUser = ref.watch(authStateProvider).valueOrNull;
    final lUser = ref.watch(localUserProvider);
    final userId = lUser?.id ?? fUser?.uid;
    final fmt = DateFormat('dd/MM/yyyy hh:mm a');

    if (userId == null) return const Scaffold(body: Center(child: Text('Usuario no disponible')));

    return Scaffold(
      appBar: AppBar(title: const Text('Control de Caja (Turnos)')),
      body: FutureBuilder<CashSession?>(
        future: db.cashSessionsDao.getActiveSession(bId, userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snapshot.data;
          final isOpen = session != null;

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isOpen ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(isOpen ? Icons.lock_open_rounded : Icons.lock_rounded, 
                        color: isOpen ? AppColors.success : AppColors.warning, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isOpen ? 'Turno Activo' : 'Caja Cerrada', 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            if (isOpen) ...[
                              const SizedBox(height: 4),
                              Text('Abierto desde: ${fmt.format(session.openedAt)}'),
                              Text('Fondo inicial: \$${session.startingCash.toStringAsFixed(2)}'),
                            ]
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isOpen ? 'Efectivo actual contado' : 'Fondo inicial base',
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    prefixIcon: Icon(Icons.note_alt_rounded),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const Spacer(),
                if (_isLoading)
                   const Center(child: CircularProgressIndicator())
                else
                  FilledButton.icon(
                    onPressed: () => _processSession(!isOpen, session),
                    style: FilledButton.styleFrom(
                      backgroundColor: isOpen ? AppColors.error : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: Icon(isOpen ? Icons.calculate_rounded : Icons.point_of_sale_rounded),
                    label: Text(isOpen ? 'Realizar Cierre Z' : 'Abrir Turno de Caja', style: const TextStyle(fontSize: 16)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
