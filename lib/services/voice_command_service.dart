import 'dart:async';

import 'package:flutter/foundation.dart';
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
        onStatus: (status) => debugPrint('STT status: $status'),
      );
    } catch (e) {
      debugPrint('STT initialization failed: $e');
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
      final preferredIds = <String>{
        requested,
        if (base == 'en') 'en-IN',
        if (base == 'hi') 'hi-IN',
        if (base == 'kn') 'kn-IN',
        if (base == 'en') 'en-US',
        if (base == 'hi') 'hi',
        if (base == 'kn') 'kn',
      };
      String? effectiveLocale;

      for (final preferred in preferredIds) {
        for (final locale in locales) {
          final id = locale.localeId.toLowerCase().replaceAll('_', '-');
          if (id == preferred) {
            effectiveLocale = locale.localeId;
            break;
          }
        }
        if (effectiveLocale != null) break;
      }

      effectiveLocale ??= locales
          .where((l) => l.localeId
              .toLowerCase()
              .replaceAll('_', '-')
              .startsWith('$base-'))
          .map((l) => l.localeId)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);

      effectiveLocale ??=
          locales.isNotEmpty ? locales.first.localeId : localeId;

      debugPrint('STT requested=$localeId effective=$effectiveLocale');

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            latestWords = words;
            debugPrint('STT recognized: $latestWords');
          }

          if (result.finalResult && !completer.isCompleted) {
            completer.complete(latestWords.isEmpty ? null : latestWords);
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

      return await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => latestWords.isEmpty ? null : latestWords,
      );
    } catch (e) {
      debugPrint('STT listen failed: $e');
      return latestWords.isEmpty ? null : latestWords;
    } finally {
      try {
        await _speech.stop();
      } catch (_) {}

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
