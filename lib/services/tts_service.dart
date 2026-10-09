import 'package:flutter/foundation.dart';
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

    final requested = languageCode.trim();
    _languageCode = requested;

    try {
      var available = false;
      try {
        available = (await _flutterTts.isLanguageAvailable(requested)) == true;
      } catch (error) {
        debugPrint('[TTS] language availability check failed: ' + error.toString());
      }

      await _flutterTts.setLanguage(requested);

      try {
        final rawVoices = await _flutterTts.getVoices;
        final voices = rawVoices
            .whereType<Map>()
            .map((voice) => Map<String, String>.from(
                  voice.map(
                    (key, value) => MapEntry(key.toString(), value.toString()),
                  ),
                ))
            .toList();

        final normalized = requested.toLowerCase().replaceAll('_', '-');
        final base = normalized.split('-').first;
        final matching = voices.where((voice) {
          final locale = (voice['locale'] ?? '').toLowerCase().replaceAll('_', '-');
          return locale == normalized || locale.startsWith(base + '-');
        }).toList();

        if (matching.isNotEmpty) {
          await _flutterTts.setVoice(matching.first);
          debugPrint(
            '[TTS] selected voice=' +
                (matching.first['name'] ?? '') +
                ' locale=' +
                (matching.first['locale'] ?? '') +
                ' for ' +
                requested,
          );
        } else {
          debugPrint(
            '[TTS] no explicit voice found for ' +
                requested +
                '; available=' +
                available.toString(),
          );
        }
      } catch (error) {
        debugPrint('[TTS] voice selection failed: ' + error.toString());
      }

      debugPrint(
        '[TTS] language set to ' +
            requested +
            ', available=' +
            available.toString(),
      );
    } catch (error) {
      debugPrint('[TTS] setLanguage failed: ' + error.toString());
    }
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
