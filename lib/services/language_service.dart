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
    AppLanguage(
      code: 'en',
      speechLocale: 'en-US',
      name: 'English',
    ),
    AppLanguage(
      code: 'hi',
      speechLocale: 'hi-IN',
      name: 'Hindi',
    ),
    AppLanguage(
      code: 'kn',
      speechLocale: 'kn-IN',
      name: 'Kannada',
    ),
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
    for (final language in languages) {
      if (language.code == code) return language;
    }
    return null;
  }

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'[^a-zA-Z\u0900-\u097F\u0C80-\u0CFF ]',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Converts common speech-recognition mishearings into a language choice.
  /// The first three numeric choices are intentionally supported because
  /// they are generally easier for speech recognition than language names.
  static String? detectCommand(String text) {
    final value = normalize(text);

    if (value.isEmpty) return null;

    // English / choice 1
    if (_containsAny(value, [
      'english',
      'england',
      'inglish',
      'in glish',
      'one',
      'number one',
      'option one',
      'first',
      '1',
    ])) {
      return 'en';
    }

    // Hindi / choice 2
    if (_containsAny(value, [
      'hindi',
      'hindee',
      'hindy',
      'indie',
      'indi',
      'hindi language',
      'two',
      'number two',
      'option two',
      'second',
      '2',
      'हिंदी',
      'हिन्दी',
    ])) {
      return 'hi';
    }

    // Kannada / choice 3.
    // "Canada"/"canada" is a frequent English recognition result for Kannada.
    if (_containsAny(value, [
      'kannada',
      'kanada',
      'canada',
      'can adda',
      'kannad',
      'kannada language',
      'three',
      'number three',
      'option three',
      'third',
      '3',
      'ಕನ್ನಡ',
    ])) {
      return 'kn';
    }

    return null;
  }

  static bool _containsAny(
    String value,
    List<String> candidates,
  ) {
    for (final candidate in candidates) {
      if (value == candidate ||
          value.contains(' ' + candidate + ' ') ||
          value.startsWith(candidate + ' ') ||
          value.endsWith(' ' + candidate)) {
        return true;
      }
    }
    return false;
  }
}
