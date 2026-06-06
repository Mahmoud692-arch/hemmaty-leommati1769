
# خطة المراجعة الشاملة والتطوير

هذا عمل ضخم جداً (7 أنظمة + مراجعة معمارية). سأنفّذه على **مراحل** حتى لا تضيع الجودة، وأبدأ بالأنظمة الأهم. أحتاج موافقتك على الخطة والترتيب قبل البدء.

## المرحلة 1 — الأنظمة الحرجة (أول دفعة تنفيذ)

### 1) نظام «صارحني» مجهول الهوية بالكامل
- جدول `anonymous_messages` منفصل (لا يربط `user_id` في عرض الأدمن).
- داخلياً نخزّن `user_id` (مشفّر منطقياً عبر RLS) لاستخدامه فقط في **صفحة المستخدم داخل لوحة الإدارة**.
- View للأدمن: `admin_anonymous_messages_view` يُرجع الرسائل بدون `user_id`.
- دالة `get_user_anonymous_messages(uid)` (security definer + has_role admin) لعرضها داخل صفحة المستخدم فقط.
- عند نشر الرد: لا يظهر اسم المرسل للجمهور (موجود جزئياً في `user_questions` — سنفصل صارحني عنه أو نضيف عمود `is_anonymous_strict`).

### 2) نظام الصلاحيات المرن (RBAC)
- `app_permission` enum: `manage_articles, manage_hadiths, manage_stories, review_content, manage_suggestions, manage_comments, manage_reports, manage_users, manage_points, view_analytics`.
- جدول `role_permissions(role, permission)` + جدول `user_permissions(user_id, permission)` للصلاحيات المباشرة.
- دالة `has_permission(uid, perm)` security definer.
- استبدال `has_role(admin)` تدريجياً في الـ RLS بـ `has_permission(...)` (مع إبقاء admin = كل الصلاحيات).
- واجهة في `UsersManager` لمنح/سحب صلاحيات فردية بدل ترقية كاملة.

### 3) نظام التعليقات على المقالات + القصص + الأحاديث
- تعميم جدول `article_comments` → `content_comments(content_type, content_id, ...)` أو إضافة `story_comments` و`hadith_comments` بنفس البنية. (الأبسط: تعميم الموجود).
- CRUD كامل: إضافة/تعديل/حذف/إبلاغ + مراجعة من لوحة الإدارة (موجودة جزئياً لـarticles).

### 4) نظام الإبلاغ عن الأخطاء
- جدول `content_reports(reporter_id, content_type, content_id, content_url, description, status: new|reviewing|resolved)`.
- زر «إبلاغ عن خطأ» في صفحات: المقال، القصة، الحديث، التعليق.
- لوحة إدارة `ReportsManager` لتغيير الحالة.

## المرحلة 2 — أنظمة المحتوى والنقاط

### 5) اقتراح المحتوى من المستخدمين
- جدول `content_suggestions(user_id, type, title, body, status, published_as_id, target_section)`.
- صفحة `/me/suggest` بثلاثة نماذج (مقال/قصة/حديث).
- لوحة `SuggestionsManager` للموافقة/الرفض + اختيار قسم النشر → ينشئ سجل في الجدول المناسب.

### 6) نقاط مكافأة المحتوى المقترح
- إعداد قابل للتعديل في `public_site_settings` (key=`suggestion_reward_points`).
- عند الموافقة → `award_points(user_id, points, 'suggestion_approved', suggestion_id)`.

### 7) تحسين احتساب نقاط القراءة
- المقالات: ≥ 180 ثانية فعلية + scroll ≥ 70%.
- الأحاديث: ≥ 60 ثانية فعلية.
- استخدام `Page Visibility API` (إيقاف العدّاد عند `document.hidden`).
- منع إعادة التحديث: `points_awarded=true` مرة واحدة (موجود).
- تسجيل `effective_read_seconds` في `article_read_progress` و`hadith_reads`.

## المرحلة 3 — تقرير المراجعة المعمارية

أكتب تقريراً مختصراً (سيظهر في الشات) يغطي:
- الأمان: ما تم تثبيته + توصيات إضافية (rate limiting، CAPTCHA على «صارحني»، فحص الصور للـ avatars).
- الأداء: lazy load للأقسام الكبيرة، تقليل queries في `me.tsx` و`HomepageSectionsManager`.
- UX: skeleton states، error boundaries، toast موحّد، فاصل واضح بين المحتوى المؤكد والمسوّدة.
- نواقص قبل الإطلاق: سياسة الخصوصية، شروط الاستخدام، صفحة 404 مخصصة، sitemap.xml، تتبع أحداث، باك أب دوري.

---

## ملاحظات تنفيذية مهمة

- العمل يتطلب **عدة migrations** (كل واحدة تحتاج موافقتك في الـ Supabase).
- التعديلات على الكود تتم على دفعات بعد كل migration.
- **سؤال مهم قبل البدء**: هل أبدأ مباشرة بالمرحلة 1 كلها معاً (4 migrations + كود)، أم نظام واحد في كل دورة لتسهيل المراجعة؟

اقترح: **نظام واحد في كل دورة** بالترتيب أعلاه. وافق وسأبدأ فوراً بـ «صارحني» المجهول.
