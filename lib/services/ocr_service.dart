import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  TextRecognizer _recognizerFor(TextRecognitionScript script) =>
      _recognizers.putIfAbsent(
        script,
        () => TextRecognizer(script: script),
      );

  Future<String> extractText(
    File imageFile,
    List<double> bbox, {
    String languageCode = 'en',
  }) async {
    final script = languageCode.toLowerCase() == 'hi'
        ? TextRecognitionScript.devanagiri
        : TextRecognitionScript.latin;

    if (bbox.length < 4) return '';

    try {
      final decoded = img.decodeImage(await imageFile.readAsBytes());
      if (decoded == null) return '';

      final image = img.bakeOrientation(decoded);
      var x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
      if (x2 <= x1 || y2 <= y1) return '';

      final padX = (x2 - x1) * 0.10;
      final padY = (y2 - y1) * 0.16;
      x1 = (x1 - padX).clamp(0.0, image.width.toDouble());
      y1 = (y1 - padY).clamp(0.0, image.height.toDouble());
      x2 = (x2 + padX).clamp(0.0, image.width.toDouble());
      y2 = (y2 + padY).clamp(0.0, image.height.toDouble());

      final cropWidth = (x2 - x1).round();
      final cropHeight = (y2 - y1).round();
      if (cropWidth < 12 || cropHeight < 12) return '';

      final cropped = img.copyCrop(
        image, x1.round(), y1.round(), cropWidth, cropHeight,
      );

      final largest = cropped.width > cropped.height
          ? cropped.width
          : cropped.height;
      final scale = largest < 700
          ? 3.0
          : (1600 / largest).clamp(1.0, 2.5);

      final enlarged = scale == 1.0
          ? cropped
          : img.copyResize(
              cropped,
              width: (cropped.width * scale).round(),
              height: (cropped.height * scale).round(),
              interpolation: img.Interpolation.cubic,
            );

      final variants = <img.Image>[
        enlarged,
        img.grayscale(enlarged),
        img.adjustColor(
          img.grayscale(enlarged),
          contrast: 1.55,
          brightness: 1.04,
        ),
      ];

      final recognizer = _recognizerFor(script);
      var bestText = '';
      var bestScore = -1.0;

      for (var i = 0; i < variants.length; i++) {
        final tempFile = File(
          '${Directory.systemTemp.path}/ocr_'
          '${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
        );

        try {
          await tempFile.writeAsBytes(
            img.encodeJpg(variants[i], quality: 94),
            flush: false,
          );
          final recognized = await recognizer.processImage(
            InputImage.fromFile(tempFile),
          );
          final cleaned = _cleanText(recognized.text);
          final score = _score(cleaned);
          if (score > bestScore) {
            bestScore = score;
            bestText = cleaned;
          }
        } catch (e) {
          debugPrint('OCR variant $i failed: $e');
        } finally {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
        }
      }

      return bestText;
    } catch (e) {
      debugPrint('OCR error: $e');
      return '';
    }
  }

  double _score(String text) {
    if (text.trim().isEmpty) return 0;
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    final matches = RegExp(r'[A-Za-z0-9\u0900-\u0CFF]')
        .allMatches(compact)
        .length;
    final ratio = compact.isEmpty ? 0 : matches / compact.length;
    return (compact.length * 0.7) + (ratio * 20);
  }

  String _cleanText(String text) => text
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> dispose() async {
    for (final recognizer in _recognizers.values) {
      try { await recognizer.close(); } catch (_) {}
    }
    _recognizers.clear();
  }
}
