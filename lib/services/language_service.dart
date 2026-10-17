import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  final String code;
  final String speechLocale;
  final String name;

  const AppLanguage({
    required this.code,
    required this.speechLocale,
    required this.name,
  });
}

class LanguageService {
  static const _key = 'preferred_language';

  static const languages = <AppLanguage>[
    AppLanguage(code: 'en', speechLocale: 'en-US', name: 'English'),
    AppLanguage(code: 'hi', speechLocale: 'hi-IN', name: 'Hindi'),
    AppLanguage(code: 'kn', speechLocale: 'kn-IN', name: 'Kannada'),
    AppLanguage(code: 'ta', speechLocale: 'ta-IN', name: 'Tamil'),
    AppLanguage(code: 'te', speechLocale: 'te-IN', name: 'Telugu'),
    AppLanguage(code: 'ml', speechLocale: 'ml-IN', name: 'Malayalam'),
  ];

  Future<AppLanguage?> load() async {
    final p = await SharedPreferences.getInstance();
    return fromCode(p.getString(_key) ?? '');
  }

  Future<void> save(AppLanguage language) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, language.code);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  static AppLanguage? fromCode(String code) {
    for (final language in languages) {
      if (language.code == code) return language;
    }
    return null;
  }

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-zA-Z\u0900-\u097F\u0B80-\u0BFF\u0C00-\u0C7F\u0C80-\u0CFF\u0D00-\u0D7F0-9 ]'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? detectCommand(String text) {
    final value = normalize(text);
    if (value.isEmpty) return null;

    // Speech recognition often adds extra words. Detect the language choice
    // from anywhere in the short response instead of requiring an exact phrase.
    if (RegExp(r'(^|\s)(one|1|first|english|inglish)(\s|$)').hasMatch(value)) return 'en';
    if (RegExp(r'(^|\s)(two|2|second|hindi|hindee|hindy|indi)(\s|$)').hasMatch(value) || value.contains('हिंदी') || value.contains('हिन्दी')) return 'hi';
    if (RegExp(r'(^|\s)(three|3|third|kannada|kanada|kannad|canada)(\s|$)').hasMatch(value) || value.contains('ಕನ್ನಡ')) return 'kn';
    if (RegExp(r'(^|\s)(four|4|fourth|tamil|tamizh)(\s|$)').hasMatch(value) || value.contains('தமிழ்')) return 'ta';
    if (RegExp(r'(^|\s)(five|5|fifth|telugu)(\s|$)').hasMatch(value) || value.contains('తెలుగు')) return 'te';
    if (RegExp(r'(^|\s)(six|6|sixth|malayalam)(\s|$)').hasMatch(value) || value.contains('മലയാളം')) return 'ml';

    // Common Android STT phonetic outputs for the numbers.
    if (RegExp(r'(^|\s)(won|wan)(\s|$)').hasMatch(value)) return 'en';
    if (RegExp(r'(^|\s)(too|tu|do)(\s|$)').hasMatch(value)) return 'hi';
    if (RegExp(r'(^|\s)(tree|free|tri)(\s|$)').hasMatch(value)) return 'kn';
    return null;
  }

  static bool isYes(String text) {
    return _containsAny(normalize(text), [
      'yes', 'yeah', 'yep', 'correct', 'confirm', 'okay', 'ok',
      'haan', 'हां', 'हाँ', 'howdu', 'ಹೌದು',
    ]);
  }

  static bool isNo(String text) {
    return _containsAny(normalize(text), [
      'no', 'nope', 'wrong', 'again', 'change', 'nah', 'nahi',
      'नहीं', 'illa', 'ಇಲ್ಲ',
    ]);
  }

  static bool _containsAny(String value, List<String> candidates) {
    for (final candidate in candidates) {
      if (value == candidate ||
          value.contains(' $candidate ') ||
          value.startsWith('$candidate ') ||
          value.endsWith(' $candidate')) {
        return true;
      }
    }
    return false;
  }
}
