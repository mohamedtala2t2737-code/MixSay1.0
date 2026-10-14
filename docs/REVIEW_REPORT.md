# MixSay — تقرير المراجعة الشاملة (Review Report)

الفرع: `review/full-audit` · التاريخ: 2026-10-14 · المراجع: وكيل Qoder + تدقيق يدوي للنتائج

طريقة العمل: ثلاث جولات تدقيق متوازية (واجهة/UX، كود/بيانات، أمان/إعدادات)، ثم **كل نتيجة
حرجة تحققت منها بنفسي بقراءة الكود أو بأمر حقيقي** قبل كتابتها هنا. نتائج الوكلاء التي
مراجعتي دحضتها مكتوبة في قسم «مرفوضة» ولا يتم إصلاحها.

## 1) ملخص التطبيق في 10 أسطر

1. تطبيق Flutter اسم حزمتها `social_chat`/`com.ms.socialchat`، واجهته عربية/إنجليزية مع وضعين داكن وفاتح.
2. مصادقة ببريد + كلمة مرور عبر Firebase Auth، مع حجز اسم مستخدم بمعاملة Firestore وتأكيد بريد إلزامي.
3. تسجيل الحساب يطلب اسمًا (4-24 `[a-z0-9.]`) واسمًا ظاهرًا وبريدًا وكلمة مرور وتاريخ ميلاد ≥ 13 سنة.
4. بعد التأكيد يهبط المستخدم على `MainShell` بأربع تبويبات + زرين: الرئيسية، المحادثات، الجرس، الملف الشخصي.
5. الرئيسية: شريط قصص `stories` (انتهاء 24 ساعة) + خلاصة `posts` (لايك/تعليق/حفظ/حذف/مشاركة بالنسخ).
6. الشات: قائمة محادثات، محادثة لحظية نص وصور، حالات `sent → delivered → read`، وصف إعادة إرسال محلي offline.
7. الإشعارات: صندوق داخلي من مجموعة `notifications` + Push عبر FCM و Cloud Functions v2 (TypeScript).
8. البحث عن مستخدم وفتح محادثة، وشاشة إنشاء منشور بضغط صورة قبل الرفع.
9. البنية: Riverpod 3 + go_router + طبقات data/presentation لكل ميزة، و 60 ملف Dart ≈ 8900 سطر.
10. النشر: Android جاهز (APK release يُبنى)، iOS مجلّد موجود لكنه غير مهيأ (بلا Podfile وبلا نصوص صلاحيات).

## 2) الطوابع الزمنية للتحقق (إخراج حقيقي)

```text
flutter pub get   → (انظر قسم «سجل الأوامر» بالأسفل)
flutter analyze   → No issues found!
flutter test      → All tests passed!  (42)
flutter build apk --release → نجح سابقًا في نفس الجلسة
npm --prefix functions run lint  → tsc --noEmit بدون أي خطأ
```

## 3) جدول المشاكل

الحالة: `مفتوح` = سيُصلَح في المرحلة 4 · `موافقة` = يحتاج قرارك · `مرفوض` = تحققت وأنه غير صحيح.

### Critical

| ID | Screen/File | Problem | Severity | Why it matters | Proposed solution | Effort | Status |
|---|---|---|---|---|---|---|---|
| A-01 | `firestore.rules:414-441` | أي مستخدم موثّق يقدر يزيد/ينقص `likesCount`/`commentsCount` لأي منشور غريب ±1 لكل كتابة، لأن القاعدة لا تشترط وجود وثيقة لايك/تعليق مقابلة في نفس الـcommit | Critical | العدّاد العام للمحتوى قابل للتزييف بلا حدود: منشور واحد يتحول لـ100k لايك بسكربت، وده يفسد مصداقية الخلاصة كلها | اشتراط `getAfter` على `posts/{id}/likes/{uid}` عند +1/−1 للايك؛ وبالنسبة للتعليقات يلزم id حتمي للتعليق أو نقل عدّاد التعليقات لـCloud Functions | L | معالجة جزئية — القواعد بقت ±1 لعدّاد واحد فقط ومختبَرة؛ اشتراط وثيقة لايك/تعليق مقابلة لسه على موافقتك |
| A-02 | `lib/main.dart:1-11` + `pubspec.yaml:54` | حزمة `firebase_app_check` موجودة كاعتمادية لكن **لا يوجد أي ذكر لـApp Check داخل `lib/`** (`grep -rn "AppCheck" lib/` رجع فاضي)، و`PROJECT_CONTEXT.md` يدّعي إنها مهيّأة — والكلامين خطأ | Critical | بدون App Check أي سكربت يقدر يضرب Auth/Firestore مباشرة (إنشاء حسابات آلي، تجريب كلمات مرور، قراءة أسماء مستخدمين) | تفعيل `FirebaseAppCheck.instance.activate` (Debug في التطوير و Play Integrity في الإنتاج) + تسجيل التطبيق في Console كخطوة منك | M | تم — `9210653` فعّل App Check في `main.dart`؛ تسجيل Debug token في Console خطوة بتاعتك |
| C-01 | `lib/features/feed/data/feed_repository.dart:124-146` | `watchPosts` بيعمل `likes/{userId}.get()` لكل منشور (N+1 ≈ 30 قراءة إضافية) جوه `asyncMap`، وبيتحرق كل ما حد تاني يعمل لايك في أي منشور بالخلاصة | Critical | استهلاك قرايات Firestore بيتضرب مع كل تحديث لحظي = فاتورة أعلى + خلاصة أبطأ على الشبكات الضعيفة | تحويلها لاستعلام واحد `likes` بالمجموعة `where documentId whereIn` أو `getAll` لدفعة الوثائق | M | تم — `130d75a` كاش لحالة لايك المستخدم لكل صفحة بدل N+1 |
| C-02 | `lib/features/chat/chat_repository.dart:664-692` و`:695-716` | `markMessagesRead` بيعمل استعلام بلا `limit` علي كل الرسائل المستلمة، و`markReceivedMessagesDelivered` بيعمل `.get()` علي كل محادثات المستخدم من غير حد | Critical | مع مستخدم عنده محادثات كتير كل فتح محادثة = قراءة تاريخ كامل: بطء وتكلفة، وكمان بيزيد زمن الاستجابة بعد كل إشعار | إضافة `limit` لكل استعلام + تشغيل `markReceivedMessagesDelivered` مرة واحدة لكل تغيّر (debounce) | S | تم — `e419a7f` حدود لكل استعلام + تسوية واحدة لكل تغيّر |

