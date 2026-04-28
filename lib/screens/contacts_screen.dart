import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _isLoading = true;
  List<Contact> _contacts = [];
  List<Map<String, dynamic>> _registeredContacts = [];

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    if (await Permission.contacts.request().isGranted) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      
      // Clean phone numbers
      List<String> phoneNumbers = [];
      for (var contact in contacts) {
        for (var phone in contact.phones) {
          String cleanNumber = phone.number.replaceAll(RegExp(r'\D'), '');
          // Very basic formatting, might need to adapt to country codes
          if (cleanNumber.isNotEmpty) {
            if (cleanNumber.length > 10) {
              cleanNumber = '+${cleanNumber}';
            } else {
              cleanNumber = '+1${cleanNumber}'; // fallback dummy CC
            }
            phoneNumbers.add(cleanNumber);
          }
        }
      }

      // Query registered users in firestore
      // Since 'in' query supports max 10, in real app we'd batch this or do it on backend
      // Here we just fetch all users and filter locally to keep it simple
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      final users = snapshot.docs.map((d) => d.data()).toList();

      List<Map<String, dynamic>> registered = [];
      for (var user in users) {
        String? userPhone = user['phoneNumber'];
        if (userPhone != null && phoneNumbers.contains(userPhone)) {
          registered.add(user);
        }
      }

      setState(() {
        _contacts = contacts;
        _registeredContacts = registered;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _startChat(Map<String, dynamic> user) async {
    final chatRoomId = await ChatService.getOrCreateChatRoom(user['uid']);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatRoomId: chatRoomId,
            otherUid: user['uid'],
            otherName: user['displayName'] ?? user['phoneNumber'] ?? 'User',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _registeredContacts.isEmpty
              ? const Center(child: Text('No contacts found using the app.'))
              : ListView.builder(
                  itemCount: _registeredContacts.length,
                  itemBuilder: (context, index) {
                    final user = _registeredContacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['photoURL'] != null
                            ? NetworkImage(user['photoURL'])
                            : null,
                        child: user['photoURL'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(user['displayName'] ?? user['phoneNumber'] ?? 'Unknown'),
                      subtitle: Text(user['phoneNumber'] ?? ''),
                      onTap: () => _startChat(user),
                    );
                  },
                ),
    );
  }
}
