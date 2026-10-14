# MixSay — Project Context

> وثيقة مرجعية للمطورين ومراجعي الكود. تصف هذه الصفحة ما هو موجود في ملفات
> المشروع، وتفصل بين الكود الفعلي والإعدادات أو الوظائف التي ما زالت تحتاج إلى
> توصيل أو نشر. لا تحتوي على كلمات مرور أو مفاتيح توقيع أو مفاتيح خادم.

## 1. نظرة عامة

### اسم المشروع والغرض

- **اسم التطبيق:** MixSay
- **اسم حزمة Flutter:** `social_chat`
- **إصدار المصدر الحالي:** `1.0.0+1` من `pubspec.yaml`
- **معرّف Android:** `com.ms.socialchat`
- **الغرض المعلن:** تطبيق اجتماعي ومراسلة Flutter، بتسجيل دخول بالبريد الإلكتروني
  وميزات دردشة مباشرة مبنية على Firebase.
- **حالة مهمة:** نقطة التشغيل في `lib/main.dart` تهيئ Firebase وApp Check،
  ثم تعرض `SocialChatApp` المتصل بمسارات المصادقة والدردشة. يبدأ المستخدم
  غير المسجل من شاشة الدخول، ويمكنه الانتقال إلى إنشاء الحساب. بعد تأكيد
  البريد ينتقل المستخدم إلى معاينة Home في `/home`. توجد في `main.dart` أيضًا
  شيفرة واجهة منزلية تجريبية قديمة غير موصولة بنقطة التشغيل.

### الميزات الموجودة في المصدر

**مصدر Firebase:**

- إنشاء حساب Firebase Authentication بالبريد وكلمة المرور.
- تأكيد البريد الإلكتروني وإعادة إرسال رسالة التأكيد وتحديث حالة التأكيد.
- اسم مستخدم من 4 إلى 24 محرفًا: `a-z` و`0-9` والنقطة فقط، مع تحويله إلى
  أحرف صغيرة.
- فحص توافر الاسم بقراءة وثيقة Firestore، ثم حجزه داخل معاملة ذرية أثناء
  إنشاء الملف الشخصي.
- تسجيل الدخول والخروج وفرض تأكيد البريد على المسارات المحمية.
- قائمة محادثات ورسائل مباشرة، مع صفحات للرسائل القديمة والرسائل الحديثة.
- إرسال نصوص وصور في المحادثات، مع ضغط الصور وتخزينها في Firebase Storage.
- قائمة محلية للرسائل التي تعذر إرسالها، ومحاولات لإعادة إرسالها بعد عودة
  الاتصال.
- استقبال إشعارات FCM، وطلب الإذن، وتسجيل رمز الجهاز في Firestore، وفتح
  المحادثة عند الضغط على الإشعار.
- اتجاه عربي RTL، ترجمة عربية/إنجليزية، سمة فاتحة/داكنة، وحالة زمنية للرسائل.

**واجهات اجتماعية تجريبية:**

- شاشة Home داكنة تدعم العربية RTL والإنجليزية LTR، مع قصص ومنشورات معاينة.
- البحث يفلتر المنشورات المحلية؛ القصص، إنشاء المنشورات، المشاركة، الإشعارات،
  والملف الشخصي ليست متصلة بخلفية اجتماعية.
- الإعجابات والتعليقات والحفظ في المعاينة يديرها Riverpod في الذاكرة ولا تُكتب
  إلى قاعدة بيانات.
- لا يوجد في الكود الحالي نظام منشورات أو قصص أو متابعة أو تعليقات متصل
  بـFirebase.

### التقنيات والحزم

الإصدارات أدناه هي قيود الإصدارات المعلنة في `pubspec.yaml`؛ النسخ المحلولة
فعليًا موثقة في `pubspec.lock`.

