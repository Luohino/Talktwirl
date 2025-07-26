// Database schema helper for Talktwirl messaging
// This ensures consistent field names across the application

class DatabaseSchemaHelper {
  // Messages table field mappings
  static const Map<String, String> messageFields = {
    'id': 'id',
    'sender_id': 'sender_id',
    'receiver_id': 'receiver_id', 
    'message_text': 'message_text',  // Primary content field
    'content': 'message_text',       // Alias for compatibility
    'created_at': 'created_at',
    'timestamp': 'created_at',       // Alias for compatibility
    'is_read': 'is_read',
    'deleted': 'deleted',
    'edited_at': 'edited_at',
    'reply_to': 'reply_to',
    'reaction': 'reaction',
    'attachment_url': 'attachment_url',
  };

  // Helper to normalize message data
  static Map<String, dynamic> normalizeMessage(Map<String, dynamic> rawMessage) {
    final normalized = <String, dynamic>{};
    
    // Ensure all fields exist with proper defaults
    normalized['id'] = rawMessage['id']?.toString() ?? '';
    normalized['sender_id'] = rawMessage['sender_id']?.toString() ?? '';
    normalized['receiver_id'] = rawMessage['receiver_id']?.toString() ?? '';
    normalized['message_text'] = (rawMessage['message_text'] ?? rawMessage['content'] ?? '').toString();
    normalized['created_at'] = (rawMessage['created_at'] ?? rawMessage['timestamp'] ?? DateTime.now().toIso8601String()).toString();
    normalized['is_read'] = rawMessage['is_read'] ?? false;
    normalized['deleted'] = rawMessage['deleted'] ?? false;
    normalized['edited_at'] = rawMessage['edited_at']?.toString();
    normalized['reply_to'] = rawMessage['reply_to']?.toString();
    normalized['reaction'] = rawMessage['reaction'];
    normalized['attachment_url'] = rawMessage['attachment_url']?.toString();
    
    return normalized;
  }

  // Helper to validate message before sending
  static bool isValidMessage(String content) {
    return content.trim().isNotEmpty;
  }

  // Helper to format message for display
  static Map<String, dynamic> formatForDisplay(Map<String, dynamic> message, String currentUserId) {
    final normalized = normalizeMessage(message);
    
    return {
      'id': normalized['id'],
      'content': normalized['message_text'],
      'type': 'text',
      'isMe': normalized['sender_id'] == currentUserId,
      'timestamp': normalized['created_at'],
      'is_read': normalized['is_read'],
      'deleted': normalized['deleted'],
      'edited_at': normalized['edited_at'],
      'reply_to': normalized['reply_to'],
      'reaction': normalized['reaction'],
      'attachment_url': normalized['attachment_url'],
    };
  }
}
