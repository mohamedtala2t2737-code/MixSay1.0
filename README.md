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

Deploy the included Firestore and Storage security rules and the composite
indexes with `firebase deploy --only firestore:rules,firestore:indexes,storage`.
Existing accounts and profile data are not migrated automatically; existing
users need Firebase Auth accounts and matching `users/{uid}` documents before
they can use chat.

### What chat does now

- Two-party conversations whose document id is derived deterministically from
  the sorted member UIDs, so a thread cannot be duplicated by racing clients.
- Only conversation members can read or write the thread and its messages.
- Messages are created as the signed-in sender, carry the seven documented
  fields, are capped at 4000 characters, and use a server timestamp.
- Delivery status moves forward only (`sent` -> `delivered` -> `read`) and only
  by the receiving side; a status can never regress.
- Only the sender can delete a message, and their queued copy is dropped from
  the local outbox at the same time.
- Per-member unread counters: a member can only lower their own counter and
  raise the other member's by one per write. Badges render Arabic-Indic digits.
- Offline outbox persisted in the app support directory with exponential retry
  backoff (2s, 4s, 8s ... with a 5-minute ceiling), duplicate-safe delivery
  through `clientId`, and pending image re-upload.
- Every Firestore read is bounded and matches the rules: 50 conversations,
  100 messages per page, 30 posts, 50 comments, 20 profiles per batch lookup.
  Listeners are cancelled when the screen goes away.
- Conversation images live under `chats/{conversationId}/{senderId}/` in
  Storage, are limited to 10 MiB and image content types, and are readable
  only by eligible conversation members.

### What is not implemented

There is no typing indicator and no reply-to-message. The Home feed, stories,
in-app notifications and user search read real Firestore documents through
`FeedRepository`, `StoryRepository` and `NotificationRepository`; follows,
reporting and blocking are not implemented.

## Security rules tests

`security-tests/` runs `firestore.rules` and `storage.rules` against the
Firebase Emulator Suite (`demo-mixsay` — no login, no real data). 76
assertions cover allowed and refused access, field and length caps, `limit`
caps, status transitions, sender-only delete, unread counters, and Storage
uploads.

```powershell
npm --prefix security-tests install
npm --prefix security-tests test
```

The command boots and shuts down the emulator itself. It needs Node.js and a
JDK, because the Firestore emulator is a Java jar. `firebase-tools` is pinned
to 13.x inside that package because 15.x refuses to run on Java 17. Passing
these tests proves the rules behave as written locally; it does not prove they
are deployed.

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
