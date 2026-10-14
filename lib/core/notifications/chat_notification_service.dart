import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/features/chat/chat_repository.dart';

@pragma('vm:entry-point')
Future<void> chatFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
  } catch (error, stackTrace) {
    debugPrint(
      'Unable to initialize Firebase for a background message: $error',
    );
    debugPrintStack(stackTrace: stackTrace);
  }
}

class ChatNotificationService {
  ChatNotificationService._();

  static final instance = ChatNotificationService._();

  static const _chatChannel = AndroidNotificationChannel(
    'chat_messages',
    'Chat messages',
    description: 'Notifications for new chat messages',
    importance: Importance.max,
  );
  static const _postChannel = AndroidNotificationChannel(
    'post_interactions',
    'Post activity',
    description: 'Notifications for likes and comments on your posts',
    importance: Importance.high,
  );
  static const _chatDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'chat_messages',
      'Chat messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
  static const _postDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'post_interactions',
      'Post activity',
      channelDescription: 'Notifications for likes and comments on your posts',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  static const _pendingConversationKey = 'pending_notification_conversation';

  /// A delivery sweep reads every conversation of the user, so bursts of pushes
  /// are coalesced into one sweep per this window instead of one per push.
  static const _deliveredSweepCooldown = Duration(seconds: 20);

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _registeredUserId;
  String? _registeredTokenDocumentId;
  String? _pendingConversationId;
  Future<void> Function(String conversationId)? _onOpenConversation;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  DateTime? _lastDeliveredSweep;
  bool _deliveredSweepRunning = false;
  bool _deliveredSweepRequestedAgain = false;
  Timer? _deliveredSweepTimer;

  Future<void> initialize({
    required Future<void> Function(String conversationId) onOpenConversation,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _onOpenConversation = onOpenConversation;
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_openPendingConversation()),
    );

    try {
      FirebaseMessaging.onBackgroundMessage(
        chatFirebaseMessagingBackgroundHandler,
      );
    } catch (error, stackTrace) {
      _logFailure('register the background message handler', error, stackTrace);
    }

