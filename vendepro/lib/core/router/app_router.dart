// lib/core/router/app_router.dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/inventory/product_form_screen.dart';
import '../../features/invoices/invoice_list_screen.dart';
import '../../features/invoices/invoice_create_screen.dart';
import '../../features/invoices/invoice_detail_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/customers/customer_form_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/platform_admin/platform_admin_screen.dart';
import '../widgets/main_scaffold.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/inventory',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: InventoryScreen(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const ProductFormScreen(),
            ),
            GoRoute(
              path: 'edit/:id',
              builder: (context, state) =>
                  ProductFormScreen(productId: state.pathParameters['id']),
            ),
          ],
        ),
        GoRoute(
          path: '/invoices',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: InvoiceListScreen(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const InvoiceCreateScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/customers',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CustomersScreen(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const CustomerFormScreen(),
            ),
            GoRoute(
              path: 'edit/:id',
              builder: (context, state) =>
                  CustomerFormScreen(customerId: state.pathParameters['id']),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        // Hidden admin route - only accessible with secret tap sequence
        GoRoute(
          path: '/platform-admin',
          builder: (context, state) => const PlatformAdminScreen(),
        ),
      ],
    ),
  ],
);
