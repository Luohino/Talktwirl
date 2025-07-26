import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'twirl_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'user_profile_screen.dart';
import 'post_detail_screen.dart';
import 'post_detail_list.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _profileActive = false;
  late Future<Map<String, List<Map<String, dynamic>>>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _checkUserSuspended();
    _notificationsFuture = _fetchAndGroupNotifications();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {}); // Refetch notifications when returning to this screen
  }

  Future<void> _checkUserSuspended() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final userDoc = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    if (userDoc == null) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF261531),
            title: const Text('Your account is suspended', style: TextStyle(color: Colors.white)),
            content: const Text('This account is no longer available.', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () async {
                  await SupabaseService.client.auth.signOut();
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },
                child: const Text('Log out', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _refreshNotifications() async {
    setState(() {
      _notificationsFuture = _fetchAndGroupNotifications();
    });
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchAndGroupNotifications() async {
    final notifications = await _fetchNotifications();
    return await groupNotifications(notifications);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>> (
      future: _notificationsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final grouped = snapshot.data!;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Colors.white, Colors.white],
                ).createShader(bounds);
              },
              child: const Text(
                'Talktwirl',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.white24, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline, color: Color(0xFFFAE6FF), size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TwirlScreen()),
                        );
                      },
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.notifications, color: Color(0xFFFAE6FF), size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.message_outlined, color: Color(0xFFFAE6FF), size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshNotifications,
            child: _buildNotificationList(grouped),
          ),
          bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.profile),
        );
      },
    );
  }

  void _onAddPostTap() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18122B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image, color: Colors.white),
            title: const Text('Post (Image)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              // Use permission_handler and image_picker as in HomeScreen
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.white),
            title: const Text('Twirl (Video)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              // Use permission_handler and image_picker as in HomeScreen
            },
          ),
        ],
      ),
    );
  }

  Widget _navBarIcon(BuildContext context, IconData icon, {required VoidCallback onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8F5CFF).withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFFFE5B8B) : Colors.white.withOpacity(0.85),
          size: 32,
        ),
      ),
    );
  }

  Widget _profileNavBarIcon({required bool isActive}) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    return SizedBox(
      width: 36,
      height: 36,
      child: buildUserAvatar(
        profilePhoto: profile.profilePhoto ?? '',
        name: profile.name,
        username: profile.username,
        radius: 18,
        fontSize: 18,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchNotifications() async {
    print('Fetching notifications...');
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return [];
    final notifs = await SupabaseService.client
        .from('notifications')
        .select('*, from_user:from_user_id (username, name, profile_photo)')
        .eq('to_user_id', user.id)
        .order('created_at', ascending: false);
    print('[notification_screen] Raw notifications fetched: $notifs');
    final result = notifs.map<Map<String, dynamic>>((notif) {
      return {
        ...notif,
        'from_user_username': notif['from_user']?['username'] ?? '',
        'from_user_name': notif['from_user']?['name'] ?? '',
        'from_user_avatar': notif['from_user']?['profile_photo'] ?? 'assets/Oval.png',
      };
    }).toList();
    print('Fetched notifications: ' + result.toString());
    return result;
  }

  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return '';
    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} week ago';
    return '${(diff.inDays / 30).floor()} month ago';
  }

  Future<Map<String, List<Map<String, dynamic>>>> groupNotifications(List<Map<String, dynamic>> notifications) async {
    final now = DateTime.now();
    final Map<String, List<Map<String, dynamic>>> grouped = {
      'New': [],
      'Today': [],
      'This Week': [],
      'This Month': [],
      'Earlier': [],
    };
    for (final notif in notifications) {
      final createdAt = DateTime.tryParse(notif['created_at'] ?? '');
      if (createdAt == null) continue;
      final diff = now.difference(createdAt);
      if (diff.inMinutes < 60) {
        grouped['New']!.add(notif);
      } else if (diff.inHours < 24 && now.day == createdAt.day) {
        grouped['Today']!.add(notif);
      } else if (diff.inDays < 7) {
        grouped['This Week']!.add(notif);
      } else if (diff.inDays < 30) {
        grouped['This Month']!.add(notif);
      } else {
        grouped['Earlier']!.add(notif);
      }
    }
    grouped.removeWhere((key, value) => value.isEmpty);
    return grouped;
  }

  Widget _buildNotificationList(Map<String, List<Map<String, dynamic>>> grouped) {
    // DEBUG: Print all notifications being rendered
    grouped.forEach((section, notifs) {
      for (final notif in notifs) {
        print('NOTIF_RENDER: type=${notif['type']} target_type=${notif['target_type']} caption=${notif['target_caption']} created_at=${notif['created_at']}');
      }
    });
    final List<_SectionedNotification> items = [];
    grouped.forEach((section, notifs) {
      items.add(_SectionedNotification(section: section, isHeader: true));
      for (final notif in notifs) {
        items.add(_SectionedNotification(section: section, notification: notif));
      }
    });
    if (items.isEmpty) {
      // AlwaysScrollableScrollPhysics ensures pull-to-refresh works even if empty
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(
            child: Text(
              'No notifications yet',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      key: const PageStorageKey('notification-list'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 18),
            child: Text(
              item.section,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          );
        } else if (item.notification != null) {
          final notif = item.notification!;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              onTap: () async {
                final notifType = notif['type'];
                final targetType = notif['target_type'];
                final targetId = notif['target_id'];
                final fromUserId = notif['from_user_id'];
                if (notifType == 'follow' && fromUserId != null) {
                  // Open user profile
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userData: {'uid': fromUserId},
                        isCurrentUser: false,
                      ),
                    ),
                  );
                } else if ((notifType == 'like' || notifType == 'comment') && targetType == 'twirl' && targetId != null) {
                  // Open TwirlScreen with the specific twirl, including profile info
                  final twirl = await SupabaseService.client
                    .from('posts')
                    .select('*, profiles(username, profile_photo)')
                    .eq('id', targetId)
                    .maybeSingle();
                  if (twirl != null) {
                    twirl['username'] = twirl['profiles']?['username'] ?? '';
                    twirl['userPfp'] = twirl['profiles']?['profile_photo'] ?? 'assets/Oval.png';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TwirlScreen(
                          twirls: [twirl],
                          initialIndex: 0,
                        ),
                      ),
                    );
                  }
                } else if ((notifType == 'like' || notifType == 'comment') && targetType == 'post' && targetId != null) {
                  // Open PostDetailScreen with the specific post, including profile info
                  final post = await SupabaseService.client
                    .from('posts')
                    .select('*, profiles(username, name, profile_photo)')
                    .eq('id', targetId)
                    .maybeSingle();
                  if (post != null) {
                    post['username'] = post['profiles']?['username'] ?? '';
                    post['name'] = post['profiles']?['name'] ?? '';
                    post['profilePhoto'] = post['profiles']?['profile_photo'] ?? 'assets/Oval.png';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailList(posts: [post], initialIndex: 0),
                      ),
                    );
                  }
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  buildUserAvatar(
                    profilePhoto: notif['from_user_avatar'] ?? 'assets/Oval.png',
                    name: notif['from_user_name'] ?? '',
                    username: notif['from_user_username'] ?? '',
                    radius: 22,
                    fontSize: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _notificationMessage(notif),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTimeAgo(notif['created_at']),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }

  String _notificationMessage(Map<String, dynamic> notif) {
    final username = notif['from_user_username'] ?? '';
    final type = notif['type'] ?? '';
    final targetType = notif['target_type'] ?? '';
    final caption = notif['target_caption'] ?? '';
    switch (type) {
      case 'follow':
        return '$username started following you';
      case 'like':
        if (targetType == 'twirl') {
          return '$username liked your twirl${caption.isNotEmpty ? ': "$caption"' : ''}';
        } else {
          return '$username liked your post${caption.isNotEmpty ? ': "$caption"' : ''}';
        }
      case 'comment':
        if (targetType == 'twirl') {
          return '$username commented on your twirl${caption.isNotEmpty ? ': "$caption"' : ''}';
        } else {
          return '$username commented on your post${caption.isNotEmpty ? ': "$caption"' : ''}';
        }
      default:
        return '$username sent a notification';
    }
  }
}

// Helper class for sectioned notifications
class _SectionedNotification {
  final String section;
  final Map<String, dynamic>? notification;
  final bool isHeader;
  _SectionedNotification({required this.section, this.notification, this.isHeader = false});
}
