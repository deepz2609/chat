import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'dart:io' show File;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'media_preview_screen.dart';

class ChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;
  final String chatRoomId;

  const ChatScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
    required this.chatRoomId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class PendingMessage {
  final String id;
  final String? text;
  final String? localPath;
  final String type;
  final DateTime timestamp;
  PendingMessage({required this.id, this.text, this.localPath, required this.type, required this.timestamp});
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _emojiShowing = false;
  final _picker = ImagePicker();
  Timer? _typingTimer;
  final List<PendingMessage> _pendingMessages = [];

  @override
  void initState() {
    super.initState();
    ChatService.markAsRead(widget.chatRoomId);
  }

  void _onTyping() {
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    
    ChatService.setTypingStatus(widget.chatRoomId, true);
    
    _typingTimer = Timer(const Duration(seconds: 2), () {
      ChatService.setTypingStatus(widget.chatRoomId, false);
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    if (!mounted) return;
    
    // Show WhatsApp-style Preview Screen
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaPreviewScreen(image: image),
      ),
    );

    if (result == null || result['send'] != true) return;
    final String? caption = result['caption'];

    final pendingId = DateTime.now().millisecondsSinceEpoch.toString();
    final pendingMsg = PendingMessage(
      id: pendingId,
      text: caption,
      localPath: image.path,
      type: 'image',
      timestamp: DateTime.now(),
    );

    setState(() {
      _pendingMessages.insert(0, pendingMsg);
    });

    try {
      String mediaUrl;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        mediaUrl = await ChatService.uploadMedia(widget.chatRoomId, bytes, image.name);
      } else {
        mediaUrl = await ChatService.uploadMedia(widget.chatRoomId, File(image.path), image.name);
      }
      
      await ChatService.sendMediaMessage(
        chatRoomId: widget.chatRoomId,
        mediaUrl: mediaUrl,
        type: 'image',
        caption: caption,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.id == pendingId);
        });
      }
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    ChatService.setTypingStatus(widget.chatRoomId, false);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await ChatService.sendMessage(chatRoomId: widget.chatRoomId, message: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtTime(int? ts) {
    if (ts == null) return '';
    return DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(ts));
  }

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat.EEEE().format(d);
    return DateFormat.yMMMd().format(d);
  }

  bool _showDateHeaderFirestore(List<QueryDocumentSnapshot> docs, int i) {
    if (i == docs.length - 1) return true;
    final c = (docs[i].data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
    final n = (docs[i + 1].data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
    if (c == null || n == null) return false;
    final cd = c.toDate();
    final nd = n.toDate();
    return cd.day != nd.day || cd.month != nd.month || cd.year != nd.year;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final myUid = AuthService.currentUser?.uid;
    final hue = (widget.otherName.hashCode % 360).abs().toDouble();
    final avColor = HSLColor.fromAHSL(1, hue, 0.6, 0.4).toColor();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(widget.otherUid).snapshots(),
          builder: (context, snap) {
            final d = snap.data?.data() as Map<String, dynamic>?;
            final online = d?['isOnline'] ?? false;
            final lastSeen = d?['lastSeen'] as Timestamp?;
            
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId).snapshots(),
              builder: (context, chatSnap) {
                final chatData = chatSnap.data?.data() as Map<String, dynamic>?;
                final isTyping = (chatData?['typing'] as Map<String, dynamic>?)?[widget.otherUid] ?? false;
                
                String status = isTyping ? 'typing...' : (online ? 'online' : (lastSeen != null ? 'last seen ${DateFormat.jm().format(lastSeen.toDate())}' : 'offline'));

                return Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: avColor, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Row(children: [
                      if (online && !isTyping) Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle)),
                      Text(status, style: TextStyle(fontSize: 12, color: (online || isTyping) ? const Color(0xFF00E676) : Colors.grey[500])),
                    ]),
                  ])),
                ]);
              }
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'clear') {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A2E),
                    title: const Text('Clear Chat?', style: TextStyle(color: Colors.white)),
                    content: const Text('This will delete all messages for everyone.', style: TextStyle(color: Colors.grey)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          ChatService.clearChat(widget.chatRoomId);
                          Navigator.pop(context);
                        }, 
                        child: const Text('Clear', style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ChatService.getMessages(widget.chatRoomId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.waving_hand_rounded, size: 48, color: cs.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('Say hello! 👋', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ]));
              }
              ChatService.markAsRead(widget.chatRoomId);
              final docs = snapshot.data!.docs;
              
              return ListView.builder(
                controller: _scrollCtrl, reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: docs.length + _pendingMessages.length,
                itemBuilder: (context, i) {
                  if (i < _pendingMessages.length) {
                    final pm = _pendingMessages[i];
                    return _Bubble(
                      text: pm.text ?? '',
                      isMe: true,
                      time: 'Sending...',
                      cs: cs,
                      localPath: pm.localPath,
                      type: pm.type,
                      isPending: true,
                    );
                  }

                  final data = docs[i - _pendingMessages.length].data() as Map<String, dynamic>;
                  final isMe = data['senderId'] == myUid;
                  final ts = data['timestamp'] as Timestamp?;
                  final tsMs = ts?.millisecondsSinceEpoch;
                  final showDate = _showDateHeaderFirestore(docs, i - _pendingMessages.length);
                  
                  return Column(children: [
                    if (showDate && tsMs != null) Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(12)),
                        child: Text(_fmtDate(tsMs), style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    _Bubble(
                      text: data['text'] ?? '',
                      isMe: isMe,
                      time: _fmtTime(tsMs),
                      cs: cs,
                      mediaUrl: data['mediaUrl'],
                      type: data['type'] ?? 'text',
                    ),
                  ]);
                },
              );
            },
          ),
        ),
        _buildInput(cs),
        Offstage(
          offstage: !_emojiShowing,
          child: SizedBox(
            height: 250,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                _msgCtrl.text += emoji.emoji;
              },
              config: const Config(
                height: 256,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInput(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(color: Color(0xFF0D0D14), border: Border(top: BorderSide(color: Color(0xFF1A1A2E)))),
      child: Row(children: [
        IconButton(
          icon: Icon(_emojiShowing ? Icons.keyboard_rounded : Icons.emoji_emotions_rounded, color: Colors.grey[500]),
          onPressed: () {
            setState(() => _emojiShowing = !_emojiShowing);
            if (!_emojiShowing) {
              FocusScope.of(context).requestFocus(FocusNode());
            }
          },
        ),
        IconButton(
          icon: Icon(Icons.add_photo_alternate_rounded, color: Colors.grey[500]),
          onPressed: _pickImage,
        ),
        Expanded(child: Container(
          decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(24)),
          child: TextField(
            controller: _msgCtrl, textCapitalization: TextCapitalization.sentences,
            maxLines: 4, minLines: 1, 
            onChanged: (val) => _onTyping(),
            onTap: () {
              if (_emojiShowing) setState(() => _emojiShowing = false);
            },
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(hintText: 'Type a message...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        )),
        const SizedBox(width: 8),
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]), borderRadius: BorderRadius.circular(16)),
          child: IconButton(icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, color: Colors.white, size: 22), onPressed: _send),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String time;
  final ColorScheme cs;
  final String? mediaUrl;
  final String? localPath;
  final String type;
  final bool isPending;
  
  const _Bubble({
    required this.text,
    required this.isMe,
    required this.time,
    required this.cs,
    this.mediaUrl,
    this.localPath,
    required this.type,
    this.isPending = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: mediaUrl != null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isMe ? cs.primary : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (mediaUrl != null || localPath != null) 
              GestureDetector(
                onTap: () {
                  if (mediaUrl == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
                        body: Center(child: InteractiveViewer(child: Image.network(mediaUrl!))),
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: localPath != null 
                        ? (kIsWeb ? Image.network(localPath!) : Image.file(File(localPath!), fit: BoxFit.cover, height: 200, width: double.infinity))
                        : Image.network(
                            mediaUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 200, width: double.infinity,
                                color: Colors.black26,
                                child: const Center(child: CircularProgressIndicator()),
                              );
                            },
                          ),
                    ),
                    if (isPending)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black26,
                          child: const Center(child: CircularProgressIndicator(color: Colors.white70)),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (text.isNotEmpty)
                    Text(text, style: TextStyle(color: isMe ? Colors.white : Colors.grey[200], fontSize: 15, height: 1.35)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time, style: TextStyle(color: isMe ? Colors.white.withValues(alpha: 0.6) : Colors.grey[600], fontSize: 11)),
                      if (isPending) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.access_time_rounded, size: 12, color: Colors.white60),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