### High

| ID | Screen/File | Problem | Severity | Why it matters | Proposed solution | Effort | Status |
|---|---|---|---|---|---|---|---|
| C-03 | `lib/features/chat/chat_screen.dart:303-314` | فشل الاشتراك في رسائل المحادثة بيظهر في `debugPrint` بس: المحادثة بتتجمّد من غير رسالة خطأ ولا زرار إعادة محاولة | High | أسوأ حالة مستخدم: شاشة فاضية/مجمّدة وهو فاكر إن الرسايلوصلت | رفع علم حالة خطأ وعرض `ErrorStateView` مع زرار إعادة محاولة يستدعي `_subscribeToMessages` | M | تم — `f2b8bce` رسالة خطأ وزرار إعادة محاولة للاشتراك الفاشل |
| U-01 | `lib/features/home/presentation/widgets/story_viewer.dart:196` | مناطق اللمس بتُقارن `dx` خام (`< width*0.35`) فالرجوع بيفضل شمال رغم إن القصص في العربي تتقدّم يمين-شمال | High | مستخدم عربي لايك/كومنت بيتقدم لما هو عايز يرجع — اتجاه معكوس | قراءة `Directionality.of(context)` وقلب الحد حسب الاتجاه | S | تم — `812b9ae` مناطق لمس تعكس الاتجاه |
| U-02 | `lib/core/theme/app_colors.dart:13-22` + `lib/core/widgets/primary_button.dart:26` | نص `onBrandGradient` (تقريبًا أسود `#0B0B10`) داخل على توقف البنفسجي `#6200EA` في التدرّج: تباين ≈ 2:1 في أول الزرار حيث يبدأ النص العربي | High | الزرار الأساسي في كل التطبيق نصه مش مقروء كفاية (وFAIL WCAG AA) — وده أهم عنصر تفاعل | تغيير يبقى الهوية: نقل التدرّج لليسار الخفيف أو وضع طبقة تعتيم خفيفة تحت النص — **لازم موافقتك لأن ده الملف اللي بيتحكم في الهوية** | S | موافقة — `app_colors.dart` ما اتلمسش (ملف هوية) |
| U-03 | `lib/features/home/presentation/widgets/post_comments_sheet.dart:112` و `lib/features/search/presentation/search_screen.dart:86` | حالة الخطأ في التعليقات وفي البحث بتظهر `ErrorStateView` من غير `onRetry` = طريق مسدود جوه الـsheet | High | المستخدم ماعندوش أي مخرج غير يقفل الشاشة ويفتحها تاني | تمرير `onRetry` (إبطال الـprovider) للشاشتين + debounce علي البحث | S | تم — `92ca5e4` إعادة محاولة + debounce |
| U-04 | `lib/features/home/presentation/profile_tab.dart:87-99` و `lib/features/chat/conversations_screen.dart:23-38` | تسجيل الخروج من غير تأكيد ومن غير حالة انشغال: ضغطة مزدوجة تنفّذه مرتين، ومعناه كمان حذف توكن FCM مرتين | High | خروج بالخطأ = إزعاج، وضغطتين = عمليات مكررة على الشبكة | حوار تأكيد + علم `_busy` يعطّل الزرار | S | تم — `457dbed` حوار تأكيد + منع تكرار |
| C-04 | `lib/features/home/presentation/main_shell.dart:68-76` | `IndexedStack` بيبني التبويبات الأربعة مع بعض فاشتراكات الخلاصة/القصص/المحادثات/الإشعارات شغالة دايمًا حتى وانت في تبويب تاني | High | مع C-01 الضعف بيتراكم: كل تبويب مخفي بيستهلك قرايات Firestore | إبقاء `IndexedStack` (لأنه بيحفظ الحالة) وتفعيل المزودات حسب التبويب الحالي، أو جعل التبويبات المخفية autoDispose | M | قرار — `IndexedStack` استمر لأنه بيحفظ حالة التبويبات؛ الاشتراك اللي ماكانش بيقفل اتعالج في `f047398` |
| A-03 | `firestore.rules:161-166` | `usernames/{username}` بيسمح بـ`get` لمن مش مسجّل (مقصود لفحص التوافر) وبيكشف هل الاسم محجوز + الـ`uid` المالك | High | أداة عدّ أسماء مستخدمين + ربط اسم ← هوية، وده تسريب بنية مستخدمين | قصر القراءة على المستخدم المسجّل بعد إنشاء الحساب وتحويل فحص التوافر لدالة خادمية، أو تخزين مرجع غير مباشر بدل الـuid | L | موافقة |
| A-04 | `functions/src/index.ts:203-210` و`:295` | نص الرسالة (160 حرف) ونص التعليق كامل بيتحطوا في `notification.body` بتاع FCM | High | محتوى خاص بينشر على قناة Google و على شاشة القفل من غير قفل التطبيق | إرسال «رسالة جديدة» فقط وجلب المحتوى من Firestore، أو تركه بقرارك لأنه تبديل تجربة شائعة | S | موافقة |
| S-01 | `android/app/build.gradle.kts:74-78` | لو `android/key.properties` مش موجود البناء بيوقع نسخة release بمفتاح debug التجريبي علطول | High | APK «release» بيتوزع بتوقيع تجريبي وده يخلي التحديثات فوق بعض مستحيلة ويوهم إن الإنتاج جاهز | إفشال البناء (`throw`) لو مفتاح التوقيع الحقيقي ناقص | S | تم جزئي — `30dc7a2` تحذير صريح عند الرجوع لمفتاح debug؛ `throw` محتاج موافقتك |
| S-02 | `ios/Runner/Info.plist` | مافيش `NSCameraUsageDescription` ولا `NSPhotoLibraryUsageDescription` رغم إن `image_picker` مستخدم في الشات والمنشور والقصص | High | أول زرار كاميرا/معرض على iOS = crash وفشل في المراجعة | إضافة النصين (عربي/إنجليزي) قبل أي بناء iOS | S | تم — `6951fea` نص الكاميرا والمعرض في `Info.plist` |

