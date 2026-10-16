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
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_attachment_sheet.dart';
import 'package:social_chat/features/chat/chat_composer.dart';
import 'package:social_chat/features/chat/chat_forward.dart';
import 'package:social_chat/features/chat/chat_forward_sheet.dart';
import 'package:social_chat/features/chat/chat_gif_search.dart';
import 'package:social_chat/features/chat/chat_media.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_time_labels.dart';
import 'package:social_chat/features/chat/chat_tray.dart';
import 'package:social_chat/features/chat/chat_voice_recorder.dart';
import 'package:social_chat/features/chat/chat_wallpaper.dart';

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

  /// A forward is written once per chosen chat, so the picker closes the
  /// moment it is tapped and the taps in between are ignored rather than
  /// starting a second round of copies.
  bool _forwarding = false;

  /// The panel that takes the keyboard's place under the composer, and the tab
  /// it last showed. Only one of the two is ever on screen at a time.
  bool _trayOpen = false;
  ChatTrayTab _trayTab = ChatTrayTab.emoji;
  bool _otherTyping = false;
  bool _claimingTyping = false;

  /// The repository the typing flag was written with, kept from the moment it
  /// was set: leaving the chat has to clear that flag, and `dispose()` is not
  /// allowed to read a provider any more.
  ChatRepository? _typingWriter;

  /// The take being recorded now, and the one that stopped and waits to be
  /// sent. Only one of the two is ever set.
  ChatVoiceRecorder? _voice;
  String? _readyTakePath;
  int _readyTakeMs = 0;
  Timer? _voiceTick;
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
    // Tapping the field is how the keyboard comes back, so it also puts the
    // panel away — the two are never both on screen.
    _messageFocusNode.addListener(_onFieldFocusChanged);
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
    _releaseTyping();
    _voiceTick?.cancel();
    // A take left in the temporary folder is the one thing leaving the chat
    // can still throw away, and the recorder owns the microphone until it goes.
    final recorder = _voice;
    if (recorder != null) unawaited(_giveVoiceRecorderBack(recorder));
    final readyTake = _readyTakePath;
    if (readyTake != null) unawaited(_deleteVoiceFile(readyTake));
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

  /// One key per message on this screen. A paged, reversed list has no index to
  /// scroll to, so jumping back to a quoted message goes through its context.
  final Map<String, GlobalKey> _messageKeys = {};

  GlobalKey _messageKey(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  void _scrollToMessage(String messageId) {
    final context = _messageKeys[messageId]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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

  /// What the paperclip does with each row of the attach sheet. Every kind has a
  /// real sender here, so a row the plan lists is never a row that does nothing.
  Future<void> _openAttachments() async {
    if (_sending) return;
    final options = ChatAttachmentSheet.availableOptions();
    final choice = await showChatAttachmentSheet(context, options: options);
    if (!mounted || choice == null) return;
    // A picker that the platform refuses — no gallery app, a denied file
    // provider — throws rather than returning nothing, and the sender deserves
    // a line on the screen rather than a dead tap.
    try {
      switch (choice) {
        case ChatAttachmentChoice.photo:
          await _sendPhoto();
        case ChatAttachmentChoice.video:
          await _sendVideo();
        case ChatAttachmentChoice.document:
          await _sendDocument();
        case ChatAttachmentChoice.gif:
          await _sendGif();
      }
    } catch (error) {
      if (!mounted) return;
      _showAttachmentFailure(error);
    }
  }

  /// Opens the microphone and starts a take. The plugin asks for the
  /// permission itself, so a refusal comes back as a null path rather than as
  /// an exception the sender has to be told about twice.
  Future<void> _startVoiceTake() async {
    if (_sending || _voice != null) return;
    final recorder = ChatVoiceRecorder(source: ChatPluginVoiceSource());
    final String? path;
    try {
      final directory = (await getTemporaryDirectory()).path;
      path = await recorder.start(directory);
    } catch (error) {
      // A recorder the platform refuses to open throws instead of answering
      // null, so the take is given back and the sender is told in one line.
      await _giveVoiceRecorderBack(recorder);
      if (!mounted) return;
      _showAttachmentFailure(error);
      return;
    }
    if (path == null) {
      await _giveVoiceRecorderBack(recorder);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).micPermissionNeeded)),
        );
      return;
    }
    setState(() {
      _voice = recorder;
      _readyTakePath = null;
      _readyTakeMs = 0;
    });
    // One tick a second is both the clock the sender watches and the guard
    // that stops the take before the rules would refuse it.
    _voiceTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_voice?.isAtLimit ?? false) {
        unawaited(_parkVoiceTake());
        return;
      }
      if (mounted) setState(() {});
    });
  }

  /// Ends a take and leaves the file ready to send: the sender pressed stop,
  /// or the recording reached ten minutes.
  Future<void> _parkVoiceTake() async {
    final recorder = _voice;
    if (recorder == null) return;
    _voiceTick?.cancel();
    _voiceTick = null;
    _voice = null;
    final durationMs = recorder.elapsedMs;
    String? path;
    try {
      path = await recorder.stop();
    } catch (error) {
      if (!mounted) {
        await _giveVoiceRecorderBack(recorder);
        return;
      }
      await _giveVoiceRecorderBack(recorder);
      _showAttachmentFailure(error);
      return;
    }
    await _giveVoiceRecorderBack(recorder);
    if (!mounted || path == null) return;
    setState(() {
      _readyTakePath = path;
      _readyTakeMs = durationMs;
    });
  }

  /// Releases a recorder without letting a plugin failure escape into a tap
  /// that already stopped mutating the screen.
  Future<void> _giveVoiceRecorderBack(ChatVoiceRecorder recorder) async {
    try {
      await recorder.dispose();
    } catch (error) {
      debugPrint('Unable to release the microphone: $error');
    }
  }

  Future<void> _sendVoiceTake() async {
    if (_sending) return;
    if (_voice != null) await _parkVoiceTake();
    final path = _readyTakePath;
    if (path == null) return;
    final durationMs = _readyTakeMs;
    setState(() {
      _readyTakePath = null;
      _readyTakeMs = 0;
    });
    await _sendDraft(
      (clientId) => chatVoiceDraft(
        recordedPath: path,
        clientId: clientId,
        durationMs: durationMs,
      ),
    );
  }

  /// Throws the take away, which is what the sender meant by pressing cancel.
  Future<void> _discardVoiceTake() async {
    _voiceTick?.cancel();
    _voiceTick = null;
    final recorder = _voice;
    final ready = _readyTakePath;
    _voice = null;
    setState(() {
      _readyTakePath = null;
      _readyTakeMs = 0;
    });
    if (recorder != null) {
      try {
        await recorder.cancel();
      } catch (error) {
        // The sender already gave up on the take; a plugin that refuses to
        // close the mic is logged, not shown as a failed action.
        debugPrint('Unable to cancel the recording: $error');
      }
      await _giveVoiceRecorderBack(recorder);
      return;
    }
    if (ready != null) await _deleteVoiceFile(ready);
  }

  Future<void> _deleteVoiceFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      debugPrint('Unable to discard the recording: $error');
    }
  }

  Future<void> _sendPhoto({ImageSource source = ImageSource.gallery}) async {
    if (_sending) return;
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null || !mounted) return;
    await _sendDraft((clientId) => _compressedPhoto(picked, clientId));
  }

  /// The camera icon in the composer: one shot, sent exactly as a picked photo
  /// is. It is only drawn while images are on, and the CAMERA permission the
  /// manifest already declares is all it needs.
  Future<void> _sendCameraPhoto() async {
    if (_sending) return;
    try {
      await _sendPhoto(source: ImageSource.camera);
    } catch (error) {
      // A camera the platform refuses — no camera app, a denied permission —
      // throws instead of answering null, so the tap still explains itself.
      if (!mounted) return;
      _showAttachmentFailure(error);
    }
  }

  Future<void> _sendVideo() async {
    if (_sending) return;
    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await _sendDraft(
      (clientId) => chatVideoDraft(
        pickedPath: picked.path,
        pickedName: picked.name,
        clientId: clientId,
      ),
    );
  }

  /// A document is measured and copied before anything is sent: the picker can
  /// report a size without opening the file, and a ceiling refusal should never
  /// cost the user a copy they were never going to be allowed to upload.
  Future<void> _sendDocument() async {
    if (_sending) return;
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > ChatFeatures.maxFileBytes) {
      if (!mounted) return;
      _showAttachmentFailure(
        ChatAttachmentRejectedException(
          'tooLarge',
          limitBytes: ChatFeatures.maxFileBytes,
        ),
      );
      return;
    }
    // A uri the app cannot open as a file still gives up its bytes, and the copy
    // is what the offline queue finds after a restart.
    final bytes = file.path == null ? await file.readAsBytes() : null;
    if (!mounted) return;
    final directory = (await getTemporaryDirectory()).path;
    await _sendDraft(
      (clientId) => chatDocumentDraft(
        fileName: file.name,
        pickedPath: file.path,
        pickedBytes: bytes,
        directory: directory,
        clientId: clientId,
      ),
    );
  }

  /// A GIF is never uploaded: the message stores the url the search returned,
  /// which is the one thing `firestore.rules` accepts for that type.
  Future<void> _sendGif() async {
    if (_sending) return;
    final gif = await showChatGifPicker(context);
    if (gif == null || !mounted) return;
    await _sendGifUrl(gif.url);
  }

  /// The same send for a GIF already chosen, whether it came from the attach
  /// sheet or from the panel's own tab.
  Future<void> _sendGifUrl(String url) async {
    await _sendDraft(
      (clientId) => ChatAttachmentDraft(
        type: ChatMessageType.gif,
        localPath: url,
        fileName: '$clientId.gif',
        byteSize: 0,
      ),
    );
  }

  /// Sends an attachment, or parks it in the offline queue with its file copied
  /// beside the queue entry. Every kind comes through here so the retry path and
  /// the "why did this fail" wording stay the same for all of them.
  Future<void> _sendDraft(
    FutureOr<ChatAttachmentDraft> Function(String clientId) buildDraft,
  ) async {
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
    ChatAttachmentDraft? draft;
    try {
      draft = await buildDraft(clientId);
      final connected = await _hasNetworkConnection();
      final message = connected
          ? await repository.sendMedia(
              conversationId: widget.conversationId,
              draft: draft,
              clientId: clientId,
              replyTo: replyTo,
            )
          : await repository.queueMessage(
              conversationId: widget.conversationId,
              text: '',
              clientId: clientId,
              attachment: draft,
              replyTo: replyTo,
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
            replyTo: replyTo,
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
      setState(() {
        _sending = false;
        _replyingTo = replyingToSnapshot;
      });
      _showAttachmentFailure(error);
    }
  }

  void _showAttachmentFailure(Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_attachmentFailureMessage(error))));
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

  /// The panel and the keyboard are two ways of typing, so one of them always
  /// gives way: the field taking focus puts the panel away.
  void _onFieldFocusChanged() {
    if (_messageFocusNode.hasFocus && _trayOpen && mounted) {
      setState(() => _trayOpen = false);
    }
  }

  /// Opens the panel on the tab it last showed, and takes the keyboard out of
  /// its way. Tapping it again is how the panel goes back down.
  void _toggleTray() {
    setState(() {
      _trayOpen = !_trayOpen;
      if (_trayOpen) _messageFocusNode.unfocus();
    });
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
    // While the panel is up it owns the bottom of the screen, so the caret
    // keeps its place without asking the keyboard back.
    if (!_trayOpen) _messageFocusNode.requestFocus();
    _onTextChanged(_messageController.text);
  }

  /// Puts a message in the reply slot, from the menu or from a swipe.
  void _replyToMessage(ChatMessage message) {
    setState(() => _replyingTo = message);
    _messageFocusNode.requestFocus();
  }

  Future<void> _claimTyping() async {
    if (_offline) return;
    if (!_claimingTyping) {
      _claimingTyping = true;
      final repository = ref.read(chatRepositoryProvider);
      _typingWriter = repository;
      try {
        await repository.setTyping(widget.conversationId, true);
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
    _releaseTyping();
  }

  /// Puts my typing flag back to false, if this screen set it. The timer is
  /// already cancelled by the time the widget is being torn down, so this part
  /// stands on its own for `dispose()` to call.
  void _releaseTyping() {
    if (!_claimingTyping) return;
    _claimingTyping = false;
    final repository = _typingWriter;
    if (repository == null) return;
    unawaited(
      repository.setTyping(widget.conversationId, false).catchError((
        Object error,
      ) {
        debugPrint('Unable to clear the typing state: $error');
      }),
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final s = AppStrings.of(context);
    final isMine = message.senderId == FirebaseAuth.instance.currentUser?.uid;
    final canCopy = message.content.isNotEmpty;
    // The payload says what a copy of this message could carry: nothing for a
    // photo or a voice note, whose file belongs to this chat alone.
    final forwardPayload = ChatForwardPayload.from(message);
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
            if (forwardPayload != null)
              AppListTile(
                leading: const Icon(Icons.forward),
                title: s.forwardAction,
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.forward),
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
        _replyToMessage(message);
      case _MessageAction.forward:
        await _forwardMessage(message);
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

  /// A copy into each chosen chat, one write per chat. Nothing here uploads a
  /// byte — [ChatForwardPayload.from] has already said the message carries only
  /// a sticker id or a public url — so one chat's failure never undoes another:
  /// the line that says it failed only counts the copies that did not go, and
  /// going offline mid-loop parks the rest in the queue like any other send.
  Future<void> _forwardMessage(ChatMessage message) async {
    if (_forwarding) return;
    final payload = ChatForwardPayload.from(message);
    if (payload == null) return;
    final s = AppStrings.of(context);
    final targets = await ChatForwardSheet.show(
      context,
      fromConversationId: widget.conversationId,
    );
    if (!mounted || targets == null || targets.isEmpty) return;
    final repository = ref.read(chatRepositoryProvider);
    setState(() => _forwarding = true);
    var sent = 0;
    var lost = 0;
    for (final target in targets) {
      if (await _forwardInto(repository, target, payload)) {
        sent++;
      } else {
        lost++;
      }
    }
    if (!mounted) return;
    setState(() => _forwarding = false);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (sent > 0) {
      messenger.showSnackBar(SnackBar(content: Text(s.forwardDone(sent))));
    }
    if (lost > 0) {
      messenger.showSnackBar(SnackBar(content: Text(s.forwardFailed)));
    }
  }

  /// One chat's turn. A person picked by name gets a conversation opened for
  /// them at this moment rather than when they were ticked, so backing out of
  /// the picker leaves no empty thread behind. Returns false only when the copy
  /// neither reached Firestore nor the queue.
  Future<bool> _forwardInto(
    ChatRepository repository,
    ChatForwardTarget target,
    ChatForwardPayload payload,
  ) async {
    String? conversationId;
    try {
      final userId = target.userId;
      conversationId = userId == null
          ? target.conversationId!
          : await repository.getOrCreateConversation(userId);
      final clientId = repository.createClientId();
      final connected = await _hasNetworkConnection();
      await (connected
          ? repository.sendForward(
              conversationId: conversationId,
              payload: payload,
              clientId: clientId,
            )
          : repository.queueForward(
              conversationId: conversationId,
              payload: payload,
              clientId: clientId,
            ));
      return true;
    } catch (error, stackTrace) {
      debugPrint('Unable to forward a chat message: $error');
      debugPrintStack(stackTrace: stackTrace);
      final id = conversationId;
      if (id == null) return false;
      // The write itself may be what noticed the network had gone, so the copy
      // gets one turn in the queue before it is called a failure.
      try {
        await repository.queueForward(
          conversationId: id,
          payload: payload,
          clientId: repository.createClientId(),
        );
        return true;
      } catch (queueError, queueTrace) {
        debugPrint('Unable to queue a forwarded message: $queueError');
        debugPrintStack(stackTrace: queueTrace);
        return false;
      }
    }
  }

  /// The three-dot menu. Every row in it does something the moment it is
  /// tapped: one is a read-receipt write the repository already has, the other
  /// opens the same settings sheet the rest of the app uses.
  Future<void> _onMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.markRead:
        await _runMessageAction(
          () => ref
              .read(chatRepositoryProvider)
              .markMessagesRead(widget.conversationId),
        );
      case _ChatMenuAction.settings:
        await showAppSettingsSheet(context);
    }
  }

  /// Nothing rings from here yet: calls are Phase 4, and the two icons that
  /// reach this are behind the `calls` flag, so they are not even drawn until
  /// the flag is flipped on purpose.
  void _startCall({required bool video}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).callsNotReady)),
      );
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
    // A message that left the screen takes its jump key with it, so the map
    // never grows past what is actually on screen.
    final loadedIds = visible.map((message) => message.id).toSet();
    _messageKeys.removeWhere((messageId, _) => !loadedIds.contains(messageId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.chatAppBar(Theme.of(context).brightness),
        foregroundColor: Colors.white,
        titleSpacing: 0,
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
                            : Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Calls are not wired up yet, so the two icons are not drawn at all
          // while the flag is off and nobody taps something that cannot ring.
          if (ChatFeatures.calls) ...[
            IconButton(
              tooltip: s.voiceCall,
              onPressed: _sending ? null : () => _startCall(video: false),
              icon: const Icon(Icons.call),
            ),
            IconButton(
              tooltip: s.videoCall,
              onPressed: _sending ? null : () => _startCall(video: true),
              icon: const Icon(Icons.videocam),
            ),
          ],
          PopupMenuButton<_ChatMenuAction>(
            tooltip: s.chatOptions,
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ChatMenuAction.markRead,
                child: AppListTile(
                  leading: const Icon(Icons.done_all),
                  title: s.markAllRead,
                ),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.settings,
                child: AppListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: s.settings,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ChatWallpaper(
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
                      final before = index == visible.length - 1
                          ? null
                          : visible[visible.length - index - 2];
                      final showDate =
                          before == null ||
                          !chatIsSameDay(before.createdAt, message.createdAt);
                      final changedSender =
                          before == null || before.senderId != message.senderId;
                      // A quote only jumps when the message it quotes is on
                      // this screen; otherwise it stays a plain quotation. The
                      // loaded ids come from the list itself, because a reply
                      // builds before the older message it quotes does.
                      final quotedId = message.replyTo?.messageId;
                      final canJumpToQuote =
                          quotedId != null && loadedIds.contains(quotedId);
                      final forwardPayload = ChatForwardPayload.from(message);
                      // Words are easy enough to long-press, and an arrow under
                      // every sentence would turn a thread into a row of
                      // buttons. Artwork gets the arrow because it has no text
                      // to hold a menu hint.
                      final showsForwardArrow =
                          forwardPayload != null &&
                          forwardPayload.type != ChatMessageType.text;
                      return Column(
                        key: _messageKey(message.id),
                        children: [
                          if (showDate)
                            _DateChip(
                              label: chatDateLabel(s, message.createdAt),
                            ),
                          ChatMessageBubble(
                            message: message,
                            isOutgoing: message.senderId == meId,
                            currentUserId: meId ?? '',
                            otherDisplayName: displayName,
                            isGroupStart: showDate || changedSender,
                            onReplyTap: canJumpToQuote
                                ? () => _scrollToMessage(quotedId)
                                : null,
                            onLongPress: () => _showMessageActions(message),
                            onForward: showsForwardArrow
                                ? () => _forwardMessage(message)
                                : null,
                            onSwipeReply: message.deletedForEveryone
                                ? null
                                : () => _replyToMessage(message),
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
                    if (_replyingTo case final replyingTo?)
                      _ReplyDraft(
                        preview: ChatReply.quoteFrom(replyingTo),
                        currentUserId: meId ?? '',
                        otherDisplayName: displayName,
                        onCancel: () => setState(() => _replyingTo = null),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                      child: ChatComposer(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        // A panel whose every tab is switched off is not
                        // offered as a button.
                        trayAvailable: ChatTray.availableTabs().isNotEmpty,
                        // The paperclip is the only door to an attachment, and
                        // it disappears while the free plan is in force, so
                        // nobody can reach a control that would cost money.
                        attachAvailable:
                            ChatAttachmentSheet.availableOptions().isNotEmpty,
                        cameraAvailable: !ChatMessageType.image.isGated,
                        // A note costs Storage like any other upload, so the
                        // mic is drawn only when that plan line is on.
                        micAvailable: !ChatMessageType.voice.isGated,
                        trayOpen: _trayOpen,
                        busy: _sending,
                        // While a take is running or waiting to be sent the
                        // field makes way for the clock and the two controls
                        // that finish it.
                        inFlight: _voice == null && _readyTakePath == null
                            ? null
                            : _VoiceTakeBar(
                                elapsed: chatMediaDurationLabel(
                                  s,
                                  _voice?.elapsedMs ?? _readyTakeMs,
                                ),
                                isRecording: _voice != null,
                                recordingLabel: s.recordingVoice,
                                cancelLabel: s.cancel,
                                sendLabel: s.sendRecording,
                                onCancel: _discardVoiceTake,
                                onSend: _sending ? null : _sendVoiceTake,
                              ),
                        onTrayTap: _toggleTray,
                        onAttachTap: _sending ? null : _openAttachments,
                        onCameraTap: _sending ? null : _sendCameraPhoto,
                        onMicTap: _sending || _voice != null
                            ? null
                            : _startVoiceTake,
                        onSend: _sendMessage,
                        onTextChanged: _onTextChanged,
                      ),
                    ),
                    // The panel takes the keyboard's place, so it slides up
                    // under the composer instead of lying over the thread.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: _trayOpen
                          ? ChatTray(
                              initial: _trayTab,
                              onTabChanged: (tab) => _trayTab = tab,
                              onEmoji: _insertEmoji,
                              onSticker: _sendSticker,
                              onGif: (gif) => _sendGifUrl(gif.url),
                            )
                          : const SizedBox(width: double.infinity),
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
    // The same green the quoted block in a bubble uses, so the draft above the
    // keyboard and the quote inside the thread read as one thing.
    final accent = AppColors.chatQuoteAccent(theme.brightness);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(start: BorderSide(color: accent, width: 3)),
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
                    color: accent,
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

enum _MessageAction { copy, reply, forward, deleteForMe, deleteForEveryone }

/// The composer while a voice note is being taken: the running clock, a cancel
/// that throws the recording away, and a send that uploads it.
class _VoiceTakeBar extends StatelessWidget {
  const _VoiceTakeBar({
    required this.elapsed,
    required this.isRecording,
    required this.recordingLabel,
    required this.cancelLabel,
    required this.sendLabel,
    required this.onCancel,
    required this.onSend,
  });

  final String elapsed;
  final bool isRecording;
  final String recordingLabel;
  final String cancelLabel;
  final String sendLabel;
  final Future<void> Function() onCancel;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        children: [
          Icon(
            isRecording ? Icons.mic : Icons.mic_none,
            color: isRecording ? theme.colorScheme.error : null,
          ),
          const SizedBox(width: 8),
          Text(isRecording ? '$recordingLabel $elapsed' : elapsed),
          const Spacer(),
          IconButton(
            tooltip: cancelLabel,
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
          IconButton(
            tooltip: sendLabel,
            onPressed: onSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

/// What the chat app bar's three-dot menu can hand back. A row only earns its
/// place here when tapping it does something today.
enum _ChatMenuAction { markRead, settings }

/// The day a part of the thread belongs to, in a small chip in the middle of the
/// screen. It is deliberately quiet: it separates the days without competing
/// with the bubbles for attention.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.chatChip(brightness),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.chatChipText(brightness),
            ),
          ),
        ),
      ),
    );
  }
}
