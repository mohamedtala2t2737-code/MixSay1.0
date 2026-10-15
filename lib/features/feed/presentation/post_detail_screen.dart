import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';

/// The one-post screen the profile wall opens.
///
/// It hosts [PostCard] rather than painting its own copy of a post: the card
/// already does the carousel, the video player with its "this clip will not
/// open" tile, the likes, the comments and the report path, and a second
/// renderer would start disagreeing with the feed.
class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).postDetailTitle)),
      body: SingleChildScrollView(child: PostCard(post: post)),
    );
  }
}

Future<void> openPostDetail(BuildContext context, FeedPost post) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => PostDetailScreen(post: post),
      ),
    );
