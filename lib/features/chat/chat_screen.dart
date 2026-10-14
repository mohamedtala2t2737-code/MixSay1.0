import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _connectivity = Connectivity();
  final _imagePicker = ImagePicker();
  final _signedImageUrls = <String, Future<String>>{};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _hasLoadedOlder = false;
  bool _sending = false;
  Object? _messagesStreamError;
  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestMessageDocument;
  ChatConversationInfo? _conversation;
  List<ChatMessage> _messages = [];
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    ActiveChatState.open(widget.conversationId);
    _loadConversation();
    _loadMessages();
    _subscribeToMessages();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(_flushPendingMessages());
      }
    });
  }

  @override
  void dispose() {
    ActiveChatState.close(widget.conversationId);
    _connectivitySubscription?.cancel();
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      final conversation = await ref
          .read(chatRepositoryProvider)
          .getConversationInfo(widget.conversationId);
      if (!mounted) return;
      setState(() => _conversation = conversation);
    } catch (error, stackTrace) {
      debugPrint('Unable to load conversation: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _conversation = null);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final repository = ref.read(chatRepositoryProvider);
      final pending = await repository.getPendingMessages(
        widget.conversationId,
      );
      if (!mounted) return;
      setState(() {
        _messages = pending;
        _loading = false;
      });
      await repository.markMessagesRead(widget.conversationId);
      _scrollToBottom();
      unawaited(_flushPendingMessages());
    } catch (error, stackTrace) {
      debugPrint('Unable to load chat messages: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final beforeDocument = _oldestMessageDocument;
      if (beforeDocument == null) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }
      final older = await ref
          .read(chatRepositoryProvider)
          .getMessages(
            widget.conversationId,
            limit: 30,
            beforeDocument: beforeDocument,
          );
      if (!mounted) return;
      setState(() {
        if (older.isNotEmpty) {
          _messages = [...older, ..._messages];
          _hasLoadedOlder = true;
          _hasMore = older.length == 30;
        } else {
          _hasMore = false;
        }
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to load older chat messages: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _hasNetworkConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _isNetworkFailure(Object error) =>
      error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException ||
      (error is FirebaseException &&
          const {
            'unavailable',
            'deadline-exceeded',
            'network-request-failed',
            'service-unavailable',
          }.contains(error.code));

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    _messageController.clear();
    setState(() => _sending = true);
    final repository = ref.read(chatRepositoryProvider);
    final clientId = repository.createClientId();
    try {
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendMessage(
              conversationId: widget.conversationId,
              text: text,
              clientId: clientId,
            )
          : await repository.queueMessage(
              conversationId: widget.conversationId,
              text: text,
              clientId: clientId,
            );
      if (!mounted) return;
      _insertOrReplaceMessage(message);
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (error) {
      if (_isNetworkFailure(error) || !await _hasNetworkConnection()) {
        try {
          final pending = await repository.queueMessage(
            conversationId: widget.conversationId,
            text: text,
            clientId: clientId,
          );
          if (!mounted) return;
          _insertOrReplaceMessage(pending);
          setState(() => _sending = false);
          _scrollToBottom();
          return;
        } catch (queueError, stackTrace) {
          debugPrint('Unable to queue chat message: $queueError');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      debugPrint('Unable to send chat message: $error');
      if (!mounted) return;
      _messageController.text = text;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    setState(() => _sending = true);
    final repository = ref.read(chatRepositoryProvider);
    final clientId = repository.createClientId();
    Uint8List? compressedBytes;
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        image.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 78,
        format: CompressFormat.jpeg,
      );
      if (compressed == null || compressed.isEmpty) {
        throw StateError('Image compression failed');
      }
      compressedBytes = compressed;
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendImage(
              conversationId: widget.conversationId,
              bytes: compressed,
              clientId: clientId,
            )
          : await repository.queueImage(
              conversationId: widget.conversationId,
              bytes: compressed,
              clientId: clientId,
            );
      if (!mounted) return;
      _insertOrReplaceMessage(message);
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (error) {
      if (compressedBytes != null &&
          (_isNetworkFailure(error) || !await _hasNetworkConnection())) {
        try {
          final pending = await repository.queueImage(
            conversationId: widget.conversationId,
            bytes: compressedBytes,
            clientId: clientId,
          );
          if (!mounted) return;
          _insertOrReplaceMessage(pending);
          setState(() => _sending = false);
          _scrollToBottom();
          return;
        } catch (queueError, stackTrace) {
          debugPrint('Unable to queue chat image: $queueError');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      debugPrint('Unable to send chat image: $error');
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  void _subscribeToMessages() {
    _messageSubscription?.cancel();
    _messageSubscription = ref
        .read(chatRepositoryProvider)
        .watchRecentMessages(widget.conversationId)
        .listen(
          _handleMessageChanges,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Unable to subscribe to chat messages: $error');
            debugPrintStack(stackTrace: stackTrace);
            if (!mounted) return;
            setState(() => _messagesStreamError = error);
          },
        );
  }

  void _retryMessageSubscription() {
    setState(() {
      _messagesStreamError = null;
      _loading = true;
    });
    _loadMessages();
    _subscribeToMessages();
  }

  void _handleMessageChanges(List<ChatMessage> messages) {
    if (!mounted) return;
    if (_messagesStreamError != null) {
      setState(() => _messagesStreamError = null);
    }
    final nearNewest =
        !_scrollController.hasClients ||
        _scrollController.position.pixels <= 80;
    if (messages.isNotEmpty) {
      _loading = false;
    }
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    var hasUnreadIncomingMessage = false;
    for (final message in messages) {
      if (message.senderId != currentUserId && message.status != 'read') {
        hasUnreadIncomingMessage = true;
      }
    }
    _insertOrReplaceMessages(messages);
    if (_messages.isNotEmpty) {
      final oldestLoadedMessage = _messages.firstWhere(
        (message) => message.documentSnapshot != null,
        orElse: () => _messages.first,
      );
      _oldestMessageDocument = oldestLoadedMessage.documentSnapshot;
    }
    if (!_hasLoadedOlder && messages.isNotEmpty) {
      _hasMore = messages.length == 100;
    }
    if (hasUnreadIncomingMessage) {
      unawaited(
        ref
            .read(chatRepositoryProvider)
            .markMessagesRead(widget.conversationId),
      );
    }
    if (nearNewest) _scrollToBottom();
  }

  void _insertOrReplaceMessage(ChatMessage message) =>
      _insertOrReplaceMessages([message]);

  void _insertOrReplaceMessages(List<ChatMessage> messages) {
    if (!mounted) return;
    setState(() {
      for (final message in messages) {
        final index = _messages.indexWhere(
          (item) =>
              item.id == message.id ||
              (message.clientId != null && item.clientId == message.clientId),
        );
        if (index == -1) {
          _messages.add(message);
        } else {
          _messages[index] = message;
        }
      }
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
  }

  Future<void> _flushPendingMessages() async {
    try {
      final repository = ref.read(chatRepositoryProvider);
      final sent = await repository.flushPendingMessages();
      final pending = await repository.getPendingMessages(
        widget.conversationId,
      );
      if (!mounted) return;
      _insertOrReplaceMessages(sent);
      _insertOrReplaceMessages(pending);
    } catch (error, stackTrace) {
      debugPrint('Unable to retry queued chat messages: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _retryMessage(ChatMessage message) async {
    final clientId = message.clientId;
    if (clientId == null) return;
    final repository = ref.read(chatRepositoryProvider);
    try {
      final sent = await repository.retryPendingMessage(clientId);
      final pending = await repository.getPendingMessages(
        widget.conversationId,
      );
      if (!mounted) return;
      _insertOrReplaceMessages([...sent, ...pending]);
      if (sent.isNotEmpty) _scrollToBottom();
    } catch (error, stackTrace) {
      debugPrint('Unable to retry failed chat message: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final clientId = message.clientId;
    if (clientId == null) return;
    try {
      await ref.read(chatRepositoryProvider).deletePendingMessage(clientId);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere(
          (item) => item.clientId == clientId || item.id == message.id,
        );
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to delete failed chat message: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  Future<void> _showImageViewer({
    Future<String>? imageUrl,
    String? localImagePath,
  }) async {
    final url = imageUrl == null ? null : await imageUrl;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: localImagePath != null
                    ? Image.file(File(localImagePath))
                    : CachedNetworkImage(
                        imageUrl: url!,
                        memCacheWidth: 440,
                        placeholder: (_, _) =>
                            const CircularProgressIndicator(),
                        errorWidget: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _signedImageUrl(String path) => _signedImageUrls.putIfAbsent(
    path,
    () =>
        ref.read(chatRepositoryProvider).getImageUrl(path)
        // A cached failed future would keep every rebuild of this bubble
        // broken; drop it so the next build tries again.
        .catchError((Object error) {
          _signedImageUrls.remove(path);
          throw error;
        }),
  );

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _dateLabel(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final meId = FirebaseAuth.instance.currentUser?.uid;
    final displayName = _conversation == null
        ? '…'
        : (_conversation!.otherFullName.isEmpty
              ? _conversation!.otherUsername
              : _conversation!.otherFullName);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: displayName,
              url: _conversation?.otherAvatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Column(
          children: [
            if (_loading)
              const Expanded(child: LoadingView())
            else if (_conversation == null)
              Expanded(
                child: ErrorStateView(
                  message: s.loadFailed,
                  onRetry: _loadConversation,
                ),
              )
            else ...[
              if (_messagesStreamError != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.loadFailed,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _retryMessageSubscription,
                        child: Text(s.retry),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.vertical &&
                        notification.metrics.extentAfter <= 300 &&
                        _hasMore) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_loadingMore && index == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      if (index < 0 || index >= _messages.length) {
                        return const SizedBox.shrink();
                      }
                      final message = _messages[_messages.length - index - 1];
                      final showDate =
                          index == _messages.length - 1 ||
                          !_isSameDay(
                            _messages[_messages.length - index - 2].createdAt,
                            message.createdAt,
                          );
                      return Column(
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Chip(
                                label: Text(_dateLabel(message.createdAt)),
                              ),
                            ),
                          _MessageBubble(
                            message: message,
                            isOutgoing: message.senderId == meId,
                            onRetry: () => _retryMessage(message),
                            onDelete: () => _deleteMessage(message),
                            imageUrl:
                                message.mediaPath == null ||
                                    message.localImagePath != null
                                ? null
                                : _signedImageUrl(message.mediaPath!),
                            localImagePath: message.localImagePath,
                            onImageTap: () => _showImageViewer(
                              imageUrl:
                                  message.mediaPath == null ||
                                      message.localImagePath != null
                                  ? null
                                  : _signedImageUrl(message.mediaPath!),
                              localImagePath: message.localImagePath,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: s.sendImage,
                        onPressed: _sending ? null : _sendImage,
                        icon: const Icon(Icons.image_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 4000,
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) => currentLength >= 3900
                              ? Text(
                                  s.messageCharacterCount(
                                    currentLength,
                                    maxLength ?? 4000,
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                )
                              : null,
                          decoration: InputDecoration(
                            hintText: s.typeMessage,
                            filled: true,
                            fillColor: AppColors.fieldFill(
                              Theme.of(context).brightness,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: IconButton(
                          onPressed: _sending ? null : _sendMessage,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isOutgoing,
    required this.onRetry,
    required this.onDelete,
    this.imageUrl,
    this.localImagePath,
    this.onImageTap,
  });

  final ChatMessage message;
  final bool isOutgoing;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final Future<String>? imageUrl;
  final String? localImagePath;
  final VoidCallback? onImageTap;

  String _timeLabel(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isOutgoing
        ? AppColors.brandPurple
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isOutgoing ? Colors.white : theme.colorScheme.onSurface;
    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Align(
      alignment: isOutgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadiusDirectional.only(
                  topStart: const Radius.circular(16),
                  topEnd: const Radius.circular(16),
                  bottomStart: Radius.circular(isOutgoing ? 16 : 4),
                  bottomEnd: Radius.circular(isOutgoing ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (localImagePath != null)
                    GestureDetector(
                      onTap: onImageTap,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(localImagePath!),
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 220,
                            height: 160,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    )
                  else if (imageUrl != null)
                    FutureBuilder<String>(
                      future: imageUrl,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Icon(Icons.broken_image_outlined);
                        }
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            width: 180,
                            height: 140,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return GestureDetector(
                          onTap: onImageTap,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: snapshot.data!,
                              width: 220,
                              fit: BoxFit.cover,
                              memCacheWidth: 440,
                              placeholder: (_, _) => const SizedBox(
                                width: 220,
                                height: 160,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (_, _, _) => const SizedBox(
                                width: 220,
                                height: 160,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  if (message.content.isNotEmpty)
                    Padding(
                      padding: imageUrl == null && localImagePath == null
                          ? EdgeInsets.zero
                          : const EdgeInsets.only(top: 6),
                      child: Text(
                        message.content,
                        textDirection:
                            RegExp(r'[\u0590-\u08FF]').hasMatch(message.content)
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: isOutgoing ? 0 : 8,
                end: isOutgoing ? 8 : 0,
                bottom: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel(message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    Icon(
                      switch (message.status) {
                        'queued' || 'sending' => Icons.access_time,
                        'delivered' || 'read' => Icons.done_all,
                        _ => Icons.check,
                      },
                      size: 15,
                      color: message.status == 'read'
                          ? AppColors.brandBlue
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
            if (isOutgoing && message.status == 'failed')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(AppStrings.of(context).retrySend),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(AppStrings.of(context).deleteMessage),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
