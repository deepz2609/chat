import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search people...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: ChatService.getUsers(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  print('DEBUG STREAM ERROR: ${snapshot.error}');
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  print('DEBUG: Users collection is completely empty in Firestore!');
                  return Center(
                    child: Text('No users found', style: TextStyle(color: Colors.grey[500])),
                  );
                }

                var users = snapshot.data!.docs;
                final myUid = AuthService.currentUser?.uid;
                // users = users.where((doc) => doc.id != myUid).toList(); // Show all users for testing

                if (_query.isNotEmpty) {
                  users = users.where((doc) {
                    final name = ((doc.data() as Map<String, dynamic>)['displayName'] as String?)?.toLowerCase() ?? '';
                    return name.contains(_query);
                  }).toList();
                }

                if (users.isEmpty) {
                  return Center(
                    child: Text('No results for "$_query"', style: TextStyle(color: Colors.grey[500])),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final data = users[index].data() as Map<String, dynamic>;
                    final name = data['displayName'] ?? 'Unknown';
                    final email = data['email'] ?? '';
                    final isOnline = data['isOnline'] ?? false;
                    final uid = data['uid'] ?? '';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    final hue = (name.hashCode % 360).abs().toDouble();
                    final avColor = HSLColor.fromAHSL(1, hue, 0.6, 0.4).toColor();

                    final isMe = uid == myUid;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Stack(
                        children: [
                          Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(color: avColor, borderRadius: BorderRadius.circular(16)),
                            child: Center(child: Text(initial,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
                          ),
                          if (isOnline)
                            Positioned(right: 0, bottom: 0,
                              child: Container(width: 14, height: 14,
                                decoration: BoxDecoration(color: const Color(0xFF00E676), shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF0D0D14), width: 2.5)))),
                        ],
                      ),
                      title: Text(isMe ? '$name (You)' : name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(email, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      trailing: Icon(Icons.chat_bubble_outline_rounded, color: cs.primary, size: 22),
                      onTap: () async {
                        final roomId = await ChatService.getOrCreateChatRoom(uid);
                        if (context.mounted) {
                          Navigator.pushReplacement(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(otherUid: uid, otherName: name, chatRoomId: roomId),
                          ));
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
