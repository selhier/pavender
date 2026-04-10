import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/inventory/product_form_screen.dart';
import '../../features/invoices/invoice_list_screen.dart';
import '../../features/invoices/invoice_create_screen.dart';
import '../../features/invoices/invoice_detail_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/customers/customer_form_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/ncf_settings_screen.dart';
import '../../features/settings/branch_management_screen.dart';
import '../../features/settings/user_management_screen.dart';
import '../../features/platform_admin/platform_admin_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/expenses/expenses_screen.dart';
import '../../features/expenses/expense_form_screen.dart';
import '../../features/reports/reports_screen.dart';
import 'package:vendepro/features/quotes/quote_list_screen.dart';
import 'package:vendepro/features/quotes/quote_create_screen.dart';
import 'package:vendepro/features/quotes/quote_detail_screen.dart';
import 'package:vendepro/features/suppliers/suppliers_screen.dart';
import '../widgets/main_scaffold.dart';
import '../providers/auth_provider.dart';
import '../providers/providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isAuth = ref.watch(isLoggedInProvider);
      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      final isLoggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final isOnboarding = state.matchedLocation == '/onboarding';

      if (!hasSeenOnboarding && !isOnboarding) {
        return '/onboarding';
      }

      if (hasSeenOnboarding && isOnboarding) {
        return isAuth ? '/dashboard' : '/login';
      }

      if (authState.isLoading) return null;

      if (!isAuth && !isLoggingIn && hasSeenOnboarding) {
        return '/login';
      }

      if (isAuth && isLoggingIn) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
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
            path: '/expenses',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExpensesScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const ExpenseFormScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/quotes',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: QuoteListScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const QuoteCreateScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => QuoteDetailScreen(quoteId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/suppliers',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SuppliersScreen(),
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'ncf',
                builder: (context, state) => const NcfSettingsScreen(),
              ),
              GoRoute(
                path: 'branches',
                builder: (context, state) => const BranchManagementScreen(),
              ),
              GoRoute(
                path: 'users',
                builder: (context, state) => const UserManagementScreen(),
              ),
            ],
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
});