| الحزمة | الاستخدام |
|---|---|
| Flutter / Dart `^3.13.5` | إطار التطبيق ولغة البرمجة |
| `flutter_riverpod ^3.4.3` | إدارة الحالة وحقن المستودعات ومراقبة المزودات |
| `go_router ^18.0.2` | التوجيه والحماية المعتمدة على حالة Firebase Auth |
| `firebase_core ^4.15.0` | تهيئة Firebase |
| `firebase_auth ^6.4.0` | إنشاء الحساب وتسجيل الدخول وتأكيد البريد |
| `cloud_firestore ^6.4.0` | المستخدمون والأسماء والملفات والمحادثات والرسائل |
| `firebase_storage ^13.3.0` | صور المحادثات |
| `firebase_messaging ^16.7.0` | استقبال FCM وإدارة رموز الأجهزة |
| `firebase_app_check ^0.4.8` | موفر App Check للتطوير والإنتاج |
| `flutter_local_notifications ^22.3.1` | عرض إشعار محلي عند وصول FCM والتطبيق مفتوح |
| `connectivity_plus ^6.1.4` | رصد تغيّر اتصال الشبكة |
| `shared_preferences ^2.5.6` | تفضيلات بسيطة، ومنها وجهة إشعار معلقة |
| `path_provider ^2.1.5` | تخزين صور الرسائل المعلقة محليًا |
| `image_picker ^1.2.4` | اختيار صور المحادثة |
| `flutter_image_compress ^2.5.1` | ضغط صور المحادثة |
| `cached_network_image ^4.0.4` | عرض الصور الشبكية مع تخزين مؤقت |
| `http ^1.6.0` | عميل HTTP مستخدم ببعض المسارات |
| `flutter_localizations` | أدوات الترجمة المحلية في Flutter |
| `cupertino_icons ^1.0.8` | أيقونات Cupertino |
| `flutter_test` | اختبارات Flutter |
| `flutter_lints ^6.0.0` | قواعد التحليل الساكن |

لا يعلن التطبيق اعتماد `supabase_flutter`. ملفات Supabase و`.env.example`
القديمة أزيلت لتفادي الخلط؛ شاشات Flutter تعتمد Firebase.

## 2. البنية المعمارية وهيكل `lib/`

يعتمد تنظيم المصدر على فصل تقريبي بين الواجهة (`presentation`)، والوصول إلى
الخدمات (`data`)، والعقود والسياسات (`domain`). تستخدم واجهات المصادقة
والمحادثة Riverpod للوصول إلى المستودعات. لا توجد طبقة Use Cases منفصلة كاملة.

```text
lib/
├── main.dart
├── app.dart
├── core/
│   ├── domain/
│   │   └── app_user.dart
│   ├── errors/
│   │   └── app_exceptions.dart
│   ├── l10n/
│   │   ├── app_strings.dart
│   │   └── locale_providers.dart
│   ├── notifications/
│   │   └── chat_notification_service.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── theme/
│   │   ├── app_colors.dart
│   │   ├── app_theme.dart
│   │   └── theme_providers.dart
│   ├── utils/
│   │   ├── picked_image.dart
│   │   └── time_ago.dart
│   └── widgets/
│       ├── app_text_field.dart
│       ├── mixsay_logo.dart
│       ├── primary_button.dart
│       ├── states.dart
│       └── user_avatar.dart
└── features/
    ├── auth/
    │   ├── data/
    │   │   └── firebase_auth_repository.dart
    │   ├── domain/
    │   │   ├── entities/
    │   │   │   └── auth_sign_up_outcome.dart
    │   │   ├── repositories/
    │   │   │   └── auth_repository.dart
    │   │   └── username_policy.dart
    │   └── presentation/
    │       ├── auth_controller.dart
    │       ├── auth_providers.dart
    │       ├── screens/
    │       │   ├── email_confirmation_screen.dart
    │       │   ├── login_screen.dart
    │       │   └── sign_up_screen.dart
    │       └── widgets/
    │           ├── or_divider.dart
    │           └── steps/
    │               ├── birth_date_step.dart
    │               ├── email_step.dart
    │               ├── name_step.dart
    │               ├── password_step.dart
    │               └── username_step.dart
    ├── chat/
    │   ├── chat_providers.dart
    │   ├── chat_repository.dart
    │   ├── chat_screen.dart
    │   ├── conversations_view.dart
    │   ├── conversations_screen.dart
    │   └── pending_queue_service.dart
    ├── feed/
    │   ├── data/feed_repository.dart
    │   └── presentation/
    │       ├── feed_providers.dart
    │       └── saved_posts_provider.dart
    ├── home/
    │   └── presentation/
    │       ├── main_shell.dart
    │       ├── home_tab.dart
    │       ├── notifications_tab.dart
    │       ├── profile_tab.dart
    │       ├── create_post_sheet.dart
    │       └── widgets/
    │           ├── mixsay_bottom_bar.dart
    │           ├── stories_bar.dart
    │           ├── story_viewer.dart
    │           ├── post_card.dart
    │           └── post_comments_sheet.dart
    ├── notifications/
    │   ├── data/notification_repository.dart
    │   └── presentation/notification_providers.dart
    ├── search/presentation/search_screen.dart
    └── stories/
        ├── data/story_repository.dart
        └── presentation/story_providers.dart
```

