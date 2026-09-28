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
    try { await _flutterTts.setLanguage(_languageCode); } catch (_) {}
    _isInitialized = true;
  }

  Future<void> setLanguage(String languageCode) async {
    _languageCode = languageCode;
    try { await _flutterTts.setLanguage(languageCode); } catch (_) {}
  }

  String get languageCode => _languageCode;

  Future<void> speak(String text, {bool interrupt = true}) async {
    final message = text.trim();
    if (message.isEmpty) return;
    if (!_isInitialized) await initialize();
    if (interrupt) await _flutterTts.stop();
    await _flutterTts.speak(message);
  }

  Future<void> stop() async => _flutterTts.stop();
  Future<void> pause() async { try { await _flutterTts.pause(); } catch (_) {} }
}
