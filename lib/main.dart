import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/app.dart';
import 'package:social_chat/core/prefs/startup_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error, stackTrace) {
    debugPrint('Unable to start Firebase: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(_StartupFailureApp(onRetry: main));
    return;
  }
  // Debug provider on purpose in debug builds: release traffic is attested by
  // Play Integrity, and enforcement stays off in the Firebase console until the
  // app is registered there.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (error, stackTrace) {
    debugPrint('App Check is unavailable: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  runApp(
    ProviderScope(
      overrides: [
        startupPreferencesProvider.overrideWithValue(
          await StartupPreferences.read(),
        ),
      ],
      child: const SocialChatApp(),
    ),
  );
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('MixSay', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 12),
                const Text(
                  'مش قادر يوصّل التطبيق بخدمة Firebase.\n'
                  'Could not reach Firebase. Check the internet connection.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('حاول تاني / Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
