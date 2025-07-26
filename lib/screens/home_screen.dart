import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';

import 'twirl_screen.dart';
import 'profile_screen.dart';
import 'post_detail_screen.dart';
import 'add_post_screen.dart';
import '../core/profile_provider.dart';
import 'notification_screen.dart';
import 'search_screen.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'full_media_screen.dart';
import 'user_profile_screen.dart';
import '../core/supabase_post_service.dart';
import 'personalmessage_screen.dart';
import '../core/inbox_notifier.dart';
import 'message_screen.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const HomeScreenBody(),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.home),
    );
  }
}

// Extract the original HomeScreen body to a new widget for reuse
class HomeScreenBody extends StatefulWidget {
  const HomeScreenBody({Key? key}) : super(key: key);

  @override
  State<HomeScreenBody> createState() => HomeScreenBodyState();
}

class HomeScreenBodyState extends State<HomeScreenBody> with RouteAware, WidgetsBindingObserver {
  // For real posts from Supabase
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingPosts = true;
  bool _isAuthenticating = true;

  TextEditingController _searchController = TextEditingController();
  bool _showSearchPopup = false;
  Set<int> _savedPostIds = {};
  int _unreadMessagesCount = 0; // State variable for unread messages
  RealtimeChannel? _messagesChannel; // Correct type import
  int _unseenNotificationCount = 0; // State variable for unseen notification count
  Map<String, Map<String, dynamic>> userProfilesCache = {};
  Set<String> _likingPostIds = {}; // Track posts being liked/unliked
  Set<String> _animatingLikeIds = {}; // Track posts animating like icon (for burst)
  Map<String, Size> _imageSizeCache = {}; // Cache for image sizes

  void _closeSearchPopup() {
    setState(() => _showSearchPopup = false);
    FocusScope.of(context).unfocus();
  }

