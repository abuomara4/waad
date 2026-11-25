# الدخول بحساب Google أو Microsoft

الأزرار جاهزة في شاشة «دخول الإدارة بالبريد» و«حساب جديد بالبريد». تظهر تلقائيا فقط بعد أن تفعّل المزوّد في Supabase. لا يحتاج النظام أي تعديل بعدها.

- **لمن:** المالك والإدارة (حسابات البريد) فقط. الموظفون يبقون على رمز المنشأة والرقم الوظيفي.
- **التحقق بخطوتين:** يبقى كما هو لمن فعّله.
- **تطبيق الآيفون:** الأزرار لا تظهر داخله، لأن Google ترفض الدخول من داخل التطبيقات المضمّنة.

## 1) عنوان الرجوع في Supabase
**Authentication → URL Configuration → Redirect URLs** ثم أضف عنوان النظام:
- `https://abuomara4.github.io/waad/site/app/`
- وعند انتقالك للدومين الخاص: أضف عنوانه الجديد أيضا.

## 2) Google
1. ادخل Google Cloud Console، ثم **APIs & Services → Credentials → Create credentials → OAuth client ID** (نوعه Web application).
2. في **Authorized redirect URIs** أضف عنوان Supabase:
   - `https://<PROJECT-REF>.supabase.co/auth/v1/callback`
   - تجده في Supabase → Authentication → Providers → Google.
3. في **OAuth consent screen** اكتب اسم التطبيق «وعد» والبريد ورابط سياسة الخصوصية.
4. انسخ Client ID و Client secret إلى Supabase → **Authentication → Providers → Google**، ثم فعّل المزوّد.

## 3) Microsoft (Azure)
1. ادخل Azure Portal، ثم **Microsoft Entra ID → App registrations → New registration**.
2. اختر **Accounts in any organizational directory and personal Microsoft accounts**.
3. في Redirect URI (Web) ضع عنوان Supabase نفسه (`…/auth/v1/callback`).
4. من **Certificates & secrets** أنشئ secret.
5. انسخ Application (client) ID والـ secret إلى Supabase → **Authentication → Providers → Azure**:
   - Azure Tenant URL: `https://login.microsoftonline.com/common`
6. فعّل المزوّد.

## ملاحظات
- **من ينشئ حسابا جديدا بـ Google:** يمر بخطوات إنشاء المنشأة نفسها، ومنها الموافقة على التخزين خارج المملكة، وموافقة فريق وعد.
- **أسرار Google و Microsoft:** لا تُوضع في المستودع ولا في GitHub أبدا. مكانها في لوحة Supabase فقط.