### Medium

| ID | Screen/File | Problem | Severity | Why it matters | Proposed solution | Effort | Status |
|---|---|---|---|---|---|---|---|
| C-05 | `lib/features/stories/data/story_repository.dart:88-92` | حدّ الـ24 ساعة بيتحسب مرة واحدة عند الاشتراك، فالستريم الطويل بيحتفظ بقصص انتهت | Medium | قصص بتفضل ظاهرة بعد انتهاء مدتها لمستخدم مااقفلش التطبيق | إعادة حساب الحد لكل snapshot أو فلترة `expiresAt` جهة العميل | S | تم — `877a65b` إسقاط القصص المنتهية مع كل snapshot |
| C-06 | `lib/features/notifications/presentation/notification_providers.dart:20` | `unreadNotificationsCountProvider` مش `autoDispose` وبيراقب مزود `autoDispose` → الاشتراك في الإشعارات عمره مايقفل | Medium | مستمع Firestore بيفضل عايش بعد مغادرة الشاشة = Reads وذاكرة | جعل العدّاد `autoDispose` أو حسابه جوه الواجهة | S | تم — `f047398` العدّاد بقى `autoDispose` |
| C-07 | `lib/features/feed/data/feed_repository.dart:186` و`:217` | عدّادات اللايك/التعليق بتتعمل read-modify-write جوه معاملة بدل `FieldValue.increment` | Medium | تحت التزاحم المعاملة بتعيد محاولة لحد ما تفشل وتطلع «operation failed» للمستخدم | استخدام `increment(±1)` للعدّاد والإبقاء على المعاملة للوثائق | S | تم — `42f7621` العدّادات بـ`increment` جوّه المعاملة |
| C-08 | `lib/features/home/presentation/create_post_sheet.dart:60-66` | الصورة بتترفع تحت `newPostId()` ثم `createPost` بيستخدم `_posts.add()` (id تاني): مسار الميديا مايطابقش وثيقة المنشور | Medium | اسم المجلد مايطابقش الـdoc = تخمين في التنظيف وصعوبة تتبع الملفات اليتيمة | `createPost` يقبل id صريح ويكتب بـ`set` بدل `add` | S | تم — `42f7621` id صريح للمنشور و`set` بدل `add` |
| C-09 | `lib/features/chat/chat_screen.dart:479` | فشل توليد رابط الصورة بيظل مخزّن في `_signedImageUrls` للأبد | Medium | انقطاع لحظة واحد يكسر فقاعة صورة بشكل دائم | حذف الـfuture الفاشل من الكاش | S | تم — `32920e5` رابط الصورة الفاشل مابقاش يتكاش |
| C-10 | `lib/features/home/presentation/create_post_sheet.dart:75-79` | `Navigator.pop` ثم استخدام `context` في نفس الإطار لإظهار SnackBar | Medium | سياق ميت = استثناء طائر بعد نجاح النشر مباشرة | التقاط `ScaffoldMessenger` قبل الـpop (والـroot context) | S | تم — `42f7621` التقاط الـmessenger قبل الـpop |
| C-11 | `lib/features/home/presentation/widgets/post_comments_sheet.dart:48` | `currentProfileProvider.value` ممكن يكون null فيمرّر اسم مستخدم فاضي في التعليق | Medium | القاعدة ترفض الكتابة برسالة غامضة «permission denied» | تعطيل الزرار لحد ما الملف يوصل أو جلبه من الخادم | S | تم — `42f7621` اسم المستخدم من الملف الخادمي |
| C-12 | `lib/core/router/app_router.dart:54-62` | إعادة التوجيه بترجع `'/home'` حتى لما المسار الحالي هو `/home` أصلًا، ومافيش `errorBuilder` | Medium | روابط مكسورة بتتحول للهوماي بصمت، وخطر إعادة توجيه متكررة | إرجاع `null` لما الوجهة == الحالي + صفحة خطأ | S | تم — `42bf258` لا إعادة توجيه لصفحة أنت فيها + صفحة خطأ |
| C-13 | `functions/src/index.ts:43-68` | الدوال مش idempotent: لو `sendPush` رمى بعد كتابة وثيقة الإشعار، إعادة المحاولة بتكرّر الإشعار والـPush | Medium | صندوق الإشعارات بيتعبّى مكررات مع كل فشل شبكة | id حتمي مشتق من `messageId`/`commentId` للإشعار | S | تم — `d854b9e` id حتمي للإشعار يجعل إعادة المحاولة idempotent |
| C-14 | `functions/src/index.ts:161-299` | ولا حد لمعدل الإرسال: طوفان رسايل/لايكات = وثائق إشعارات + fan-out بلا سقف | Medium | تكلفة DoS وقبوله بسيط من حساب واحد | عدّاد لكل مستخدم جوه Admin وتجاهل ما يزيد عن الحد | M | موافقة |
| A-05 | `firestore.rules:197-198` | مجموعة `conversations` ماعندهاش حد `request.query.list` بينما المنشورات/القصص/الإشعارات كلها محدودة | Medium | قائمة محادثات ضخمة = قرايات بلا سقف | إضافة `limit <= 100` مع التأكد إن العميل بيحدّ فعلًا | S | تم — `limit <= 50` في القواعد والعميل، ومختبَر على المحاكى |
| A-06 | `firestore.rules:277-286` | أي عضو يقدر يزوّد `unreadCounts` التاني +1 من غير رسايل جديدة (إزعاج شارة) | Medium | عدّاد غير صحيح وسيل إشعارات بصرية | اشتراط وجود رسالة جديدة في نفس الـcommit عبر `getAfter` | M | معالجة جزئية — +1 لكل كتابة محدود ومختبَر؛ اشتراط وجود رسالة جديدة لسه على موافقتك |
| A-07 | `storage.rules:43-78` | حدود لكل ملف لكن مافيش سقف إجمالي لكل مستخدم | Medium | تخزين غير محدود جوه مساحة المشروع | كوتا لكل uid أو مهمة تنظيف يومية | M | موافقة |
| U-05 | `lib/features/home/presentation/widgets/stories_bar.dart:29` و`:71` | علم الرفع بيتظبط بعد ما الـpicker يرجع (ضغطة سريعة تفتح المختار مرتين)، وأخطاء/تحميل الستريم بتتجاهل (`value ?? []`) | Medium | سلوك مزدوج + شريط قصص فاضي بصمت لو القراية فشلت | ضبط الانشغال قبل الاختيار + هيكل عظمي/إعادة محاولة | S | مفتوح |
| U-06 | `lib/features/home/presentation/widgets/story_viewer.dart:96` | مؤقت 33ms بيعمل `setState` للصفحة كلها (الصور والرأس 30 مرة/ثانية) | Medium | هبوط في الأداء وحرارة بطارية على شاشة المفروض تكون أنعم | تحريك `_ProgressBar` لوحده بـ`ValueNotifier`/`AnimatedBuilder` | M | تم — `3b0c435` شريط التقدم بـ`ValueNotifier` |
| U-07 | `lib/features/auth/presentation/screens/login_screen.dart:90` | `autofillHints` مفقودة على بريد وكلمة المرور (وفي كل `AppTextField`) | Medium | مديري كلمات المرور والمتصفح مايعبّوش بيانات الدخول | إضافة بارامتر autofill في `AppTextField` وتوصيله | S | تم — `f489f41` `autofillHints` |
| U-08 | `lib/core/widgets/app_text_field.dart:91` | زرار إظهار/إخفاء كلمة المرور من غير `tooltip` ولا `Semantics` | Medium | قارئ الشاشة مايقولش الزرار بيعمل إيه | tooltip + label من `AppStrings` (مفتاح جديد) | S | تم — `f489f41` tooltip + semantics لزرار إظهار كلمة المرور |
| U-09 | `lib/features/home/presentation/widgets/notifications_tab.dart:145` | الضغط على إشعار لايك/تعليق بيشيله مقروء وبس — مافيش تنقل للمنشور | Medium | الإشعار يوديك لمكان غامض: المستخدم مايشوفش حاجة | فتح تبويب الإشعارات/المنشور المناسب (يتطلب مسار عرض منشور) | M | موافقة |
| U-10 | `lib/features/home/presentation/widgets/*` + `mixsay_bottom_bar.dart:20` + `stories_bar.dart:78` + `home_tab.dart:43` + `app_settings_sheet.dart:75` + `create_post_sheet.dart:196` | مقاسات ثابتة (ارتفاع 68/96، عرض 150، كتل 300/340px، `Column` من غير تمرير) | Medium | على خط نظام كبير أو شاشة صغيرة المحتوى يتقص أو يفيض | مقاسات مشتقة من `textScaler` + `SingleChildScrollView` + حدود مرنة | M | مفتوح |
| U-11 | `lib/features/chat/chat_screen.dart:491` و`:720`، `conversations_view.dart:19` | فواصل التواريخ مخطوفة اليد `dd/MM/yyyy` وإجبار 24 ساعة: ولا «اليوم/أمس» ولا تنسيق عربي صحيح | Medium | قارئ عربي يشوف تواريخ غريبة ومتقطعة | `intl.DateFormat` + مفاتيح `AppStrings` (حزمة جديدة = موافقة) | M | موافقة |
| U-12 | `lib/features/chat/chat_screen.dart:769` و`:673` | فقاعات الصور 220×160 بثبات، وزرار الإرسال محشور في `CircleAvatar` (~40dp) و«حذف الصورة» 28dp | Medium | صورة كبيرة بتقطع نص الكلام، وأهداف لمس تحت 48dp صعبة على الموبايل | عرض نسبي للصور + أزرار `IconButton` كاملة 48dp | S | تم — `22c1c8a` فقاعات صور نسبية + أهداف لمس 48dp |
| U-13 | `lib/app.dart:27-29` + `lib/main.dart:7-10` | اللغة والسمة بيتسترجعوا بعد أول frame: ثانية بالعربي/الوضع الداكن قبل أن تظهر اختيارات المستخدم | Medium | ومضة لغة/سمة غلط أول كل فتح | قراءة `SharedPreferences` قبل `runApp` | S | تم — `722f4d6` اللغة والسمة تُقرآن قبل أول frame |
| U-14 | `lib/features/home/presentation/main_shell.dart:98` + `lib/core/widgets/mixSay_logo` + `splash_view.dart:53` | ثلاث رسمات لعلامة «MixSay» (Pacifico في واحدة، مائل في الثانية، صورة في التالتة) | Medium | الهوية البصرية مش ثابتة عبر التطبيق | مصدر واحد لعلامة MixSay النصية + قرارك عن الخط | M | موافقة |
| U-15 | `lib/core/utils/time_ago.dart:8` + `sign_up_screen.dart:222` | أرقام لاتينية في نص عربي («5 د») مع بقية النصوص بأرقام عربية | Medium | تناسق بصري مش مريح في العربي | تنسيق حسب اللغة (بدون حزمة جديدة: تبديل رمزي للأرقام) | S | تم — `38d2d1e` أرقام عربية في كل النصوص العربية |
| Q-01 | `lib/features/auth/presentation/widgets/steps/{name,email,password,birth_date}_step.dart` | أربع وديكات خطوة غير مستخدمة إطلاقًا (شاشة التسجيل بتعيد تنفيذها جوه نفسها) | Medium | كود ميت بيضلّل أي مراجع جديد | حذفهم بعد التأكد إن مافيش مرجع | S | تم — `6af454a` حذف الوديكات غير المستخدمة |
| Q-02 | `lib/features/chat/chat_screen.dart` (890 سطر) و`chat_repository.dart` (872) | أكبر ملفين في المشروع بيركّزوا شات + وسائط + حالات + قائمة معلقة في نفس المكان | Medium | صعوبة تعديل وسهولة كسر حاجة وأنت بتصلح التانية | تقسيم لـwidgets/methods على مراحل (مش دلوقتي) | L | موافقة — مؤجل عمدًا (تقسيم ملفات كبيرة مش مطلوب الآن) |

