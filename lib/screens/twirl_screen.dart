import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'user_profile_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import 'add_post_screen.dart';
import '../core/supabase_client.dart';
import '../core/avatar_widget.dart';
import '../core/bottom_nav_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import '../core/supabase_post_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';

// Like burst animation widget (copied from home_screen.dart, can be moved to a shared file)
class LikeBurst extends StatefulWidget {
  final bool trigger;
  final double size;
  const LikeBurst({Key? key, required this.trigger, this.size = 48}) : super(key: key);
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

class TwirlPost {
  final String id;
  final String userId;
  final String videoPath;
  final String username;
  final String userPfp;
  final String caption;
  final String song;
  final String location;
  int likes;
  final int comments;
  bool isLiked;
  bool isMuted;
  TwirlPost({
    required this.id,
    required this.userId,
    required this.videoPath,
    required this.username,
    required this.userPfp,
    required this.caption,
    required this.song,
    required this.location,
    required this.likes,
    required this.comments,
    this.isLiked = false,
    this.isMuted = true,
  });
}

class TwirlScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? twirls;
  final int? initialIndex;
  const TwirlScreen({Key? key, this.twirls, this.initialIndex}) : super(key: key);
  @override
  State<TwirlScreen> createState() => _TwirlScreenState();
}

class _TwirlScreenState extends State<TwirlScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  int _currentPage = 0;
  final List<TwirlPost> _twirlPosts = [];
  final List<VideoPlayerController> _controllers = [];
  final List<ChewieController> _chewieControllers = [];
  final List<AnimationController> _heartControllers = [];
  final List<Animation<double>> _heartScales = [];
  bool _isLongPressing = false;
  List<TwirlPost> savedTwirlList = [];
  List<List<Map<String, String>>> _comments = [];
  List<bool> _showHeart = [];
  static const int _pageSize = 10;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _tabIndex = 0; // 0 = Recent, 1 = Trending, 2 = For You
  List<String> _followingIds = [];
  Set<String> _likedTwirlIds = {};
  Set<String> _savedTwirlIds = {};
  Set<String> _likingTwirlIds = {}; // Track twirls being liked/unliked

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUserSuspended();
    _pageController = PageController();
    if (widget.twirls != null && widget.twirls!.isNotEmpty) {
      _initFromProvidedTwirls(widget.twirls!, widget.initialIndex ?? 0);
    } else {
      _fetchFollowingIds().then((_) {
        _fetchTwirlPosts(initial: true);
      });
      _fetchUserLikesAndSaves();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playCurrent();
    });
  }

  Future<void> _checkUserSuspended() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final userDoc = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    if (userDoc == null || userDoc.isEmpty) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Your account is suspended', style: TextStyle(color: Colors.black)),
            content: const Text('This account is no longer available.', style: TextStyle(color: Colors.black54)),
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

  Future<void> _playCurrent() async {
    for (int i = 0; i < _controllers.length; i++) {
      if (i == _currentPage) {
        await _controllers[i].seekTo(Duration.zero);
        await _controllers[i].play();
        _controllers[i].setLooping(true);
        _controllers[i].removeListener(_onVideoEnd);
        _controllers[i].addListener(_onVideoEnd);
        // Preload next video
        if (i + 1 < _controllers.length && !_controllers[i + 1].value.isInitialized) {
          _controllers[i + 1].initialize();
        }
      } else {
        _controllers[i].pause();
      }
    }
  }

  void _onVideoEnd() async {
    final controller = _controllers[_currentPage];
    if (controller.value.position >= controller.value.duration && !controller.value.isPlaying) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted && _currentPage < _controllers.length && _controllers[_currentPage] == controller) {
        await controller.seekTo(Duration.zero);
        await controller.play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (var c in _controllers) {
      c.removeListener(_onVideoEnd);
      c.dispose();
    }
    for (var c in _chewieControllers) {
      c.dispose();
    }
    for (var a in _heartControllers) {
      a.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      for (var controller in _controllers) {
        if (controller.value.isPlaying) {
          controller.pause();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      // Resume the current video when returning to the app
      if (_controllers.isNotEmpty && _currentPage < _controllers.length) {
        final controller = _controllers[_currentPage];
        if (!controller.value.isPlaying) {
          controller.play();
        }
      }
    }
  }

  void _onPageChanged(int idx) {
    setState(() {
      _currentPage = idx;
    });
    _playCurrent();
    // Infinite scroll: if near end, load more
    if (_hasMore && idx >= _twirlPosts.length - 3) {
      _fetchTwirlPosts();
    }
  }

  void _toggleLike(int idx) async {
    final post = _twirlPosts[idx];
    final twirlId = post.id;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    if (_likingTwirlIds.contains(twirlId)) return; // Prevent spamming
    setState(() { _likingTwirlIds.add(twirlId); });
    final wasLiked = post.isLiked;
    final oldLikes = post.likes;
    try {
      if (wasLiked) {
        await SupabaseService.client
            .from('twirl_likes')
            .delete()
            .eq('twirl_id', twirlId)
            .eq('user_id', user.id);
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes - 1})
            .eq('id', twirlId);
        setState(() {
          post.likes = oldLikes - 1;
          post.isLiked = false;
        });
      } else {
        await SupabaseService.client
            .from('twirl_likes')
            .insert({'twirl_id': twirlId, 'user_id': user.id});
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes + 1})
            .eq('id', twirlId);
        setState(() {
          post.likes = oldLikes + 1;
          post.isLiked = true;
        });
        // Add notification for like
        final twirlOwnerId = post.userId;
        final twirlCaption = post.caption;
        SupabasePostService.sendNotification(
          client: SupabaseService.client,
          type: 'like',
          toUserId: twirlOwnerId,
          fromUserId: user.id,
          targetType: 'twirl',
          targetId: twirlId,
          targetCaption: twirlCaption,
        );
      }
    } catch (e, stack) {
      // print('Failed to update like:');
      // print(e);
      // print(stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update like. Please try again.')),
      );
      // No UI update on error
    } finally {
      setState(() { _likingTwirlIds.remove(twirlId); });
    }
  }

  void _toggleMute(int idx) {
    setState(() {
      _twirlPosts[idx].isMuted = !_twirlPosts[idx].isMuted;
      _controllers[idx].setVolume(_twirlPosts[idx].isMuted ? 0 : 1);
    });
  }

  // Remove twirl_comments usage and use comments table with post_id
  Stream<List<Map<String, dynamic>>> _commentStream(String twirlId) {
    return SupabaseService.client
      .from('comments')
      .stream(primaryKey: ['id'])
      .eq('post_id', twirlId)
      .order('created_at')
      .map((event) => List<Map<String, dynamic>>.from(event));
  }

  Future<void> _addComment(String twirlId, String comment) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || comment.trim().isEmpty) return;
    await SupabaseService.client.from('comments').insert({
      'post_id': twirlId,
      'user_id': user.id,
      'comment': comment.trim(),
    });
    // Add notification for comment
    final post = _twirlPosts.firstWhere((p) => p.id == twirlId);
    final twirlOwnerId = post.userId;
    final twirlCaption = post.caption;
    SupabasePostService.sendNotification(
      client: SupabaseService.client,
      type: 'comment',
      toUserId: twirlOwnerId,
      fromUserId: user.id,
      targetType: 'twirl',
      targetId: twirlId,
      targetCaption: twirlCaption,
      commentText: comment,
    );
  }

  void _onCommentTap(int idx) {
    final post = _twirlPosts[idx];
    final twirlId = post.id;
    final TextEditingController _commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<List<Map<String, dynamic>>> fetchComments() async {
              final comments = await SupabaseService.client
                  .from('comments')
                  .select('comment, created_at, user_id, profiles(username, profile_photo)')
                  .eq('post_id', twirlId)
                  .order('created_at', ascending: false);
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
                              itemBuilder: (context, cidx) {
                                final c = loadedComments[cidx];
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
                                await _addComment(twirlId, comment);
                                _commentController.clear();
                                // Refresh comments after sending
                                setModalState(() {});
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
    final post = _twirlPosts[idx];
    final twirlId = post.id;
    final url = 'https://luohino.github.io/Talktwirl/';
    Share.share('Check out this twirl on TalkTwirl!\n$url');
  }

  void _onSaveTap(int idx) async {
    final post = _twirlPosts[idx];
    final twirlId = post.id;
    await _toggleSaveTwirl(twirlId);
  }

  void _onLongPress(int idx) {
    setState(() {
      _isLongPressing = true;
    });
    _controllers[idx].pause();
  }

  void _onLongPressUp(int idx) {
    setState(() {
      _isLongPressing = false;
    });
    _controllers[idx].play();
  }

  void _onProfileTap(String username) {
    // TODO: Implement navigation to user profile
    // Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: username)));
  }

  void _onAddPostTap() async {
    // print('[_onAddPostTap] Tapped add post icon');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image, color: Colors.white),
            title: const Text('Post (Photos)', style: TextStyle(color: Colors.black)),
            onTap: () async {
              // print('[_onAddPostTap] Tapped Post (Photos)');
              Navigator.pop(context);
              final permissionStatus = await Permission.photos.request();
              // print('[_onAddPostTap] Photos permission status: ${permissionStatus.isGranted}');
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                // print('[_onAddPostTap] Picked image: ${picked?.path}');
                if (picked != null) {
                  // print('[_onAddPostTap] Navigating to AddPostScreen for image');
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'image'),
                    ),
                  );
                  // print('[_onAddPostTap] Received result from AddPostScreen: $result');
                  if (result != null && mounted) {
                    _handleNewPost(result, 'Post');
                  }
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.white),
            title: const Text('Twirls (Videos)', style: TextStyle(color: Colors.black)),
            onTap: () async {
              // print('[_onAddPostTap] Tapped Twirls (Videos)');
              Navigator.pop(context);
              final permissionStatus = await Permission.videos.request();
              // print('[_onAddPostTap] Videos permission status: ${permissionStatus.isGranted}');
              if (permissionStatus.isGranted) {
                final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
                // print('[_onAddPostTap] Picked video: ${picked?.path}');
                if (picked != null) {
                  // print('[_onAddPostTap] Navigating to AddPostScreen for video');
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPostScreen(mediaPath: picked.path, mediaType: 'video'),
                    ),
                  );
                  // print('[_onAddPostTap] Received result from AddPostScreen: $result');
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
    // print('[_handleNewPost] Called with result: $result, category: $category');
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    profile.incrementPostCount(category);
    // Generate a uuid for the new post/twirl
    final id = const Uuid().v4();
    final newPost = {
      'id': id,
      'username': profile.username,
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
    // print('[_handleNewPost] Created new post object: $newPost');

    // Save to shared_preferences for profile_screen
    final prefs = await SharedPreferences.getInstance();
    final posts = prefs.getStringList('user_posts') ?? [];
    posts.insert(0, jsonEncode(newPost));
    await prefs.setStringList('user_posts', posts);

    if (category == 'Twirl') {
      // Insert into posts table
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
      // Insert into twirls table
      await SupabaseService.client.from('twirls').insert({
        'id': id,
        'user_id': profile.userId,
        'video_url': result['mediaPath'],
        'caption': result['caption'] ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });
      setState(() {
        _twirlPosts.insert(0, TwirlPost(
          id: id,
          userId: profile.userId,
          videoPath: result['mediaPath'],
          username: profile.username,
          userPfp: profile.profilePhoto ?? 'assets/Oval.png',
          caption: result['caption'] ?? '',
          song: result['music'] ?? '',
          location: 'Your City',
          likes: 0,
          comments: 0,
        ));
        // Initialize controllers for new post
        final vController = VideoPlayerController.network(_twirlPosts[0].videoPath);
        _controllers.insert(0, vController);
        final cController = ChewieController(
          videoPlayerController: vController,
          looping: true,
          autoPlay: true,
          showControls: false,
          allowMuting: false,
          allowPlaybackSpeedChanging: false,
          allowFullScreen: false,
        );
        _chewieControllers.insert(0, cController);
        final heartAnim = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 350),
        );
        _heartControllers.insert(0, heartAnim);
        _heartScales.insert(0, Tween<double>(begin: 0.0, end: 1.4)
          .chain(CurveTween(curve: Curves.elasticOut))
          .animate(heartAnim));
        vController.initialize().then((_) {
          setState(() {});
        });
        _showHeart.insert(0, false);
        _comments.insert(0, []);
      });
    }
  }

  Future<void> _fetchFollowingIds() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final rels = await SupabaseService.client
        .from('user_relationships')
        .select('target_id')
        .eq('user_id', user.id);
    _followingIds = rels != null ? List<String>.from(rels.map((r) => r['target_id'])) : [];
  }

  Future<void> _fetchTwirlPosts({bool initial = false}) async {
    if (_isLoadingMore || (!_hasMore && !initial)) return;
    setState(() { _isLoadingMore = true; });
    final user = SupabaseService.client.auth.currentUser;
    final from = initial ? 0 : _twirlPosts.length;
    final to = from + _pageSize - 1;
    var query = SupabaseService.client
        .from('posts')
        .select('*, profiles(username, profile_photo)')
        .eq('category', 'Twirl')
        .eq('media_type', 'video')
        .range(from, to)
        .order('created_at', ascending: false);
    final response = await query;
    if (response != null && response is List) {
      var posts = List<Map<String, dynamic>>.from(response);
      if (posts.isEmpty) _hasMore = false;

      // Fetch all liked twirl IDs for the current user
      Set<String> likedTwirlIds = {};
      if (user != null) {
        final likes = await SupabaseService.client
            .from('twirl_likes')
            .select('twirl_id')
            .eq('user_id', user.id);
        likedTwirlIds = likes != null ? Set<String>.from(likes.map((l) => l['twirl_id'].toString())) : {};
      }

      setState(() {
        for (var post in posts) {
          final videoUrl = post['media_url'] ?? '';
          final userPfp = post['profiles']?['profile_photo'] ?? 'assets/Oval.png';
          final username = post['profiles']?['username'] ?? 'Unknown';
          final userId = post['user_id'] ?? post['profiles']?['id'] ?? '';
          final caption = post['caption'] ?? '';
          final song = post['song'] ?? '';
          final location = post['location'] ?? '';
          final likes = post['likes'] ?? 0;
          final comments = post['comments'] ?? 0;
          final isLiked = likedTwirlIds.contains(post['id'].toString());
          final twirlPost = TwirlPost(
            id: post['id'] ?? '',
            userId: userId,
            videoPath: videoUrl,
            username: username,
            userPfp: userPfp,
            caption: caption,
            song: song,
            location: location,
            likes: likes,
            comments: comments,
            isLiked: isLiked,
          );
          _twirlPosts.add(twirlPost);
          final vController = VideoPlayerController.network(videoUrl);
          _controllers.add(vController);
          final cController = ChewieController(
            videoPlayerController: vController,
            looping: true,
            autoPlay: true,
            showControls: false,
            allowMuting: false,
            allowPlaybackSpeedChanging: false,
            allowFullScreen: false,
          );
          _chewieControllers.add(cController);
          final heartAnim = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 350),
          );
          _heartControllers.add(heartAnim);
          _heartScales.add(Tween<double>(begin: 0.0, end: 1.4).chain(CurveTween(curve: Curves.elasticOut)).animate(heartAnim));
          vController.initialize().then((_) {
            setState(() {});
          });
          _showHeart.add(false);
        }
        _isLoadingMore = false;
      });
      // Ensure auto-play after posts are loaded
      if (initial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playCurrent();
        });
      }
    }
  }

  void _togglePause(int idx) {
    final controller = _controllers[idx];
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  void _onTabChanged(int idx) {
    setState(() {
      _tabIndex = idx;
      _twirlPosts.clear();
      _controllers.clear();
      _chewieControllers.clear();
      _heartControllers.clear();
      _heartScales.clear();
      _showHeart.clear();
      _hasMore = true;
    });
    if (idx == 2) {
      _fetchFollowingIds().then((_) => _fetchTwirlPosts(initial: true));
    } else {
      _fetchTwirlPosts(initial: true);
    }
  }

  Future<void> _fetchUserLikesAndSaves() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final likes = await SupabaseService.client
        .from('twirl_likes')
        .select('twirl_id')
        .eq('user_id', user.id);
    final saves = await SupabaseService.client
        .from('twirl_saves')
        .select('twirl_id')
        .eq('user_id', user.id);
    setState(() {
      _likedTwirlIds = likes != null ? Set<String>.from(likes.map((l) => l['twirl_id'])) : {};
      _savedTwirlIds = saves != null ? Set<String>.from(saves.map((s) => s['twirl_id'])) : {};
    });
  }

  Future<void> _toggleSaveTwirl(String twirlId) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    if (_savedTwirlIds.contains(twirlId)) {
      await SupabaseService.client
          .from('saved_posts')
          .delete()
          .eq('post_id', twirlId)
          .eq('user_id', user.id);
      setState(() {
        _savedTwirlIds.remove(twirlId);
      });
    } else {
      await SupabaseService.client
          .from('saved_posts')
          .insert({'post_id': twirlId, 'user_id': user.id});
      setState(() {
        _savedTwirlIds.add(twirlId);
      });
    }
  }

  Future<void> _refreshLikeStatus() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    for (var post in _twirlPosts) {
      final likeRes = await SupabaseService.client
          .from('twirl_likes')
          .select('id')
          .eq('twirl_id', post.id)
          .eq('user_id', user.id)
          .maybeSingle();
      setState(() {
        post.isLiked = likeRes != null;
      });
    }
  }

  void _initFromProvidedTwirls(List<Map<String, dynamic>> twirls, int initialIndex) async {
    _twirlPosts.clear();
    _controllers.clear();
    _chewieControllers.clear();
    _heartControllers.clear();
    _heartScales.clear();
    _showHeart.clear();
    _comments.clear();
    for (var post in twirls) {
      final videoUrl = post['media_url'] ?? '';
      final userPfp = post['userPfp'] ?? post['profile_photo'] ?? post['profiles']?['profile_photo'] ?? 'assets/Oval.png';
      final username = post['profiles']?['username'] ?? 'Unknown';
      final userId = post['uid'] ?? post['user_id'] ?? post['profiles']?['id'] ?? '';
      // print('TwirlPost: username=$username, userPfp=$userPfp');
      final caption = post['caption'] ?? '';
      final song = post['song'] ?? '';
      final location = post['location'] ?? '';
      final likes = post['likes'] ?? 0;
      final comments = post['comments'] ?? 0;
      final twirlPost = TwirlPost(
        id: post['id'] ?? '',
        userId: userId,
        videoPath: videoUrl,
        username: username,
        userPfp: userPfp,
        caption: caption,
        song: song,
        location: location,
        likes: likes,
        comments: comments,
      );
      _twirlPosts.add(twirlPost);
      final vController = VideoPlayerController.network(videoUrl);
      _controllers.add(vController);
      final cController = ChewieController(
        videoPlayerController: vController,
        looping: true,
        autoPlay: true,
        showControls: false,
        allowMuting: false,
        allowPlaybackSpeedChanging: false,
        allowFullScreen: false,
      );
      _chewieControllers.add(cController);
      final heartAnim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      );
      _heartControllers.add(heartAnim);
      _heartScales.add(Tween<double>(begin: 0.0, end: 1.4).chain(CurveTween(curve: Curves.elasticOut)).animate(heartAnim));
      vController.initialize().then((_) {
        setState(() {});
      });
      _showHeart.add(false);
      _comments.add([]);
    }
    setState(() {
      _currentPage = initialIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController.jumpToPage(initialIndex);
      _playCurrent();
    });
    await _refreshLikeStatus();
  }

  // Add this helper for compact dialog content
  Widget compactDialogContent({required Widget child}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMore && _twirlPosts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _twirlPosts.isEmpty
                    ? const Center(
                        child: Text(
                          "No Twirls yet!\nBe the first to post.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 18),
                        ),
                      )
                    : PageView.builder(
                        scrollDirection: Axis.vertical,
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _twirlPosts.length,
                        itemBuilder: (context, idx) {
                          final post = _twirlPosts[idx];
                          final controller = _controllers[idx];
                          final chewie = _chewieControllers[idx];
                          // Track burst animation for like button
                          bool showBurst = false;
                          if (mounted && _likingTwirlIds.contains(post.id)) {
                            showBurst = true;
                          }
                          return Stack(
                            children: [
                              controller.value.isInitialized
                                ? GestureDetector(
                                    onTap: () => _togglePause(idx),
                                    onLongPress: () => _onLongPress(idx),
                                    onLongPressUp: () => _onLongPressUp(idx),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Chewie(controller: chewie),
                                        ),
                                        AnimatedOpacity(
                                          opacity: _showHeart[idx] ? 1.0 : 0.0,
                                          duration: const Duration(milliseconds: 350),
                                          child: Center(
                                            child: Icon(Icons.favorite, color: Colors.redAccent, size: MediaQuery.of(context).size.width * 0.32),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Stack(
                                    children: [
                                      FutureBuilder<Uint8List?>(
                                        future: VideoThumbnail.thumbnailData(
                                          video: post.videoPath,
                                          imageFormat: ImageFormat.PNG,
                                          maxWidth: 600,
                                          quality: 75,
                                        ),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                            return Center(child: Image.memory(snapshot.data!, fit: BoxFit.cover));
                                          } else {
                                            return const Center(child: CircularProgressIndicator());
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                              // Heart pop animation
                              if (_heartControllers[idx].isAnimating || _twirlPosts[idx].isLiked)
                                Center(
                                  child: ScaleTransition(
                                    scale: _heartScales[idx],
                                    child: Icon(Icons.favorite, color: Colors.pinkAccent.withOpacity(0.8), size: 120),
                                  ),
                                ),
                              // Overlay UI
                              Positioned(
                                top: 48,
                                left: 16,
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        final user = SupabaseService.client.auth.currentUser;
                                        if (user != null && post.userId == user.id) {
                                          // Go to ProfileScreen if it's the current user
                                          Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                          );
                                        } else {
                                          // Go to UserProfileScreen for others
                                          // Try to get user id if possible (not always available in TwirlPost)
                                          // We'll pass username, profile photo, and fallback values
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => UserProfileScreen(
                                                userData: {
                                                  'uid': post.userId,
                                                  'username': post.username,
                                                  'profile_photo': post.userPfp,
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
                                            profilePhoto: post.userPfp != null && post.userPfp.isNotEmpty ? post.userPfp : 'assets/Oval.png',
                                            name: '',
                                            username: post.username,
                                            radius: 22,
                                            fontSize: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            post.username.isNotEmpty ? post.username : 'Unknown',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Bottom left: caption and song with gradient overlay
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 100, 32),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black87],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        post.caption,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.music_note, color: Colors.white, size: 18),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Text(
                                                post.song,
                                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Bottom right: action icons
                              Positioned(
                                right: 16,
                                bottom: 48,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    GestureDetector(
                                      onTap: _likingTwirlIds.contains(post.id) ? null : () => _toggleLike(idx),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: [
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 250),
                                            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                            child: Icon(
                                              post.isLiked ? Icons.favorite : Icons.favorite_border,
                                              key: ValueKey(post.isLiked),
                                              color: post.isLiked ? Colors.pinkAccent : Colors.white,
                                              size: 36,
                                            ),
                                          ),
                                          if (showBurst)
                                            Positioned(
                                              left: -10,
                                              top: -10,
                                              right: -10,
                                              bottom: -10,
                                              child: IgnorePointer(
                                                child: LikeBurst(trigger: true, size: 56),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_twirlPosts[idx].likes}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
                                    ),
                                    const SizedBox(height: 24),
                                    GestureDetector(
                                      onTap: () => _onCommentTap(idx),
                                      child: const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 32),
                                    ),
                                    const SizedBox(height: 24),
                                    GestureDetector(
                                      onTap: () => _onShareTap(idx),
                                      child: const Icon(Icons.share, color: Colors.white, size: 32),
                                    ),
                                    const SizedBox(height: 24),
                                    GestureDetector(
                                      onTap: () => _onSaveTap(idx),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                        child: _savedTwirlIds.contains(post.id)
                                            ? const Icon(Icons.bookmark, key: ValueKey('saved'), color: Colors.white, size: 32)
                                            : const Icon(Icons.bookmark_border, key: ValueKey('unsaved'), color: Colors.white, size: 32),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Three-dot menu
                              Positioned(
                                top: 48,
                                right: 16,
                                child: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                                  onSelected: (value) async {
                                    final currentUser = SupabaseService.client.auth.currentUser;
                                    final post = _twirlPosts[idx];
                                    if (post.userId == currentUser?.id && value == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          title: const Text('Delete Twirl', style: TextStyle(color: Colors.black)),
                                          content: compactDialogContent(
                                            child: const Text('Are you sure you want to delete this twirl? This cannot be undone.', style: TextStyle(color: Colors.black54)),
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
                                        final mediaUrl = post.videoPath;
                                        // print('Full mediaUrl: $mediaUrl');
                                        if (mediaUrl.toString().contains('/storage/v1/object/public/')) {
                                          try {
                                            final uri = Uri.parse(mediaUrl);
                                            // Find the bucket name and path
                                            final publicIdx = uri.pathSegments.indexOf('public');
                                            if (publicIdx != -1 && publicIdx + 2 <= uri.pathSegments.length) {
                                              final bucket = uri.pathSegments[publicIdx + 1];
                                              final filePath = uri.pathSegments.skip(publicIdx + 2).join('/');
                                              // print('Attempting to delete from bucket: $bucket, filePath: $filePath');
                                              final res = await SupabaseService.client.storage.from(bucket).remove([filePath]);
                                              // print('Delete result: $res');
                                            }
                                          } catch (e) {
                                            // print('Failed to delete video from storage: $e');
                                          }
                                        }
                                        // Delete all related likes, comments, and saves before deleting the post
                                        final postId = post.id;
                                        await SupabaseService.client.from('twirl_likes').delete().eq('twirl_id', postId);
                                        await SupabaseService.client.from('comments').delete().eq('post_id', postId);
                                        await SupabaseService.client.from('twirl_saves').delete().eq('twirl_id', postId);
                                        // Now delete the post
                                        await SupabaseService.client.from('posts').delete().eq('id', postId);

                                        // Dispose controllers before removing from lists
                                        if (idx < _controllers.length) _controllers[idx].dispose();
                                        if (idx < _chewieControllers.length) _chewieControllers[idx].dispose();
                                        if (idx < _heartControllers.length) _heartControllers[idx].dispose();

                                        setState(() {
                                          if (idx < _twirlPosts.length) _twirlPosts.removeAt(idx);
                                          if (idx < _controllers.length) _controllers.removeAt(idx);
                                          if (idx < _chewieControllers.length) _chewieControllers.removeAt(idx);
                                          if (idx < _heartControllers.length) _heartControllers.removeAt(idx);
                                          if (idx < _heartScales.length) _heartScales.removeAt(idx);
                                          if (idx < _showHeart.length) _showHeart.removeAt(idx);
                                        });

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Twirl deleted.')),
                                        );
                                      }
                                    } else if (post.userId != currentUser?.id && value == 'report') {
                                      String? selectedReason;
                                      final reasons = ['Nudity', 'Violence', 'Spam', 'Hate Speech', 'Other'];
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setModalState) => AlertDialog(
                                            backgroundColor: Colors.white,
                                            title: const Text('Report Twirl', style: TextStyle(color: Colors.black)),
                                            content: compactDialogContent(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ...reasons.map((r) => RadioListTile<String>(
                                                    value: r,
                                                    groupValue: selectedReason,
                                                    onChanged: (v) => setModalState(() => selectedReason = v),
                                                    title: Text(r, style: const TextStyle(color: Colors.black, fontSize: 15)),
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
                                          'post_id': post.id,
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
                                    if (_twirlPosts[idx].userId == currentUser?.id) {
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
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: BottomNavTab.home),
    );
  }

  @override
  void deactivate() {
    // Pause all videos when navigating away from TwirlScreen
    for (var controller in _controllers) {
      if (controller.value.isPlaying) {
        controller.pause();
      }
    }
    super.deactivate();
  }
}
