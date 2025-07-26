import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/supabase_client.dart';
import 'personalmessage_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({Key? key}) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> with AutomaticKeepAliveClientMixin {
  String? _currentUserId;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _messagesChannel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseService.client.auth.currentUser?.id;
    _syncFromServer();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    if (_currentUserId == null) return;
    
    _messagesChannel = SupabaseService.client
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Check if this message is relevant to current user
            final newMessage = payload.newRecord;
            if (newMessage != null && 
                (newMessage['sender_id'] == _currentUserId || 
                 newMessage['receiver_id'] == _currentUserId)) {
              // Add to Hive cache immediately
              final messagesBox = Hive.box('messages');
              messagesBox.put(newMessage['id'], newMessage);
            }
          },
        )
        .subscribe();
  }

  void _syncFromServer() async {
    if (_currentUserId == null) return;
    try {
      final messages = await SupabaseService.client
          .from('messages')
          .select()
          .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId')
          .order('created_at', ascending: false);
      final messagesBox = Hive.box('messages');
      // Remove any local messages not present on server
      final serverIds = messages.map((msg) => msg['id']).toSet();
      final localIds = messagesBox.keys.toSet();
      for (final id in localIds) {
        if (!serverIds.contains(id)) {
          messagesBox.delete(id);
        }
      }
      for (final msg in messages) {
        messagesBox.put(msg['id'], msg);
      }
     
      // Also sync profiles for all users in messages
      final userIds = <String>{};
      for (final msg in messages) {
        if (msg['sender_id'] != null) userIds.add(msg['sender_id']);
        if (msg['receiver_id'] != null) userIds.add(msg['receiver_id']);
      }
      
      if (userIds.isNotEmpty) {
        final profiles = await SupabaseService.client
            .from('profiles')
            .select()
            .inFilter('id', userIds.toList());
            
        final profilesBox = Hive.box('profiles');
        for (final profile in profiles) {
          profilesBox.put(profile['id'], profile);
        }
      }
    } catch (e) {}
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      if (difference.inDays > 0) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inMinutes < 0) {
        return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final messagesBox = Hive.box('messages');
    final profilesBox = Hive.box('profiles');
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 10) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Image.asset(
                'assets/icon.png',
                width: 32,
                height: 32,
              ),
              const SizedBox(width: 8),
              const Text('Talktwirl', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 28),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E), // exact match to screenshot - dark grey with slight contrast
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 1.0),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) => setState(() => _searchText = value.trim()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    hintText: 'Search...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: messagesBox.listenable(),
                builder: (context, Box box, _) {
                  final cachedMessages = box.values
                      .where((msg) => (msg as Map)['sender_id'] == _currentUserId || (msg as Map)['receiver_id'] == _currentUserId)
                      .toList();
                  // Group by conversation and get latest message
                  final Map<String, Map<String, dynamic>> conversationMap = {};
                  for (final msg in cachedMessages) {
                    final message = msg as Map<String, dynamic>;
                    final isMe = message['sender_id'] == _currentUserId;
                    final otherUserId = isMe ? message['receiver_id'] : message['sender_id'];
                    if (conversationMap[otherUserId] == null || 
                        DateTime.parse(message['created_at']).isAfter(
                          DateTime.parse(conversationMap[otherUserId]!['created_at']))) {
                      conversationMap[otherUserId] = message;
                    }
                  }
                  List<Map<String, dynamic>> conversations = [];
                  for (final entry in conversationMap.entries) {
                    final otherUserId = entry.key;
                    final message = entry.value;
                    final profile = profilesBox.get(otherUserId) ?? {};
                    conversations.add({
                      'avatar': (profile['profile_photo'] ?? 'assets/Oval.png').toString(),
                      'username': (profile['username'] ?? 'Unknown').toString(),
                      'name': (profile['name'] ?? profile['username'] ?? 'Unknown').toString(),
                      'message': (message['message_text'] ?? message['content'] ?? '').toString(),
                      'created_at': (message['created_at'] ?? DateTime.now().toIso8601String()).toString(),
                      'uid': otherUserId.toString(),
                      'isMe': message['sender_id'] == _currentUserId,
                      'isRead': message['is_read'] ?? true,
                    });
                  }
                  conversations.sort((a, b) {
                    final aTime = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
                    final bTime = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
                    return bTime.compareTo(aTime);
                  });
                  if (_searchText.isNotEmpty) {
                    conversations = conversations.where((c) =>
                      (c['username'] as String).toLowerCase().contains(_searchText.toLowerCase()) ||
                      (c['message'] as String).toLowerCase().contains(_searchText.toLowerCase())
                    ).toList();
                  }
                  if (conversations.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 64),
                          SizedBox(height: 16),
                          Text('No messages yet', style: TextStyle(color: Colors.white54, fontSize: 18)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (context, i) => const Divider(color: Colors.transparent, height: 2),
                    itemBuilder: (context, i) {
                      final conversation = conversations[i];
                      final isMe = conversation['isMe'] as bool;
                      final isRead = conversation['isRead'] as bool;
                      return Container(
                        color: Colors.transparent, // Remove grey background for unread messages
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          leading: CircleAvatar(
                            backgroundImage: conversation['avatar'].toString().startsWith('http')
                                ? NetworkImage(conversation['avatar'])
                                : const AssetImage('assets/Oval.png') as ImageProvider,
                            radius: 26,
                          ),
                          title: Text(
                            conversation['username'] ?? 'Unknown',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: (!isMe && !isRead) ? FontWeight.w800 : FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            conversation['message'] ?? '',
                            style: TextStyle(
                              color: (!isMe && !isRead) ? Colors.white : Colors.white60,
                              fontWeight: (!isMe && !isRead) ? FontWeight.bold : FontWeight.normal,
                              fontSize: (!isMe && !isRead) ? 15 : 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTime(conversation['created_at']),
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          onTap: () {
                            // Navigate to personal message screen
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration: const Duration(milliseconds: 300),
                                pageBuilder: (context, animation, secondaryAnimation) => PersonalMessageScreen(
                                  username: conversation['username'] ?? '',
                                  avatarAsset: conversation['avatar'] ?? 'assets/Oval.png',
                                  name: conversation['name'] ?? conversation['username'] ?? '',
                                  otherUserId: conversation['uid'] ?? '',
                                ),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
