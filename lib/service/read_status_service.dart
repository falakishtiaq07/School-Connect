import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReadStatusService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<Set<String>> getReadIds({required String type}) async {
    final user = _auth.currentUser;

    if (user == null) {
      return {};
    }

    try {
      final snapshot = await _firestore
          .collection('read_status')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: type)
          .get();

      return snapshot.docs.map((doc) => doc['itemId'].toString()).toSet();
    } catch (e) {
      print('Error getting read IDs: $e');
      return {};
    }
  }

  static Future<void> markAsRead({
    required String type,
    required String itemId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) return;

    try {
      final docId = '${user.uid}_${type}_$itemId';

      await _firestore.collection('read_status').doc(docId).set({
        'userId': user.uid,
        'type': type,
        'itemId': itemId,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking as read: $e');
    }
  }
}
