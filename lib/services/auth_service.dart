import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_service.dart';

/// Authentication service provider
final authServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

/// Current user provider
final currentUserProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Authentication state notifier
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final FirebaseService _authService;

  AuthNotifier(this._authService) : super(const AsyncValue.loading()) {
    _initializeAuth();
  }

  void _initializeAuth() {
    _authService.authStateChanges.listen(
      (user) {
        state = AsyncValue.data(user);
      },
      onError: (error, stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
  }

  /// Sign in with email and password
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      state = const AsyncValue.loading();
      final credential = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
      
      if (credential?.user != null) {
        state = AsyncValue.data(credential!.user);
      } else {
        state = AsyncValue.error('Sign in failed', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Create account with email and password
  Future<void> createUserWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      state = const AsyncValue.loading();
      final credential = await _authService.createUserWithEmail(
        email: email,
        password: password,
      );
      
      if (credential?.user != null) {
        state = AsyncValue.data(credential!.user);
      } else {
        state = AsyncValue.error('Account creation failed', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      state = const AsyncValue.loading();
      final credential = await _authService.signInWithGoogle();
      
      if (credential?.user != null) {
        state = AsyncValue.data(credential!.user);
      } else {
        state = AsyncValue.error('Google sign in failed', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Sign in with Apple
  Future<void> signInWithApple() async {
    try {
      state = const AsyncValue.loading();
      final credential = await _authService.signInWithApple();
      
      if (credential?.user != null) {
        state = AsyncValue.data(credential!.user);
      } else {
        state = AsyncValue.error('Apple sign in failed', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Sign in with Facebook
  Future<void> signInWithFacebook() async {
    try {
      state = const AsyncValue.loading();
      final credential = await _authService.signInWithFacebook();
      
      if (credential?.user != null) {
        state = AsyncValue.data(credential!.user);
      } else {
        state = AsyncValue.error('Facebook sign in failed', StackTrace.current);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// Provider for authentication notifier
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

/// Provider for checking if user is signed in
final isSignedInProvider = Provider<bool>((ref) {
  final authAsync = ref.watch(authNotifierProvider);
  return authAsync.when(
    data: (user) => user != null,
    loading: () => false,
    error: (_, __) => false,
  );
});

