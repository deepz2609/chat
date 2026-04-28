import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up with email and password
  static Future<UserCredential> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name
    await credential.user?.updateDisplayName(displayName);

    // Create user doc in Firestore
    await _db.collection('users').doc(credential.user!.uid).set({
      'uid': credential.user!.uid,
      'email': email,
      'displayName': displayName,
      'photoURL': null,
      'lastSeen': FieldValue.serverTimestamp(),
      'isOnline': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  /// Sign in with email and password
  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update online status
    await _db.collection('users').doc(credential.user!.uid).update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  /// Sign out
  static Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _db.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    await _auth.signOut();
  }

  /// Auto login as a specific character (Krishna or Radha)
  static Future<void> loginAs(String username) async {
    final email = '${username.toLowerCase()}@quickchat.local';
    const password = 'password123';
    final displayName = username;

    try {
      // Try to sign in first
      await signIn(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // If user doesn't exist, sign them up
        await signUp(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Update online status and heal missing user documents
  static Future<void> setOnlineStatus(bool isOnline) async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _db.collection('users').doc(user.uid).get();
      
      if (!doc.exists && isOnline) {
        // Self-heal: Create the document if it's missing (happens if signup was interrupted)
        await _db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email ?? 'unknown@email.com',
          'displayName': user.displayName ?? 'User',
          'photoURL': user.photoURL,
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (doc.exists) {
        // Normal update
        await _db.collection('users').doc(user.uid).update({
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}
