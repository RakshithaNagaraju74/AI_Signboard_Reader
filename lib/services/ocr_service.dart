import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  TextRecognizer _recognizerFor(TextRecognitionScript script) =>
      _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));

  Future<String> extractText(File imageFile, List<double> bbox, {
    String languageCode = 'en',
  }) async {
    final script = languageCode.toLowerCase() == 'hi'
        ? TextRecognitionScript.devanagiri
        : TextRecognitionScript.latin;
    if (bbox.length < 4) return '';
    try {
      final image = img.decodeImage(await imageFile.readAsBytes());
      if (image == null) return '';
      var x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
      if (x2 <= x1 || y2 <= y1) return '';
      const padding = 8.0;
      x1 = (x1 - padding).clamp(0.0, image.width.toDouble());
      y1 = (y1 - padding).clamp(0.0, image.height.toDouble());
      x2 = (x2 + padding).clamp(0.0, image.width.toDouble());
      y2 = (y2 + padding).clamp(0.0, image.height.toDouble());
      final cropWidth = (x2 - x1).round();
      final cropHeight = (y2 - y1).round();
      if (cropWidth < 12 || cropHeight < 12) return '';
      final cropped = img.copyCrop(image, x1.round(), y1.round(), cropWidth, cropHeight);
      final largest = cropped.width > cropped.height ? cropped.width : cropped.height;
      final scale = largest < 500 ? 2.0 : (1200 / largest).clamp(1.0, 2.0);
      final enlarged = scale == 1.0 ? cropped : img.copyResize(cropped,
        width: (cropped.width * scale).round(),
        height: (cropped.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
      final tempFile = File(Directory.systemTemp.path + '/ocr_' + DateTime.now().microsecondsSinceEpoch.toString() + '.jpg');
      try {
        await tempFile.writeAsBytes(img.encodeJpg(enlarged, quality: 82), flush: false);
        final recognized = await _recognizerFor(script).processImage(InputImage.fromFile(tempFile));
        return _cleanText(recognized.text);
      } finally {
        try { if (await tempFile.exists()) await tempFile.delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('OCR error: $e');
      return '';
    }
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