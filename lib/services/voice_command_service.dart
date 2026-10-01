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
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await initialize()) return null;

    await stop();

    final completer = Completer<String?>();
    _activeCompleter = completer;

    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
        ),
      );

      final result = await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => null,
      );

      await stop();
      return result;
    } catch (_) {
      await stop();
      return null;
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