### Low

| ID | Screen/File | Problem | Severity | Why it matters | Proposed solution | Effort | Status |
|---|---|---|---|---|---|---|---|
| U-16 | `lib/features/home/presentation/widgets/post_card.dart:198` | `EdgeInsets.only(right: 4)` — آخر inset غير اتجاهي فاضي في المشروع | Low | مسافة غلط علي العربي | `EdgeInsetsDirectional.only(end: 4)` | S | تم — `6af454a` `EdgeInsetsDirectional.only(end: 4)` |
| U-17 | `lib/features/home/presentation/widgets/post_card.dart:122`, `conversations_screen.dart:25` | خلط أيقونات ممتلئة/مفرّغة في نفس القوائم (`bookmark_rounded` و`bookmark_add_outlined`، `favorite_rounded` و`mode_comment_outlined`) | Low | إحساس غير موحد | توحيد علي الـoutlined | S | مفتوح |
| U-18 | `lib/features/chat/conversations_view.dart:164` | حوار «محادثة جديدة» مثبّت 420×280 و`Column` من غير تمرير | Low | بيتقص في الوضع الأفقي/الشاشات القصيرة | حدود مرنة + تمرير | S | مفتوح |
| U-19 | `lib/features/chat/conversations_screen.dart:39` | تلات أزرار في الـAppBar ممكن تزاحم العنوان علي 320dp | Low | عنوان/أزرار متداخلة | نقل الخروج لورشة الإعدادات | S | موافقة |
| U-20 | `lib/features/auth/presentation/screens/sign_up_screen.dart:111` | التحقق بيضبط أخطاء لكن مايفتحش أول حقل غلط (تاريخ الميلاد تحت الشاشة) | Low | المستخدم مايشوفش سبب الرفض | `ScrollController.ensureVisible` | S | مفتوح |
| U-21 | `lib/features/chat/conversations_view.dart:82` | نص «مافيش رسايل بعد» بيُستخدم كوصف للمحادثة الفاضية | Low | رسالة مش منطيقة في غير سياقها | مفتاح «لا رسالة» منفصل | S | مرفوض — انظر R-06: النص في مكانه الصحيح |
| U-22 | `android/app/src/main/res/values/styles.xml:16` | خلفية `NormalTheme` هي `launch_background` الأسود: الانتقال/الاستئناف في الوضع الفاتح يومض أسود (يحتاج تأكيد على جهاز) | Low | ومضة لون أول ثانية | خلفية `?android:colorBackground` في نسخة night | S | تم — `de55439` خلفية النافذة لكل وضع؛ يحتاج تأكيدًا بصريًا على جهاز |
| C-15 | `lib/core/notifications/chat_notification_service.dart:141,157,419` | إنشاء `ChatRepository()` مباشر بدل مزود Riverpod | Low | مثالين مختلفين لنفس الطبقة | تمرير المزود أو حقن المستودع | S | تم — `1b3066b` المستودع من مزود Riverpod |
| C-16 | `lib/main.dart:9` | ولا التقاط خطأ حول `Firebase.initializeApp` | Low | فشل التهيئة = شاشة بيضا | try/catch + شاشة خطأ | S | تم — `a86d517` شاشة خطأ لو فشل `Firebase.initializeApp` |
| A-08 | `.github/workflows/main.yml:24-26` | الـCI بيعمل `pub get` + `build apk` بس: ولا `analyze` ولا `test` ولا فحص الدوال | Low | CI أخضر مايعنيش إن التطبيق سليم | إضافة خطوات analyze/test/functions-lint | S | تم — `9a4929f` الـCI يشغّل analyze وtest وbuild الدوال قبل APK |
| A-09 | `lib/features/home/presentation/widgets/post_card.dart:33` | `username` بيتاخد من كاش ملف nullable؛ لو ناقص بيرسل «» فترفضه القاعدة برسالة غامضة | Low | رسالة خطأ غلط للمستخدم | جلب الاسم من الملف الخادمي أو تعطيل الفعل | S | تم — `42f7621` الاسم يجي من الخادم |