### أدوار الطبقات والملفات

- `main.dart`: يهيئ Firebase وApp Check، ثم يشغل `SocialChatApp`؛ ويحتوي
  كذلك على شيفرة واجهة تجريبية قديمة غير موصولة.
- `app.dart`: غلاف التطبيق المتصل الذي يوفر الترجمة والسمة و`GoRouter`.
- `core/domain`: نماذج مشتركة مثل `AppUser`.
- `core/errors`: استثناءات المجال وتحويل أخطاء Firebase إلى رسائل للمستخدم.
- `core/l10n`: النصوص والترجمة ومزودات اللغة.
- `core/notifications`: تسجيل FCM، الإشعارات المحلية، فتح المحادثة، وتحديث
  حالات التسليم.
- `core/router`: المسارات وإعادة التوجيه حسب مستخدم Firebase وحالة تأكيد البريد.
- `core/theme` و`core/widgets`: عناصر واجهة مشتركة قابلة لإعادة الاستخدام.
- `features/auth/domain`: عقد المستودع وسياسة اسم المستخدم ونتيجة التسجيل.
- `features/auth/data`: تنفيذ التسجيل/الدخول وقراءة Firestore باستخدام Firebase.
- `features/auth/presentation`: الشاشات والمتحكمات ومزودات Riverpod.
- `features/chat`: واجهات المحادثات، مستودع Firestore/Storage، وإدارة صف
  الرسائل غير المرسلة.
- `features/feed/presentation`: معاينة Home الاجتماعية؛ بيانات المنشورات
  والقصص تجريبية وليست مستمدة من Firebase.

### إدارة الحالة

`auth_providers.dart` يوفّر مستودع المصادقة ومزودات حالة المستخدم، بينما
`authControllerProvider` هو `AsyncNotifierProvider` للتحكم في إجراءات المصادقة.
`chat_providers.dart` يوفّر مستودع الدردشة و`StreamProvider.autoDispose` لقائمة
المحادثات:

```dart
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final authStateChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChanged,
);

final conversationsProvider =
    StreamProvider.autoDispose<List<ChatConversationPreview>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream.error(StateError('Sign in with Firebase to use chat'));
  }
  return ref.watch(chatRepositoryProvider).watchConversations(userId: userId);
});
```

### التنقل والحماية

`app_router.dart` يعرّف المسارات التالية:

| المسار | الشاشة | السياسة |
|---|---|---|
| `/login` | تسجيل الدخول | متاح دون تسجيل |
| `/signup` | إنشاء الحساب | متاح دون تسجيل |
| `/check-email` | تأكيد البريد | للمستخدم غير المؤكد |
| `/home` | معاينة الخلاصة الرئيسية | يتطلب مستخدمًا مؤكد البريد |
| `/conversations` | قائمة المحادثات | يتطلب مستخدمًا مؤكد البريد |
| `/chat/:conversationId` | المحادثة | يتطلب مستخدمًا مؤكد البريد |

يعاد تقييم إعادة التوجيه عند تغير `FirebaseAuth.authStateChanges()`. المستخدم
غير المسجل يوجّه إلى `/login`، والمستخدم غير المؤكد إلى `/check-email`،
والمستخدم المؤكد يوجّه افتراضيًا إلى `/home`. تظل `/conversations` متاحة
كمسار محمي للدردشة.

