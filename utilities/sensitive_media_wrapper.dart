import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SensitiveMediaWrapper extends StatefulWidget {
  final String mediaUrl;
  final bool isSensitive;
  final bool isVideo;
  final String topic;

  const SensitiveMediaWrapper({
    super.key,
    required this.mediaUrl,
    required this.isSensitive,
    required this.isVideo,
    this.topic = "Incident Scene",
  });

  @override
  State<SensitiveMediaWrapper> createState() => _SensitiveMediaWrapperState();
}

class _SensitiveMediaWrapperState extends State<SensitiveMediaWrapper> {
  bool _revealed = false;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void didUpdateWidget(covariant SensitiveMediaWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _revealed = false;
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildMedia() {
    if (widget.isVideo) {
      if (_controller == null || !_controller!.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.mediaUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) => const Icon(Icons.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSensitive) return _buildMedia();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // The Blurred Media
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _revealed ? 0 : 25,
              sigmaY: _revealed ? 0 : 25,
            ),
            child: _buildMedia(),
          ),

          // The Warning Overlay
          if (!_revealed)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 60),
                    const SizedBox(height: 20),
                    const Text("Graphic Content", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text("Contains ${widget.topic}.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _revealed = true);
                        if (widget.isVideo) _controller?.play();
                      },
                      icon: const Icon(Icons.visibility),
                      label: const Text("Reveal"),
                    )
                  ],
                ),
              ),
            ),

          // The Hide Button
          if (_revealed)
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () {
                  setState(() => _revealed = false);
                  if (widget.isVideo) _controller?.pause();
                },
                icon: const Icon(Icons.visibility_off, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            )
        ],
      ),
    );
  }
}