## 4) مرفوضة (دحضها التحقق اليدوي — لا يتم إصلاحها)

| ID | المطالبة من التدقيق | الحقيقة اللي تحققت منها |
|---|---|---|
| R-01 | «`Icons.send` و`Icons.arrow_back` ماانعكسوش في العربي ويلزم إصلاح» | `flutter/…/material/icons.dart:22565` و`:2290` بيعرّفوهم بـ`matchTextDirection: true` — فالفريمويك بيرمجهم أوتوماتيك حسب `Directionality`. ولا زرار إرسال ولا سهم رجوع مكسور. |
| R-02 | «استعلامات رسائل الشات تحتاج فهرس مركّب `(createdAt, __name__)`» | الفهرس أحادي الحقل في Firestore بينطوي أصلًا على `__name__` كمكوّن ترتيب أخير، والاستعلامات اللي بتستخدم `where+orderBy` فعلاً عندها المركّبات المطلوبة في `firestore.indexes.json` (`recipientId,status,createdAt` و`status,createdAt`). |
| R-03 | «مزودات المستودعات بتبني مثال جديد لكل قراءة» | كلها `Provider((ref) => X())` بدون `autoDispose` فتُحفظ مرة واحدة — التدقيق نفسه رجّحها وبعدها رجعها FALSE. |
| R-04 | «ازدواج ضغط علي إرسال/نشر/لايك/رفع» | كلها محروسة بأعلام `_sending`/`_busy`/`_liking`/`_uploading`. الاستثناء الحقيقي: تسجيل الخروج (U-04). |
| R-05 | «تسريبات ذاكرة: controllers/timers/subscriptions من غير dispose» | جولة التدقيق نفسها لمّا أُعيد التحقق رجعت: كل عنصر له دورة حياة مقابلة (dispose)، ولا `addListener` من غير `removeListener`. |
| R-06 | **U-21** ««مافيش رسايل بعد» نص مش منطقي في وصف المحادثة الفاضية» | `conversations_view.dart:84` يعرض `item.lastMessageContent ?? s.noMessagesYet`: الوصف ده بيظهر لما المحادثة لسه مفيهاش أي رسالة (`lastMessageContent == null`)، و«مافيش رسائل لسه» هو بالضبط المعنى الصح في المكان ده، وهو مستخدم كمان كعنوان قائمة المحادثات الفاضية (سطر 44). مفتاح جديد هيكرّر نفس الجملة. |

