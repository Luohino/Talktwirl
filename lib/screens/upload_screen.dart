import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/profile_provider.dart';
import '../core/supabase_client.dart';

class UploadScreen extends StatefulWidget {
  final String mediaPath;
  final String mediaType; // 'image' or 'video'
  const UploadScreen({Key? key, required this.mediaPath, required this.mediaType}) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _captionController = TextEditingController();
  String? _selectedSong;
  String _category = 'Post';
  VideoPlayerController? _videoController;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _videoController = VideoPlayerController.file(File(widget.mediaPath))
        ..initialize().then((_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _pickSong() async {
    final songs = [
      {'title': 'Chill Vibes', 'file': 'assets/songs/chill_vibes.mp3'},
      {'title': 'Upbeat Mood', 'file': 'assets/songs/upbeat_mood.mp3'},
      {'title': 'Night Drive', 'file': 'assets/songs/night_drive.mp3'},
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
              title: Text(song['title']!),
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                onPressed: () {}, // Optionally play preview
              ),
              onTap: () {
                setState(() => _selectedSong = song['title']);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  void _uploadPost() async {
    setState(() => _isUploading = true);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final posts = prefs.getStringList('user_posts') ?? [];
    final newPost = {
      'mediaType': widget.mediaType,
      'mediaPath': widget.mediaPath,
      'caption': _captionController.text,
      'songTitle': _selectedSong ?? '',
      'postedAt': DateTime.now().toIso8601String(),
      'userID': profile.username,
      'category': _category,
    };
    posts.add(jsonEncode(newPost));
    await prefs.setStringList('user_posts', posts);
    profile.incrementPostCount(_category);
    setState(() => _isUploading = false);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Upload', style: TextStyle(color: Colors.white)),
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
            else if (_videoController != null && _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
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
                DropdownButton<String>(
                  value: _category,
                  dropdownColor: const Color(0xFF261531),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'Post', child: Text('Post')),
                    DropdownMenuItem(value: 'Twirl', child: Text('Twirl')),
                  ],
                  onChanged: (val) => setState(() => _category = val ?? 'Post'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('Post Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
