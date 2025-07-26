import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:talktwirl/screens/full_media_screen.dart';
import '../core/supabase_client.dart';
import 'package:talktwirl/screens/profile_screen.dart';
import 'package:talktwirl/screens/user_profile_screen.dart';
import '../core/supabase_post_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

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

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late bool isLiked;
  late int likes;
  bool isSaved = false;
  bool _isLiking = false;
  bool _showBurst = false;

  @override
  void initState() {
    super.initState();
    isLiked = widget.post['isLiked'] == true;
    likes = widget.post['likes'] ?? 0;
    _loadLatestLikeState();
    _loadSavedState();
  }

  Future<void> _loadLatestLikeState() async {
    final user = SupabaseService.client.auth.currentUser;
    final postId = widget.post['id'].toString();
    // Fetch like count
    final postRes = await SupabaseService.client
        .from('posts')
        .select('likes')
        .eq('id', postId)
        .maybeSingle();
    // Fetch isLiked
    bool liked = false;
    if (user != null) {
      final likeRes = await SupabaseService.client
          .from('likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      liked = likeRes != null;
    }
    if (mounted) {
      setState(() {
        likes = postRes?['likes'] ?? 0;
        isLiked = liked;
      });
    }
  }

  Future<void> _loadSavedState() async {
    final user = SupabaseService.client.auth.currentUser;
    final postId = widget.post['id'].toString();
    if (user == null) return;
    final savedRes = await SupabaseService.client
        .from('saved_posts')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', user.id)
        .maybeSingle();
    if (mounted) {
      setState(() {
        isSaved = savedRes != null;
      });
    }
  }

  Future<void> _toggleSave() async {
    final user = SupabaseService.client.auth.currentUser;
    final postId = widget.post['id'].toString();
    if (user == null) return;
    setState(() {
      isSaved = !isSaved;
    });
    try {
      if (isSaved) {
        await SupabaseService.client.from('saved_posts').insert({
          'user_id': user.id,
          'post_id': postId,
        });
      } else {
        await SupabaseService.client
            .from('saved_posts')
            .delete()
            .eq('user_id', user.id)
            .eq('post_id', postId);
      }
    } catch (e) {
      setState(() {
        isSaved = !isSaved;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update saved post.')),
      );
    }
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;
    setState(() { _isLiking = true; });
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      setState(() { _isLiking = false; });
      return;
    }
    final postId = widget.post['id'].toString();
    final wasLiked = isLiked;
    final oldLikes = likes;
    final postService = SupabasePostService(SupabaseService.client);
    // Optimistic UI update
    setState(() {
      if (wasLiked) {
        likes = oldLikes - 1;
        isLiked = false;
        _showBurst = false;
      } else {
        likes = oldLikes + 1;
        isLiked = true;
        _showBurst = true;
      }
    });
    if (!wasLiked) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() { _showBurst = false; });
      });
    }
    try {
      if (wasLiked) {
        await postService.unlikePost(postId, user.id);
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes - 1})
            .eq('id', postId);
      } else {
        await postService.likePost(postId, user.id);
        await SupabaseService.client
            .from('posts')
            .update({'likes': oldLikes + 1})
            .eq('id', postId);
        // Add notification for like
        final postOwnerId = widget.post['user_id'];
        final postCaption = widget.post['caption'] ?? '';
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
      print('Failed to update like:');
      print(e);
      print(stack);
      // Revert UI if error
      setState(() {
        likes = oldLikes;
        isLiked = wasLiked;
        _showBurst = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update like. Please try again.')),
      );
      // No UI update on error
    } finally {
      setState(() { _isLiking = false; });
    }
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
    final post = widget.post;
    print('PostDetailScreen post: $post');
    final String mediaUrl = post['media_url']?.toString() ?? '';
    final String profilePhoto = post['profilePhoto']?.toString().isNotEmpty == true
        ? post['profilePhoto']
        : 'assets/Oval.png';
    final String username = post['username']?.toString().isNotEmpty == true
        ? post['username']
        : 'Unknown';
    final String name = post['name']?.toString().isNotEmpty == true
        ? post['name']
        : '';
    final String location = post['location']?.toString() ?? '';
    final String caption = post['caption']?.toString() ?? '';
    final String postId = post['id']?.toString() ?? '';
    final String userId = post['user_id']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Row (like feed)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 12, right: 12, bottom: 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    final currentUser = SupabaseService.client.auth.currentUser;
                    if (currentUser != null && userId == currentUser.id) {
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
                              'uid': userId,
                              'username': username,
                              'profile_photo': profilePhoto,
                              'name': name,
                            },
                            isCurrentUser: false,
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: profilePhoto.isNotEmpty && profilePhoto != 'assets/Oval.png'
                            ? NetworkImage(profilePhoto)
                            : const AssetImage('assets/Oval.png') as ImageProvider,
                        radius: 22,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (username.isNotEmpty && username != 'Unknown')
                            Text(
                              '@$username',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          if (name.isNotEmpty)
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          if (location.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                location,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  onSelected: (value) async {
                    final currentUser = SupabaseService.client.auth.currentUser;
                    if (post['user_id'] == currentUser?.id && value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF261531),
                          title: const Text('Delete Post', style: TextStyle(color: Colors.white)),
                          content: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: const Text('Are you sure you want to delete this post? This cannot be undone.', style: TextStyle(color: Colors.white70)),
                            ),
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
                        final mediaUrl = post['media_url'] ?? '';
                        if (mediaUrl.toString().contains('/storage/v1/object/public/')) {
                          try {
                            final uri = Uri.parse(mediaUrl);
                            final path = uri.pathSegments.skipWhile((s) => s != 'public').skip(1).join('/');
                            await SupabaseService.client.storage.from('post-images').remove([path]);
                          } catch (e) {
                            print('Failed to delete media from storage: $e');
                          }
                        }
                        // Delete from posts table
                        await SupabaseService.client.from('posts').delete().eq('id', post['id']);
                        if (mounted) Navigator.of(context).pop(); // Go back after delete
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Post deleted.')),
                        );
                      }
                    } else if (post['user_id'] != currentUser?.id && value == 'report') {
                      String? selectedReason;
                      final reasons = ['Nudity', 'Violence', 'Spam', 'Hate Speech', 'Other'];
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setModalState) => AlertDialog(
                            backgroundColor: const Color(0xFF261531),
                            title: const Text('Report Post', style: TextStyle(color: Colors.white)),
                            content: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: 220),
                              child: SingleChildScrollView(
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
                          'post_id': post['id'],
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
                    if (post['user_id'] == currentUser?.id) {
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
          // Post Image with Instagram-like aspect ratio (no blur)
          if (mediaUrl.isNotEmpty)
            Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullMediaScreen(
                        mediaPath: mediaUrl,
                        mediaType: 'image',
                      ),
                    ),
                  );
                },
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.contain,
                ),
              ),
            )
          else
            Image.asset(
              'assets/Rectangle.png',
              fit: BoxFit.contain,
            ),
          // Interaction Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _isLiking ? null : _toggleLike,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          key: ValueKey(isLiked),
                          color: isLiked ? Colors.pinkAccent : Colors.white,
                          size: 26,
                        ),
                      ),
                      if (_showBurst)
                        Positioned(
                          left: -10,
                          top: -10,
                          right: -10,
                          bottom: -10,
                          child: IgnorePointer(
                            child: LikeBurst(trigger: true, size: 40),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _onCommentTap(context, postId),
                  child: const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () {
                    final postId = post['id']?.toString() ?? widget.post['id']?.toString();
                    if (postId == null) return;
                    final url = 'https://luohino.github.io/Talktwirl/';
                    Share.share('Check out this post on TalkTwirl!\n$url');
                  },
                  child: const Icon(Icons.send, color: Colors.white, size: 24),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleSave,
                  child: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: Colors.white,
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
                  '$likes likes',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                ),
              ],
            ),
          ),
          // Caption
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              (caption.isNotEmpty ? caption : 'No caption'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ),
          // Time below caption
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              _formatTimestamp(post['postedAt'] ?? post['created_at']),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
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

  void _onCommentTap(BuildContext context, String postId) {
    final TextEditingController _commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
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
                                // Add notification for comment
                                final postOwnerId = widget.post['user_id'];
                                final postCaption = widget.post['caption'] ?? '';
                                SupabasePostService.sendNotification(
                                  client: SupabaseService.client,
                                  type: 'comment',
                                  toUserId: postOwnerId,
                                  fromUserId: userId,
                                  targetType: 'post',
                                  targetId: postId,
                                  targetCaption: postCaption,
                                  commentText: comment,
                                );
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
}
