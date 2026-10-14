import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/app.dart';
import 'package:social_chat/core/prefs/startup_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