  void _onToggleLike(int idx) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to like posts.')),
      );
      return;
    }
    final postId = _posts[idx]['id']?.toString();
    if (postId == null) return;
    if (_likingPostIds.contains(postId)) return; // Prevent spamming
    setState(() {
      _likingPostIds.add(postId);
    });
    final wasLiked = _posts[idx]['isLiked'] == true;
    int oldLikes = _posts[idx]['likes'] ?? 0;
    // Optimistically update only the liked post in the local list
    setState(() {
      _posts[idx]['isLiked'] = !wasLiked;
      _posts[idx]['likes'] = wasLiked ? oldLikes - 1 : oldLikes + 1;
      if (!wasLiked) {
        _animatingLikeIds.add(postId); // Start burst animation only when liking
      }
    });
    // Remove animation after a short delay
    if (!wasLiked) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _animatingLikeIds.remove(postId);
          });
        }
      });
    }
    try {
      if (wasLiked) {
        await SupabasePostService(SupabaseService.client).unlikePost(postId, user.id);
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes - 1})
            .eq('id', postId);
      } else {
        await SupabasePostService(SupabaseService.client).likePost(postId, user.id);
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes + 1})
            .eq('id', postId);
        // Add notification for like
        final postOwnerId = _posts[idx]['user_id'];
        final postCaption = _posts[idx]['caption'] ?? '';
        SupabasePostService.sendNotification(
          client: SupabaseService.client,
          type: 'like',
          toUserId: postOwnerId,
          fromUserId: user.id,
          targetType: 'post',
          targetId: postId,
          targetCaption: postCaption,
        );
      }
    } catch (e, stack) {
      // Failed to update like: $e
      // Revert UI if error
      setState(() {
        _posts[idx]['isLiked'] = wasLiked;
        _posts[idx]['likes'] = oldLikes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update like. Please try again.')),
      );
    } finally {
      setState(() {
        _likingPostIds.remove(postId);
      });
    }
  }

  void _onCommentTap(String postId) {
    final TextEditingController _commentController = TextEditingController();
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18122B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<List<Map<String, dynamic>>> fetchComments() async {
              final comments = await SupabaseService.client
                  .from('comments')
                  .select('comment, created_at, user_id, profiles(username, profile_photo)')
                  .eq('post_id', postId)
                  .order('created_at', ascending: true);
              return List<Map<String, dynamic>>.from(comments);
            }

            List<Map<String, dynamic>> loadedComments = [];

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                color: Colors.black,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: fetchComments(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return const Center(child: Text('Failed to load comments', style: TextStyle(color: Colors.white54)));
                          }
                          loadedComments = snapshot.data ?? [];
                          if (loadedComments.isEmpty) {
                              return const Center(child: Text('No comments yet.', style: TextStyle(color: Colors.white70)));
                          }
                          return ListView.builder(
                            itemCount: loadedComments.length,
                            itemBuilder: (context, idx) {
                              final c = loadedComments[idx];
                              final user = c['profiles'] ?? {};
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: (user['profile_photo'] != null && user['profile_photo'].toString().isNotEmpty)
                                    ? NetworkImage(user['profile_photo'])
                                    : const AssetImage('assets/Oval.png') as ImageProvider,
                                    backgroundColor: Colors.white,
                                ),
                                title: Text('@${user['username'] ?? 'user'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                subtitle: Text(c['comment'] ?? '', style: const TextStyle(color: Colors.white70)),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              decoration: InputDecoration(
                                hintText: 'Add a comment...',
                                hintStyle: const TextStyle(color: Colors.white54),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: () async {
                              final comment = _commentController.text.trim();
                              if (comment.isEmpty) return;
                              final userId = SupabaseService.client.auth.currentUser?.id;
                              if (userId == null) return;
                              await SupabaseService.client.from('comments').insert({
                                'post_id': postId,
                                'user_id': userId,
                                'comment': comment,
                              });
                              _commentController.clear();
                              // Refresh comments after sending
                              setModalState(() {});
                              // Add notification for comment
                              final postIdx = _posts.indexWhere((p) => p['id'] == postId);
                              if (postIdx != -1) {
                                final postOwnerId = _posts[postIdx]['user_id'];
                                final postCaption = _posts[postIdx]['caption'] ?? '';
                                await SupabasePostService.sendNotification(
                                  client: SupabaseService.client,
                                  type: 'comment',
                                  toUserId: postOwnerId,
                                  fromUserId: userId,
                                  targetType: 'post',
                                  targetId: postId,
                                  targetCaption: postCaption,
                                  commentText: comment,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onShareTap(int idx) {
    final postId = _posts[idx]['id']?.toString();
    if (postId == null) return;
    final url = 'https://luohino.github.io/Talktwirl/';
    Share.share('Check out this post on TalkTwirl!\n$url');
  }

  void _onSearchFocus(bool hasFocus) {
    setState(() {
      _showSearchPopup = hasFocus;
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _showSearchPopup = true;
    });
  }

  void _onSearchTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen()),
    );
  }

  // Replace Firebase Auth and Firestore logic with Supabase equivalents
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Check authentication first
      final isAuthenticated = await SupabaseService.ensureAuthenticated();
      
      if (!isAuthenticated) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }
      }
      
      // If authenticated, proceed with initialization
      setState(() {
        _isAuthenticating = false;
      });
      
      await Future.wait([
        _fetchPosts(),
        _checkUserSuspended(),
        _loadSavedPosts(),
        _ensureProfileLoaded(),
        _fetchUnseenNotificationCount(),
        _prefetchAllUserProfiles(),
        _cacheProfilesAndMessages(),
      ]);
      
      // Setup real-time subscriptions after initial data load
      _setupMessagesSubscription();
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _isLoadingPosts = false;
        });
        
        // Show error or redirect to login
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _fetchPosts() async {
    try {
    final user = SupabaseService.client.auth.currentUser;
    final postsRes = await SupabaseService.client
        .from('posts')
        .select('*, profiles(username, name, profile_photo)')
        .order('created_at', ascending: false);

    List<String> likedPostIds = [];
    List<String> savedPostIds = [];
    if (user != null) {
      final likesRes = await SupabaseService.client
          .from('likes')
          .select('post_id')
          .eq('user_id', user.id);
      if (likesRes != null && likesRes is List) {
        likedPostIds = List<String>.from(likesRes.map((like) => like['post_id'].toString()));
      }
      final savedRes = await SupabaseService.client
          .from('saved_posts')
          .select('post_id')
          .eq('user_id', user.id);
      if (savedRes != null && savedRes is List) {
        savedPostIds = List<String>.from(savedRes.map((s) => s['post_id'].toString()));
      }
    }

    setState(() {
      _posts = List<Map<String, dynamic>>.from(postsRes.map((post) {
        return {
          ...post,
          'username': post['profiles']?['username'] ?? '',
          'name': post['profiles']?['name'] ?? '',
          'profilePhoto': post['profiles']?['profile_photo'] ?? 'assets/Oval.png',
          'media_url': post['media_url'] ?? post['image'],
          'isLiked': likedPostIds.contains(post['id']?.toString()),
          'isSaved': savedPostIds.contains(post['id']?.toString()),
        };
      }));
      });
    } catch (e) {
      // Optionally log or show error
    } finally {
      setState(() {
      _isLoadingPosts = false;
    });
    }
  }

  Future<void> _loadSavedPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPostsJson = prefs.getStringList('saved_posts') ?? [];
    setState(() {
      _savedPostIds.clear();
      for (var i = 0; i < _posts.length; i++) {
        _posts[i]['isSaved'] = false;
      }
      for (var postJson in savedPostsJson) {
        final post = Map<String, dynamic>.from(jsonDecode(postJson));
        final idx = _posts.indexWhere((p) => p['username'] == post['username'] && p['caption'] == post['caption']);
        if (idx != -1) {
          _posts[idx] = post;
          _savedPostIds.add(idx);
        }
      }
    });
  }

  void _onToggleSave(int idx) async {
    setState(() {
      _posts[idx]['isSaved'] = !_posts[idx]['isSaved'];
      if (_posts[idx]['isSaved']) {
        _savedPostIds.add(idx);
      } else {
        _savedPostIds.remove(idx);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    List<String> savedPostsJson = prefs.getStringList('saved_posts') ?? [];

    if (_posts[idx]['isSaved']) {
      savedPostsJson.add(jsonEncode(_posts[idx]));
    } else {
      savedPostsJson = savedPostsJson.where((postJson) {
        final post = Map<String, dynamic>.from(jsonDecode(postJson));
        return !(post['username'] == _posts[idx]['username'] && post['caption'] == _posts[idx]['caption']);
      }).toList();
    }

    await prefs.setStringList('saved_posts', savedPostsJson);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for profile photo changes from ProfileScreen
    final ModalRoute? route = ModalRoute.of(context);
    if (route != null && route.settings.arguments is Map) {
      final args = route.settings.arguments as Map;
      if (args['profilePhoto'] != null) {
        setState(() {
          // Removed local _profilePhoto state
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_messagesChannel != null) {
      // Disposing messages subscription
      _messagesChannel?.unsubscribe(); // Unsubscribe from messages
    }
    // Removed dispose calls for controllers that are not in this class
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this screen from MessageScreen.
    // MessageScreen's initState should have already marked messages as read.
    // We just need to refresh the count here.
    _fetchUnreadMessagesCount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is resumed, check for new messages
      _fetchUnreadMessagesCount();
    }
  }

  Future<void> _ensureProfileLoaded() async {
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    if (profileProvider.profilePhoto == null || profileProvider.profilePhoto!.isEmpty) {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        final profileRes = await SupabaseService.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (profileRes != null) {
          profileProvider.updateProfile(
            username: profileRes['username'] ?? '',
            name: profileRes['name'] ?? 'TalkTwirl User',
            website: profileRes['website'] ?? '',
            bio: profileRes['bio'] ?? '',
            email: profileRes['email'] ?? '',
            phone: profileRes['phone'] ?? '',
            gender: profileRes['gender'] ?? '',
            profilePhoto: profileRes['profile_photo'],
          );
        }
      }
    }
  }

  void _setupMessagesSubscription() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    // Setting up messages subscription for user: ${user.id}

    // Using the correct Supabase Flutter SDK API for real-time subscriptions
    _messagesChannel = SupabaseService.client
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // Received real-time message payload
            // Check if the inserted message is for the current user
            if (payload.newRecord?['receiver_id'] == user.id) {
              // New message received for user: ${user.id}
              setState(() {
                _unreadMessagesCount++;
              });
              // Updated unread count to: $_unreadMessagesCount
            }
          },
        )
        .subscribe();

    // Messages subscription set up successfully

    // Fetch initial unread count
    _fetchUnreadMessagesCount();
  }

  Future<void> _fetchUnreadMessagesCount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    // Assuming a 'messages' table with 'receiver_id' and 'is_read' columns
    final response = await SupabaseService.client
        .from('messages')
        .select('*')
        .eq('receiver_id', user.id) // Changed from recipient_id to receiver_id
        .eq('is_read', false);

    if (response != null) {
      setState(() {
        _unreadMessagesCount = response.length; // Count the actual messages
      });
      // Updated unread message count: $_unreadMessagesCount
    }
  }

  void _resetMessageBadge() {
    if (!mounted) return;
    setState(() {
      _unreadMessagesCount = 0;
    });
    // Reset message badge to 0
    // Mark messages as read in the database. This will be handled by MessageScreen as well,
    // but we do it here for instant feedback and robustness.
    _markMessagesAsRead();
  }

  Future<void> _markMessagesAsRead() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    
    try {
      final response = await SupabaseService.client
          .from('messages')
          .update({'is_read': true})
          .eq('receiver_id', user.id) // Changed from recipient_id to receiver_id
          .eq('is_read', false);
      
      // Marked messages as read successfully
      // After marking, fetch the count again to ensure consistency.
      if (mounted) {
        _fetchUnreadMessagesCount();
      }
    } catch (e) {
      // Error marking messages as read: $e
    }
  }

  Future<void> _fetchUnseenNotificationCount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final response = await SupabaseService.client
        .from('notifications')
        .select('*')
        .eq('to_user_id', user.id)
        .eq('seen', false);
    setState(() {
      _unseenNotificationCount = response.length;
    });
  }

  void _onNotificationIconTap() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;
    await SupabaseService.client
        .from('notifications')
        .update({'seen': true})
        .eq('to_user_id', userId)
        .eq('seen', false);
    _fetchUnseenNotificationCount();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
  }

  Future<void> _prefetchAllUserProfiles() async {
    try {
      final profiles = await SupabaseService.client
          .from('profiles')
          .select('id, username, name, profile_photo');
      final Map<String, Map<String, dynamic>> cache = {};
      for (final profile in profiles) {
        if (profile['id'] != null) {
          cache[profile['id']] = profile;
        }
      }
      setState(() {
        userProfilesCache = cache;
      });
      // Prefetched and cached ${cache.length} user profiles
    } catch (e) {
      // Error prefetching user profiles: $e
    }
  }

  Future<void> _cacheProfilesAndMessages() async {
    // Cache all user profiles
    final profilesBox = Hive.box('profiles');
    final profiles = await SupabaseService.client
        .from('profiles')
        .select('id, username, name, profile_photo');
    for (final profile in profiles) {
      if (profile['id'] != null) {
        profilesBox.put(profile['id'], profile);
      }
    }
    // Cache ALL messages for the current user
    final messagesBox = Hive.box('messages');
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      final messages = await SupabaseService.client
          .from('messages')
          .select()
          .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
          .order('created_at', ascending: false);
      int count = 0;
      for (final msg in messages) {
        if (msg['id'] != null && msg['sender_id'] != null && msg['receiver_id'] != null) {
          messagesBox.put(msg['id'], msg);
          count++;
        }
      }
      // Cached $count messages for user ${user.id} in Hive
    }
    // Cached ${profiles.length} profiles in Hive
  }

  String _formatTimestamp(dynamic postedAt) {
    if (postedAt is DateTime) {
      final diff = DateTime.now().difference(postedAt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }
    if (postedAt is String && postedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(postedAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
        if (diff.inHours < 24) return '${diff.inHours}h ago';
        return '${diff.inDays}d ago';
      } catch (_) {}
    }
    return '';
  }

  Future<Size> _getImageSize(String url) async {
    final Completer<Size> completer = Completer();
    final Image image = Image.network(url);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        var myImage = info.image;
        completer.complete(Size(myImage.width.toDouble(), myImage.height.toDouble()));
      }),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while authenticating
    if (_isAuthenticating) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text('Authenticating...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    
    // Only show posts with category 'Post' in the feed
    final imagePosts = _posts.where((p) => (p['category'] == 'Post')).toList();
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
          // Left swipe detected
          _resetMessageBadge();
          navigateToMessageScreen(context);
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            pinned: true,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Image.asset('assets/icon.png', height: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        colors: [Colors.white, Colors.white],
                      ).createShader(bounds);
                    },
                    child: const Text(
                      'TalkTwirl',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.notifications_none, color: Color(0xFFFAE6FF), size: 24),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: _onNotificationIconTap,
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
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.message_outlined, color: Color(0xFFFAE6FF), size: 24),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => MessageScreen()),
                            );
                          },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: FocusScope(
                child: Focus(
                  onFocusChange: _onSearchFocus,
                  child: GestureDetector(
                    onTap: _onSearchTap,
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 8),
                            child: Icon(Icons.search, color: Colors.white54, size: 24),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          hintText: 'Search...',
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(50),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, idx) {
                if (_isLoadingPosts && imagePosts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (idx >= imagePosts.length) return const SizedBox(height: 90);
                final post = imagePosts[idx];
                return _buildFeedPost(context, post: post, idx: idx);
              },
              childCount: (imagePosts.isEmpty && _isLoadingPosts) ? 1 : imagePosts.length + 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedPost(BuildContext context, {required Map<String, dynamic> post, required int idx}) {
    final realIdx = _posts.indexWhere((p) => p['id'] == post['id']);
    final realPost = realIdx != -1 ? _posts[realIdx] : post;
    // Debug print removed to prevent console spam and flickering
    final postId = realPost['id']?.toString() ?? '';
    Widget imageWidget;
    if (_imageSizeCache.containsKey(postId)) {
      final size = _imageSizeCache[postId]!;
      final double minAspectRatio = 0.8;
      final double maxAspectRatio = 1.91;
      double aspectRatio = size.width / size.height;
      aspectRatio = aspectRatio.clamp(minAspectRatio, maxAspectRatio);
      imageWidget = AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.network(
          realPost['media_url'],
          fit: BoxFit.contain,
        ),
      );
    } else {
      imageWidget = FutureBuilder<Size>(
        future: _getImageSize(realPost['media_url']),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final size = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_imageSizeCache.containsKey(postId)) {
              setState(() {
                _imageSizeCache[postId] = size;
              });
            }
          });
          final double minAspectRatio = 0.8;
          final double maxAspectRatio = 1.91;
          double aspectRatio = size.width / size.height;
          aspectRatio = aspectRatio.clamp(minAspectRatio, maxAspectRatio);
          return AspectRatio(
            aspectRatio: aspectRatio,
            child: Image.network(
              realPost['media_url'],
              fit: BoxFit.contain,
            ),
          );
        },
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      // No decoration: flat, edge-to-edge like Instagram
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info (unchanged)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 12, right: 12, bottom: 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    final currentUser = SupabaseService.client.auth.currentUser;
                    if (currentUser != null && realPost['user_id'] == currentUser.id) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userData: {
                              'uid': realPost['user_id'],
                              'username': realPost['username'],
                              'profile_photo': realPost['profilePhoto'],
                              'name': realPost['name'],
                            },
                            isCurrentUser: false,
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      buildUserAvatar(
                        profilePhoto: realPost['profilePhoto'] ?? 'assets/Oval.png',
                        name: realPost['name'] ?? '',
                        username: realPost['username'] ?? '',
                        radius: 22,
                        fontSize: 22,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              '@${realPost['username'] ?? ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                            ),
                          ),
                          if ((realPost['name'] ?? '').toString().isNotEmpty)
                            Text(
                              realPost['name'],
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          if ((realPost['location'] ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                realPost['location'],
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  onSelected: (value) async {
                    final currentUser = SupabaseService.client.auth.currentUser;
                    if (realPost['user_id'] == currentUser?.id && value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF261531),
                          title: const Text('Delete Post', style: TextStyle(color: Colors.white)),
                          content: compactDialogContent(
                            child: const Text('Are you sure you want to delete this post? This cannot be undone.', style: TextStyle(color: Colors.white70)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        // Delete from storage bucket if media_url is present
                        final mediaUrl = realPost['media_url'] ?? '';
                        if (mediaUrl.toString().contains('/storage/v1/object/public/')) {
                          try {
                            final uri = Uri.parse(mediaUrl);
                            final path = uri.pathSegments.skipWhile((s) => s != 'public').skip(1).join('/');
                            await SupabaseService.client.storage.from('post-images').remove([path]);
                          } catch (e) {
                            // Failed to delete media from storage: $e
                          }
                        }
                        // Delete from posts table
                        await SupabaseService.client.from('posts').delete().eq('id', realPost['id']);
                        setState(() {
                          _posts.removeWhere((p) => p['id'] == realPost['id']);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Post deleted.')),
                        );
                      }
                    } else if (realPost['user_id'] != currentUser?.id && value == 'report') {
                      String? selectedReason;
                      final reasons = ['Nudity', 'Violence', 'Spam', 'Hate Speech', 'Other'];
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setModalState) => AlertDialog(
                            backgroundColor: const Color(0xFF261531),
                            title: const Text('Report Post', style: TextStyle(color: Colors.white)),
                            content: compactDialogContent(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ...reasons.map((r) => RadioListTile<String>(
                                    value: r,
                                    groupValue: selectedReason,
                                    onChanged: (v) => setModalState(() => selectedReason = v),
                                    title: Text(r, style: const TextStyle(color: Colors.white, fontSize: 15)),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  )),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                              ),
                              TextButton(
                                onPressed: selectedReason == null ? null : () => Navigator.pop(context, true),
                                child: const Text('Report', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (confirmed == true && selectedReason != null) {
                        await SupabaseService.client.from('reports').insert({
                          'post_id': realPost['id'],
                          'reported_by': currentUser?.id,
                          'reason': selectedReason,
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report submitted. Thank you!')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) {
                    final currentUser = SupabaseService.client.auth.currentUser;
                    if (realPost['user_id'] == currentUser?.id) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ];
                    } else {
                      return [
                        const PopupMenuItem<String>(
                          value: 'report',
                          child: Text('Report'),
                        ),
                      ];
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Post Image (show loader only in image area)
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullMediaScreen(
                    mediaPath: realPost['media_url'],
                    mediaType: 'image',
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: realPost['media_url'] != null && realPost['media_url'].toString().isNotEmpty
                  ? imageWidget
                  : Image.asset('assets/Rectangle.png', fit: BoxFit.contain),
            ),
          ),
          // Interaction Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _likingPostIds.contains(realPost['id']?.toString()) ? null : () => _onToggleLike(realIdx),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    realPost['isLiked'] == true ? Icons.favorite : Icons.favorite_border,
                          key: ValueKey(realPost['isLiked']),
                          color: realPost['isLiked'] == true ? Colors.pinkAccent : Colors.white,
                    size: 26,
                        ),
                      ),
                      if (_animatingLikeIds.contains(realPost['id']?.toString()))
                        Positioned(
                          left: -10,
                          top: -10,
                          right: -10,
                          bottom: -10,
                          child: IgnorePointer(
                            child: LikeBurst(trigger: true, size: 48),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _onCommentTap(realPost['id']?.toString() ?? ''),
                  child: const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _onShareTap(realIdx),
                  child: const Icon(Icons.send, color: Colors.white, size: 24),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _toggleSavePost(realIdx),
                  child: Icon(
                    realPost['isSaved'] == true ? Icons.bookmark : Icons.bookmark_border,
                    color: realPost['isSaved'] == true ? Colors.white : Colors.white54,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
          // Likes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: Colors.pinkAccent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${realPost['likes'] ?? 0} likes',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                ),
              ],
            ),
          ),
          // Caption
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '@${realPost['username']} ${realPost['caption'] ?? ''}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          // Date
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              _formatTimestamp(realPost['postedAt'] ?? realPost['created_at']),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _onAddPostTap() async {
    // Add post icon tapped
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
              // Post (Photos) selected
              Navigator.pop(context);
              final permissionStatus = await Permission.photos.request();
              // Photos permission status: ${permissionStatus.isGranted}
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                // Image selected: ${picked?.path}
                if (picked != null) {
                  // Navigating to AddPostScreen for image
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'image'),
                    ),
                  );
                  // Received result from AddPostScreen
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
              // Twirls (Videos) selected
              Navigator.pop(context);
              final permissionStatus = await Permission.videos.request();
              // Videos permission status: ${permissionStatus.isGranted}
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
                // Video selected: ${picked?.path}
                if (picked != null) {
                  // Navigating to AddPostScreen for video
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'video'),
                    ),
                  );
                  // Received result from AddPostScreen
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
    // Handle new post: category $category
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    profile.incrementPostCount(category);
    final newPost = {
      'username': profile.username ?? '',
      'name': profile.name ?? '',
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
      _posts.insert(0, newPost);
    });
    // Save to shared_preferences for profile_screen
    final prefs = await SharedPreferences.getInstance();
    final posts = prefs.getStringList('user_posts') ?? [];
    posts.insert(0, jsonEncode(newPost));
    await prefs.setStringList('user_posts', posts);
    // New post added and saved
  }

  Future<void> _toggleSavePost(int idx) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final postId = _posts[idx]['id']?.toString();
    if (postId == null) return;

    final isSaved = _posts[idx]['isSaved'] == true;

    setState(() {
      _posts[idx]['isSaved'] = !isSaved;
    });

    try {
      if (!isSaved) {
        // Save post in Supabase
        await SupabaseService.client.from('saved_posts').insert({
          'user_id': user.id,
          'post_id': postId,
        });
      } else {
        // Unsave post in Supabase
        await SupabaseService.client
          .from('saved_posts')
          .delete()
          .eq('user_id', user.id)
          .eq('post_id', postId);
      }
    } catch (e) {
      // Revert UI if error
      setState(() {
        _posts[idx]['isSaved'] = isSaved;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update saved post.')),
      );
    }
  }

  // Helper for compact dialog content
  Widget compactDialogContent({required Widget child}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(child: child),
    );
  }
}