النمط هو `GoRouter` مع مستمع لحالة Firebase Auth، وليس تنقلًا مستقلًا عن
حالة الحساب. المثال التالي توضيحي مختصر؛ راجع الملف للمسارات والاستثناءات
الفعلية:

```dart
final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '/login';
    if (!user.emailVerified) return '/check-email';
    return '/home';
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
    GoRoute(
      path: '/conversations',
      builder: (_, __) => const ConversationsScreen(),
    ),
  ],
);
```

**حد تكاملي حالي:** `app_router.dart` ينشئ `FirebaseAuth.instance` عند تعريف
الموجّه؛ لذلك يجب أن تكون Firebase مهيأة قبل تشغيل `SocialChatApp`. نقطة
التشغيل الحالية لا تحقق ذلك ولا تستدعي `SocialChatApp`.

## 3. الملفات المحورية وتدفق البيانات

### المصادقة وإنشاء الحساب

`FirebaseAuthRepository` يعتمد على `FirebaseAuth` و`FirebaseFirestore`:

1. يتحقق من تنسيق اسم المستخدم عبر `UsernamePolicy`.
2. ينشئ المستخدم في Firebase Authentication بالبريد وكلمة المرور.
3. ينفذ معاملة Firestore تقرأ `usernames/{normalizedUsername}`.
4. إذا كان الاسم مستخدمًا، يرمي `UsernameAlreadyTakenException`.
5. إذا كان متاحًا، تنشئ المعاملة وثيقة حجز الاسم والبيانات الخاصة والملف العام
   ذريًا.
6. عند فشل إنشاء ملفات Firestore يحاول حذف حساب Auth الذي أنشئ كي لا يبقى
   حساب جزئي، ثم يعيد رمي الخطأ الأصلي.
7. يرسل رسالة تأكيد البريد ويعيد نتيجة تتطلب التأكيد.

مخطط مبسط:

```text
SignUpScreen
  └─ authControllerProvider
      └─ AuthRepository
          └─ FirebaseAuthRepository
              ├─ Firebase Authentication
              └─ Firestore transaction
                  ├─ usernames/{lowercaseUsername}
                  ├─ users/{uid}
                  └─ publicProfiles/{uid}
```

سياسة الاسم في `username_policy.dart` هي 4–24 محرفًا من `a-z`, `0-9`, `.`.
الواجهة تحول المدخل إلى أحرف صغيرة وتسمح بالنقطة. قواعد Firestore المحلية
تطبق النمط نفسه. فحص التوافر قراءة خادمية مباشرة، لذلك يعتمد نجاحه على نشر
القواعد وتهيئة App Check الفعلية في Firebase.

قراءة التوافر الحالية تتطلب المصدر الخادمي ولا تعتبر فشل الخدمة اسمًا متاحًا:

```dart
final normalized = UsernamePolicy.normalize(username);
if (!UsernamePolicy.isValid(username)) {
  throw const FormatException('Invalid username format');
}
final claim = await firestore
    .collection('usernames')
    .doc(normalized)
    .get(const GetOptions(source: Source.server));
return !claim.exists;
```

التنفيذ الفعلي يستخدم مثيل Firestore المحقون في `FirebaseAuthRepository`.
أخطاء Firebase تسجل في شاشة التسجيل مع `plugin` و`code` و`message` وstack
trace، وتعرض الرسائل تمييزًا بين تنسيق غير صالح واسم مأخوذ ومشكلة خدمة أو
صلاحيات.

### المحادثات والرسائل

`ChatRepository` يتعامل مباشرة مع Cloud Firestore وFirebase Storage:

- بيانات المحادثة في `conversations/{conversationId}`.
- الرسائل في `conversations/{conversationId}/messages/{messageId}`.
- الرسائل الأحدث تُراقب عبر snapshots، والقديمة تجلب على صفحات.
- لكل رسالة `clientId` لمقاومة التكرار عند إعادة الإرسال.
- النص محدود بـ4000 محرف في العميل والقواعد.
- صور المحادثات ترفع إلى `chats/{conversationId}/{senderId}/{clientId}.jpg`
  بحد 10 MiB، وتخزن الرسالة مسار Storage في `mediaUrl`.
