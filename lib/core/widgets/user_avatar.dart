import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 20,
  });

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      backgroundImage: url == null || url!.isEmpty
          ? null
          : CachedNetworkImageProvider(url!, errorListener: (_) {}),
      child: url == null || url!.isEmpty
          ? name.trim().isEmpty
              ? Icon(Icons.person, size: radius, color: theme.colorScheme.primary)
              : Text(
                  name.trim().characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: radius * 0.9,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                )
          : null,
    );
  }
}
