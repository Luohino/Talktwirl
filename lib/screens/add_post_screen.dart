import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/supabase_client.dart';
import '../core/supabase_post_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class AddPostScreen extends StatefulWidget {
  final String? mediaPath;
  final String mediaType; // 'image'
  const AddPostScreen({Key? key, this.mediaPath, this.mediaType = 'image'}) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final TextEditingController _captionController = TextEditingController();
  bool _isUploading = false;
  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();
    if (widget.mediaPath != null && widget.mediaPath!.isNotEmpty) {
      _selectedImagePath = widget.mediaPath;
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImagePath = picked.path;
      });
    }
  }

  Future<void> _uploadAndCreatePost() async {
    if (_selectedImagePath == null || _selectedImagePath!.isEmpty || _captionController.text.trim().isEmpty) return;
    setState(() { _isUploading = true; });
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      setState(() { _isUploading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated!')),
      );
      return;
    }
    try {
      final fileName = p.basename(_selectedImagePath!);
      final uniqueFileName = '${const Uuid().v4()}_$fileName';
      final fileBytes = await File(_selectedImagePath!).readAsBytes();
      // Upload to Supabase Storage
      final storageResponse = await SupabaseService.client.storage
          .from('post-images')
          .uploadBinary(uniqueFileName, fileBytes);
      final publicUrl = SupabaseService.client.storage.from('post-images').getPublicUrl(uniqueFileName);
      // Save to posts table
      await SupabasePostService(SupabaseService.client).addPost({
        'user_id': user.id,
        'media_url': publicUrl,
        'media_type': 'image',
        'caption': _captionController.text.trim(),
        'category': 'Post',
      });
      setState(() { _isUploading = false; });
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      setState(() { _isUploading = false; });
      print('Upload/Create post error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: _isUploading
                ? null
                : () async {
                    if (_captionController.text.trim().isEmpty || _selectedImagePath == null || _selectedImagePath!.isEmpty) return;
                    await _uploadAndCreatePost();
                  },
            child: const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _selectedImagePath == null
                  ? GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 220,
                        width: 220,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.add_a_photo, color: Colors.white54, size: 64),
                      ),
                    )
                  : Image.file(
                      File(_selectedImagePath!),
                      height: 220,
                      fit: BoxFit.contain,
                    ),
            ),
            const SizedBox(height: 20),
            TextField(
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
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
