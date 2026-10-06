import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  String _languageCode = 'en-US';

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _flutterTts.setSpeechRate(0.48);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    try {
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (_) {}
    try {
      await _flutterTts.setLanguage(_languageCode);
    } catch (_) {}
    _isInitialized = true;
  }

  Future<void> setLanguage(String languageCode) async {
    if (!_isInitialized) await initialize();
    _languageCode = languageCode;
    try {
      await _flutterTts.setLanguage(languageCode);
    } catch (_) {}
  }

  String get languageCode => _languageCode;

  Future<void> speak(String text, {bool interrupt = true}) async {
    final message = _prepareForSpeech(text);
    if (message.isEmpty) return;
    if (!_isInitialized) await initialize();
    if (interrupt) {
      try { await _flutterTts.stop(); } catch (_) {}
    }
    await _flutterTts.speak(message);
  }

  String _prepareForSpeech(String text) {
    var value = text.trim();

    // Android TTS can interpret a six-digit PIN or a long phone number as
    // one large quantity. Keep the exact digits but add speech-only spacing.
    // The visible UI and history continue to use the original text.
    value = value.replaceAllMapped(
      RegExp(r'\b\d{6}\b'),
      (match) => match.group(0)!.split('').join(' '),
    );

    value = value.replaceAllMapped(
      RegExp(r'\b\d{10,12}\b'),
      (match) => match.group(0)!.split('').join(' '),
    );

    return value;
  }

  Future<void> stop() async {
    try { await _flutterTts.stop(); } catch (_) {}
  }

  Future<void> pause() async {
    try { await _flutterTts.pause(); } catch (_) {}
  }
}