// Twitter/X style like burst animation widget
class LikeBurst extends StatefulWidget {
  final bool trigger;
  final double size;
  const LikeBurst({Key? key, required this.trigger, this.size = 40}) : super(key: key);
  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _burstAnim;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _burstAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    if (widget.trigger) _controller.forward();
  }
  @override
  void didUpdateWidget(covariant LikeBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _burstAnim,
      builder: (context, child) {
        if (_burstAnim.value == 0) return const SizedBox.shrink();
        final burstCount = 8;
        final List<Widget> bursts = [];
        for (int i = 0; i < burstCount; i++) {
          final angle = (2 * pi / burstCount) * i;
          final radius = widget.size * 0.7 * _burstAnim.value;
          bursts.add(Positioned(
            left: widget.size / 2 + radius * cos(angle) - 4,
            top: widget.size / 2 + radius * sin(angle) - 4,
            child: Opacity(
              opacity: 1 - _burstAnim.value,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ));
        }
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(children: bursts),
        );
      },
    );
  }
}

// Add this import at the top:

// Insert HomeMessagePager widget before HomeScreen
class HomeMessagePager extends StatefulWidget {
  const HomeMessagePager({Key? key}) : super(key: key);

  @override
  State<HomeMessagePager> createState() => _HomeMessagePagerState();
}

