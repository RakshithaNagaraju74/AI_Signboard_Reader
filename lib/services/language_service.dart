import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code;
  final String speechLocale;
  final String name;
  const AppLanguage({required this.code, required this.speechLocale, required this.name});
}

class LanguageService {
  static const _key = 'preferred_language';
  static const languages = <AppLanguage>[
    AppLanguage(code:'en', speechLocale:'en-US', name:'English'),
    AppLanguage(code:'hi', speechLocale:'hi-IN', name:'Hindi'),
    AppLanguage(code:'kn', speechLocale:'kn-IN', name:'Kannada'),
  ];

  Future<AppLanguage?> load() async {
    final p = await SharedPreferences.getInstance();
    return fromCode(p.getString(_key) ?? '');
  }

  Future<void> save(AppLanguage language) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, language.code);
  }

  static AppLanguage? fromCode(String code) {
    for (final l in languages) { if (l.code == code) return l; }
    return null;
  }

  static String normalize(String text) => text.toLowerCase()
      .replaceAll(RegExp(r'[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? detectCommand(String text) {
    final v = normalize(text);
    if (v.contains('english')) return 'en';
    if (v.contains('hindi') || v.contains('हिंदी')) return 'hi';
    if (v.contains('kannada') || v.contains('ಕನ್ನಡ')) return 'kn';
    return null;
  }
}
