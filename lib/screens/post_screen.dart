import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:video_player/video_player.dart';
import '../core/supabase_client.dart';
import '../core/supabase_post_service.dart';
import 'package:uuid/uuid.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({Key? key}) : super(key: key);

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  File? _selectedImage;
  File? _selectedVideo;
  VideoPlayerController? _videoController;
  final TextEditingController _captionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _captionFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _captionFocusNode.addListener(() {
      if (_captionFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _captionFocusNode.dispose();
    _scrollController.dispose();
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  void _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedVideo = File(picked.path);
        _videoController = VideoPlayerController.file(_selectedVideo!)
          ..initialize().then((_) {
            setState(() {});
          });
      });
    }
  }

  Future<void> _uploadAndCreatePost() async {
    if (_selectedVideo == null || _captionController.text.trim().isEmpty) return;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    final fileName = basename(_selectedVideo!.path);
    final uniqueFileName = '${const Uuid().v4()}_$fileName';
    final fileBytes = await _selectedVideo!.readAsBytes();
    // Upload to Supabase Storage
    final storageResponse = await SupabaseService.client.storage
        .from('twirls')
        .uploadBinary(uniqueFileName, fileBytes);
    final publicUrl = SupabaseService.client.storage.from('twirls').getPublicUrl(uniqueFileName);
    // Save to posts table
    await SupabasePostService(SupabaseService.client).addPost({
      'user_id': user.id,
      'media_url': publicUrl,
      'media_type': 'video',
      'caption': _captionController.text.trim(),
      'category': 'Twirl',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: () async {
              if (_captionController.text.trim().isEmpty || _selectedVideo == null) return;
              await _uploadAndCreatePost();
              Navigator.pop(context);
            },
            child: const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: _selectedVideo == null
                    ? GestureDetector(
                        onTap: _pickVideo,
                        child: Container(
                          width: 350 * 9 / 16,
                          height: 350,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.video_library, color: Colors.white54, size: 48),
                        ),
                      )
                    : _videoController != null && _videoController!.value.isInitialized
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_videoController!.value.isPlaying) {
                                  _videoController!.pause();
                                } else {
                                  _videoController!.play();
                                }
                              });
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 350 * 9 / 16,
                                height: 350,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _videoController!.value.size.width,
                                    height: _videoController!.value.size.height,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const CircularProgressIndicator(),
              ),
              const SizedBox(height: 20),
              TextField(
                focusNode: _captionFocusNode,
                controller: _captionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Write a caption...',
                  labelStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white10,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 