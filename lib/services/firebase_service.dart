import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// Firebase service for authentication and data management
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Collections
  static const String _usersCollection = 'users';
  static const String _warningsCollection = 'warnings';
  static const String _poisCollection = 'pois';

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;

  /// Sign in with email and password
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      print('FirebaseService.signInWithEmail: Error: $e');
      return null;
    }
  }

  /// Create account with email and password
  Future<UserCredential?> createUserWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Create user document
      if (credential.user != null) {
        await _createUserDocument(credential.user!);
      }
      
      return credential;
    } catch (e) {
      print('FirebaseService.createUserWithEmail: Error: $e');
      return null;
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      
      // Create user document if new user
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await _createUserDocument(userCredential.user!);
      }
      
      return userCredential;
    } catch (e) {
      print('FirebaseService.signInWithGoogle: Error: $e');
      return null;
    }
  }

  /// Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      
      // Create user document if new user
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await _createUserDocument(userCredential.user!);
      }
      
      return userCredential;
    } catch (e) {
      print('FirebaseService.signInWithApple: Error: $e');
      return null;
    }
  }

  /// Sign in with Facebook
  Future<UserCredential?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();
      
      if (result.status == LoginStatus.success) {
        final OAuthCredential facebookAuthCredential = 
            FacebookAuthProvider.credential(result.accessToken!.token);
        
        final userCredential = await _auth.signInWithCredential(facebookAuthCredential);
        
        // Create user document if new user
        if (userCredential.additionalUserInfo?.isNewUser == true) {
          await _createUserDocument(userCredential.user!);
        }
        
        return userCredential;
      }
      return null;
    } catch (e) {
      print('FirebaseService.signInWithFacebook: Error: $e');
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
        FacebookAuth.instance.logOut(),
      ]);
    } catch (e) {
      print('FirebaseService.signOut: Error: $e');
    }
  }

  /// Create user document in Firestore
  Future<void> _createUserDocument(User user) async {
    try {
      await _firestore.collection(_usersCollection).doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'preferences': {
          'notifications': true,
          'cyclingStyle': 'balanced',
          'showWarnings': true,
          'showPOIs': true,
        },
      });
    } catch (e) {
      print('FirebaseService._createUserDocument: Error: $e');
    }
  }

  /// Get user document
  Future<DocumentSnapshot?> getUserDocument(String uid) async {
    try {
      return await _firestore.collection(_usersCollection).doc(uid).get();
    } catch (e) {
      print('FirebaseService.getUserDocument: Error: $e');
      return null;
    }
  }

  /// Update user preferences
  Future<void> updateUserPreferences(String uid, Map<String, dynamic> preferences) async {
    try {
      await _firestore.collection(_usersCollection).doc(uid).update({
        'preferences': preferences,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('FirebaseService.updateUserPreferences: Error: $e');
    }
  }

  /// Submit community warning
  Future<void> submitWarning(Map<String, dynamic> warningData) async {
    try {
      await _firestore.collection(_warningsCollection).add({
        ...warningData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
    } catch (e) {
      print('FirebaseService.submitWarning: Error: $e');
      // Re-throw the error so it can be handled by the UI
      rethrow;
    }
  }

  /// Get nearby warnings
  Stream<QuerySnapshot> getNearbyWarnings(double latitude, double longitude, double radiusKm) {
    // This is a simplified version - in production, you'd use GeoFirestore
    return _firestore
        .collection(_warningsCollection)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Get cycling POIs
  Stream<QuerySnapshot> getCyclingPOIs() {
    return _firestore
        .collection(_poisCollection)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  /// Add a new cycling POI
  Future<void> addPOI(Map<String, dynamic> poiData) async {
    try {
      await _firestore.collection(_poisCollection).add({
        ...poiData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
    } catch (e) {
      print('FirebaseService.addPOI: Error: $e');
      rethrow;
    }
  }

  /// Update an existing POI
  Future<void> updatePOI(String poiId, Map<String, dynamic> updateData) async {
    try {
      await _firestore.collection(_poisCollection).doc(poiId).update({
        ...updateData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('FirebaseService.updatePOI: Error: $e');
      rethrow;
    }
  }

  /// Delete a POI (soft delete)
  Future<void> deletePOI(String poiId) async {
    try {
      await _firestore.collection(_poisCollection).doc(poiId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('FirebaseService.deletePOI: Error: $e');
      rethrow;
    }
  }

  /// Get nearby POIs within a radius
  Stream<QuerySnapshot> getNearbyPOIs(double latitude, double longitude, double radiusKm) {
    // Note: This is a simplified implementation. For production, you'd want to use
    // GeoFirestore or implement proper geospatial queries
    return _firestore
        .collection(_poisCollection)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  /// Initialize push notifications
  Future<void> initializeNotifications() async {
    try {
      // Request permission
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FirebaseService.initializeNotifications: User granted permission');
        
        // Get FCM token
        String? token = await _messaging.getToken();
        print('FirebaseService.initializeNotifications: FCM Token: $token');
        
        // Save token to user document
        if (currentUser != null && token != null) {
          await _firestore.collection(_usersCollection).doc(currentUser!.uid).update({
            'fcmToken': token,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        print('FirebaseService.initializeNotifications: User declined or has not accepted permission');
      }
    } catch (e) {
      print('FirebaseService.initializeNotifications: Error: $e');
    }
  }

  /// Subscribe to topic for notifications
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('FirebaseService.subscribeToTopic: Subscribed to $topic');
    } catch (e) {
      print('FirebaseService.subscribeToTopic: Error: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('FirebaseService.unsubscribeFromTopic: Unsubscribed from $topic');
    } catch (e) {
      print('FirebaseService.unsubscribeFromTopic: Error: $e');
    }
  }
}