## 5) محتاج موافقتك قبل التنفيذ

1. **A-01** تزييف عدّادات المنشورات: الحل المطبوع أأمن أمانًا لكنه يغيّر سلوك القواعد (ممكن يكسر عميل قديم).
2. **U-02** تباين النص فوق التدرّج: أي تعديل ده يلمس ملف الهوية `app_colors.dart` — لن ألمسه غير بقولك.
3. **C-04** تحويل التبويبات لقراءة كسولة: يغيّر سلوك حفظ الحالة (الفيد هيتحدث لما ترجع له).
4. **A-03** تقييد `usernames`: يغيّر تجربة فحص التوافر قبل إنشاء الحساب.
5. **A-04** إخفاء نص الرسالة من إشعار القفل: تجربة أقل إفادة مقابل خصوصية أعلى.
6. **U-11 / U-14** تنسيق التواريخ بالحزمة `intl` وخط الـwordmark: الأول حزمة جديدة، التاني يلمس الهوية.
7. **U-09** الضغط على إشعار لايك/تعليق يفتح المنشور: محتاج شاشة تفاصيل منشور (ميزة جديدة).
8. **C-14 / A-06 / A-07 / Q-02** كوتا إشعارات، شارة غير مقروءة، كوتا تخزين، تقسيم الملفات الكبيرة: كلها شغل كبير.

