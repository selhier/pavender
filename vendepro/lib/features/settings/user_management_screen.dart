// lib/features/settings/user_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final bId = ref.watch(currentBusinessIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Usuarios')),
      body: FutureBuilder<List<AppUser>>(
        // We'll need a method in AuthDao to list users by business
        future: _getUsers(db, bId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!;

          if (users.isEmpty) {
            return IllustrationEmptyState(
              primaryIcon: Icons.people_rounded,
              secondaryIcon: Icons.add_moderator_rounded,
              title: 'Sin empleados',
              subtitle: 'Crea cuentas para tus empleados y asigna roles como Cajero o Administrador.',
              actionLabel: 'Agregar Usuario',
              onAction: () => _showAddUserDialog(context, ref),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final user = users[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: user.role == 'admin' ? AppColors.primary : AppColors.accent,
                    child: Icon(
                      user.role == 'admin' ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(user.email, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(user.role == 'admin' ? 'Administrador' : 'Cajero'),
                  trailing: const Icon(Icons.edit_rounded, size: 20),
                  onTap: () {
                    // Edit logic
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUserDialog(context, ref),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Nuevo Usuario'),
      ),
    );
  }

  Future<List<AppUser>> _getUsers(AppDatabase db, String bId) async {
     // For now select all, later filter by bId if needed
     return (db.select(db.appUsers)..where((u) => u.businessId.equals(bId))).get();
  }

  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'cashier';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Agregar Usuario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Contraseña / PIN'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                ],
                onChanged: (v) => setState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (userCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
                
                final db = ref.read(databaseProvider);
                final bId = ref.read(currentBusinessIdProvider);
                final newId = const Uuid().v4();
                
                // In production use a proper password hasher
                await db.authDao.register(AppUsersCompanion(
                  id: drift.Value(newId),
                  email: drift.Value(userCtrl.text.trim()),
                  passwordHash: drift.Value(passCtrl.text), // Plain for now, in prod use Argon2/BCrypt
                  role: drift.Value(role),
                  businessId: drift.Value(bId),
                ));

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}
