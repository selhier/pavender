import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _cardFeeCtrl = TextEditingController();
  String _currency = 'USD';
  String _currencySymbol = '\$';
  bool _isLoading = false;
  String? _logoBase64;

  // Secret admin tap counter
  int _logoTapCount = 0;

  @override
  void initState() {
    super.initState();
    _loadBusiness();
  }

  Future<void> _loadBusiness() async {
    final db = ref.read(databaseProvider);
    final bId = ref.read(currentBusinessIdProvider);
    final b = await db.businessDao.getBusiness(bId);
    if (b != null && mounted) {
      setState(() {
        _nameCtrl.text = b.name;
        _addressCtrl.text = b.address ?? '';
        _phoneCtrl.text = b.phone ?? '';
        _emailCtrl.text = b.email ?? '';
        _taxCtrl.text = b.taxRate.toString();
        _currency = b.currency;
        _currencySymbol = b.currencySymbol;
        _logoBase64 = b.logoPath;
      });
    }
    final feeVal = await db.businessDao.getSetting('card_fee_percentage');
    if (mounted) setState(() => _cardFeeCtrl.text = feeVal ?? '0.0');
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final bId = ref.read(currentBusinessIdProvider);
      await db.businessDao.upsert(BusinessesCompanion(
        id: drift.Value(bId),
        name: drift.Value(_nameCtrl.text.trim()),
        address: drift.Value(
            _addressCtrl.text.isEmpty ? null : _addressCtrl.text.trim()),
        phone: drift.Value(
            _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text.trim()),
        email: drift.Value(
            _emailCtrl.text.isEmpty ? null : _emailCtrl.text.trim()),
        taxRate: drift.Value(double.tryParse(_taxCtrl.text) ?? 0.0),
        currency: drift.Value(_currency),
        currencySymbol: drift.Value(_currencySymbol),
        logoPath: drift.Value(_logoBase64),
        updatedAt: drift.Value(DateTime.now()),
      ));
      
      await db.businessDao.setSetting('card_fee_percentage', _cardFeeCtrl.text.trim().isEmpty ? '0' : _cardFeeCtrl.text.trim());
      
      // Invalidate the provider so fresh invoices pick it up immediately
      ref.invalidate(cardFeeProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración guardada'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 80,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _logoBase64 = base64Encode(bytes);
      });
    }
  }

  void _onAdminTap() {
    _logoTapCount++;
    if (_logoTapCount >= 7) {
      _logoTapCount = 0;
      _showAdminDialog();
    }
  }

  void _showAdminDialog() {
    final pwCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Acceso de Plataforma'),
        content: TextField(
          controller: pwCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña de acceso',
            hintText: 'Ingresa tu clave',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Password stored as hash in real prod; simple check for now
              if (pwCtrl.text == 'vendepro2025admin') {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/platform-admin');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contraseña incorrecta'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: LoadingOverlay(
            isLoading: _isLoading,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Business logo area (secret admin trigger - 7 taps)
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickLogo,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 2),
                            image: _logoBase64 != null
                                ? DecorationImage(
                                    image: MemoryImage(base64Decode(_logoBase64!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _logoBase64 == null
                              ? const Icon(Icons.storefront_rounded,
                                  color: AppColors.primary, size: 48)
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: AppColors.primary,
                          radius: 16,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, size: 16),
                            color: Colors.white,
                            onPressed: _pickLogo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Logo de la empresa',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 28),
    
                // Business info section
                _SectionCard(
                  title: 'Información del Negocio',
                  children: [
                    _field('Nombre del negocio', _nameCtrl,
                        icon: Icons.storefront_rounded),
                    const SizedBox(height: 12),
                    _field('Dirección', _addressCtrl,
                        icon: Icons.location_on_outlined, maxLines: 2),
                    const SizedBox(height: 12),
                    _field('Teléfono', _phoneCtrl,
                        icon: Icons.phone_outlined,
                        type: TextInputType.phone),
                    const SizedBox(height: 12),
                    _field('Email', _emailCtrl,
                        icon: Icons.email_outlined,
                        type: TextInputType.emailAddress),
                  ],
                ),
                const SizedBox(height: 16),
    
                // Fiscal section
                _SectionCard(
                  title: 'Configuración Fiscal',
                  children: [
                    _field('Tasa de impuesto (%)', _taxCtrl,
                        icon: Icons.percent_rounded,
                        type: TextInputType.number),
                    const SizedBox(height: 12),
                    _field('Comisión de Tarjeta (%)', _cardFeeCtrl,
                        icon: Icons.credit_card_rounded,
                        type: TextInputType.number),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Moneda',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                      items: [
                        'USD', 'EUR', 'MXN', 'COP', 'ARS', 'PEN', 'BOB',
                        'CLP', 'VES', 'CRC', 'GTQ', 'DOP'
                      ]
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _currency = v!;
                        _currencySymbol = _getCurrencySymbol(v);
                      }),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
                      title: const Text('Gestionar Secuencias NCF'),
                      subtitle: const Text('Configurar rangos de comprobantes'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/settings/ncf'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
    
                // Administrative section (Branch & Users)
                _SectionCard(
                  title: 'Administración Global (Solo Admin)',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.business_rounded, color: AppColors.primary),
                      title: const Text('Sucursales / Empresas'),
                      subtitle: const Text('Crear y cambiar entre sucursales'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/settings/branches'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.people_alt_rounded, color: AppColors.primary),
                      title: const Text('Gestión de Usuarios'),
                      subtitle: const Text('Cuentas para empleados y cajeros'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/settings/users'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
    
                // Hardware
                _SectionCard(
                  title: 'Hardware y Dispositivos',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.print_rounded, color: AppColors.primary),
                      title: const Text('Configuración de Impresora'),
                      subtitle: const Text('Conectar billetera térmica Bluetooth'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/settings/printer'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Preferences
                _SectionCard(
                  title: 'Preferencias y Seguridad',
                  children: [
                    SwitchListTile(
                      title: const Text('Modo Oscuro'),
                      subtitle: const Text('Interfaz oscura'),
                      value: isDark,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) =>
                          ref.read(themeModeProvider.notifier).state = v,
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Rol de Usuario'),
                      subtitle: Text(ref.watch(userRoleProvider) == 'admin' ? 'Administrador (Total)' : 'Cajero (Restringido)'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
    
                SizedBox(
                  height: 52,
                  child: GradientButton(
                    label: 'Guardar Configuración',
                    icon: Icons.save_rounded,
                    onTap: _save,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: GradientButton(
                    label: 'Cerrar Sesión',
                    icon: Icons.logout_rounded,
                    gradient: const LinearGradient(colors: [AppColors.error, Color.fromARGB(255, 235, 114, 114)]),
                    onTap: () async {
                      await ref.read(authControllerProvider.notifier).signOut(ref);
                      // The router will handle redirection to /login
                    },
                  ),
                ),
                const SizedBox(height: 32),
    
                // App version
                GestureDetector(
                  onTap: _onAdminTap,
                  child: const Center(
                    child: Text(
                      'VendePro v1.0.0\n© 2025 VendePro Platform',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    IconData? icon,
    TextInputType? type,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
    );
  }

  String _getCurrencySymbol(String code) {
    const map = {
      'USD': '\$', 'EUR': '€', 'MXN': '\$', 'COP': 'COP\$',
      'ARS': '\$', 'PEN': 'S/', 'BOB': 'Bs', 'CLP': '\$',
      'VES': 'Bs.S', 'CRC': '₡', 'GTQ': 'Q', 'DOP': 'RD\$'
    };
    return map[code] ?? '\$';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppColors.primary)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
