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
          if (error.permanent && _activeCompleter != null) {
            final completer = _activeCompleter!;
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onStatus: (_) {},
      );
    } catch (_) {
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
      final supportedIds = locales.map((locale) => locale.localeId).toSet();

      var effectiveLocale = localeId;
      if (!supportedIds.contains(effectiveLocale)) {
        final base = localeId.split(RegExp(r'[-_]')).first.toLowerCase();
        final matching = locales.where(
          (locale) =>
              locale.localeId.toLowerCase() == base ||
              locale.localeId.toLowerCase().startsWith('${base}-') ||
              locale.localeId.toLowerCase().startsWith('${base}_'),
        );

        if (matching.isNotEmpty) {
          effectiveLocale = matching.first.localeId;
        } else if (locales.isNotEmpty) {
          effectiveLocale = locales.first.localeId;
        }
      }

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) latestWords = words;

          if (result.finalResult &&
              latestWords.isNotEmpty &&
              !completer.isCompleted) {
            completer.complete(latestWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: effectiveLocale,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: false,
        ),
      );

      final result = await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => latestWords.isEmpty ? null : latestWords,
      );

      await stop();
      return result;
    } catch (_) {
      await stop();
      return latestWords.isEmpty ? null : latestWords;
    } finally {
      if (identical(_activeCompleter, completer)) {
        _activeCompleter = null;
      }
    }
  }

  Future<void> stop() async {
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }

    try {
      await _speech.stop();
    } catch (_) {}
  }
}
