# MixSay — إزاي تفتح ميزة مقفولة

الملف ده للمطور اللي يراجع المشروع بعد شهر (وليا). كل ميزة بتكلّف فلوس —
تخزين على Cloud Storage، أو تسجيل صوت بالميكروفون، أو بحث GIF على Tenor، أو
إشعارات والتطبيق مقفول — **مقفولة دلوقتي** بفلاغ في
`lib/core/config/chat_features.dart`.

الفكرة: قلب الفلاغ ل`true` هو **آخر** خطوة مش أولها. الشغل اللي في كونسول
Firebase لازم يبقى واقع قبل قلب الفلاغ، وإلا المستخدم يضغط زرار ويلاقي رسالة
فشل.

> الحالة الحالية (٢٠٢٦-١٠-١٦): الفرع `feature/chat`. قواعد الأمان
> `firestore.rules` و`storage.rules` وملف الـ indexes **مكتوبين بس لسه
> منشورين** على المشروع `ms-chat-b9635`. يعني أي فلاغ مفتوح دلوقتي بيوصل لفشل.

---

## خطوة صفر: النشر (مرة واحدة لكل المشروع)

بالترتيب ده بالظبط — الـ indexes الأول، لأن استعلامات مركّبة ناقصة ترمي خطأ
وقت التشغيل مش وقت النشر:

```bash
firebase deploy --only firestore:indexes --project ms-chat-b9635
firebase deploy --only firestore:rules   --project ms-chat-b9635
```

قواعد Storage محتاجة خطة Blaze (Cloud Storage نفسه مش متاح على الخطة
المجانية):

```bash
firebase deploy --only storage --project ms-chat-b9635
```

لو أمر `firebase` مش موجود على الجهاز استخدم `npx firebase-tools@13` مكانه —
الإصدار ١٣ هو اللي اختبارات القواعد في `security-tests/` شغّالة عليه.

**التأكيد:** `npm --prefix security-tests test` (١٣٠ فحص على إمولاتور
Firestore/Storage). نجاحه معناه إن القواعد والـ indexes سليمة، **مش** إنها
اتنشرت.

---

## الصور — `images`

- **السقف:** `ChatFeatures.maxImageBytes` = ٥ ميجا، و`storage.rules` بيقرأ نفس
  الرقم. غيّرت واحد غيّر التاني.
- **قبل القلب:** Storage مفعّل وقواعد Storage منشورة (خطوة صفر).
- **القلب:** `static const bool images = true;`
- **هتشوف إيه:** زرار المرفق (+) بيظهر في الشات وفيه سطر صورة.
- **التأكيد:** موبايلين — ابعت صورة واستقبلها، وابعت واحدة وانت في وضع الطيران
  (الرسالة بتدخل الطابور وتتابع لما الشبكة ترجع).

## الفيديو — `videos`

- **السقف:** ٢٥ ميجا.
- **قبل القلب:** نفس شروط الصور.
- **القلب:** `static const bool videos = true;`
- **ملحوظة:** مفيش مولّد صورة مصغّرة في المشروع (مكتبة `video_thumbnail`
  اتشالت لأن build بتاعها مكسور على Gradle ٩). الفيديو بيوصل من غير بوستر
  والفقاعة بتعرض المشغّل على طول. لو عايز بوستر لازم مكتبة بديلة الأول.

## المستندات — `documents`

- **السقف:** ١٠ ميجا.
- **قبل القلب:** نفس شروط الصور.
- **القلب:** `static const bool documents = true;`
- **هتشوف إيه:** سطر «مستند» في ورقة المرفقات، وبعده منتقي ملفات النظام.
- **التأكيد:** افتح ملف وصلك من الجهة التانية (المستلم بينزّله وبيفتحه
  ب`open_filex`)، وجرب اسم فيه مسافات ورموز.

## الرسالة الصوتية — `voiceMessages`

- **السقف:** ٥ ميجا، وأطول تسجيل ١٠ دقايق (`chatMediaMaxDurationMs`) لأن
  `firestore.rules` بيرفض `durationMs` أكبر من كده.
- **قبل القلب:** نفس شروط الصور. تصريح `RECORD_AUDIO` **موجود بالفعل** في
  `android/app/src/main/AndroidManifest.xml` مع `uses-feature` للميكروفون
  ب`required="false"`.
- **القلب:** `static const bool voiceMessages = true;`
- **هتشوف إيه:** زرار ميكروفون في الشات. الضغط = تسجيل وعدّاد ثواني؛ إلغاء =
  بيرمي الملف; إرسال = بيرفعه ويكتب رسالة `voice`. عند عشر دقايق التسجيل
  يقف لوحده وخيار الإرسال يفضل ظاهر.
- **التأكيد:** أول ضغطة لازم تطلب تصريح الميكروفون. سجّل ثانية وابعتها،
  وشغّلها من الموبايل التاني، وجرب كمان إلغاء بعد التسجيل.

## بحث GIF — `gifSearch`

دي الوحيدة اللي محتاجة مفتاح مش تخزين:

```bash
cp chat.secrets.example.json chat.secrets.json
```

واكتب `TENOR_API_KEY` بتاعك جواه (المفتاح من لوحة مطوّري Tenor).
`chat.secrets.json` مستثني في `.gitignore` — **متعملوش commit** ومتبعتوش لأحد.

- **القلب:** `static const bool gifSearch = true;`
- **معناه:** سطر GIF في ورقة المرفقات بيظهر بس لو المفتاح موجود فعلًا وقت
  البناء. من غيره الورقة تستمر من دونه، فمش تقابل زرار بايظ.
- **مهم:** المفتاح بيدخل وقت البناء، فالـ APK لازم يتعمل من جديد بعد أي تغيير:

  ```bash
  flutter build apk --release --split-per-abi --dart-define-from-file=chat.secrets.json
  ```

- **التأكيد:** ابحث في التبويب واضغط نتيجة؛ الـ GIF يوصل كنوع `gif` (رابط
  خارجي من غير أي رفع).

## الإشعارات والتطبيق مقفول — `pushNotifications`

- **قبل القلب:** خطة Blaze، ودوال Functions منشورة، و`google-services.json`
  بتاع المشروع نفسه:

  ```bash
  firebase deploy --only functions --project ms-chat-b9635
  ```

- **القلب:** `static const bool pushNotifications = true;`
- **الدالة:** `sendChatMessageNotification` في `functions/src/index.ts`، بتشتغل
  على إنشاء مستند رسالة جديدة.
- **التأكيد:** اقفل التطبيق على الموبايل المستلم، ابعت رسالة، والإشعار يوصل.

---

## فلاغات قلبه لوحده مش كفاية

- **`userUploadedStickers`**: رسالة `sticker` في `firestore.rules` بتقبل
  `stickerId` وبس، من غير `mediaUrl`. ملصق من جاليري المستخدم محتاج تغيير في
  القواعد **وفي شكل الرسالة** الأول — متعملوش دلوقتي. الباندل اللي في
  `assets/stickers/` شغال من غير أي حاجة وده اللي `bundledStickers` بيفتحه.
- **أسقف الأحجام و`maxTextLength`**: أرقامها مكتوبة كمان في `firestore.rules`
  و`storage.rules`. تغيير واحد منهم لوحده معناه إن التطبيق يقبل ملف والقاعدة
  ترفضه.

## بعد أي فتحة، بالأمر ده

```bash
flutter analyze --no-pub
flutter test
flutter build apk --release --split-per-abi
```

والاختبار اليدوي على موبايلين في `docs/TEST_CHECKLIST.md`.