class _HomeMessagePagerState extends State<HomeMessagePager> with TickerProviderStateMixin {
  late AnimationController _controller;
  double _dragStartX = 0.0;
  double _dragDx = 0.0;
  bool _isDragging = false;
  bool _onHome = true;

  final _home = const RepaintBoundary(child: HomeScreenBody());
  final _messages = const RepaintBoundary(child: MessageScreen());

  static const double _threshold = 0.25;
  static const Duration _animationDuration = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
      value: 0.0,
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
    _dragDx = 0.0;
    _isDragging = true;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final width = MediaQuery.of(context).size.width;
    double delta = details.globalPosition.dx - _dragStartX;
    _dragDx = delta;
    if (_onHome && delta < 0) {
      _controller.value = (delta.abs() / width).clamp(0.0, 1.0);
    } else if (!_onHome && delta > 0) {
      _controller.value = 1.0 - (delta.abs() / width).clamp(0.0, 1.0);
    }
    setState(() {});
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final width = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0.0;
    final shouldComplete = (_controller.value > _threshold) || velocity.abs() > 800;
    if (_onHome && _controller.value > 0) {
      if (shouldComplete && velocity < 0) {
        _animateTo(1.0);
      } else {
        _animateTo(0.0);
      }
    } else if (!_onHome && _controller.value < 1) {
      if (shouldComplete && velocity > 0) {
        _animateTo(0.0);
      } else {
        _animateTo(1.0);
      }
    }
    _isDragging = false;
    _dragDx = 0.0;
  }

  void _animateTo(double target) {
    _controller.animateTo(target, duration: _animationDuration, curve: Curves.easeOutCubic).then((_) {
      if (target == 1.0 && _onHome) {
        setState(() {
          _onHome = false;
          _controller.value = 0.0;
        });
        HapticFeedback.mediumImpact();
      } else if (target == 0.0 && !_onHome) {
        setState(() {
          _onHome = true;
          _controller.value = 0.0;
        });
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final slide = _controller.value;
    // Parallax: message screen moves slightly slower
    final homeOffset = Offset(-slide * width, 0);
    final messageOffset = Offset((1.0 - slide) * width * 0.85, 0); // parallax
    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          ClipRect(
            child: Opacity(
              opacity: 1.0 - slide,
              child: Transform.translate(
                offset: homeOffset,
                child: Container(
                  color: Colors.black,
                  child: _onHome || _isDragging ? _home : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (!_onHome || _isDragging)
            ClipRect(
              child: Opacity(
                opacity: slide,
                child: Transform.translate(
                  offset: messageOffset,
                  child: Container(
                    color: Colors.black,
                    child: _messages,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

void navigateToMessageScreen(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => const MessageScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideIn = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeInOut));
        final fadeIn = Tween<double>(begin: 0.7, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut));
        return Stack(
          children: [
            // HomeScreen stays visible underneath
            Positioned.fill(
              child: Opacity(
                opacity: 1.0 - animation.value * 0.3,
                child: IgnorePointer(child: context.findAncestorWidgetOfExactType<HomeScreenBody>() ?? Container()),
              ),
            ),
            SlideTransition(
              position: animation.drive(slideIn),
              child: FadeTransition(
                opacity: animation.drive(fadeIn),
                child: child,
              ),
            ),
          ],
        );
      },
    ),
  );
}