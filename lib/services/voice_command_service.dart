import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();

  bool _available = false;
  Completer<String?>? _activeCompleter;

  Future<bool> initialize() async {
    if (_available) return true;

    _available = await _speech.initialize(
      onError: (_) {
        final completer = _activeCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(null);
        }
      },
      onStatus: (_) {},
    );

    return _available;
  }

  Future<String?> listen({
    required String localeId,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!await initialize()) return null;

    await stop();

    final completer = Completer<String?>();
    _activeCompleter = completer;
    var latestWords = '';

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            latestWords = words;
          }

          if (result.finalResult &&
              latestWords.isNotEmpty &&
              !completer.isCompleted) {
            completer.complete(latestWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: false,
        ),
      );

      final result = await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () =>
            latestWords.isEmpty ? null : latestWords,
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
