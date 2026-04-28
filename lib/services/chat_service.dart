import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get all users except current user
  static Stream<QuerySnapshot> getUsers() {
    return _db.collection('users').snapshots();
  }

  /// Search users by display name
  static Stream<QuerySnapshot> searchUsers(String query) {
    return _db
        .collection('users')
        .where('uid', isNotEqualTo: _auth.currentUser?.uid)
        .snapshots();
  }

  /// Generate a unique chat room ID from two user UIDs
  static String _getChatRoomId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Get or create a chat room between two users
  static Future<String> getOrCreateChatRoom(String otherUid) async {
    final myUid = _auth.currentUser!.uid;
    final chatRoomId = _getChatRoomId(myUid, otherUid);

    final doc = await _db.collection('chatRooms').doc(chatRoomId).get();
    if (!doc.exists) {
      await _db.collection('chatRooms').doc(chatRoomId).set({
        'users': [myUid, otherUid],
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return chatRoomId;
  }

  /// Send a message using Firestore
  static Future<void> sendMessage({
    required String chatRoomId,
    required String message,
  }) async {
    final user = _auth.currentUser!;

    // Add message to Firestore
    await _db
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'senderId': user.uid,
      'senderName': user.displayName ?? user.phoneNumber ?? 'Unknown',
      'text': message.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'text',
      'isRead': false,
    });

    // Update chat room with last message info
    await _db.collection('chatRooms').doc(chatRoomId).update({
      'lastMessage': message.trim(),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': user.uid,
    });
  }

  /// Get messages stream for a chat room from Firestore
  static Stream<QuerySnapshot> getMessages(String chatRoomId, {int limit = 100}) {
    return _db
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Get chat rooms for the current user
  static Stream<QuerySnapshot> getChatRooms() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('chatRooms')
        .where('users', arrayContains: uid)
        .snapshots();
  }

  /// Mark messages as read in Firestore
  static Future<void> markAsRead(String chatRoomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await _db
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('senderId', isNotEqualTo: uid)
        .get();

    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      if (doc.data()['isRead'] == false) {
        batch.update(doc.reference, {'isRead': true});
      }
    }
    await batch.commit();
  }

  /// Upload media to Firebase Storage
  static Future<String> uploadMedia(String chatRoomId, dynamic file, String fileName) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('chat_media')
        .child(chatRoomId)
        .child(DateTime.now().millisecondsSinceEpoch.toString() + '_' + fileName);

    UploadTask uploadTask;
    if (file is Uint8List) {
      uploadTask = ref.putData(file);
    } else {
      uploadTask = ref.putFile(file);
    }
    
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// Send a media message using Firestore
  static Future<void> sendMediaMessage({
    required String chatRoomId,
    required String mediaUrl,
    required String type, // 'image' or 'video'
    String? caption,
  }) async {
    final user = _auth.currentUser!;

    await _db
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'senderId': user.uid,
      'senderName': user.displayName ?? user.phoneNumber ?? 'Unknown',
      'text': caption ?? (type == 'image' ? '📷 Image' : '🎥 Video'),
      'mediaUrl': mediaUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'type': type,
      'isRead': false,
    });

    await _db.collection('chatRooms').doc(chatRoomId).update({
      'lastMessage': caption ?? (type == 'image' ? '📷 Image' : '🎥 Video'),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': user.uid,
    });
  }

  /// Clear all messages in a chat room
  static Future<void> clearChat(String chatRoomId) async {
    final messages = await _db
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .get();

    final batch = _db.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    
    // Reset last message info
    batch.update(_db.collection('chatRooms').doc(chatRoomId), {
      'lastMessage': 'Messages cleared',
      'lastMessageTime': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Update typing status
  static Future<void> setTypingStatus(String chatRoomId, bool isTyping) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('chatRooms').doc(chatRoomId).update({
      'typing.$uid': isTyping,
    });
  }
}
