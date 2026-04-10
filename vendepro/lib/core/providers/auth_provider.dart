// lib/core/providers/auth_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  return prefs.getString('active_branch_id') ?? 'default_business';
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
        await auth.signInAnonymously();
      }
      
      // Pull latest data for this branch
      await ref.read(syncServiceProvider).pullFromCloud();
    }
  }
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final FirebaseAuth _auth;

  AuthController(this._auth) : super(const AsyncData(null));

  Future<void> signIn(String email, String password, WidgetRef ref) async {
    state = const AsyncLoading();
    try {
      // 1. Try Firebase Auth first
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      
      // Trigger initial pull
      await ref.read(syncServiceProvider).pullFromCloud();
      
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
          await _auth.signInAnonymously();
        }
        
        // Trigger initial pull for the branch
        await ref.read(syncServiceProvider).pullFromCloud();
        
        state = const AsyncData(null);
      } else {
        // Both failed
        state = AsyncError(e, StackTrace.current);
        rethrow;
      }
    }
  }

  Future<void> signUp(String email, String password) async {
    state = const AsyncLoading();
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
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