- عند انقطاع الشبكة تحفظ الرسائل النصية في قائمة محلية باستخدام ملف دعم
  التطبيق، وتحفظ الصور المعلقة محليًا ثم تعاد محاولة رفعها.
- حالة الرسالة تتحرك للأمام: `sent` ثم `delivered` ثم `read`.

### استقبال FCM

`ChatNotificationService`:

- يطلب إذن الإشعارات ويهيئ قناة Android باسم `chat_messages`.
- يسجل FCM token في
  `users/{uid}/deviceTokens/{encodedToken}` مع `platform` و`updatedAt`.
- يحدث رمز الجهاز عند تغيره.
- يستقبل الرسائل في الواجهة الأمامية ويعرض إشعارًا محليًا عند الحاجة.
- يحفظ المحادثة المطلوبة عند فتح إشعار ويعيد التوجيه إليها.
- يحدث حالة تسليم الرسالة عند الاستلام/الفتح.
- قيمة `platform` المسجلة حاليًا هي السلسلة الثابتة `android`؛ يلزم تكييفها
  قبل الاعتماد على تسجيل الرموز في iOS.

### Cloud Function لإرسال FCM

- المصدر: `functions/src/index.ts`.
- نقطة التشغيل: `onDocumentCreated` على
  `conversations/{conversationId}/messages/{messageId}`.
- وقت التشغيل: Node.js 22، وFirebase Functions SDK 7، وFirebase Admin SDK 14.
- `functions/package-lock.json` يثبت شجرة الاعتماديات لإعادة بناء حتمية.
- `firebase.json` يحدد مجلد الوظائف ويشغّل TypeScript build قبل النشر.
- الوظيفة تتحقق من وجود مرسل ومحادثة صحيحة ثنائية العضوية، ثم ترسل الإشعار
  إلى رموز بقية الأعضاء، وتقسم الإرسال إلى دفعات لا تتجاوز 500 رمز، وتحذف
  وثائق الرموز التي يرفضها FCM باعتبارها قديمة/غير صالحة.
- اجتاز مصدر الوظيفة TypeScript build وفحص npm الأمني المحلي؛ لا يعني ذلك
  أنه نُشر أو يعمل على Firebase.

يوجد مصدر Cloud Function في `functions/src/index.ts` يستمع إلى إنشاء
`conversations/{conversationId}/messages/{messageId}`. يتحقق من أن المرسل
عضو في محادثة ثنائية، ثم يجلب ملفات وأجهزة المستلمين فقط ويرسل عبر Firebase
Admin SDK. ينظف رموز FCM غير الصالحة، ويستخدم مفاتيح البيانات
`conversation_id` و`message_id` التي يتعامل معها العميل. يستعمل هوية بيئة
Cloud Functions ولا يحتوي مفاتيح خدمة مضمّنة. الوظيفة **مصدر محلي ولم يثبت
نشرها** حتى تنفيذ أمر Firebase CLI والتحقق من سجلاتها.

## 4. Firebase، البيانات، وقواعد الحماية

### إعدادات Firebase

- إعداد Android موجود في `android/app/google-services.json`.
- `project_id` الظاهر في الإعداد هو `ms-chat-b9635`.
- اسم الحزمة المستخدم في Gradle هو `com.ms.socialchat`، ويظهر له إعداد عميل
  Android في ملف Google Services.
- ملفات إعداد Firebase العميلية ليست بديلًا عن Firebase Rules أو App Check؛
  الحماية تفرض على الخادم.
- `firebase.json` يحدد `firestore.rules` و`firestore.indexes.json` و
  `storage.rules`.
- يستدعي `main.dart` ‏`Firebase.initializeApp()` قبل تشغيل التطبيق، ثم يهيئ
  App Check (Debug provider للتطوير وPlay Integrity على Android للإنتاج).
- حالة فرض App Check الفعلية لا يمكن استنتاجها من ملفات المصدر. يجب تسجيل
  Debug token للتطوير قبل فرض التحقق على خدمات Firebase.

