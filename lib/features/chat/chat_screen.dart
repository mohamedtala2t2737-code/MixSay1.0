import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_emoji_picker.dart';
import 'package:social_chat/features/chat/chat_media.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';
import 'package:social_chat/features/chat/chat_time_labels.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _connectivity = Connectivity();
  final _imagePicker = ImagePicker();
  final _signedMediaUrls = <String, Future<String>>{};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _hasLoadedOlder = false;
  bool _sending = false;
  bool _offline = false;
  bool _showEmojiPicker = false;
  bool _showStickerPicker = false;
  bool _otherTyping = false;
  bool _claimingTyping = false;
  ChatMessage? _replyingTo;
  Object? _messagesStreamError;
  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestMessageDocument;
  ChatConversationInfo? _conversation;
  String? _conversationError;
  List<ChatMessage> _messages = [];
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<bool>? _typingSubscription;
  Timer? _typingDebounce;

  /// How long the typing flag stays up after the last keystroke. It has to
  /// expire on its own: a chat that is simply closed would otherwise leave the
  /// other side staring at "typing…" forever.
  static const _typingLinger = Duration(seconds: 4);

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
      final connected = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (mounted) setState(() => _offline = !connected);
      if (connected) unawaited(_flushPendingMessages());
    });
    unawaited(
      _hasNetworkConnection().then((connected) {
        if (mounted) setState(() => _offline = !connected);
      }),
    );
  }

  @override
  void dispose() {
    ActiveChatState.close(widget.conversationId);
    _connectivitySubscription?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingDebounce?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    try {
      final conversation = await ref
          .read(chatRepositoryProvider)
          .getConversationInfo(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _conversationError = null;
      });
      _subscribeToTyping(conversation);
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to load conversation: ${describeFirestoreFailure(error)}',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _conversation = null;
        _conversationError = describeFirestoreFailure(error);
      });
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

    final replyingToSnapshot = _replyingTo;
    final replyTo = replyingToSnapshot == null
        ? null
        : ChatReply.quoteFrom(replyingToSnapshot);
    _messageController.clear();
    _stopClaimingTyping();
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
    final repository = ref.read(chatRepositoryProvider);
    final clientId = repository.createClientId();
    try {
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendMessage(
              conversationId: widget.conversationId,
              text: text,
              clientId: clientId,
              replyTo: replyTo,
            )
          : await repository.queueMessage(
              conversationId: widget.conversationId,
              text: text,
              clientId: clientId,
              replyTo: replyTo,
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
            replyTo: replyTo,
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
      // Nothing left Firestore: put the draft back exactly as it was typed,
      // quote included, rather than making the message be written twice.
      _messageController.text = text;
      setState(() {
        _sending = false;
        _replyingTo = replyingToSnapshot;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _sending = true);
    final repository = ref.read(chatRepositoryProvider);
    final clientId = repository.createClientId();
    ChatAttachmentDraft? draft;
    try {
      draft = await _compressedPhoto(picked, clientId);
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendMedia(
              conversationId: widget.conversationId,
              draft: draft,
              clientId: clientId,
            )
          : await repository.queueMessage(
              conversationId: widget.conversationId,
              text: '',
              clientId: clientId,
              attachment: draft,
            );
      if (!mounted) return;
      _insertOrReplaceMessage(message);
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (error) {
      final staged = draft;
      if (staged != null &&
          (_isNetworkFailure(error) || !await _hasNetworkConnection())) {
        try {
          final pending = await repository.queueMessage(
            conversationId: widget.conversationId,
            text: '',
            clientId: clientId,
            attachment: staged,
          );
          if (!mounted) return;
          _insertOrReplaceMessage(pending);
          setState(() => _sending = false);
          _scrollToBottom();
          return;
        } catch (queueError, stackTrace) {
          debugPrint('Unable to queue chat attachment: $queueError');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      debugPrint('Unable to send chat attachment: $error');
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_attachmentFailureMessage(error))),
        );
    }
  }

  /// Sends a sticker from a bundled pack: one document write, no upload, and
  /// the receiver paints the same asset from the id.
  Future<void> _sendSticker(String stickerId) async {
    if (_sending) return;
    final replyingToSnapshot = _replyingTo;
    final replyTo = replyingToSnapshot == null
        ? null
        : ChatReply.quoteFrom(replyingToSnapshot);
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
    final repository = ref.read(chatRepositoryProvider);
    final clientId = repository.createClientId();
    try {
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendSticker(
              conversationId: widget.conversationId,
              stickerId: stickerId,
              clientId: clientId,
              replyTo: replyTo,
            )
          : await repository.queueMessage(
              conversationId: widget.conversationId,
              text: '',
              clientId: clientId,
              stickerId: stickerId,
              replyTo: replyTo,
            );
      if (!mounted) return;
      _insertOrReplaceMessage(message);
      setState(() => _sending = false);
      _scrollToBottom();
    } catch (error) {
      debugPrint('Unable to send sticker: $error');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _replyingTo = replyingToSnapshot;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  /// Shrinks a picked photo to the ceiling a chat upload gets and keeps it in
  /// the app's own temporary folder, where the offline queue can copy it.
  Future<ChatAttachmentDraft> _compressedPhoto(
    XFile picked,
    String clientId,
  ) async {
    final directory = await getTemporaryDirectory();
    final compressed = await FlutterImageCompress.compressAndGetFile(
      picked.path,
      '${directory.path}/$clientId.jpg',
      minWidth: 1600,
      minHeight: 1600,
      quality: 78,
      format: CompressFormat.jpeg,
    );
    if (compressed == null) throw StateError('Image compression failed');
    final file = File(compressed.path);
    return ChatAttachmentDraft(
      type: ChatMessageType.image,
      localPath: file.path,
      fileName: '$clientId.jpg',
      byteSize: await file.length(),
    );
  }

  /// Why an attachment did not go out, in the user's language. A file over the
  /// ceiling gets the number it exceeded, because "it failed" would only make
  /// the user pick the same photo again.
  String _attachmentFailureMessage(Object error) {
    final s = AppStrings.of(context);
    if (error is ChatAttachmentRejectedException) {
      final limit = error.limitBytes;
      if (error.reason == 'tooLarge' && limit != null) {
        return s.chatAttachmentTooLarge(s.chatSizeLimit(limit));
      }
      return s.chatAttachmentUnusable;
    }
    return s.actionFailed;
  }

  void _subscribeToMessages() {
    _messageSubscription?.cancel();
    _messageSubscription = ref
        .read(chatRepositoryProvider)
        .watchRecentMessages(widget.conversationId)
        .listen(
          _handleMessageChanges,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'Unable to subscribe to chat messages: '
              '${describeFirestoreFailure(error)}',
            );
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
      _messages = ChatRepository.mergeMessages(_messages, messages);
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
      await ref
          .read(chatRepositoryProvider)
          .deleteMessage(
            conversationId: message.conversationId,
            clientId: clientId,
          );
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

  Future<String> _signedMediaUrl(String path) => _signedMediaUrls.putIfAbsent(
    path,
    () =>
        ref.read(chatRepositoryProvider).getMediaUrl(path)
        // A cached failed future would keep every rebuild of this bubble
        // broken; drop it so the next build tries again.
        .catchError((Object error) {
          _signedMediaUrls.remove(path);
          throw error;
        }),
  );

  /// Watches the other participant's typing flag. It is one document listener
  /// on the conversation, not a second listener on the whole thread.
  void _subscribeToTyping(ChatConversationInfo conversation) {
    _typingSubscription?.cancel();
    if (conversation.otherUserId.isEmpty) return;
    _typingSubscription = ref
        .read(chatRepositoryProvider)
        .watchOtherTyping(
          widget.conversationId,
          otherUserId: conversation.otherUserId,
        )
        .listen((isTyping) {
          if (!mounted) return;
          setState(() => _otherTyping = isTyping);
        });
  }

  void _onTextChanged(String value) {
    _typingDebounce?.cancel();
    if (value.trim().isEmpty) {
      _stopClaimingTyping();
      return;
    }
    _typingDebounce = Timer(const Duration(milliseconds: 400), _claimTyping);
  }

  /// Drops an emoji where the caret is, or at the end when there is no caret,
  /// and leaves the field focused so a sentence can be built one tap at a time.
  void _insertEmoji(String emoji) {
    final value = _messageController.value;
    final inserted = insertIntoMessageField(
      text: value.text,
      selection: value.selection,
      insert: emoji,
    );
    _messageController.value = value.copyWith(
      text: inserted.text,
      selection: inserted.selection,
    );
    _messageFocusNode.requestFocus();
    _onTextChanged(_messageController.text);
  }

  Future<void> _claimTyping() async {
    if (_offline) return;
    if (!_claimingTyping) {
      _claimingTyping = true;
      try {
        await ref
            .read(chatRepositoryProvider)
            .setTyping(widget.conversationId, true);
      } catch (error, stackTrace) {
        debugPrint('Unable to publish the typing state: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    if (!mounted) return;
    if (_messageController.text.trim().isEmpty) {
      _stopClaimingTyping();
      return;
    }
    // The flag has to expire by itself: a chat that is simply closed would
    // otherwise leave the other side watching "typing…" forever.
    _typingDebounce = Timer(_typingLinger, _stopClaimingTyping);
  }

  void _stopClaimingTyping() {
    _typingDebounce?.cancel();
    if (!_claimingTyping) return;
    _claimingTyping = false;
    unawaited(
      ref
          .read(chatRepositoryProvider)
          .setTyping(widget.conversationId, false)
          .catchError((Object error) {
            debugPrint('Unable to clear the typing state: $error');
          }),
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final s = AppStrings.of(context);
    final isMine = message.senderId == FirebaseAuth.instance.currentUser?.uid;
    final canCopy = message.content.isNotEmpty;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCopy)
              AppListTile(
                leading: const Icon(Icons.copy_rounded),
                title: s.copyText,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.copy),
              ),
            AppListTile(
              leading: const Icon(Icons.reply_rounded),
              title: s.replyAction,
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.reply),
            ),
            if (isMine && !message.deletedForEveryone)
              AppListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: s.deleteForEveryone,
                onTap: () =>
                    Navigator.of(sheetContext)
                        .pop(_MessageAction.deleteForEveryone),
              ),
            AppListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: s.deleteForMe,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MessageAction.deleteForMe),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.content));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.textCopied)));
      case _MessageAction.reply:
        setState(() => _replyingTo = message);
        _messageFocusNode.requestFocus();
      case _MessageAction.deleteForMe:
        await _runMessageAction(
          () => ref
              .read(chatRepositoryProvider)
              .deleteForMe(
                conversationId: widget.conversationId,
                message: message,
              ),
        );
      case _MessageAction.deleteForEveryone:
        await _runMessageAction(
          () => ref
              .read(chatRepositoryProvider)
              .deleteForEveryone(
                conversationId: widget.conversationId,
                messageId: message.id,
              ),
        );
    }
  }

  /// A hide or a tombstone is a single Firestore write, and the thread
  /// listener is what repaints the bubble, so failures only need to be said
  /// out loud; the message simply stays as it was.
  Future<void> _runMessageAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('Unable to update the chat message: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).actionFailed)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final meId = FirebaseAuth.instance.currentUser?.uid;
    final conversation = _conversation;
    final displayName = conversation == null
        ? '…'
        : (conversation.otherFullName.isEmpty
              ? conversation.otherUsername
              : conversation.otherFullName);
    final subtitle = conversation == null
        ? null
        : (_otherTyping
              ? s.typing
              : (conversation.otherProfileMissing ? s.userUnavailable : null));
    // "Delete for me" hides a message on this side only, and the thread
    // listener still delivers it, so the list drops it here rather than in the
    // database.
    final visible = _messages
        .where((message) => meId == null || !message.deletedFor.contains(meId))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: displayName,
              url: conversation?.otherAvatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _otherTyping
                            ? AppColors.brandBlue
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
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
                  debugDetail: _conversationError,
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
                          kDebugMode
                              ? '${s.loadFailed} '
                                    '(${firestoreErrorCode(_messagesStreamError!)})'
                              : s.loadFailed,
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
              if (_offline)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.offlineBanner,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
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
                    itemCount: visible.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_loadingMore && index == visible.length) {
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
                      if (index < 0 || index >= visible.length) {
                        return const SizedBox.shrink();
                      }
                      final message = visible[visible.length - index - 1];
                      final older = index == visible.length - 1
                          ? null
                          : visible[visible.length - index - 2].createdAt;
                      final showDate =
                          older == null ||
                          !chatIsSameDay(older, message.createdAt);
                      return Column(
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Chip(
                                label: Text(
                                  chatDateLabel(s, message.createdAt),
                                ),
                              ),
                            ),
                          ChatMessageBubble(
                            message: message,
                            isOutgoing: message.senderId == meId,
                            currentUserId: meId ?? '',
                            otherDisplayName: displayName,
                            onLongPress: () => _showMessageActions(message),
                            onRetry: () => _retryMessage(message),
                            onDeleteFailed: () => _deleteMessage(message),
                            imageUrl:
                                message.mediaPath == null ||
                                    message.localImagePath != null
                                ? null
                                : _signedMediaUrl(message.mediaPath!),
                            localImagePath: message.localImagePath,
                            onImageTap: () => _showImageViewer(
                              imageUrl:
                                  message.mediaPath == null ||
                                      message.localImagePath != null
                                  ? null
                                  : _signedMediaUrl(message.mediaPath!),
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
                child: Column(
                  children: [
                    if (_showEmojiPicker)
                      ChatEmojiPicker(onSelected: _insertEmoji),
                    if (_showStickerPicker)
                      ChatStickerPicker(onSelected: _sendSticker),
                    if (_replyingTo != null)
                      _ReplyDraft(
                        preview: ChatReply.quoteFrom(_replyingTo!),
                        currentUserId: meId ?? '',
                        otherDisplayName: displayName,
                        onCancel: () => setState(() => _replyingTo = null),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (ChatFeatures.emojiPicker)
                            IconButton(
                              tooltip: s.emoji,
                              onPressed: () => setState(
                                () => _showEmojiPicker = !_showEmojiPicker,
                              ),
                              icon: Icon(
                                _showEmojiPicker
                                    ? Icons.keyboard_outlined
                                    : Icons.emoji_emotions_outlined,
                              ),
                            ),
                          // A sticker type is gated by every sticker source, so
                          // this disappears when the plan has none.
                          if (!ChatMessageType.sticker.isGated)
                            IconButton(
                              tooltip: s.stickers,
                              onPressed: () => setState(() {
                                _showStickerPicker = !_showStickerPicker;
                                if (_showStickerPicker) {
                                  _showEmojiPicker = false;
                                }
                              }),
                              icon: const Icon(Icons.sticky_note_2_outlined),
                            ),
                          // Hidden completely while the free plan is in force, so
                          // nobody can reach a control that would cost money.
                          if (ChatFeatures.images)
                            IconButton(
                              tooltip: s.sendImage,
                              onPressed: _sending ? null : _sendImage,
                              icon: const Icon(Icons.image_outlined),
                            ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: ChatFeatures.maxTextLength,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: _onTextChanged,
                              onSubmitted: (_) => _sendMessage(),
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
                                        maxLength ?? ChatFeatures.maxTextLength,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
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
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton(
                              onPressed: _sending ? null : _sendMessage,
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                shape: const CircleBorder(),
                              ),
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
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reply being drafted, shown above the input until it is sent or
/// dismissed. It is the same snapshot that will travel with the message, so
/// what is previewed is exactly what the other side will read.
class _ReplyDraft extends StatelessWidget {
  const _ReplyDraft({
    required this.preview,
    required this.currentUserId,
    required this.otherDisplayName,
    required this.onCancel,
  });

  final ChatReply preview;
  final String currentUserId;
  final String otherDisplayName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final author = preview.senderId == currentUserId
        ? strings.youLabel
        : otherDisplayName;
    final text = preview.content.isNotEmpty
        ? preview.content
        : preview.type.previewLabel(strings);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: const BorderDirectional(
          start: BorderSide(color: AppColors.brandPurple, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.replyingTo(author),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.brandPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            tooltip: strings.cancel,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Put [insert] where the caret sits, replacing any selection, and report the
/// caret after it. A field nobody has tapped yet (an invalid selection) takes
/// the text at its end, the way every chat app does.
({String text, TextSelection selection}) insertIntoMessageField({
  required String text,
  required TextSelection selection,
  required String insert,
}) {
  final caret = selection.isValid
      ? selection
      : TextSelection.collapsed(offset: text.length);
  return (
    text: text.replaceRange(caret.start, caret.end, insert),
    selection: TextSelection.collapsed(offset: caret.start + insert.length),
  );
}

enum _MessageAction { copy, reply, deleteForMe, deleteForEveryone }