## 6) الناقص مقارنةً بتطبيق شات كامل (المرحلة 5)

| البند | الحالة | كيف يجب أن يعمل | الجهد |
|---|---|---|---|
| ملف شخصي: اسم/صورة/نبذة + تعديل | **ناقص** (قراءة فقط) | شاشة تعديل ترفع الصورة لـ`profiles/{uid}` وتكتب `publicProfiles` بقاعدة حقول مقيّدة | M |
| حذف الحساب | **ناقص** | معاملة: حذف `users`/`publicProfiles`/`deviceTokens` + وثائق المنشورات/القصص، و`usernames`، ثم `delete()` في Auth، مع تحذير | L (موافقة) |
| مؤشر «يكتب…» | **ناقص** | حقل `typingUntil` في `conversations/{id}` بكتابة مشروطة وزمن انتهاء، وقراءة لحظية | M |
| رسائل صوتية/ملفات | **ناقص** (صور فقط) | تسجيل `record` + رفع `attachments/` مع مدة ونوع محدد في قواعد Storage | L (حزمة + موافقة) |
| تعديل/حذف رسالة | **حذف جزئي موجود؟** — مافيش تعديل ولا حذف جوه الواجهة | حذف مملوك خلال 15 دقيقة + نص «الرسالة حُذفت» | M |
| حظر/إبلاغ مستخدم | **ناقص** | مجموعة `blocks/{uid}` و`reports/` + إخفاء المحتوى وقواعد مطابقة | L (موافقة) |
| Onboarding أول تشغيل | **ناقص** | 3 شرائح تعريفية + زار لـ`app_first_run` | S |
| إعدادات الإشعارات (كتم) | **ناقص** | مفتاح per-conversation `muted` وقراءة في العميل والدوال | S |
| أيقونة تطبيق مخصّصة | **ناقص محتمل** | `flutter_launcher_icons` من `assets/images/mixsay_logo.png` | S (حزمة + موافقة) |
| شاشة سبلاش | **موجود** (`launch_background` + `splash_view.dart`) | — | — |
| تقرير أعطال | **ناقص** | Crashlytics أو Sentry — خدمة خارجية، اختيارك | M (موافقة) |
| سياسة خصوصية/شروط | **ناقص** | روابط نصية في ورشة الإعدادات لصفحات ويب تنشرها | S |
| بحث داخل المحادثة | **ناقص** | استعلام `content` بـ`array-contains`/نص جزئي (مؤقتًا) | M |
| إعادة تعيين كلمة المرور | **موجود** | — | — |
| الوضعان الداكن والفاتح + عربي/إنجليزي | **موجود ومُختبَر بالاختبارات** | — | — |
| دعم offline + طابور إرسال | **موجود** | — | — |
| Push (foreground/background/terminated) | **موجود**، والتفاعل على المنشور لسه ماانشرش كـCloud Function | — | M (خطوتك) |

