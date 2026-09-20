import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AuthorizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AuthorizedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return errorWidget ?? const Icon(Icons.person);
    }

    return FutureBuilder<String?>(
      future: FirebaseAuth.instance.currentUser?.getIdToken(),
      builder: (context, snapshot) {
        final token = snapshot.data;

        return CachedNetworkImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: fit,
          httpHeaders: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          placeholder: (context, url) =>
          placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (context, url, error) =>
          errorWidget ?? const Icon(Icons.person),
        );
      },
    );
  }
}