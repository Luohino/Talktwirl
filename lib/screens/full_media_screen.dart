import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FullMediaScreen extends StatefulWidget {
  final String mediaPath;
  final String mediaType;
  final String? songTitle;
  const FullMediaScreen({Key? key, required this.mediaPath, required this.mediaType, this.songTitle}) : super(key: key);

  @override
  State<FullMediaScreen> createState() => _FullMediaScreenState();
}

class _FullMediaScreenState extends State<FullMediaScreen> {
  VideoPlayerController? _videoController;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Stack(
          children: [
            if (widget.mediaType == 'image')
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: widget.mediaPath.startsWith('http')
                  ? Image.network(widget.mediaPath, fit: BoxFit.contain, width: double.infinity, height: double.infinity)
                  : Image.file(File(widget.mediaPath), fit: BoxFit.contain, width: double.infinity, height: double.infinity),
              )
            else if (_videoController != null && _videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            if (widget.songTitle != null && widget.songTitle!.isNotEmpty)
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(widget.songTitle!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
