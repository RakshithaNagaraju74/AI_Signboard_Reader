import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  Future<bool> initialize() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    return _available;
  }

  Future<String?> listen({
    required String localeId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await initialize()) return null;

    final completer = Completer<String?>();

    await _speech.listen(
<<<<<<< HEAD
      onResult: (r) { if (r.finalResult && !c.isCompleted) c.complete(r.recognizedWords); },
=======
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
      options: SpeechListenOptions(
        localeId: localeId,
        listenFor: timeout,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      ),
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
    );

    final result = await completer.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );

    await stop();
    return result;
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }
}
