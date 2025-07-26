import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'followers_screen.dart';
import 'following_screen.dart';
import 'personalmessage_screen.dart';
import 'user_followers_screen.dart';
import 'user_following_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'post_detail_screen.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'twirl_screen.dart';
import 'post_detail_list.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool isCurrentUser;

  const UserProfileScreen({
    Key? key,
    required this.userData,
    this.isCurrentUser = false,
  }) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool isFollowing = false;
  int followersCount = 0;
  int followingCount = 0;
  int postsCount = 0;
  String? currentUid;
  int _tabIndex = 0;
  bool _isFollowLoading = false;
  RealtimeChannel? _followersChannel;
  RealtimeChannel? _followingChannel;
  Map<String, dynamic>? _profileData;
  List<Map<String, dynamic>> _userPosts = [];
  List<Map<String, dynamic>> _userTwirls = [];
  bool _isLoadingPosts = true;
  String? _bio;
  bool _bioLoading = true;

  @override
  void initState() {
    super.initState();
    followersCount = widget.userData['followers'] ?? 0;
    followingCount = widget.userData['following'] ?? 0;
    _initFollowState();
    _loadCounts();
    _loadPostsCount();
    _subscribeToFollowRealtime();
    _fetchLatestProfile();
    _loadUserPostsAndTwirls();
    _fetchBioOnce();
  }

  Future<void> _fetchLatestProfile() async {
    final uid = widget.userData['uid'];
    final profile = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (profile != null && mounted) {
      setState(() {
        _profileData = profile;
      });
    }
  }

  @override
  void dispose() {
    _followersChannel?.unsubscribe();
    _followingChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToFollowRealtime() {
    final userId = widget.userData['uid'];
    // Followers (people who follow this user)
    _followersChannel = SupabaseService.client.channel('public:user_relationships:target_id=eq.$userId');
    _followersChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_relationships',
      filter: PostgresChangeFilter(column: 'target_id', value: userId, type: PostgresChangeFilterType.eq),
      callback: (payload) => _loadCounts(),
    );
    _followersChannel!.subscribe();
    // Following (people this user follows)
    _followingChannel = SupabaseService.client.channel('public:user_relationships:user_id=eq.$userId');
    _followingChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_relationships',
      filter: PostgresChangeFilter(column: 'user_id', value: userId, type: PostgresChangeFilterType.eq),
      callback: (payload) => _loadCounts(),
    );
    _followingChannel!.subscribe();
  }

  Future<void> _initFollowState() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    currentUid = user.id;
    final rel = await SupabaseService.client
        .from('user_relationships')
        .select('user_id')
        .eq('user_id', user.id.toString())
        .eq('target_id', widget.userData['uid'].toString())
        .maybeSingle();
    print('Follow relationship found: $rel');
    if (!mounted) return;
    setState(() {
      isFollowing = rel != null;
      print('isFollowing set to: $isFollowing');
    });
  }

  Future<void> _loadCounts() async {
    final userId = widget.userData['uid'];
    final followersRes = await SupabaseService.client
        .from('user_relationships')
        .select('user_id')
        .eq('target_id', userId);
    final followingRes = await SupabaseService.client
        .from('user_relationships')
        .select('target_id')
        .eq('user_id', userId);
    if (!mounted) return;
    setState(() {
      followersCount = followersRes.length;
      followingCount = followingRes.length;
    });
  }

  Future<void> _loadPostsCount() async {
    final userId = widget.userData['uid'];
    final postsRes = await SupabaseService.client
        .from('posts')
        .select('id')
        .eq('user_id', userId);
    setState(() {
      postsCount = postsRes.length;
    });
  }

  Future<String?> _fetchBio() async {
    final userId = widget.userData['uid'];
    final bioRes = await SupabaseService.client
        .from('profiles')
        .select('bio')
        .eq('id', userId)
        .maybeSingle();
    return bioRes != null ? (bioRes['bio'] as String?) : null;
  }

  Future<void> _fetchBioOnce() async {
    setState(() { _bioLoading = true; });
    final userId = widget.userData['uid'];
    final bioRes = await SupabaseService.client
        .from('profiles')
        .select('bio')
        .eq('id', userId)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      _bio = bioRes != null ? (bioRes['bio'] as String?) : null;
      _bioLoading = false;
    });
  }

  Future<void> _followUser() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      print('[_followUser] No current user');
      return;
    }
    final targetUid = widget.userData['uid'];
    if (isFollowing || user.id == targetUid || _isFollowLoading) {
      print('[_followUser] Early return: isFollowing=$isFollowing, user.id==targetUid=${user.id == targetUid}, _isFollowLoading=$_isFollowLoading');
      return;
    }
    setState(() {
      _isFollowLoading = true;
    });
    try {
      var resp = await SupabaseService.client.from('user_relationships').insert({
        'user_id': user.id,
        'target_id': targetUid,
      });
      print('[_followUser] Insert response: $resp');
      // Insert notification for follow
      await SupabaseService.client.from('notifications').insert({
        'type': 'follow',
        'from_user_id': user.id,
        'to_user_id': targetUid,
        'created_at': DateTime.now().toIso8601String(),
        'seen': false,
      });
      await _initFollowState();
      await _loadCounts();
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('duplicate key') || errStr.contains('23505')) {
        // Already following, just refresh state and do not show error
        print('[_followUser] Duplicate key error, already following. Refreshing state.');
        await _initFollowState();
        await _loadCounts();
        // Optionally, set isFollowing = true explicitly
        if (mounted) setState(() { isFollowing = true; });
      } else if (mounted) {
        setState(() { _isFollowLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errStr.contains('SocketException')
                ? 'No internet connection.'
                : 'Failed to follow: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _followUser(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _unfollowUser() async {
    final user = SupabaseService.client.auth.currentUser;
    final targetUid = widget.userData['uid'];
    print('Unfollow attempt: user.id=${user?.id}, targetUid=$targetUid, isFollowing=$isFollowing, loading=$_isFollowLoading');
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unfollow failed: No current user')),
        );
      }
      return;
    }
    if (user.id == targetUid || _isFollowLoading) {
      print('Blocked: user.id == targetUid or loading');
      return;
    }
    setState(() {
      _isFollowLoading = true;
    });
    try {
      await SupabaseService.client
          .from('user_relationships')
          .delete()
          .eq('user_id', user.id)
          .eq('target_id', targetUid);
      await _initFollowState();
      await _loadCounts();
      print('Unfollowed successfully.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('SocketException')
                ? 'No internet connection.'
                : 'Failed to unfollow: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _unfollowUser(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _loadUserPostsAndTwirls() async {
    final userId = widget.userData['uid'];
    final postsRes = await SupabaseService.client
        .from('posts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    setState(() {
      _userPosts = List<Map<String, dynamic>>.from(postsRes.where((p) => p['category'] == 'Post'));
      _userTwirls = List<Map<String, dynamic>>.from(postsRes.where((p) => p['category'] == 'Twirl'));
      _isLoadingPosts = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    print('isCurrentUser: \\${widget.isCurrentUser}, isFollowing: \\$isFollowing, _isFollowLoading: \\$_isFollowLoading');
    final profile = _profileData ?? widget.userData;
    final uid = profile['id'] ?? widget.userData['uid'];
    final profilePhoto = profile['profile_photo'] ?? profile['profilePhoto'] ?? 'assets/Oval.png';
    final username = profile['username'] ?? 'Unknown';
    final name = (profile['name'] == null || profile['name'].toString().trim().isEmpty)
        ? 'TalkTwirl User'
        : profile['name'];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          username,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        buildUserAvatar(
                          profilePhoto: profilePhoto,
                          name: name,
                          username: username,
                          radius: 40,
                          fontSize: 28,
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatColumn(postsCount, 'Posts'),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserFollowersScreen(userId: uid))),
                                child: Container(color: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: _buildStatColumn(followersCount, 'Followers')),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserFollowingScreen(userId: uid))),
                                child: Container(color: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: _buildStatColumn(followingCount, 'Following')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('@$username', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    _bioLoading && _bio == null
                        ? const SizedBox(height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text((_bio != null && _bio!.isNotEmpty) ? _bio! : 'No bio yet...', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isFollowing ? Colors.black : Colors.white,
                                foregroundColor: isFollowing ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: isFollowing ? BorderSide(color: Colors.grey.shade800) : BorderSide.none),
                              ),
                              onPressed: _isFollowLoading ? null : () async { if (isFollowing) { await _unfollowUser(); } else { await _followUser(); } },
                              child: _isFollowLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(widget.isCurrentUser ? 'Your Profile' : isFollowing ? 'Unfollow' : 'Follow', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ),
                        if (!widget.isCurrentUser) const SizedBox(width: 8),
                        if (!widget.isCurrentUser)
                          SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade800), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => PersonalMessageScreen(otherUserId: uid, username: username, avatarAsset: profilePhoto, name: name))),
                              child: const Icon(Icons.message_outlined, color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tabIndex = 0),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tabIndex == 0 ? Colors.white : Colors.transparent, width: 1.5))),
                      child: Icon(Icons.grid_on_rounded, color: _tabIndex == 0 ? Colors.white : Colors.white54, size: 24),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tabIndex = 1),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tabIndex == 1 ? Colors.white : Colors.transparent, width: 1.5))),
                      child: Icon(Icons.play_circle_outline_rounded, color: _tabIndex == 1 ? Colors.white : Colors.white54, size: 24),
                    ),
                  ),
                ),
              ],
            ),
            Divider(color: Colors.white24.withOpacity(0.5), thickness: 0.5, height: 0.5),
            Expanded(
              child: _isLoadingPosts
                  ? const Center(child: CircularProgressIndicator())
                  : _tabIndex == 0
                      ? _userPosts.isEmpty
                          ? const Center(child: Text('No posts yet.', style: TextStyle(color: Colors.white54, fontSize: 16)))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
                              itemCount: _userPosts.length,
                              itemBuilder: (context, idx) {
                                final post = _userPosts[idx];
                                return GestureDetector(
                                  onTap: () {
                                      final postsWithProfile = _userPosts.map((p) => { ...p, 'username': username, 'name': name, 'profilePhoto': profilePhoto }).toList();
                                      Navigator.of(context).push(PageRouteBuilder(pageBuilder: (_, __, ___) => PostDetailList(posts: postsWithProfile, initialIndex: idx), transitionDuration: Duration.zero));
                                  },
                                  child: Image.network(post['media_url'], fit: BoxFit.cover),
                                );
                              },
                            )
                      : _userTwirls.isEmpty
                          ? const Center(child: Text('No Twirls yet.', style: TextStyle(color: Colors.white54, fontSize: 16)))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
                              itemCount: _userTwirls.length,
                              itemBuilder: (context, idx) {
                                final twirl = _userTwirls[idx];
                                final twirlsWithProfile = _userTwirls.map((t) => { ...t, 'username': username, 'userPfp': profilePhoto }).toList();
                                return GestureDetector(
                                  onTap: () async {
                                      // ... onTap logic ...
                                  },
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(twirl['media_url'], fit: BoxFit.cover),
                                      const Positioned.fill(child: Align(alignment: Alignment.center, child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 48))),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.profile),
    );
  }

  Widget _buildStatColumn(int count, String label) {
    return Column(
      children: [
        Text('$count', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
      ],
    );
  }
}
