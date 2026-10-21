class AppConstants {
  static const supabaseUrl = 'https://azzjjqdgmefdvfdarpbp.supabase.co';

  /// مفتاح anon public — آمن للاستخدام في Flutter (لا تستخدم service_role أبداً هنا).
  /// المصدر: Supabase Dashboard > Project Settings > API > anon public
  /// يمكن تمريره أيضاً عبر: flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...
  /// إذا لم يتوفر المفتاح، ضع القيمة مباشرة هنا بدل REPLACE_WITH_ANON_KEY.
  // TODO: استبدل REPLACE_WITH_ANON_KEY بالمفتاح الحقيقي من Supabase Dashboard
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF6empqcWRnbWVmZHZmZGFycGJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0NjQyNjMsImV4cCI6MjEwODA0MDI2M30.yqkyievxxKv4uTtlZQicaS2ogt5PJd0yPObS1UNxNpA';
  

  static const aiProxyUrl =
      'https://azzjjqdgmefdvfdarpbp.supabase.co/functions/v1/ai-proxy';

  static const appName = 'AI سوريا';
  static const appNameEn = 'AI Syria';

  // Hive boxes
  static const hiveChatsBox = 'chats_box';
  static const hiveMessagesBox = 'messages_box';
  static const hiveSettingsBox = 'settings_box';

  // SharedPreferences keys
  static const keyDeviceId = 'device_id';
  static const keyThemeMode = 'theme_mode';
  static const keyLocale = 'locale';

  // Chat modes
  static const modes = ['fast', 'coding', 'math', 'pdf'];
  static const modeLabels = {
    'fast': 'سريع',
    'coding': 'برمجة',
    'math': 'رياضيات',
    'pdf': 'ملفات',
  };
  static const modeIcons = {
    'fast': '⚡',
    'coding': '💻',
    'math': '∑',
    'pdf': '📄',
  };

  // Quota limits per plan
  static const quotaLimits = {
    'free': {'heavy': 5, 'fast': 20},
    'student': {'heavy': 50, 'fast': 200},
    'pro': {'heavy': 100, 'fast': -1}, // -1 = unlimited
  };
}
