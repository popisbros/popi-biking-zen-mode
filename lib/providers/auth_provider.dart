import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile.dart';
import '../utils/app_logger.dart';
import '../services/toast_service.dart';

/// Provider for Firebase Auth instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Provider for current Firebase user stream
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Provider for user profile
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((doc) {
        if (!doc.exists) return null;
        return UserProfile.fromFirestore(doc);
      });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Auth service notifier
class AuthNotifier extends Notifier<AsyncValue<User?>> {
  late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;

  @override
  AsyncValue<User?> build() {
    _auth = ref.watch(firebaseAuthProvider);
    _firestore = FirebaseFirestore.instance;

    // Listen to auth state changes
    _auth.authStateChanges().listen((user) {
      state = AsyncValue.data(user);
    });

    return const AsyncValue.loading();
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      AppLogger.info('Starting Google Sign-In', tag: 'AUTH');

      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        AppLogger.warning('Google Sign-In cancelled by user', tag: 'AUTH');
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _createOrUpdateUserProfile(userCredential.user!, 'google');

      AppLogger.success('Google Sign-In successful', tag: 'AUTH');
      return userCredential;
    } catch (e, stackTrace) {
      AppLogger.error('Google Sign-In failed', tag: 'AUTH', error: e, stackTrace: stackTrace);
      state = AsyncValue.error(e, stackTrace);
      return null;
    }
  }

  /// Sign in with Email/Password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      AppLogger.info('Starting Email Sign-In', tag: 'AUTH');

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _createOrUpdateUserProfile(userCredential.user!, 'email');
      AppLogger.success('Email Sign-In successful', tag: 'AUTH');
      return userCredential;
    } catch (e, stackTrace) {
      AppLogger.error('Email Sign-In failed', tag: 'AUTH', error: e, stackTrace: stackTrace);
      state = AsyncValue.error(e, stackTrace);
      rethrow; // Re-throw so UI can show specific error message
    }
  }

  /// Register with Email/Password
  Future<UserCredential?> registerWithEmail(String email, String password, String firstName, String lastName) async {
    try {
      AppLogger.info('Starting Email Registration', tag: 'AUTH', data: {
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
      });

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update Firebase Auth displayName with combined name
      final displayName = '$firstName $lastName'.trim();
      await userCredential.user?.updateDisplayName(displayName);

      // Create user profile with separate firstName/lastName
      await _createOrUpdateUserProfile(
        userCredential.user!,
        'email',
        firstName: firstName,
        lastName: lastName,
      );

      AppLogger.success('Email Registration successful', tag: 'AUTH');
      return userCredential;
    } catch (e, stackTrace) {
      AppLogger.error('Email Registration failed', tag: 'AUTH', error: e, stackTrace: stackTrace);
      state = AsyncValue.error(e, stackTrace);
      rethrow; // Re-throw so UI can show specific error message
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      AppLogger.info('Signing out', tag: 'AUTH');

      // Sign out from Google if user signed in with Google
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final providerData = currentUser.providerData;
        final hasGoogleProvider = providerData.any((info) => info.providerId == 'google.com');

        if (hasGoogleProvider) {
          await GoogleSignIn().signOut();
          AppLogger.debug('Signed out from Google', tag: 'AUTH');
        }
      }

      // Sign out from Firebase Auth
      await _auth.signOut();
      state = const AsyncValue.data(null);
      AppLogger.success('Sign out successful', tag: 'AUTH');
    } catch (e, stackTrace) {
      AppLogger.error('Sign out failed', tag: 'AUTH', error: e, stackTrace: stackTrace);
      state = AsyncValue.error(e, stackTrace);
      rethrow; // Re-throw so UI can handle the error
    }
  }

  /// Create or update user profile in Firestore
  Future<void> _createOrUpdateUserProfile(
    User user,
    String authProvider, {
    String? firstName,
    String? lastName,
  }) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (docSnapshot.exists) {
      // Update existing profile - only update non-null fields to preserve existing data
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (user.email != null) updates['email'] = user.email;
      if (user.phoneNumber != null) updates['phoneNumber'] = user.phoneNumber;
      if (user.photoURL != null) updates['photoURL'] = user.photoURL;

      // Update firstName/lastName if provided
      if (firstName != null) updates['firstName'] = firstName;
      if (lastName != null) updates['lastName'] = lastName;

      // If firstName/lastName not provided but displayName exists, split it
      if (firstName == null && lastName == null && user.displayName != null) {
        final parts = user.displayName!.trim().split(' ');
        updates['firstName'] = parts.first;
        if (parts.length > 1) {
          updates['lastName'] = parts.sublist(1).join(' ');
        }
      }

      await userDoc.update(updates);
      AppLogger.debug('Updated existing user profile (only non-null fields)', tag: 'AUTH');
    } else {
      // Create new profile
      final profile = UserProfile.fromAuth(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        phoneNumber: user.phoneNumber,
        photoURL: user.photoURL,
        authProvider: authProvider,
      );

      // Override firstName/lastName if explicitly provided
      final profileData = profile.toFirestore();
      if (firstName != null) profileData['firstName'] = firstName;
      if (lastName != null) profileData['lastName'] = lastName;

      await userDoc.set(profileData);
      AppLogger.success('Created new user profile', tag: 'AUTH');
    }
  }

  /// Update user profile fields
  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? country,
    String? lastUsedRouteProfile,
    String? defaultRouteProfile,
    String? appearanceMode,
    bool? audioAlertsEnabled,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.warning('Cannot update profile - no user logged in', tag: 'AUTH');
      return;
    }

    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (firstName != null) {
        updates['firstName'] = firstName;
        AppLogger.debug('Updating firstName: $firstName', tag: 'AUTH');
      }
      if (lastName != null) {
        updates['lastName'] = lastName;
        AppLogger.debug('Updating lastName: $lastName', tag: 'AUTH');
      }
      if (phoneNumber != null) {
        updates['phoneNumber'] = phoneNumber;
        AppLogger.debug('Updating phoneNumber: $phoneNumber', tag: 'AUTH');
      }
      if (country != null) {
        updates['country'] = country;
        AppLogger.debug('Updating country: $country', tag: 'AUTH');
      }
      if (lastUsedRouteProfile != null) {
        updates['lastUsedRouteProfile'] = lastUsedRouteProfile;
        AppLogger.debug('Updating lastUsedRouteProfile: $lastUsedRouteProfile', tag: 'AUTH');
      }
      if (defaultRouteProfile != null) {
        updates['defaultRouteProfile'] = defaultRouteProfile;
        AppLogger.debug('Updating defaultRouteProfile: $defaultRouteProfile', tag: 'AUTH');
      }
      if (appearanceMode != null) {
        updates['appearanceMode'] = appearanceMode;
        AppLogger.debug('Updating appearanceMode: $appearanceMode', tag: 'AUTH');
      }
      if (audioAlertsEnabled != null) {
        updates['audioAlertsEnabled'] = audioAlertsEnabled;
        AppLogger.debug('Updating audioAlertsEnabled: $audioAlertsEnabled', tag: 'AUTH');
      }

      // Also update Firebase Auth displayName if firstName or lastName changed
      if (firstName != null || lastName != null) {
        final currentProfile = ref.read(userProfileProvider).value;
        final newFirstName = firstName ?? currentProfile?.firstName ?? '';
        final newLastName = lastName ?? currentProfile?.lastName ?? '';
        final newDisplayName = '$newFirstName $newLastName'.trim();
        await user.updateDisplayName(newDisplayName);
        AppLogger.debug('Updated Firebase Auth displayName: $newDisplayName', tag: 'AUTH');
      }

      // Use set with merge: true to create document if it doesn't exist
      await _firestore.collection('users').doc(user.uid).set(
        updates,
        SetOptions(merge: true),
      );
      AppLogger.success('Profile updated successfully', tag: 'AUTH', data: updates);
    } catch (e, stackTrace) {
      AppLogger.error('Profile update failed', tag: 'AUTH', error: e, stackTrace: stackTrace);
      rethrow; // Re-throw so caller can handle the error
    }
  }

  /// Add recent search (keep last 20)
  Future<void> addRecentSearch(String query) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      final searches = List<String>.from(snapshot.data()?['recentSearches'] ?? []);

      searches.remove(query); // Remove if exists
      searches.insert(0, query); // Add to front
      if (searches.length > 20) searches.removeRange(20, searches.length);

      await userDoc.update({'recentSearches': searches});
    } catch (e) {
      AppLogger.error('Failed to add recent search', tag: 'AUTH', error: e);
    }
  }

  /// Add recent destination (keep last 20)
  Future<void> addRecentDestination(String name, double lat, double lng) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final location = SavedLocation(
        name: name,
        latitude: lat,
        longitude: lng,
        savedAt: DateTime.now(),
      );

      final userDoc = _firestore.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      final destinations = (snapshot.data()?['recentDestinations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e))
              .toList() ??
          [];

      destinations.removeWhere((d) => d.name == name); // Remove duplicates
      destinations.insert(0, location);
      if (destinations.length > 20) destinations.removeRange(20, destinations.length);

      await userDoc.update({
        'recentDestinations': destinations.map((e) => e.toMap()).toList(),
      });
    } catch (e) {
      AppLogger.error('Failed to add recent destination', tag: 'AUTH', error: e);
    }
  }

  /// Add/remove favorite location (max 20)
  Future<void> toggleFavorite(String name, double lat, double lng) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      final favorites = (snapshot.data()?['favoriteLocations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e))
              .toList() ??
          [];

      final existingIndex = favorites.indexWhere((f) => f.name == name);

      if (existingIndex != -1) {
        favorites.removeAt(existingIndex); // Remove if exists
        ToastService.info('Removed from favorites');
      } else {
        if (favorites.length >= 20) {
          AppLogger.warning('Max 20 favorites reached', tag: 'AUTH');
          ToastService.warning('Maximum 20 favorites reached. Please remove some favorites before adding new ones.');
          return;
        }
        favorites.add(SavedLocation(
          name: name,
          latitude: lat,
          longitude: lng,
          savedAt: DateTime.now(),
        ));
        ToastService.success('Added to favorites');
      }

      await userDoc.update({
        'favoriteLocations': favorites.map((e) => e.toMap()).toList(),
      });
    } catch (e) {
      AppLogger.error('Failed to toggle favorite', tag: 'AUTH', error: e);
    }
  }

  /// Update default route profile
  Future<void> updateDefaultRouteProfile(String profile) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'defaultRouteProfile': profile,
      });
    } catch (e) {
      AppLogger.error('Failed to update route profile', tag: 'AUTH', error: e);
    }
  }

  /// Update destination name at specific index
  Future<void> updateDestinationName(int index, String newName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final destinations = (data['recentDestinations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];

      if (index >= 0 && index < destinations.length) {
        destinations[index] = SavedLocation(
          name: newName,
          latitude: destinations[index].latitude,
          longitude: destinations[index].longitude,
          savedAt: destinations[index].savedAt,
        );

        await _firestore.collection('users').doc(user.uid).update({
          'recentDestinations': destinations.map((e) => e.toMap()).toList(),
        });
        AppLogger.debug('Destination name updated', tag: 'AUTH');
      }
    } catch (e) {
      AppLogger.error('Failed to update destination name', tag: 'AUTH', error: e);
    }
  }

  /// Delete destination at specific index
  Future<void> deleteDestination(int index) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final destinations = (data['recentDestinations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];

      if (index >= 0 && index < destinations.length) {
        destinations.removeAt(index);

        await _firestore.collection('users').doc(user.uid).update({
          'recentDestinations': destinations.map((e) => e.toMap()).toList(),
        });
        AppLogger.debug('Destination deleted', tag: 'AUTH');
      }
    } catch (e) {
      AppLogger.error('Failed to delete destination', tag: 'AUTH', error: e);
    }
  }

  /// Update favorite name at specific index
  Future<void> updateFavoriteName(int index, String newName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final favorites = (data['favoriteLocations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];

      if (index >= 0 && index < favorites.length) {
        favorites[index] = SavedLocation(
          name: newName,
          latitude: favorites[index].latitude,
          longitude: favorites[index].longitude,
          savedAt: favorites[index].savedAt,
        );

        await _firestore.collection('users').doc(user.uid).update({
          'favoriteLocations': favorites.map((e) => e.toMap()).toList(),
        });
        AppLogger.debug('Favorite name updated', tag: 'AUTH');
      }
    } catch (e) {
      AppLogger.error('Failed to update favorite name', tag: 'AUTH', error: e);
    }
  }

  /// Delete favorite at specific index
  Future<void> deleteFavorite(int index) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final favorites = (data['favoriteLocations'] as List?)
              ?.map((e) => SavedLocation.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];

      if (index >= 0 && index < favorites.length) {
        favorites.removeAt(index);

        await _firestore.collection('users').doc(user.uid).update({
          'favoriteLocations': favorites.map((e) => e.toMap()).toList(),
        });
        AppLogger.debug('Favorite deleted', tag: 'AUTH');
      }
    } catch (e) {
      AppLogger.error('Failed to delete favorite', tag: 'AUTH', error: e);
    }
  }
}

/// Auth provider
final authNotifierProvider = NotifierProvider<AuthNotifier, AsyncValue<User?>>(() {
  return AuthNotifier();
});
