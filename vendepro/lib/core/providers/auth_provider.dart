// lib/core/providers/auth_provider.dart
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import 'providers.dart';

// Firebase Auth Instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// Auth State Changes Stream
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// Provides the currently active branch ID (tenant ID)
final activeBranchIdProvider = StateProvider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final stored = prefs.getString('active_branch_id');
  final fbUser = FirebaseAuth.instance.currentUser;
  
  // If stored is default_business but we have a firebase user, use their UID
  if (fbUser != null && (stored == null || stored == 'default_business')) {
    return fbUser.uid;
  }
  return stored ?? 'default_business';
});

// Unified Auth State for Routing/Logic
final isLoggedInProvider = Provider<bool>((ref) {
  final firebaseUser = ref.watch(authStateProvider).valueOrNull;
  final localUser = ref.watch(localUserProvider);
  return firebaseUser != null || localUser != null;
});

// Alias for compatibility with existing code
final currentBusinessIdProvider = Provider<String>((ref) {
  return ref.watch(activeBranchIdProvider);
});

// Provides the current user role (local for POS multi-user)
final userRoleProvider = StateProvider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getString('user_role') ?? 'admin';
});

// Provides the current locally authenticated employee
final localUserProvider = StateProvider<AppUser?>((ref) => null);

// Provider to initialize/restore the local session on start
final authInitProvider = FutureProvider<void>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  final localId = prefs.getString('local_user_id');
  
  if (localId != null) {
    final db = ref.read(databaseProvider);
    final user = await (db.select(db.appUsers)..where((u) => u.id.equals(localId))).getSingleOrNull();
    if (user != null) {
      ref.read(localUserProvider.notifier).state = user;
      ref.read(userRoleProvider.notifier).state = user.role;
      ref.read(activeBranchIdProvider.notifier).state = user.businessId;

      // Ensure a Firebase session for Firestore access
      final auth = ref.read(firebaseAuthProvider);
      if (auth.currentUser == null) {
        try {
          await auth.signInAnonymously();
        } catch (_) {}
      }
      
      // Sync pending changes and pull latest data with conflict resolution
      await ref.read(syncServiceProvider).syncPendingChanges();
    }
  }
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final FirebaseAuth _auth;

  AuthController(this._auth) : super(const AsyncData(null));

  Future<void> _ensureBusinessSetup(String uid, AppDatabase db, WidgetRef ref) async {
    // 1. Ensure business record exists
    final existing = await db.businessDao.getBusiness(uid);
    if (existing == null) {
      await db.into(db.businesses).insertOnConflictUpdate(BusinessesCompanion(
        id: drift.Value(uid),
        name: const drift.Value('Mi Negocio'),
        currency: const drift.Value('USD'),
        currencySymbol: const drift.Value('\$'),
        updatedAt: drift.Value(DateTime.now()),
      ));
    }

    // 2. Ensure default categories exist for this business
    final existingCats = await db.productsDao.getCategories(uid);
    if (existingCats.isEmpty) {
      const cats = ['General', 'Bebidas', 'Alimentos', 'Electrónica', 'Ropa'];
      for (final cat in cats) {
        final catId = '${uid}_${cat.toLowerCase().replaceAll('é', 'e').replaceAll('ó', 'o')}';
        await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion(
          id: drift.Value(catId),
          name: drift.Value(cat),
          businessId: drift.Value(uid),
          updatedAt: drift.Value(DateTime.now()),
        ));
      }
    }

    // 3. Migrate any offline inventory from 'default_business' if target account has no inventory
    try {
      final targetProducts = await db.productsDao.watchAll(uid).first;
      if (targetProducts.isEmpty) {
        final defaultProducts = await db.productsDao.watchAll('default_business').first;
        if (defaultProducts.isNotEmpty) {
          for (final p in defaultProducts) {
            await (db.update(db.products)..where((tbl) => tbl.id.equals(p.id))).write(
              ProductsCompanion(
                businessId: drift.Value(uid),
                updatedAt: drift.Value(DateTime.now()),
              ),
            );
            await db.syncDao.enqueue(SyncQueueCompanion.insert(
              id: 'prod_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
              entity: 'products',
              entityId: p.id,
              operation: 'upsert',
              data: jsonEncode({
                'id': p.id,
                'name': p.name,
                'description': p.description,
                'sku': p.sku,
                'price': p.price,
                'cost': p.cost,
                'stock': p.stock,
                'minStock': p.minStock,
                'categoryId': p.categoryId,
                'unit': p.unit,
                'taxRate': p.taxRate,
                'brand': p.brand,
                'subCategory': p.subCategory,
                'businessId': uid,
                'isActive': p.isActive,
                'updatedAt': DateTime.now().toIso8601String(),
              }),
            ));
          }
        }
      }
    } catch (_) {}

    // 4. Trigger two-way sync: upload pending offline changes then pull cloud changes with conflict resolution
    await ref.read(syncServiceProvider).syncPendingChanges();
  }

  Future<void> signIn(String email, String password, WidgetRef ref) async {
    state = const AsyncLoading();
    try {
      // 1. Try Firebase Auth first
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      
      final uid = _auth.currentUser!.uid;
      ref.read(activeBranchIdProvider.notifier).state = uid;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('active_branch_id', uid);

      final db = ref.read(databaseProvider);
      await _ensureBusinessSetup(uid, db, ref);
      
      state = const AsyncData(null);
    } catch (e) {
      // 2. Fallback to Local Auth if Firebase fails
      final db = ref.read(databaseProvider);
      final localUser = await db.authDao.login(email, password);
      
      if (localUser != null) {
        // Logged in as Local User
        ref.read(localUserProvider.notifier).state = localUser;
        ref.read(userRoleProvider.notifier).state = localUser.role;
        
        // Persist session
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.setString('local_user_id', localUser.id);
        await prefs.setString('user_role', localUser.role);
        
        // Switch to the user's branch
        ref.read(activeBranchIdProvider.notifier).state = localUser.businessId;
        await prefs.setString('active_branch_id', localUser.businessId);
        
        // 3. Ensure Firebase session for Firestore permissions
        if (_auth.currentUser == null) {
          try {
            await _auth.signInAnonymously();
          } catch (_) {}
        }
        
        await _ensureBusinessSetup(localUser.businessId, db, ref);
        
        state = const AsyncData(null);
      } else {
        // Both failed
        state = AsyncError(e, StackTrace.current);
        rethrow;
      }
    }
  }

  Future<void> signUp(String email, String password, WidgetRef ref) async {
    state = const AsyncLoading();
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
          
      final uid = _auth.currentUser!.uid;
      ref.read(activeBranchIdProvider.notifier).state = uid;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('active_branch_id', uid);

      final db = ref.read(databaseProvider);
      await _ensureBusinessSetup(uid, db, ref);
      
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> signInWithGoogle(WidgetRef ref) async {
    state = const AsyncLoading();
    try {
      final googleProvider = GoogleAuthProvider();
      await _auth.signInWithPopup(googleProvider);
          
      final uid = _auth.currentUser!.uid;
      ref.read(activeBranchIdProvider.notifier).state = uid;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('active_branch_id', uid);

      final db = ref.read(databaseProvider);
      await _ensureBusinessSetup(uid, db, ref);
      
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> signOut(WidgetRef ref) async {
    state = const AsyncLoading();
    try {
      // 1. Firebase logout
      await _auth.signOut();
      
      // 2. Local session cleanup
      ref.read(localUserProvider.notifier).state = null;
      ref.read(userRoleProvider.notifier).state = 'admin';
      
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove('local_user_id');
      await prefs.remove('user_role');
      // Note: We might want to keep the active_branch_id or reset it to default
      await prefs.setString('active_branch_id', 'default_business');
      ref.read(activeBranchIdProvider.notifier).state = 'default_business';

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(firebaseAuthProvider));
});