### نموذج Firestore

| المسار | المحتوى والاستخدام |
|---|---|
| `users/{uid}` | معلومات خاصة، بينها `birthDate` و`createdAt` |
| `users/{uid}/deviceTokens/{tokenId}` | FCM token والمنصة ووقت التحديث |
| `publicProfiles/{uid}` | اسم المستخدم والاسم الظاهر والصورة والنبذة |
| `usernames/{username}` | حجز فريد للاسم، يحوي `uid` |
| `conversations/{conversationId}` | الأعضاء والبيانات الظاهرة للمشاركين وآخر رسالة والعدادات |
| `conversations/{conversationId}/messages/{messageId}` | النص أو مسار الصورة والمرسل والوقت وحالة التسليم |

الرسالة التي ينشئها `ChatRepository` تتبع هذا الشكل:

```json
{
  "senderId": "Firebase Auth UID",
  "recipientId": "Firebase Auth UID",
  "clientId": "message UUID",
  "content": "Message text, or empty for an image",
  "mediaUrl": "Storage object path, or null",
  "createdAt": "Firestore server timestamp",
  "status": "sent"
}
```

وتحتوي وثيقة المحادثة على عضوين في `members`، ولقطات ملفاتهم في
`participants`، وحقول `lastMessageContent` و`lastMessageAt` وعدادات
`unreadCounts`. يتم تحديث الرسالة وآخر رسالة والعداد غير المقروء ضمن معاملة.

### قواعد Firestore (`firestore.rules`)

- `users/{uid}`: قراءة المالك فقط؛ إنشاء ذاتي مرة واحدة مع تاريخ ميلاد مناسب
  وحقول محددة؛ لا تحديث أو حذف للمستند الأساسي.
- `deviceTokens`: قراءة/كتابة/حذف مقيدة بصاحب الحساب، مع قائمة حقول مسموحة.
- `publicProfiles`: لا يقرأها إلا مستخدم مؤهل ومؤكد البريد؛ البحث الجماعي
  محدود بطلبات قائمة لا تتجاوز 20 عنصرًا.
- `usernames`: يسمح بـ`get` لاسم واحد حتى قبل تسجيل الدخول كي تعمل شاشة
  التسجيل؛ يمنع `list`؛ الإنشاء مقيد بالمستخدم الحالي وبالملف العام الذي
  ينشأ في المعاملة نفسها؛ لا تعديل أو حذف.
- السماح بـ`get` العام مقصود لفحص التوافر لكنه يكشف هل اسم محدد موجودًا؛ لا
  يسمح بقراءة قائمة الأسماء. راجع قيود إساءة الاستخدام وApp Check عند النشر.
- `conversations`: القراءة للمشاركين فقط؛ الإنشاء يتطلب مستخدمًا مؤكدًا،
  عضوين مرتبين، ومعرّفًا حتميًا وبيانات مشاركين تطابق ملفاتهم العامة.
- `messages`: القراءة والإنشاء للمشاركين فقط؛ الرسالة تنسب للمرسل المسجل،
  النص لا يتجاوز 4000 محرف، والحقول محددة؛ تحديث الحالة محدود بالانتقال
  المسموح، والحذف ممنوع.
- يتطلب الوصول المحمي بريدًا مؤكدًا وتاريخ ميلاد يفيد بعمر 13 عامًا على الأقل.
  هذا فحص لتاريخ الميلاد المرسل وليس تحققًا من الهوية الحقيقية.

### قواعد Storage (`storage.rules`)

- نطاق الصور: `chats/{conversationId}/{senderId}/{fileName}`.
- القراءة للمستخدم المؤهل المؤكد المنتمي للمحادثة.
- الرفع والتحديث يتطلبان أن يكون مسار المرسل هو UID للمستخدم الحالي، ونوع
  المحتوى صورة، وحجم الملف أقل من 10 MiB.
- الحذف للمشارك المؤهل في المحادثة الذي يطابق UID المرسل في المسار.

### النشر والتحقق

