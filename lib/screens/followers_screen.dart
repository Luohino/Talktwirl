import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talktwirl/screens/user_profile_screen.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';

class FollowersScreen extends StatefulWidget {
  final String userId;
  final List<Map<String, dynamic>>? initialFollowers;
  const FollowersScreen({Key? key, required this.userId, this.initialFollowers}) : super(key: key);

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  List<Map<String, dynamic>> followers = [];
  bool isLoading = true;
  RealtimeChannel? _followersChannel;

  @override
  void initState() {
    super.initState();
    if (widget.initialFollowers != null && widget.initialFollowers!.isNotEmpty) {
      followers = List<Map<String, dynamic>>.from(widget.initialFollowers!);
      isLoading = false;
      _loadFollowers(background: true);
    } else {
      _loadFollowers();
    }
    _subscribeToFollowersRealtime();
  }

  @override
  void dispose() {
    _followersChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToFollowersRealtime() {
    final userId = widget.userId;
    _followersChannel = SupabaseService.client.channel('public:user_relationships:target_id=eq.$userId');
    _followersChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_relationships',
      filter: PostgresChangeFilter(column: 'target_id', value: userId, type: PostgresChangeFilterType.eq),
      callback: (payload) => _loadFollowers(),
    );
    _followersChannel!.subscribe();
  }

  Future<void> _loadFollowers({bool background = false}) async {
    if (!background) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      // Fetch follower user_ids from user_relationships table where target_id = widget.userId
      final rels = await SupabaseService.client
          .from('user_relationships')
          .select('user_id')
          .eq('target_id', widget.userId);
      final followerIds = List<String>.from(rels.map((r) => r['user_id']));
      if (followerIds.isEmpty) {
        if (!background) {
          setState(() {
            followers = [];
            isLoading = false;
          });
        } else {
          followers = [];
        }
        return;
      }
      // Fetch user profiles for all followerIds
      final users = await SupabaseService.client
          .from('profiles')
          .select('id, username, name, profile_photo')
          .inFilter('id', followerIds);
      final userList = List<Map<String, dynamic>>.from(users.map((user) => {
        'uid': user['id'],
        'username': user['username'] ?? '',
        'name': user['name'] ?? '',
        'profilePhoto': user['profile_photo'] ?? 'assets/Oval.png',
      }));
      if (!background) {
        setState(() {
          followers = userList;
          isLoading = false;
        });
      } else {
        setState(() {
          followers = userList;
        });
      }
    } catch (e) {
      print('Error loading followers: $e');
      if (!background) {
        setState(() {
          isLoading = false;
        });
      }
      if (mounted && e.toString().contains('SocketException')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No internet connection.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _loadFollowers(),
          ),
        ));
      }
    }
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
        name: profile.name ?? '',
        username: profile.username ?? '',
        radius: 18,
        fontSize: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Followers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : followers.isEmpty
              ? const Center(child: Text('No followers yet', style: TextStyle(color: Colors.white54, fontSize: 18)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  itemCount: followers.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final user = followers[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: ListTile(
                        leading: buildUserAvatar(
                          profilePhoto: user['profilePhoto'] ?? '',
                          name: user['name'] ?? '',
                          username: user['username'] ?? '',
                          radius: 22,
                          fontSize: 22,
                        ),
                        title: Text(user['name'] != null && user['name'].toString().isNotEmpty ? user['name'] : 'TalkTwirl User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('@${user['username']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        onTap: () {
                          final currentUser = SupabaseService.client.auth.currentUser;
                          if (currentUser != null && user['uid'] == currentUser.id) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(userData: user, isCurrentUser: false),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.profile),
    );
  }
}
