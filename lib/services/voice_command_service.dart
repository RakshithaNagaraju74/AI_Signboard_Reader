import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();

  bool _available = false;
  Completer<String?>? _activeCompleter;

  Future<bool> initialize() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (error) {
          final completer = _activeCompleter;
          if (completer != null && !completer.isCompleted && error.permanent) {
            completer.complete(null);
          }
        },
        onStatus: (status) => print('STT status: $status'),
      );
    } catch (e) {
      print('STT initialization failed: $e');
      _available = false;
    }
    return _available;
  }

  Future<String?> listen({
    required String localeId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await initialize()) return null;
    await stop();

    final completer = Completer<String?>();
    _activeCompleter = completer;
    var latestWords = '';

    try {
      final locales = await _speech.locales();
      final requested = localeId.toLowerCase().replaceAll('_', '-');
      final base = requested.split('-').first;
      String? effectiveLocale;

      for (final locale in locales) {
        final id = locale.localeId.toLowerCase().replaceAll('_', '-');
        if (id == requested) { effectiveLocale = locale.localeId; break; }
      }
      effectiveLocale ??= locales
          .where((l) => l.localeId.toLowerCase().replaceAll('_', '-').startsWith('$base-'))
          .map((l) => l.localeId)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
      effectiveLocale ??= locales.isNotEmpty ? locales.first.localeId : localeId;

      print('STT requested=$localeId effective=$effectiveLocale');

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            latestWords = words;
            print('STT recognized: $latestWords');
          }
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(latestWords.isEmpty ? null : latestWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: effectiveLocale,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: false,
        ),
      );

      return await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => latestWords.isEmpty ? null : latestWords,
      );
    } catch (e) {
      print('STT listen failed: $e');
      return latestWords.isEmpty ? null : latestWords;
    } finally {
      try { await _speech.stop(); } catch (_) {}
      if (identical(_activeCompleter, completer)) _activeCompleter = null;
    }
  }

  Future<void> stop() async {
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(null);
    try { await _speech.stop(); } catch (_) {}
  }
}
