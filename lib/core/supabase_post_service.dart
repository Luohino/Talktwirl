import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase/supabase.dart';

class SupabasePostService {
  final SupabaseClient client;
  SupabasePostService(this.client);

  Future<List<Map<String, dynamic>>> fetchPosts() async {
    final response = await client.from('posts').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addPost(Map<String, dynamic> post) async {
    await client.from('posts').insert(post);
  }

  Future<void> likePost(String postId, String userId) async {
    await client.from('likes').insert({'post_id': postId, 'user_id': userId});
  }

  Future<void> unlikePost(String postId, String userId) async {
    await client.from('likes').delete().eq('post_id', postId).eq('user_id', userId);
  }

  Future<void> commentOnPost(String postId, String userId, String comment) async {
    await client.from('comments').insert({
      'post_id': postId,
      'user_id': userId,
      'comment': comment,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchComments(String postId) async {
    final response = await client.from('comments').select().eq('post_id', postId).order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<int> getLikesCount(String postId) async {
    final response = await client
        .from('likes')
        .select('id')
        .eq('post_id', postId);
    return (response as List).length;
  }

  /// Helper to send like/comment notifications. Debounces if [debounceMs] > 0.
  static Future<void> sendNotification({
    required SupabaseClient client,
    required String type, // 'like' or 'comment'
    required String toUserId,
    required String fromUserId,
    required String targetType, // 'post' or 'twirl'
    required String targetId,
    String? targetCaption,
    String? commentText,
    int debounceMs = 0,
  }) async {
    if (toUserId == fromUserId) return; // Don't notify self
    if (debounceMs > 0) {
      await Future.delayed(Duration(milliseconds: debounceMs));
    }
    final notif = {
      'type': type,
      'to_user_id': toUserId,
      'from_user_id': fromUserId,
      'target_type': targetType,
      'target_id': targetId,
      'target_caption': targetCaption ?? '',
      'created_at': DateTime.now().toIso8601String(),
    };
    if (type == 'comment' && commentText != null) {
      notif['comment_text'] = commentText;
    }
    print('[sendNotification] Inserting notification: $notif');
    try {
      final res = await client.from('notifications').insert(notif);
      print('[sendNotification] Insert result: $res');
    } catch (e, stack) {
      print('[sendNotification] Insert error: $e');
      print(stack);
    }
  }
}
