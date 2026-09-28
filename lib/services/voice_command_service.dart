import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  Future<bool> initialize() async {
    if (_available) return true;
    _available = await _speech.initialize(onError: (_) {}, onStatus: (_) {});
    return _available;
  }

  Future<String?> listen({required String localeId, Duration timeout = const Duration(seconds:5)}) async {
    if (!await initialize()) return null;
    final c = Completer<String?>();
    await _speech.listen(
      localeId: localeId,
      listenFor: timeout,
      pauseFor: const Duration(seconds:2),
      onResult: (r) { if (r.finalResult && !c.isCompleted) c.complete(r.recognizedWords); },
    );
    final result = await c.future.timeout(timeout + const Duration(seconds:1), onTimeout:()=>null);
    await stop();
    return result;
  }

  Future<void> stop() async { try { await _speech.stop(); } catch (_) {} }
}
