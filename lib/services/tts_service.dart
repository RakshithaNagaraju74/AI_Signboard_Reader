
import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance =
      TTSService._internal();

  factory TTSService() => _instance;

  TTSService._internal();

  final FlutterTts _flutterTts =
      FlutterTts();

  bool _isInitialized = false;
  bool _isSpeaking = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Stop anything currently speaking.
    await _flutterTts.stop();

    _isSpeaking = true;

    try {
      await _flutterTts.speak(text);
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;
}
