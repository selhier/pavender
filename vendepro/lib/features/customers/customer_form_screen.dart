// lib/features/customers/customer_form_screen.dart
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../core/utils/dr_utils.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormScreen({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormScreen> createState() =>
      _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) _loadCustomer();
  }

  Future<void> _loadCustomer() async {
    final db = ref.read(databaseProvider);
    final c = await db.customersDao.getById(widget.customerId!);
    if (c != null && mounted) {
      setState(() {
        _name.text = c.name;
        _phone.text = c.phone ?? '';
        _email.text = c.email ?? '';
        _address.text = c.address ?? '';
        _taxId.text = c.taxId ?? '';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final syncService = ref.read(syncServiceProvider);
      final bId = ref.read(currentBusinessIdProvider);
      final id = widget.customerId ?? const Uuid().v4();

      await db.customersDao.upsert(CustomersCompanion(
        id: drift.Value(id),
        name: drift.Value(_name.text.trim()),
        phone: drift.Value(
            _phone.text.isEmpty ? null : _phone.text.trim()),
        email: drift.Value(
            _email.text.isEmpty ? null : _email.text.trim()),
        address: drift.Value(
            _address.text.isEmpty ? null : _address.text.trim()),
        taxId: drift.Value(
            _taxId.text.isEmpty ? null : _taxId.text.trim()),
        businessId: drift.Value(bId),
        updatedAt: drift.Value(DateTime.now()),
      ));

      await syncService.enqueueChange(
        entity: 'customers',
        entityId: id,
        operation: widget.customerId == null ? 'create' : 'update',
        data: {
          'name': _name.text,
          'phone': _phone.text,
          'email': _email.text,
          'businessId': bId,
        },
      );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customerId != null;
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'Editar Cliente' : 'Nuevo Cliente'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Avatar circle
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 40),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Nombre completo *',
                    prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined)),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                    labelText: 'Dirección',
                    prefixIcon: Icon(Icons.location_on_outlined)),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxId,
                decoration: InputDecoration(
                    labelText: _taxId.text.length <= 9 ? 'RNC (9 dígitos)' : 'Cédula (11 dígitos)',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    helperText: 'Validación para Rep. Dominicana',
                ),
                onChanged: (v) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final clean = v.replaceAll(RegExp(r'[^0-9]'), '');
                  if (clean.length != 9 && clean.length != 11) {
                    return 'Debe tener 9 o 11 dígitos';
                  }
                  if (!DRUtils.isValidTaxId(clean)) {
                    return 'Número inválido para RD';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              GradientButton(
                label: isEdit ? 'Guardar Cambios' : 'Crear Cliente',
                icon: isEdit ? Icons.save_rounded : Icons.person_add_rounded,
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _taxId.dispose();
    super.dispose();
  }
}