    try {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final conversationId = response.payload;
          if (conversationId != null && conversationId.isNotEmpty) {
            unawaited(_openConversation(conversationId));
          }
        },
      );
    } catch (error, stackTrace) {
      _logFailure('initialize local notifications', error, stackTrace);
    }
    try {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final channel in [_chatChannel, _postChannel]) {
        await android?.createNotificationChannel(channel);
      }
    } catch (error, stackTrace) {
      _logFailure('create the notification channels', error, stackTrace);
    }

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_showForegroundMessage(message)),
      onError: (Object error, StackTrace stackTrace) =>
          _logFailure('receive a foreground message', error, stackTrace),
    );
    _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleRemoteOpen,
      onError: (Object error, StackTrace stackTrace) =>
          _logFailure('receive a notification tap', error, stackTrace),
    );
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        unawaited(_registerCurrentDevice(user));
        if (user != null) {
          unawaited(_openPendingConversation());
          unawaited(_markReceivedMessagesDelivered());
          unawaited(ChatRepository().flushPendingMessages());
        }
      },
      onError: (Object error, StackTrace stackTrace) =>
          _logFailure('observe authentication changes', error, stackTrace),
    );
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (_) =>
          unawaited(_registerCurrentDevice(FirebaseAuth.instance.currentUser)),
      onError: (Object error, StackTrace stackTrace) =>
          _logFailure('observe notification token changes', error, stackTrace),
    );
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (FirebaseAuth.instance.currentUser != null &&
            results.any((result) => result != ConnectivityResult.none)) {
          unawaited(ChatRepository().flushPendingMessages());
        }
      },
      onError: (Object error, StackTrace stackTrace) =>
          _logFailure('observe network connectivity', error, stackTrace),
    );

    try {
      await _messaging.requestPermission();
    } catch (error, stackTrace) {
      _logFailure('request notification permission', error, stackTrace);
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      _pendingConversationId ??= preferences.getString(_pendingConversationKey);
    } catch (error, stackTrace) {
      _logFailure(
        'restore a pending notification conversation',
        error,
        stackTrace,
      );
    }
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) _handleRemoteOpen(initialMessage);
    } catch (error, stackTrace) {
      _logFailure('read the initial notification', error, stackTrace);
    }
    try {
      await _registerCurrentDevice(FirebaseAuth.instance.currentUser);
    } catch (error, stackTrace) {
      _logFailure('register this device for notifications', error, stackTrace);
    }
    try {
      await _markReceivedMessagesDelivered();
    } catch (error, stackTrace) {
      _logFailure('mark received messages as delivered', error, stackTrace);
    }
    unawaited(_openPendingConversation());
  }

  Future<void> dispose() async {
    _initialized = false;
    _onOpenConversation = null;
    _pendingConversationId = null;
    _deliveredSweepTimer?.cancel();
    _deliveredSweepTimer = null;
    _deliveredSweepRunning = false;
    _deliveredSweepRequestedAgain = false;
    _lastDeliveredSweep = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await Future.wait([
      _foregroundMessageSubscription?.cancel() ?? Future<void>.value(),
      _openedMessageSubscription?.cancel() ?? Future<void>.value(),
      _authSubscription?.cancel() ?? Future<void>.value(),
      _tokenRefreshSubscription?.cancel() ?? Future<void>.value(),
      _connectivitySubscription?.cancel() ?? Future<void>.value(),
    ]);
    _foregroundMessageSubscription = null;
    _openedMessageSubscription = null;
    _authSubscription = null;
    _tokenRefreshSubscription = null;
    _connectivitySubscription = null;
  }

  /// Removes this device's token before signing out: the Firestore rules only
  /// let an authenticated owner delete their own token document, so waiting for
  /// the auth-state listener would arrive too late.
  Future<void> unregisterForPush() => _unregisterDevice();

  static String _tokenDocumentId(String token) =>
      base64Url.encode(utf8.encode(token)).replaceAll('=', '');

  Future<void> _registerCurrentDevice(User? user) async {
    if (user == null) {
      await _unregisterDevice();
      return;
    }
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      final documentId = _tokenDocumentId(token);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('deviceTokens')
          .doc(documentId)
          .set({
            'token': token,
            'platform': 'android',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      final previousUserId = _registeredUserId;
      final previousDocumentId = _registeredTokenDocumentId;
      _registeredUserId = user.uid;
      _registeredTokenDocumentId = documentId;
      // A refreshed token or another account on this device would otherwise
      // leave a live registration behind, and Cloud Functions would keep
      // pushing this device to the old inbox.
      if (previousUserId != null &&
          previousDocumentId != null &&
          (previousUserId != user.uid || previousDocumentId != documentId)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(previousUserId)
            .collection('deviceTokens')
            .doc(previousDocumentId)
            .delete();
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to register this device for notifications: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _unregisterDevice() async {
    final userId = _registeredUserId ?? FirebaseAuth.instance.currentUser?.uid;
    var documentId = _registeredTokenDocumentId;
    _registeredUserId = null;
    _registeredTokenDocumentId = null;
    if (userId == null) return;
    try {
      // A session that never registered (offline start, failed token) still has
      // a document from the previous session to remove.
      documentId ??= _tokenDocumentId(await _messaging.getToken() ?? '');
      if (documentId.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('deviceTokens')
          .doc(documentId)
          .delete();
    } catch (error, stackTrace) {
      debugPrint('Unable to unregister this device: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    unawaited(_markReceivedMessagesDelivered());
    final conversationId = message.data['conversation_id']?.toString();
    final isChat = conversationId != null && conversationId.isNotEmpty;
    if (isChat) {
      final messageId = message.data['message_id']?.toString();
      if (messageId != null && messageId.isNotEmpty) {
        unawaited(_markMessageDelivered(conversationId, messageId));
      }
      if (conversationId == ActiveChatState.conversationId) return;
    }

    final notification = message.notification;
    try {
      await _localNotifications.show(
        id: message.messageId.hashCode,
        title: notification?.title ?? 'MixSay',
        body: notification?.body ?? '',
        notificationDetails: isChat ? _chatDetails : _postDetails,
        payload: isChat ? conversationId : null,
      );
    } catch (error, stackTrace) {
      _logFailure('show a foreground notification', error, stackTrace);
    }
  }

  void _handleRemoteOpen(RemoteMessage message) {
    final conversationId = message.data['conversation_id']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      final messageId = message.data['message_id']?.toString();
      if (messageId != null && messageId.isNotEmpty) {
        unawaited(_markMessageDelivered(conversationId, messageId));
      }
      unawaited(_openConversation(conversationId));
    }
  }

  Future<void> _openConversation(String conversationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) {
      await _savePendingConversation(conversationId);
      return;
    }
    try {
      await _onOpenConversation?.call(conversationId);
    } catch (error, stackTrace) {
      _logFailure('open a notification conversation', error, stackTrace);
      await _savePendingConversation(conversationId);
      return;
    }
    if (_pendingConversationId == conversationId) {
      _pendingConversationId = null;
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_pendingConversationKey);
      } catch (error, stackTrace) {
        _logFailure(
          'clear a pending notification conversation',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<void> _savePendingConversation(String conversationId) async {
    _pendingConversationId = conversationId;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingConversationKey, conversationId);
    } catch (error, stackTrace) {
      _logFailure(
        'save a pending notification conversation',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _openPendingConversation() async {
    final conversationId = _pendingConversationId;
    if (conversationId == null || conversationId.isEmpty) return;
    try {
      await _openConversation(conversationId);
    } catch (error, stackTrace) {
      _logFailure(
        'open a pending notification conversation',
        error,
        stackTrace,
      );
    }
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Unable to $operation: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  Future<void> _markMessageDelivered(
    String conversationId,
    String messageId,
  ) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      final reference = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final message = await transaction.get(reference);
        if (!message.exists ||
            message.data()?['senderId'] == userId ||
            message.data()?['status'] != 'sent') {
          return;
        }
        transaction.update(reference, {'status': 'delivered'});
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to update message delivery status: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _markReceivedMessagesDelivered() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_deliveredSweepRunning) {
      _deliveredSweepRequestedAgain = true;
      return;
    }
    final lastSweep = _lastDeliveredSweep;
    if (lastSweep != null) {
      final remaining =
          _deliveredSweepCooldown - DateTime.now().difference(lastSweep);
      if (remaining > Duration.zero) {
        _deliveredSweepTimer?.cancel();
        _deliveredSweepTimer = Timer(
          remaining,
          () => unawaited(_markReceivedMessagesDelivered()),
        );
        return;
      }
    }
    _deliveredSweepRunning = true;
    try {
      await ChatRepository().markReceivedMessagesDelivered();
      _lastDeliveredSweep = DateTime.now();
    } catch (error, stackTrace) {
      debugPrint('Unable to update received message statuses: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _deliveredSweepRunning = false;
      if (_deliveredSweepRequestedAgain) {
        _deliveredSweepRequestedAgain = false;
        unawaited(_markReceivedMessagesDelivered());
      }
    }
  }
}
