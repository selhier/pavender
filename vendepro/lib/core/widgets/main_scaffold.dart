// lib/core/widgets/main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _primaryItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Inicio', path: '/dashboard'),
    _NavItem(icon: Icons.receipt_long_rounded, label: 'Ventas', path: '/invoices'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'Productos', path: '/inventory'),
    _NavItem(icon: Icons.people_rounded, label: 'Clientes', path: '/customers'),
  ];

  static const _secondaryItems = [
    _NavItem(icon: Icons.description_outlined, label: 'Cotizaciones', path: '/quotes'),
    _NavItem(icon: Icons.local_shipping_outlined, label: 'Proveedores', path: '/suppliers'),
    _NavItem(icon: Icons.account_balance_wallet_rounded, label: 'Gastos', path: '/expenses'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Reportes', path: '/reports'),
    _NavItem(icon: Icons.settings_rounded, label: 'Ajustes', path: '/settings'),
  ];

  static List<_NavItem> _allNavItems(String role) {
    final all = [..._primaryItems, ..._secondaryItems];
    if (role == 'admin') return all;
    return all.where((item) => 
      item.path == '/dashboard' || 
      item.path == '/invoices' || 
      item.path == '/quotes' || 
      item.path == '/customers'
    ).toList();
  }

  int _selectedIndex(BuildContext context, List<_NavItem> items) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < items.length; i++) {
      if (location.startsWith(items[i].path)) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start/Watch the sync service
    ref.watch(syncServiceProvider);
    
    final role = ref.watch(userRoleProvider);
    final businessInfo = ref.watch(businessProvider).valueOrNull;
    final localUser = ref.watch(localUserProvider);
    final lowStock = ref.watch(lowStockProvider);
    final lowStockCount = lowStock.valueOrNull?.length ?? 0;
    final activeSession = ref.watch(activeSessionProvider).valueOrNull;
    final allItems = _allNavItems(role);
    
    // For mobile bottom bar, we only show primary items that are allowed for the role
    final bottomItems = _primaryItems.where((item) => allItems.contains(item)).toList();
    // For the drawer, we show secondary items allowed for the role
    final drawerItems = _secondaryItems.where((item) => allItems.contains(item)).toList();

    final isWide = MediaQuery.of(context).size.width >= 768;
    final selectedIdxBottom = _selectedIndex(context, bottomItems);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            Column(
              children: [
                if (businessInfo != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: const Icon(Icons.store_rounded, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          businessInfo.name, 
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                _UserAvatar(user: localUser),
                const SizedBox(height: 20),
                Expanded(
                  flex: 10,
                  child: _SideNavRail(
                    selectedIndex: _selectedIndex(context, allItems),
                    onTap: (i) => context.go(allItems[i].path),
                    items: allItems,
                    onLogout: () => ref.read(authControllerProvider.notifier).signOut(ref),
                  ),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(
                  key: ValueKey(GoRouterState.of(context).uri.path.split('/')[1]),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(businessInfo?.name ?? 'VendePro'),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          if (lowStockCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => context.go('/inventory'),
                  tooltip: '$lowStockCount producto(s) con stock bajo',
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                    child: Text('$lowStockCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          _CashStatusBadge(isOpen: activeSession != null),
          _UserAvatar(user: localUser, small: true),
        ],
      ),
      drawer: NavigationDrawer(
        backgroundColor: Theme.of(context).colorScheme.surface,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: AppColors.gradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.store_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  businessInfo?.name ?? 'Mi Negocio',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  localUser?.email ?? 'Administrador',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('Módulos', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ...drawerItems.map((item) => NavigationDrawerDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          )),
          const Divider(indent: 16, endIndent: 16),
          NavigationDrawerDestination(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            label: const Text('Cerrar Sesión', style: TextStyle(color: AppColors.error)),
          ),
        ],
        onDestinationSelected: (idx) {
          if (idx == drawerItems.length) {
            // Logout selected (last item)
            ref.read(authControllerProvider.notifier).signOut(ref);
            return;
          }
          context.go(drawerItems[idx].path);
          Navigator.pop(context);
        },
        selectedIndex: _selectedIndex(context, drawerItems) == -1 ? null : _selectedIndex(context, drawerItems),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: KeyedSubtree(
          key: ValueKey(GoRouterState.of(context).uri.path.split('/')[1]),
          child: child,
        ),
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: selectedIdxBottom,
        onTap: (i) => context.go(bottomItems[i].path),
        items: bottomItems,
      ),
    );
  }
}

class _CashStatusBadge extends StatelessWidget {
  final bool isOpen;
  const _CashStatusBadge({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isOpen ? AppColors.success : Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isOpen ? AppColors.success : Colors.grey).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isOpen ? AppColors.success : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOpen ? 'Caja Abierta' : 'Caja Cerrada',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isOpen ? AppColors.success : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends ConsumerWidget {
  final AppUser? user;
  final bool small;
  const _UserAvatar({this.user, this.small = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: small ? 16 : 22,
            backgroundColor: user?.role == 'admin' ? AppColors.primary : AppColors.accent.withValues(alpha: 0.2),
            child: Icon(
              user?.role == 'admin' ? Icons.shield_rounded : Icons.person_rounded,
              size: small ? 18 : 24,
              color: user?.role == 'admin' ? Colors.white : AppColors.accent,
            ),
          ),
          if (!small) ...[
            const SizedBox(height: 4),
            Text(
              user?.email ?? 'Admin', 
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}


class _SideNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  final VoidCallback onLogout;

  const _SideNavRail({
    required this.selectedIndex,
    required this.onTap,
    required this.items,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'VendePro',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ...items.asMap().entries.map((e) {
            final selected = e.key == selectedIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: _HoverMenuTile(
                selected: selected,
                icon: e.value.icon,
                label: e.value.label,
                onTap: () => onTap(e.key),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _HoverMenuTile(
              selected: false,
              icon: Icons.logout_rounded,
              label: 'Cerrar Sesión',
              isError: true,
              onTap: onLogout,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  const _BottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((e) {
              final selected = e.key == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(e.key),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: selected ? AppColors.gradient : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          e.value.icon,
                          color: selected ? Colors.white : Colors.grey,
                          size: 22,
                        ),
                      ).animate(target: selected ? 1 : 0).scaleXY(
                            begin: 0.9,
                            end: 1.0,
                            duration: 200.ms,
                          ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          e.value.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected ? AppColors.primary : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _HoverMenuTile extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isError;

  const _HoverMenuTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isError = false,
  });

  @override
  State<_HoverMenuTile> createState() => _HoverMenuTileState();
}

class _HoverMenuTileState extends State<_HoverMenuTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isError 
      ? AppColors.error 
      : (widget.selected ? Colors.white : Colors.grey);
      
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: widget.selected ? AppColors.gradient : null,
          color: !widget.selected && _isHovered 
            ? (widget.isError ? AppColors.error.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1)) 
            : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: color, size: 22),
          title: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem(
      {required this.icon, required this.label, required this.path});
}