النشر المقصود للقواعد والفهارس:

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage --project ms-chat-b9635
```

نجاح وجود ملفات القواعد محليًا لا يثبت أنها منشورة في Firebase. يجب تسجيل
الدخول إلى المشروع الصحيح، مراجعة القواعد، ثم التحقق من نتيجة Firebase CLI
وفحص App Check في Firebase Console. لا توجد في هذه الوثيقة مصادقة على حالة
النشر أو إعداد Console.

لنشر وظيفة الإشعارات (يتطلب Node.js 22 وFirebase CLI، وقد يتطلب خطة Blaze):

```powershell
npm --prefix functions install
firebase deploy --only functions:sendChatMessageNotification --project ms-chat-b9635
```

## 5. الحالة الحالية وخطة العمل

### مكتمل بحسب المصدر

- مشروع Flutter به شاشات تسجيل ودخول وتأكيد بريد.
- سياسة اسم المستخدم موحدة في الواجهة والمستودع وقواعد Firestore المحلية.
- مستودع Firebase Auth وعمليات إنشاء الملف الشخصي وحجز الاسم بمعاملة.
- محادثات مباشرة ورسائل نصية وصور وتصفح صفحات رسائل.
- تخزين صور المحادثات في Firebase Storage وقائمة إعادة إرسال محلية.
- استقبال FCM وتسجيل رموز الأجهزة ومعالجة الضغط على الإشعار.
- قواعد محلية لـFirestore وStorage وفهارس Firestore.
- اختبارات وحدة وWidget لسياسة الاسم وتسجيل الحساب وأخطاء التحقق وبعض سلوك
  الدردشة.
- إعداد Android Firebase للمعرّف `com.ms.socialchat`.
- نقطة تشغيل التطبيق عبر Firebase وواجهات الدخول وإنشاء الحساب.

### مهام حرجة قبل اعتبار النسخة الحالية نسخة إطلاق

1. **اختبار تدفق كامل على جهاز:** إنشاء حساب جديد، تأكيد البريد، تسجيل الدخول،
   فحص اسم متاح ومأخوذ، إنشاء محادثة، إرسال نص وصورة، إعادة الإرسال بعد
   انقطاع الشبكة، وإشعار على جهاز مستقبل.
2. **تثبيت قواعد Firebase:** التحقق من مشروع Firebase الصحيح ونشر Firestore
   Rules وIndexes وStorage Rules، ثم تجربة العمليات من حسابات اختبار ذات
   صلاحيات مختلفة.
3. **حسم App Check:** تسجيل تطبيقات Android/iOS وبصمات التوقيع المطلوبة،
   تسجيل Debug token للتطوير، التأكد من استقبال Play Integrity للإنتاج، وعدم
   فرض App Check قبل التحقق من عمل البناء التجريبي والإنتاجي.
5. **إكمال إشعارات الإرسال:** نشر واختبار Function الموجودة في
   `functions/src/index.ts`، والتحقق من foreground / background / terminated.
   يحتاج الإطلاق على iOS إلى إعداد APNs. يتطلب بناء الوظيفة Node.js 22، ويتطلب
   النشر أداة Firebase CLI وإمكانية النشر إلى المشروع.
6. **مراجعة استراتيجية حساب Firebase:** التسجيل ينشئ Auth ثم يحجز الاسم
   وينشئ البيانات، بينما القواعد تتطلب حسابًا مسجلًا وبيانات مؤهلة. يجب
   اختبار معاملة الإنشاء فعليًا بالقواعد المنشورة لضمان أن كل كتابات التسجيل
   المتعددة تُقبل كوحدة واحدة.
7. **إعداد Release والتحقق منه:** تأكيد وجود keystore محليًا دون رفعه، مراجعة
   `android/key.properties` محليًا، زيادة `version` و`versionCode` قبل كل
   إصدار، إنتاج APK/AAB موقع، والتحقق من التوقيع والبصمة على الملف الناتج.
8. **اختبارات أمنية وقواعد:** استخدام Firebase Emulator Suite لاختبار
   الوصول المسموح والمرفوض، والحدود والطول والتحديثات وحالات المستخدم غير
   المؤكد.
9. **تنظيف بقايا Supabase:** أزيل مجلد `supabase/` و`.env.example` وأداة
   التحقق القديمة الخاصة بمتغيرات Supabase بعد التأكد من أن تطبيق Flutter
   يستخدم Firebase. لا ترفع `.env` أو service account أو أسرار التوقيع.

### تكامل اجتماعي غير منفذ

توجد معاينة واجهة Home، لكن ما زالت هذه الأنظمة تحتاج تنفيذًا وربطًا بخدمة
خلفية وقواعد أمان:

- Feed منشورات حقيقي بدل البيانات الثابتة.
- إنشاء منشور ورفع الوسائط وإدارة التعليقات والإعجابات والحفظ على الخادم.
- البحث عن المستخدمين وتبويب بحث وظيفي.
- متابعة/إلغاء متابعة المستخدمين.
- قصص وحالات بمدة انتهاء وصلاحيات مشاهدة.
- صفحة ملف شخصي حقيقية وتعديل آمن للحقول.
- صندوق إشعارات داخل التطبيق، إلى جانب Push Notifications.
- صفحات الإبلاغ والحظر وسياسات المحتوى وإدارة إساءة الاستخدام.
- اختبارات أداء وفهرسة وتكلفة Firestore/Storage، وسياسة حذف/احتفاظ بالبيانات.

### البناء والتحقق

أوامر التطوير الأساسية:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

أوامر إصدار Android بعد استكمال التهيئة:

```powershell
flutter build appbundle --release
flutter build apk --split-per-abi --release
```

يجب عدم إعلان الجاهزية للإطلاق بناءً على نجاح البناء وحده: نقطة التشغيل
والقواعد المنشورة وApp Check وتوقيع الإصدار واختبار Firebase الفعلي شروط
مستقلة.

سجل التحقق المتاح من العمل السابق: `flutter analyze` اجتاز دون مشكلات،
والاختبارات المركزة لاسم المستخدم والتسجيل اجتازت (14 اختبارًا)، وبُني APK
Debug بنجاح. هذه النتائج لا تثبت تكامل نقطة التشغيل الحالية أو اتصال Firebase
على جهاز فعلي، ولا تثبت نشر القواعد أو توقيع نسخة Release.

## 6. ملفات الإعداد والأسرار

- `android/app/google-services.json`: إعداد Firebase Android العميل.
- `firebase.json`: مواقع قواعد Firestore/Storage والفهارس.
- `android/key.properties` وملف `.jks`: إعداد ومفتاح توقيع Release محليان؛
  مستثنيان من Git ويجب عدم تضمين قيمهما في التوثيق أو المستودع.
- `.env`: إن وجد محليًا، فهو مستثنى من Git. ليس مصدر إعداد لخدمات Firebase
  في مسار التطبيق الحالي.
- مجلد Supabase و`.env.example` القديمان: أزيلا من نسخة المشروع لتفادي
  الالتباس مع Backend Firebase.
- `build/` و`.dart_tool/` و`.gradle/` وملفات APK/AAB: نواتج مولدة يجب عدم
  تتبعها في Git.

## 7. ملاحظات للمراجعة والتطوير

- لا تضع مفاتيح Service Account أو مفاتيح FCM الخادمية أو بيانات keystore في
  Flutter أو GitHub.
- Firebase client config ليس بديلًا عن Rules؛ يجب حماية كل كتابة/قراءة في
  القواعد واختبارها باستخدام Emulator.
- فحص الاتصال عبر `connectivity_plus` لا يثبت أن خدمة Firebase متاحة؛ يجب
  عرض رمز استثناء Firebase الحقيقي عند الفشل.
- فحص توفر اسم المستخدم لا يحجزه؛ المعاملة الذرية أثناء إنشاء الحساب هي
  الحاجز النهائي ضد التكرار.
- أي تغيير في مخطط Firestore يجب أن ينعكس في المستودعات والقواعد والاختبارات
  والفهارس، وأي تغيير في FCM يجب أن يطابق معالجة فتح المحادثة في العميل.
- لا تعتبر واجهة Home الحالية دليلاً على وجود Feed أو قاعدة اجتماعية عاملة؛
  بياناتها محلية ثابتة.
