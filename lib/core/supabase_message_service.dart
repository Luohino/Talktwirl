import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseMessageService {
  final SupabaseClient client;
  SupabaseMessageService(this.client);

  Stream<List<Map<String, dynamic>>> subscribeToMessages(String channelId) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('channel_id', channelId)
        .order('created_at')
        .map((event) => List<Map<String, dynamic>>.from(event));
  }

  Future<void> sendMessage(String senderId, String receiverId, String content) async {
    if (content.trim().isEmpty) throw Exception('Message content cannot be empty');
    
    await client.from('messages').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': content.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'is_read': false,
      'deleted': false,
    });
  }

  // Fix subscribeToDM: stream all messages, filter sender/receiver in Dart only
  Stream<List<Map<String, dynamic>>> subscribeToDM(String userId1, String userId2) {
    return client
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((event) => List<Map<String, dynamic>>.from(event).where((msg) =>
        (msg['sender_id'] == userId1 && msg['receiver_id'] == userId2) ||
        (msg['sender_id'] == userId2 && msg['receiver_id'] == userId1)
      ).toList());
  }

  // Add a markMessagesAsRead stub
  Future<void> markMessagesAsRead(String receiverId, String senderId) async {
    await client.from('messages')
      .update({'is_read': true})
      .eq('receiver_id', receiverId)
      .eq('sender_id', senderId)
      .eq('is_read', false);
  }

  // Add an editMessage stub
  Future<void> editMessage(String messageId, String newText) async {
    if (newText.trim().isEmpty) throw Exception('Message content cannot be empty');
    
    await client.from('messages').update({
      'message_text': newText.trim(), 
      'edited_at': DateTime.now().toIso8601String()
    }).eq('id', messageId);
  }

  // Add a softDeleteMessage stub
  Future<void> softDeleteMessage(String messageId) async {
    await client.from('messages').update({'deleted': true}).eq('id', messageId);
  }

  // Fix fetchMessageHistory to use .or() for both directions
  Future<List<Map<String, dynamic>>> fetchMessageHistory(String userId1, String userId2) async {
    final response = await client.from('messages')
      .select()
      .or('and(sender_id.eq.$userId1,receiver_id.eq.$userId2),and(sender_id.eq.$userId2,receiver_id.eq.$userId1)')
      .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }
}
