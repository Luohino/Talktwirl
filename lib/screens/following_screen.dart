import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'user_profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';

class FollowingScreen extends StatefulWidget {
  final String userId;
  const FollowingScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  List<Map<String, dynamic>> following = [];
  bool isLoading = true;
  RealtimeChannel? _followingChannel;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
    _subscribeToFollowingRealtime();
  }

  @override
  void dispose() {
    _followingChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToFollowingRealtime() {
    final userId = widget.userId;
    _followingChannel = SupabaseService.client.channel('public:user_relationships:user_id=eq.$userId');
    _followingChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_relationships',
      filter: PostgresChangeFilter(column: 'user_id', value: userId, type: PostgresChangeFilterType.eq),
      callback: (payload) => _loadFollowing(),
    );
    _followingChannel!.subscribe();
  }

  Future<void> _loadFollowing() async {
    try {
      // Fetch target_ids from user_relationships where user_id = widget.userId
      final rels = await SupabaseService.client
          .from('user_relationships')
          .select('target_id')
          .eq('user_id', widget.userId);
      final followingIds = List<String>.from(rels.map((r) => r['target_id']));
      if (followingIds.isEmpty) {
        setState(() {
          following = [];
          isLoading = false;
        });
        return;
      }
      // Fetch user profiles for all followingIds
      final users = await SupabaseService.client
          .from('profiles')
          .select('id, username, name, profile_photo')
          .inFilter('id', followingIds);
      final userList = List<Map<String, dynamic>>.from(users.map((user) => {
        'uid': user['id'],
        'username': user['username'] ?? '',
        'name': user['name'] ?? '',
        'profilePhoto': user['profile_photo'] ?? 'assets/Oval.png',
      }));
      setState(() {
        following = userList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted && e.toString().contains('SocketException')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No internet connection.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _loadFollowing(),
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
        title: const Text('Following', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : following.isEmpty
              ? const Center(child: Text('No following yet', style: TextStyle(color: Colors.white54, fontSize: 18)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  itemCount: following.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final user = following[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(
                                userData: user,
                                isCurrentUser: currentUser != null && user['uid'] == currentUser.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.profile),
    );
  }
}
