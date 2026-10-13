# MixSay

Flutter chat UI backed by Firebase Authentication, Cloud Firestore, Firebase
Storage, and Firebase Cloud Messaging.

## Firebase chat

New accounts use Firebase Authentication. After email verification, users can
sign in with their email address and search for other users by username to start
a chat. Their private data (including birth dates) is stored in owner-readable-only
`users/{uid}` documents. Searchable profile previews are stored separately in
`publicProfiles/{uid}` documents with `username`, `usernameLowercase`,
`fullName`, and optional `avatarUrl` fields. Conversations and messages are
stored in `conversations/{conversationId}` and its `messages` subcollection.
Conversation images use Firebase Storage.

Deploy the included Firestore and Storage security rules with
`firebase deploy --only firestore:rules,storage`. Existing accounts and profile
data are not migrated automatically; existing users need Firebase Auth
accounts and matching `users/{uid}` documents before they can use chat.
The current app supports sign-in, account creation, user lookup for starting
conversations, and chat. The Home route includes a dark, localized feed UI
preview with sample stories and posts; feed content, post publishing, follows,
notifications, and full profiles are not yet backed by Firebase.
Feed preview interactions use Riverpod state and reset when the app process
restarts. The Home layout is constrained on wide screens and mirrors navigation
automatically for Arabic RTL.

## App Check and Android releases

App Check uses the debug provider for development builds and Play Integrity for
Android releases (App Attest for Apple releases). Register each development
debug token in Firebase Console before enabling App Check enforcement for the
Firebase services. Verify a production-signed build before enforcing Play
Integrity so test and sideloaded builds are not unexpectedly blocked.

New chat images store their Firebase Storage object path in the existing
message `mediaUrl` field; older messages containing download URLs remain
readable. The client resolves object paths to download URLs only when displaying
images.

Android release builds enable R8 and resource shrinking. To sign them, create
`android/key.properties` locally (it is git-ignored) with `storeFile`,
`storePassword`, `keyAlias`, and `keyPassword`, then place the referenced
keystore on the local machine. Without this private release keystore, release
APKs are unsigned and cannot be installed as production builds. Build ABI-
specific APKs with `flutter build apk --split-per-abi --release`.

## Android push notifications

The Android application ID is `com.ms.socialchat`. The matching Firebase file
belongs at `android/app/google-services.json`.

The app stores each signed-in device's FCM token in the owner's
`users/{uid}/deviceTokens` subcollection and handles foreground messages and
notification taps. `functions/src/index.ts` contains the trusted Cloud
Function that sends a notification after a chat message is created. It uses
the Firebase Admin SDK and the function's service identity; no server
credentials are embedded in the client.

Deploy the function with Node.js 22 and the Firebase CLI:

```powershell
Push-Location functions
npm ci
Pop-Location
firebase deploy --only functions:sendChatMessageNotification --project ms-chat-b9635
```

Cloud Functions deployment may require the Firebase project to use the Blaze
plan and the Cloud Messaging API to be enabled. Configure APNs in Firebase
before enabling iOS push delivery.
