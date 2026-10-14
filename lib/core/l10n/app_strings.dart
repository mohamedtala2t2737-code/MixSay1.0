import 'package:flutter/material.dart';

import 'package:social_chat/core/utils/arabic_digits.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  bool get isArabic => locale.languageCode == 'ar';

  /// Arabic copy is written with ٠-٩, so numbers shown beside it convert too.
  String number(Object value) => localizeDigits('$value', isArabic: isArabic);

  static const supportedLocales = [Locale('en'), Locale('ar')];

  static const delegate = AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('en'));

  // ---------- generic ----------
  String get continueButton => isArabic ? 'متابعة' : 'Continue';
  String get retry => isArabic ? 'حاول تاني' : 'Try again';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get savedProfile => isArabic ? 'تم الحفظ' : 'Saved';
  String get loadingMore => isArabic ? 'جاري التحميل…' : 'Loading…';
  String get loadFailed => isArabic ? 'حصل خطأ في التحميل' : 'Failed to load';
  String get actionFailed => isArabic
      ? 'تعذّر تنفيذ العملية، جرّب تاني'
      : 'Could not complete, try again';

  // ---------- login ----------
  String get emailAddress => isArabic ? 'البريد الإلكتروني' : 'Email address';
  String get password => isArabic ? 'كلمة السر' : 'Password';
  String get logInButton => isArabic ? 'تسجيل الدخول' : 'Log in';
  String get or => isArabic ? 'أو' : 'OR';
  String get noAccount =>
      isArabic ? 'ليس لديك حساب؟' : "Don't have an account?";
  String get signUpLink => isArabic ? 'أنشئ حسابًا' : 'Sign up';

  // ---------- sign-up steps ----------
  String get signUpTitle =>
      isArabic ? 'إنشاء حساب جديد' : 'Create a new account';
  String get signupTagline => isArabic
      ? 'شارك أفكارك وتواصل مع أصدقائك على MixSay.'
      : 'Share your thoughts and connect with friends on MixSay.';
  String get signupCardSubtitle =>
      isArabic ? 'إنه سريع وسهل.' : "It's quick and easy.";
  String get firstName => isArabic ? 'الاسم الأول' : 'First name';
  String get lastName => isArabic ? 'اسم العائلة' : 'Last name';
  String get day => isArabic ? 'اليوم' : 'Day';
  String get month => isArabic ? 'الشهر' : 'Month';
  String get year => isArabic ? 'السنة' : 'Year';
  String get birthDatePrivacyNote => isArabic
      ? 'نستخدم تاريخ الميلاد لحساب عمرك فقط، ولن يظهر في ملفك العام.'
      : 'We use your birthday to calculate your age; it will not appear on your public profile.';
  String get alreadyHaveAccount =>
      isArabic ? 'لديك حساب بالفعل؟' : 'Already have an account?';
  List<String> get birthMonths => isArabic
      ? const [
          'يناير',
          'فبراير',
          'مارس',
          'أبريل',
          'مايو',
          'يونيو',
          'يوليو',
          'أغسطس',
          'سبتمبر',
          'أكتوبر',
          'نوفمبر',
          'ديسمبر',
        ]
      : const [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
  String get stepNameTitle => isArabic ? 'إيه اسمك؟' : "What's your name?";
  String get stepNameSubtitle => isArabic
      ? 'اكتب اسمك الحقيقي عشان أصحابك تعرفوك.'
      : 'Enter your real name so friends can find you.';
  String get fullName => isArabic ? 'الاسم بالكامل' : 'Full name';
  String get stepBirthTitle =>
      isArabic ? 'تاريخ ميلادك إيه؟' : 'When is your birthday?';
  String get stepBirthSubtitle => isArabic
      ? 'هنعرفه ليك بس، مش هيظهر لأي حد.'
      : 'We use it to calculate your age only.';
  String get birthDate => isArabic ? 'تاريخ الميلاد' : 'Birth date';
  String get pickDate => isArabic ? 'اختار التاريخ' : 'Pick a date';
  String get stepEmailTitle =>
      isArabic ? 'إيه بريدك الإلكتروني؟' : "What's your email?";
  String get stepEmailSubtitle => isArabic
      ? 'هنستخدمه لاسترجاع حسابك لو نسيت كلمة السر.'
      : "We'll use it to recover your account.";
  String get email => isArabic ? 'البريد الإلكتروني' : 'Email';
  String get stepUsernameTitle =>
      isArabic ? 'اختار اسم مستخدم' : 'Choose a username';
  String get stepUsernameSubtitle => isArabic
      ? 'هتدخل بيه حسابك، وهيظهر لكل الناس.'
      : 'You will sign in with it, and others will see it.';
  String get username => isArabic ? 'اسم المستخدم' : 'Username';
  String get usernameFormatHint => isArabic
      ? 'من ٤ إلى ٢٤ حرفًا: أحرف إنجليزية صغيرة وأرقام ونقطة فقط.'
      : '4–24 characters: lowercase English letters, numbers, and periods only.';
  String get usernameAvailable =>
      isArabic ? 'الاسم متاح' : 'Username is available';
  String get usernameTaken =>
      isArabic ? 'الاسم ده مأخود' : 'This username is taken';
  String get usernameCheckFailed =>
      isArabic ? 'تعذّر التحقق، جرّب تاني' : 'Could not check, try again';
  String get usernameCheckPermissionDenied => isArabic
      ? 'تعذّر الوصول للأسماء. انشر قواعد Firestore وسجّل رمز App Check لهذا التطبيق.'
      : 'Username lookup was denied. Deploy Firestore rules and register this app’s App Check token.';
  String get usernameCheckDatabaseUnavailable => isArabic
      ? 'قاعدة بيانات Firestore غير جاهزة. فعّل قاعدة البيانات ثم أعد المحاولة.'
      : 'Firestore is not ready. Enable the database, then try again.';
  String usernameCheckErrorCode(String code) =>
      isArabic ? 'رمز الخطأ: $code' : 'Error code: $code';
  String get stepPasswordTitle =>
      isArabic ? 'اعمل كلمة سر' : 'Create a password';
  String get stepPasswordSubtitle =>
      isArabic ? '٨ حروف على الأقل.' : 'Use at least 8 characters.';
  String get passwordHint =>
      isArabic ? '٨ حروف على الأقل' : 'At least 8 characters';
  String get createAccount => isArabic ? 'إنشاء الحساب' : 'Create account';
  String get confirmPassword =>
      isArabic ? 'تأكيد كلمة السر' : 'Confirm password';
  String get showPassword => isArabic ? 'إظهار كلمة السر' : 'Show password';
  String get hidePassword => isArabic ? 'إخفاء كلمة السر' : 'Hide password';
  String get forgotPassword =>
      isArabic ? 'نسيت كلمة السر؟' : 'Forgot your password?';
  String get resetLinkSent => isArabic
      ? 'ابعتنالك لينك تغيير كلمة السر على بريدك.'
      : 'A password reset link has been sent to your email.';
  String get ageError =>
      isArabic ? 'لازم عمرك ١٣ سنة على الأقل.' : 'You must be at least 13.';

  // ---------- validation errors ----------
  String get errRequired =>
      isArabic ? 'الحقل ده مطلوب' : 'This field is required';
  String get errNameTooShort => isArabic
      ? 'اكتب اسم فيه حرفين على الأقل'
      : 'Name must be at least 2 characters';
  String get errFirstName =>
      isArabic ? 'اكتب اسمك الأول.' : 'Enter your first name.';
  String get errLastName =>
      isArabic ? 'اكتب اسم العائلة.' : 'Enter your last name.';
  String get errInvalidEmail =>
      isArabic ? 'البريد الإلكتروني مش صحيح' : 'Enter a valid email';
  String get errInvalidUsername => isArabic
      ? 'استخدم ٤ إلى ٢٤ حرفًا صغيرًا أو رقمًا أو نقطة فقط.'
      : 'Use 4–24 lowercase English letters, numbers, or periods only.';
  String get errPasswordTooShort =>
      isArabic ? '٨ حروف على الأقل' : 'At least 8 characters';
  String get errPasswordMismatch =>
      isArabic ? 'كلمة السر غير مطابقة' : 'Passwords do not match';

  // ---------- auth errors ----------
  String get errInvalidCredentials => isArabic
      ? 'البريد الإلكتروني أو كلمة السر غير صحيح'
      : 'Wrong email address or password';
  String get errEmailTaken =>
      isArabic ? 'البريد ده مسجل قبل كده' : 'This email is already registered';
  String get errWeakPassword =>
      isArabic ? 'كلمة السر ضعيفة' : 'Password is too weak';
  String get errEmailNotConfirmed =>
      isArabic ? 'أكّد بريدك الإلكتروني الأول' : 'Confirm your email first';
  String get errNetwork =>
      isArabic ? 'شوف اتصالك بالإنترنت' : 'Check your internet connection';
  String get errTooManyAttempts =>
      isArabic ? 'محاولات كتير، استنى شوية' : 'Too many attempts, try later';
  String get errGeneric =>
      isArabic ? 'حصل خطأ، جرّب تاني' : 'Something went wrong, try again';

  // ---------- email confirmation ----------
  String get checkEmailTitle =>
      isArabic ? 'أكّد بريدك الإلكتروني' : 'Confirm your email';
  String get checkEmailBody => isArabic
      ? 'بعتنالك رابط على بريدك. افتحه، وبعدها اضغط «تحققت من البريد».'
      : 'We sent a link to your email. Open it, then tap “I’ve verified my email”.';
  String get backToLogin => isArabic ? 'رجوع لتسجيل الدخول' : 'Back to login';
  String get resendVerification =>
      isArabic ? 'إعادة إرسال رسالة التأكيد' : 'Resend verification email';
  String get checkVerification =>
      isArabic ? 'تحققت من البريد' : "I've verified my email";
  String get verificationEmailSent => isArabic
      ? 'تم إرسال رسالة التأكيد. راجع بريدك.'
      : 'Verification email sent. Check your inbox.';
  String get emailNotVerifiedYet => isArabic
      ? 'لم يتم تأكيد البريد بعد. افتح رابط الرسالة أولًا.'
      : 'Email is not verified yet. Open the link in the email first.';
  String verificationResendCooldown(int seconds) => isArabic
      ? 'إعادة الإرسال بعد ${number(seconds)} ثانية'
      : 'Resend in $seconds seconds';
  String get signInToResendVerification => isArabic
      ? 'سجّل الدخول ببريدك وكلمة السر لإعادة إرسال رسالة التأكيد.'
      : 'Sign in with your email and password to resend the verification email.';
  String get verificationResendFailed => isArabic
      ? 'تعذّر إرسال الرسالة. حاول بعد قليل.'
      : 'Could not send the email. Please try again later.';
  String get verificationStatusFailed => isArabic
      ? 'تعذّر التحقق من حالة البريد.'
      : 'Could not check email verification status.';

  String get logOut => isArabic ? 'تسجيل الخروج' : 'Log out';
  String get logOutConfirm => isArabic
      ? 'هتسجل الخروج من حسابك على الجهاز ده. هل أنت متأكد؟'
      : 'You will be signed out of this device. Are you sure?';
  String get messages => isArabic ? 'الرسائل' : 'Messages';
  String get message => isArabic ? 'رسالة' : 'Message';
  String get typeMessage => isArabic ? 'اكتب رسالة…' : 'Type a message…';
  String get send => isArabic ? 'إرسال' : 'Send';
  String get sendImage => isArabic ? 'إرسال صورة' : 'Send image';
  String get retrySend => isArabic ? 'إعادة الإرسال' : 'Retry';
  String get deleteMessage => isArabic ? 'حذف الرسالة' : 'Delete';
  String messageCharacterCount(int current, int maximum) => isArabic
      ? '${number(current)}/${number(maximum)} حرف'
      : '$current/$maximum characters';
  String get noMessagesYet => isArabic ? 'مافيش رسائل لسه' : 'No messages yet';
  String get startConversation => isArabic
      ? 'ابدأ محادثة مع أي شخص من حسابه أو البحث.'
      : 'Start a conversation from a profile or search.';

  String get searchHint =>
      isArabic ? 'ابحث باسم المستخدم…' : 'Search usernames…';
  String get searchInitial => isArabic
      ? 'اكتب اسم المستخدم اللي بتدور عليه.'
      : 'Type a username to search for people.';
  String get noResults => isArabic ? 'مفيش نتايج' : 'No results';

  // ---------- settings: language & appearance ----------
  String get settings => isArabic ? 'الإعدادات' : 'Settings';
  String get language => isArabic ? 'اللغة' : 'Language';
  String get appearance => isArabic ? 'المظهر' : 'Appearance';
  String get followSystem => isArabic ? 'زي النظام' : 'Follow system';
  String get arabic => isArabic ? 'العربية' : 'Arabic';
  String get english => isArabic ? 'الإنجليزية' : 'English';
  String get lightMode => isArabic ? 'فاتح' : 'Light';
  String get darkMode => isArabic ? 'غامق' : 'Dark';

  // ---------- home shell: tabs ----------
  String get home => isArabic ? 'الرئيسية' : 'Home';
  String get notifications => isArabic ? 'الإشعارات' : 'Notifications';
  String get profile => isArabic ? 'حسابي' : 'Profile';
  String get createPost => isArabic ? 'منشور جديد' : 'Create a post';
  String get search => isArabic ? 'بحث' : 'Search';

  // ---------- stories ----------
  String get yourStory => isArabic ? 'حكايتك' : 'Your story';
  String get addStory => isArabic ? 'إضافة حكاية' : 'Add story';
  String get removeStory => isArabic ? 'حذف الحكاية' : 'Delete story';
  String get noStories =>
      isArabic ? 'مافيش حكايات دلوقتي' : 'No stories right now';
  String get noStoriesSubtitle => isArabic
      ? 'الحكايات تختفي بعد ٢٤ ساعة.'
      : 'Stories disappear after 24 hours.';

  // ---------- feed ----------
  String get feedEmptyTitle => isArabic ? 'مافيش منشورات لسه' : 'No posts yet';
  String get feedEmptySubtitle => isArabic
      ? 'كن أول من ينشر شيئًا اليوم.'
      : 'Be the first to post something today.';
  String get postCaptionHint => isArabic ? 'اكتب حاجه…' : 'Write a caption…';
  String get attachPhoto => isArabic ? 'إضافة صورة' : 'Add photo';
  String get attachVideo => isArabic ? 'إضافة فيديو' : 'Add video';
  String get mediaTooLarge => isArabic
      ? 'الملف أكبر من ٤٨ ميجا. اختار ملف أصغر.'
      : 'That file is over 48 MB. Pick a smaller one.';
  String get mediaUnsupported => isArabic
      ? 'النوع ده مش مدعوم. الصور JPG/PNG والفيديو MP4/MOV.'
      : 'Unsupported type. Images (JPG/PNG) and videos (MP4/MOV) only.';
  String uploadProgress(int percent) =>
      isArabic ? 'جاري الرفع… ${number(percent)}٪' : 'Uploading… $percent%';
  String get uploadFailed => isArabic
      ? 'الرفع فشل. اتأكد من الإنترنت وحاول تاني.'
      : 'Upload failed. Check your connection and try again.';
  String get publish => isArabic ? 'نشر' : 'Post';
  String get videoUnavailable => isArabic
      ? 'الفيديو ده ماقدرش يشتغل هنا.'
      : 'This video could not be played here.';
  String get playVideo => isArabic ? 'تشغيل' : 'Play';
  String get pauseVideo => isArabic ? 'إيقاف مؤقت' : 'Pause';
  String get muteVideo => isArabic ? 'كتم الصوت' : 'Mute';
  String get unmuteVideo => isArabic ? 'تشغيل الصوت' : 'Unmute';
  String get publishing => isArabic ? 'جاري النشر…' : 'Posting…';
  String get postPublished => isArabic ? 'تم النشر' : 'Posted';
  String get like => isArabic ? 'إعجاب' : 'Like';
  String get unlike => isArabic ? 'إلغاء الإعجاب' : 'Unlike';
  String get comments => isArabic ? 'تعليقات' : 'Comments';
  String likesCount(int count) =>
      isArabic ? '${number(count)} إعجاب' : '$count likes';
  String commentsCount(int count) =>
      isArabic ? '${number(count)} تعليق' : '$count comments';
  String get writeComment => isArabic ? 'اكتب تعليقًا…' : 'Add a comment…';
  String get seeMore => isArabic ? 'اقرأ المزيد' : 'See more';
  String get seeLess => isArabic ? 'عرض أقل' : 'See less';
  String get noComments => isArabic ? 'مافيش تعليقات لسه' : 'No comments yet';
  String get commentAdded => isArabic ? 'تم إرسال التعليق' : 'Comment added';
  String get share => isArabic ? 'مشاركة' : 'Share';
  String get copyText => isArabic ? 'نسخ النص' : 'Copy text';
  String get textCopied => isArabic ? 'تم نسخ النص' : 'Text copied';
  String get savePost => isArabic ? 'حفظ' : 'Save';
  String get unsavePost => isArabic ? 'إلغاء الحفظ' : 'Unsave';
  String get postOptions => isArabic ? 'خيارات المنشور' : 'Post options';
  String get deletePost => isArabic ? 'حذف المنشور' : 'Delete post';
  String get postDeleted => isArabic ? 'تم حذف المنشور' : 'Post deleted';
  String get deletePostConfirm =>
      isArabic ? 'هل تريد حذف هذا المنشور؟' : 'Delete this post?';
  String get deleteConfirm => isArabic ? 'هل تريد الحذف؟' : 'Delete this?';

  // ---------- reports ----------
  String get report => isArabic ? 'إبلاغ' : 'Report';
  String get reportPost => isArabic ? 'الإبلاغ عن المنشور' : 'Report post';
  String get reportStory => isArabic ? 'الإبلاغ عن القصة' : 'Report story';
  String get reportReason => isArabic
      ? 'اختار السبب اللي يوصّف المحتوى'
      : 'Choose the reason that fits';
  String get reportNoteHint =>
      isArabic ? 'ملاحظة إضافية (اختياري)' : 'Extra note (optional)';
  String get sendReport => isArabic ? 'إرسال البلاغ' : 'Send report';
  String get reportSent => isArabic ? 'تم إرسال البلاغ' : 'Report sent';

  /// Keyed on the same values as the `reason in [...]` rule, so a label cannot
  /// drift away from what the rules accept.
  String reasonLabel(String reason) => switch (reason) {
    'spam' => isArabic ? 'رسائل مزعجة' : 'Spam',
    'harassment' => isArabic ? 'تحرش أو تنمر' : 'Harassment or bullying',
    'nudity' => isArabic ? 'محتوى غير لائق' : 'Nudity or sexual content',
    'violence' => isArabic ? 'عنف' : 'Violence',
    'misinformation' => isArabic ? 'معلومات مضللة' : 'False information',
    _ => isArabic ? 'سبب تاني' : 'Something else',
  };

  String get copyLink => isArabic ? 'نسخ الرابط' : 'Copy link';
  String get linkCopied => isArabic ? 'تم نسخ الرابط' : 'Link copied';

  // ---------- notifications tab ----------
  String get noNotifications =>
      isArabic ? 'مافيش إشعارات لسه' : 'No notifications yet';
  String get markAllRead => isArabic ? 'تعليم الكل كمقروء' : 'Mark all read';
  String get notifLike => isArabic ? 'أعجب بمنشورك' : 'liked your post';
  String get notifComment =>
      isArabic ? 'علّق على منشورك' : 'commented on your post';
  String get notifMessage => isArabic ? 'أرسل لك رسالة' : 'sent you a message';
  String get notifFollow => isArabic ? 'بدأ متابعتك' : 'started following you';
  String get notifGeneric =>
      isArabic ? 'عندك إشعار جديد' : 'updated something you follow';

  // ---------- profile tab ----------
  String get myPosts => isArabic ? 'منشوراتي' : 'My posts';
  String get noPostsYet =>
      isArabic ? 'لم تنشر أي شيء بعد' : 'You have not posted yet';
}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