## 7) اختبارات ناقصة

مغطّى: الدخول + استعادة كلمة المرور، إنشاء حساب (ناجح/مرفوض/اسم مأخوذ/سن <13)، تبويبات الهيكل الرئيسي + RTL، ورشة اللغة والسمة، الطابور المعلّق، نماذج الشات، بطاقة المنشور + الحفظ، الزرار الأساسي، `timeAgo`.

أُضيف في المرحلة 4: اختبارات وحدة لقرارات الدردشة المنطقية (`test/chat_repository_logic_test.dart` — المعرّف الحتمي للمحادثة، منع تصادم بادئة UID، `recipientOf`، ترتيب ودمج الطابور، انتقالات الحالة للأمام فقط، جاهزية إعادة المحاولة و`retryBackoff` و`nextAttemptCount` و`PendingQueueService` حقيقي مع `SharedPreferences` mock)، و76 فحصًا للقواعد على Firebase Emulator (`security-tests/run.mjs`) يغطّون إرسال رسالة/رفض خارجي/الحذف من المرسل/حدود الحقول والـ`limit`/الصلاحيات في Storage.

**بقى غير مغطّى:** رسم ويدجت لشاشات الشات نفسها (محتاج Firebase mocks أو
`fake_cloud_firestore`)، سلوك `ChatRepository` من طرف لطرف ضد Firestore حقيقي
(القواعد مغطّاة بالمحاكى والقرارات المنطقية بوحدة، لكن مسار الإرسال الكامل
لأ)، وفحص يدوي على جهازين حسب `docs/TEST_CHECKLIST.md`.

## 8) سجل الأوامر

آخر تشغيل على فرع `review/full-audit` (بعد كل الإصلاحات):

```text
$ flutter analyze
No issues found!

$ flutter test
+64: All tests passed!

$ npm --prefix security-tests test
76 passed, 0 failed        # firestore.rules + storage.rules على Firebase Emulator

$ npm --prefix functions run build
(tsc نظيف)

$ flutter build apk --release
√ Built build\app\outputs\flutter-apk\app-release.apk (57.6MB)
```

سجل ما قبل الإصلاحات (يبقى للتاريخ — بند App Check اتحل في `9210653`):

```text
$ flutter test
... All tests passed!   (42 tests, 11 files)

$ npm --prefix functions install
added 244 packages, and audited 245 packages in 20s
found 0 vulnerabilities

$ npm --prefix functions run lint      # tsc --noEmit
(no output => zero type errors)

$ grep -rn "AppCheck" lib/
(no output => App Check غير مهيأ فعليًا رغم وجود الاعتمادية)

$ grep -n "matchTextDirection: true" $FLUTTER_SDK/packages/flutter/lib/src/material/icons.dart
303 matches (send و arrow_back من بينهم)
```

**ملاحظة بيئة:** `flutter build apk` كان بيفشل لأن `ANDROID_HOME` و
`ANDROID_SDK_ROOT` في Windows اشاره لمسار `D:\Android\Sdk` المحذوف. الثابت
الآن بأمر `flutter config --android-sdk="D:\New folder\Android\Sdk"`؛ يُفضّل
تصحيح متغيّرات البيئة نفسها.

## 9) حالة التنفيذ

| المرحلة | الحالة |
|---|---|
| 1 تدقيق التصميم و UX | تمت |
| 2 تدقيق الكود والوظائف والأمان | تمت |
| 3 التقرير (الملف ده) | تمت |
| 4 الإصلاحات | تمت للموافق عليه؛ المفتوح الآن: U-05، U-10، U-17، U-18، U-20 + بنود «على موافقتك» |
| 5 استكمال التطبيق | معلّق على موافقاتك في قسم 5 و6 |
| 6 الفحص النهائي | تمت: analyze نظيف، 64 اختبار Dart، 76 فحص قواعد على المحاكى، APK release مبني |
