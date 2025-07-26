import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/supabase_client.dart';
import '../screens/notification_screen.dart';
import '../screens/home_screen.dart';

/// Universal avatar builder for user profile photos.
/// Handles network, asset, local file, and fallback to first letter.
Widget buildUserAvatar({
  required String profilePhoto,
  required String name,
  required String username,
  double radius = 28,
  double fontSize = 28,
}) {
  ImageProvider? imageProvider;
  if (profilePhoto.isNotEmpty) {
    if (profilePhoto.startsWith('http')) {
      imageProvider = CachedNetworkImageProvider(profilePhoto);
    } else if (profilePhoto.contains('/') && !profilePhoto.startsWith('assets/')) {
      imageProvider = FileImage(File(profilePhoto));
    } else if (profilePhoto.startsWith('assets/')) {
      imageProvider = AssetImage(profilePhoto);
    }
  }
  if (imageProvider != null) {
    return ClipOval(
      child: Image(
        image: imageProvider,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover, // Use cover for a proper avatar look
      ),
    );
  }
  // Fallback to first letter: use name if available, else username
  final letter = (name.isNotEmpty && name != "TalkTwirl User"
      ? name[0]
      : (username.isNotEmpty ? username[0] : '?')).toUpperCase();
  return CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFF7B5CF6),
    child: Text(letter, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)),
  );
}

class AppBarActions extends StatefulWidget {
  const AppBarActions({Key? key}) : super(key: key);

  @override
  State<AppBarActions> createState() => _AppBarActionsState();
}

class _AppBarActionsState extends State<AppBarActions> {
  int _unseenNotificationCount = 0;
  int _unreadMessagesCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchUnseenNotificationCount();
    _fetchUnreadMessagesCount();
  }

  Future<void> _fetchUnseenNotificationCount() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;
    final response = await SupabaseService.client
        .from('notifications')
        .select('*')
        .eq('to_user_id', userId)
        .eq('seen', false);
    setState(() {
      _unseenNotificationCount = response.length;
    });
  }

  Future<void> _fetchUnreadMessagesCount() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;
    final response = await SupabaseService.client
        .from('messages')
        .select('*')
        .eq('receiver_id', userId)
        .eq('is_read', false);
    setState(() {
      _unreadMessagesCount = response.length;
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

  void _onMessageIconTap() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;
    await SupabaseService.client
        .from('messages')
        .update({'is_read': true})
        .eq('receiver_id', userId)
        .eq('is_read', false);
    _fetchUnreadMessagesCount();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Stack(
          children: [
            IconButton(
              icon: Icon(Icons.message_outlined, color: Color(0xFFFAE6FF), size: 24),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
              onPressed: _onMessageIconTap,
            ),
            if (_unreadMessagesCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
} 