import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileFirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Creates the user document if it doesn't exist
  Future<void> createUserIfNotExists({
    required String uid,
    required String username,
    required String displayName,
    required String photoUrl,
  }) async {
    final docRef = _db.collection('users').doc(uid);
    final snap = await docRef.get();

    if (!snap.exists) {
      await docRef.set({
        'username': username,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Fetch user profile data
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  /// Live updates when profile fields (e.g. photoUrl) change.
  Stream<Map<String, dynamic>?> userProfileStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  /// Update profile fields (only updates what you pass in)
  Future<void> updateUserProfile({
    required String uid,
    String? username,
    String? displayName,
    String? photoUrl,
  }) async {
    await _db.collection('users').doc(uid).set({
      if (username != null) 'username': username,
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
