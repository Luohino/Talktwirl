import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/profile_provider.dart';
import '../core/supabase_client.dart';

class PostEditScreen extends StatefulWidget {
  final String mediaPath;
  final String mediaType; // 'image' or 'video'
  final Function(Map<String, dynamic>) onPostComplete;
  const PostEditScreen({Key? key, required this.mediaPath, required this.mediaType, required this.onPostComplete}) : super(key: key);

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  final TextEditingController _captionController = TextEditingController();
  String? _selectedSong;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _checkUserSuspended();
  }

  Future<void> _checkUserSuspended() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final userDoc = await SupabaseService.client.from('profiles').select().eq('id', user.id).maybeSingle();
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

  void _pickSong() async {
    final songs = [
      'Chill Vibes',
      'Upbeat Mood', 
      'Night Drive',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final song in songs)
            ListTile(
              leading: const Icon(Icons.music_note, color: Colors.white),
              title: Text(song),
              onTap: () {
                setState(() => _selectedSong = song);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  void _post() async {
    setState(() => _isPosting = true);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final newPost = {
      'mediaType': widget.mediaType,
      'mediaPath': widget.mediaPath,
      'caption': _captionController.text,
      'songTitle': _selectedSong ?? '',
      'postedAt': DateTime.now().toIso8601String(),
      'userID': profile.username,
      'category': widget.mediaType == 'image' ? 'Post' : 'Twirl',
    };
    widget.onPostComplete(newPost);
    setState(() => _isPosting = false);
    Navigator.of(context).pop(); // Pop PostEditScreen
    Navigator.of(context).pop(); // Pop modal
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('New Post', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.mediaType == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(File(widget.mediaPath), height: 260, fit: BoxFit.cover),
              )
            else
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 64)),
              ),
            const SizedBox(height: 18),
            TextField(
              controller: _captionController,
              maxLength: 2200,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write a caption... (max 2200 chars)',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickSong,
                  icon: const Icon(Icons.music_note),
                  label: Text(_selectedSong == null ? '+ Add Song' : _selectedSong!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPosting ? null : _post,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                child: _isPosting ? const CircularProgressIndicator(color: Colors.white) : const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}