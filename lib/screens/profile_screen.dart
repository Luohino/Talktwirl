import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'notification_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'add_post_screen.dart';
import 'followers_screen.dart';
import 'following_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'post_detail_screen.dart';
import 'twirl_screen.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'editprofile_screen.dart';
import 'post_detail_list.dart';
import 'message_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tabIndex = 0;
  List<Map<String, dynamic>> _userPosts = [];
  int _unseenNotificationCount = 0; // New state variable for unseen notifications

  @override
  void initState() {
    super.initState();
    _loadProfileFromSupabase();
    _loadUserPosts();
    _fetchFollowingCount();
    _fetchFollowersCount();
    _fetchUnseenNotificationCount(); // Fetch unseen notification count on init
  }

  Future<void> _loadProfileFromSupabase() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      final profileRes = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (profileRes != null && mounted) {
        final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
        final name = (profileRes['name'] == null || profileRes['name'].toString().trim().isEmpty)
            ? 'TalkTwirl User'
            : profileRes['name'];
        profileProvider.updateProfile(
          username: profileRes['username'] ?? '',
          name: name,
          website: profileRes['website'] ?? '',
          bio: profileRes['bio'] ?? '',
          email: profileRes['email'] ?? '',
          phone: profileRes['phone'] ?? '',
          gender: profileRes['gender'] ?? '',
          profilePhoto: profileRes['profile_photo'],
        );
        // Persist username, name, and profilePhoto locally for offline use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_username', profileRes['username'] ?? '');
        await prefs.setString('profile_name', name);
        await prefs.setString('profile_photo', profileRes['profile_photo'] ?? '');
        setState(() {});
      }
    } else {
      // On logout, load from local storage
      final prefs = await SharedPreferences.getInstance();
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      final localName = prefs.getString('profile_name');
      profileProvider.updateProfile(
        username: prefs.getString('profile_username') ?? '',
        name: (localName == null || localName.trim().isEmpty) ? 'TalkTwirl User' : localName,
        profilePhoto: prefs.getString('profile_photo'),
        website: '', bio: '', email: '', phone: '', gender: '',
      );
      setState(() {});
    }
  }

  Future<void> _loadUserPosts() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final postsRes = await SupabaseService.client
        .from('posts')
        .select('*, profiles(username, name)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    setState(() {
      _userPosts = List<Map<String, dynamic>>.from(postsRes.map((post) => {
        ...post,
        'username': post['profiles']?['username'] ?? '',
        'name': post['profiles']?['name'] ?? '',
      }));
    });
  }

  Future<void> _fetchFollowingCount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final rels = await SupabaseService.client
        .from('user_relationships')
        .select('target_id')
        .eq('user_id', user.id);
    setState(() {
      Provider.of<ProfileProvider>(context, listen: false).following = rels.length;
    });
  }

  Future<void> _fetchFollowersCount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final rels = await SupabaseService.client
        .from('user_relationships')
        .select('user_id')
        .eq('target_id', user.id);
    setState(() {
      Provider.of<ProfileProvider>(context, listen: false).followers = rels.length;
    });
  }

  Future<void> _fetchUnseenNotificationCount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final res = await SupabaseService.client
        .from('notifications')
        .select('id')
        .eq('recipient_id', user.id)
        .eq('is_seen', false);
    setState(() {
      _unseenNotificationCount = res.length;
    });
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
            title: const Text('Post (Photos)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final permissionStatus = await Permission.photos.request();
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (picked != null) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'image'),
                    ),
                  );
                  if (result != null && mounted) {
                    _handleNewPost(result, 'Post');
                  }
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.white),
            title: const Text('Twirls (Videos)', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final permissionStatus = await Permission.videos.request();
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'video'),
                    ),
                  );
                  if (result != null && mounted) {
                    _handleNewPost(result, 'Twirl');
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _handleNewPost(Map result, String category) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    profile.incrementPostCount(category);
    final id = const Uuid().v4();
    final newPost = {
      'id': id,
      'username': profile.username,
      'user_id': SupabaseService.client.auth.currentUser?.id,
      'location': 'Your City',
      'image': result['mediaType'] == 'image' ? result['mediaPath'] : 'assets/Rectangle.png',
      'video': result['mediaType'] == 'video' ? result['mediaPath'] : null,
      'likes': 0,
      'caption': result['caption'] ?? '',
      'date': 'now',
      'isLiked': false,
      'isSaved': false,
      'mediaType': result['mediaType'],
      'mediaPath': result['mediaPath'],
      'songTitle': result['music'] ?? '',
      'category': category,
      'postedAt': DateTime.now().toIso8601String(),
    };
    setState(() {
      _userPosts.insert(0, newPost);
    });
    if (category == 'Twirl') {
      await SupabaseService.client.from('posts').insert({
        'id': id,
        'user_id': profile.userId,
        'media_url': result['mediaPath'],
        'caption': result['caption'] ?? '',
        'song': result['music'] ?? '',
        'location': 'Your City',
        'likes': 0,
        'comments': 0,
        'category': 'Twirl',
        'media_type': 'video',
        'created_at': DateTime.now().toIso8601String(),
      });
      await SupabaseService.client.from('twirls').insert({
        'id': id,
        'user_id': profile.userId,
        'video_url': result['mediaPath'],
        'caption': result['caption'] ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      await SupabaseService.client.from('posts').insert(newPost);
    }
  }

  Future<void> _showFollowersList() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    
    // Navigate immediately for better responsiveness
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowersScreen(userId: user.id, initialFollowers: []),
      ),
    );
    
    // Load data in background after navigation
    try {
      final rels = await SupabaseService.client
          .from('user_relationships')
          .select('user_id')
          .eq('target_id', user.id);
      final followerIds = List<String>.from(rels.map((r) => r['user_id']));
      List<Map<String, dynamic>> users = [];
      if (followerIds.isNotEmpty) {
        final userRows = await SupabaseService.client
            .from('profiles')
            .select('id, username, name, profile_photo')
            .inFilter('id', followerIds);
        users = List<Map<String, dynamic>>.from(userRows.map((user) => {
          'uid': user['id'],
          'username': user['username'] ?? '',
          'name': user['name'] ?? '',
          'profilePhoto': user['profile_photo'] ?? 'assets/Oval.png',
        }));
      }
      
      // Update the screen if it's still mounted
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FollowersScreen(userId: user.id, initialFollowers: users),
          ),
        );
      }
    } catch (e) {
      print('Error loading followers: $e');
    }
  }

  Widget _statColumn(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
        children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1.5,
      height: 28,
      color: Colors.white24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final posts = _userPosts.where((p) => p['category'] == 'Post').toList();
    final twirls = _userPosts.where((p) => p['category'] == 'Twirl').toList();
    final totalPosts = posts.length + twirls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 28),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Colors.white, Colors.white],
                ).createShader(bounds);
              },
              child: const Text(
                'TalkTwirl',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings, color: Color(0xFFFAE6FF), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 2),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none, color: Color(0xFFFAE6FF), size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationScreen()),
                        );
                      },
                    ),
                    if (_unseenNotificationCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.message_outlined, color: Color(0xFFFAE6FF), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MessageScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
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
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          backgroundImage: () {
                            final photoFile = profile.profilePhoto;
                            if (photoFile != null && photoFile.isNotEmpty) {
                              if (photoFile.startsWith('http')) {
                                return CachedNetworkImageProvider(photoFile) as ImageProvider<Object>;
                              } else if (photoFile.startsWith('assets/')) {
                                return AssetImage(photoFile) as ImageProvider<Object>;
                              } else {
                                return FileImage(File(photoFile)) as ImageProvider<Object>;
                              }
                            } else {
                              return const AssetImage('assets/Oval.png') as ImageProvider<Object>;
                            }
                          }(),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _statColumn('$totalPosts', 'Posts'),
                              GestureDetector(
                                onTap: _showFollowersList,
                                child: Container(color: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: _statColumn('${profile.followers}', 'Followers')),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowingScreen(userId: SupabaseService.client.auth.currentUser!.id))),
                                child: Container(color: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: _statColumn('${profile.following}', 'Following')),
                            ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(profile.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('@${profile.username.isNotEmpty ? profile.username : "user"}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(profile.bio, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                    if (profile.website.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(profile.website, style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade800),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
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
                      child: Icon(Icons.grid_on, color: _tabIndex == 0 ? Colors.white : Colors.white54, size: 24),
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
                      child: Icon(Icons.play_circle_outline, color: _tabIndex == 1 ? Colors.white : Colors.white54, size: 24),
                    ),
                  ),
                ),
              ],
            ),
            Divider(color: Colors.white24.withOpacity(0.5), thickness: 0.5, height: 0.5),
            Expanded(
              child: (_tabIndex == 0 && posts.isEmpty) || (_tabIndex == 1 && twirls.isEmpty)
                  ? Center(child: Text(_tabIndex == 0 ? 'No posts yet.' : 'No twirls yet.', style: const TextStyle(color: Colors.white54, fontSize: 16)))
                : GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
                    itemCount: _tabIndex == 0 ? posts.length : twirls.length,
                    itemBuilder: (context, idx) {
                      final post = _tabIndex == 0 ? posts[idx] : twirls[idx];
                      return GestureDetector(
                        onTap: () {
                          if (_tabIndex == 1) {
                            final user = SupabaseService.client.auth.currentUser;
                            final twirlsWithProfile = twirls.map((twirl) => {
                              ...twirl,
                              'username': profile.username,
                              'userPfp': profile.profilePhoto,
                            }).toList();
                            Future<void> openTwirlScreen() async {
                              final List<Map<String, dynamic>> enrichedTwirls = [];
                              for (final t in twirlsWithProfile) {
                                final twirlId = t['id'];
                                // Fetch like count
                                final likeCountRes = await SupabaseService.client
                                    .from('twirl_likes')
                                    .select('id')
                                    .eq('twirl_id', twirlId);
                                final likeCount = likeCountRes.length;
                                // Check if current user liked
                                bool isLiked = false;
                                if (user != null) {
                                  final likedRes = await SupabaseService.client
                                      .from('twirl_likes')
                                      .select('id')
                                      .eq('twirl_id', twirlId)
                                      .eq('user_id', user.id)
                                      .maybeSingle();
                                  isLiked = likedRes != null;
                                }
                                enrichedTwirls.add({
                                  ...t,
                                  'likes': likeCount,
                                  'isLiked': isLiked,
                                });
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TwirlScreen(
                                    twirls: enrichedTwirls,
                                    initialIndex: idx,
                                  ),
                                ),
                              );
                            }
                            openTwirlScreen();
                          } else {
                            final profilePhoto = profile.profilePhoto ?? 'assets/Oval.png';
                            final postsWithProfile = posts.map((post) => {
                              ...post,
                              'profilePhoto': profilePhoto,
                            }).toList();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PostDetailList(
                                  posts: postsWithProfile,
                                  initialIndex: idx,
                                ),
                              ),
                            );
                          }
                        },
                        child: Stack(
                          children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                              child: post['media_type'] == 'image'
                                ? post['media_url'] != null && post['media_url'].toString().isNotEmpty
                                  ? Image.network(post['media_url'], fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                                  : Container(color: Colors.grey[900])
                                : FutureBuilder<Uint8List?>(
                                    future: VideoThumbnail.thumbnailData(
                                      video: post['media_url'],
                                      imageFormat: ImageFormat.PNG,
                                      maxWidth: 300,
                                      quality: 75,
                                    ),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                        return Image.memory(snapshot.data!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
                                      } else {
                                        return Container(color: Colors.black);
                                      }
                                    },
                                  ),
                            ),
                            if (post['media_type'] == 'video')
                              const Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                    child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                                ),
                              ),
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
}
