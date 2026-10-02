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
      _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));

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
      final crop = _safeCrop(image, bbox);
      if (crop == null) return '';

      final variants = _buildVariants(crop);
      final recognizer = _recognizerFor(script);
      final candidates = <_OCRCandidate>[];

      for (var i = 0; i < variants.length; i++) {
        final tempFile = File(
          '\${Directory.systemTemp.path}/s2s_ocr_'
          '\${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
        );

        try {
          await tempFile.writeAsBytes(
            img.encodeJpg(variants[i], quality: 96),
            flush: true,
          );
          final recognized = await recognizer.processImage(
            InputImage.fromFile(tempFile),
          );
          final cleaned = _cleanText(recognized.text);
          if (cleaned.isNotEmpty) {
            candidates.add(_OCRCandidate(
              text: cleaned,
              variant: i,
              score: _score(cleaned),
            ));
          }
        } catch (e) {
          debugPrint('OCR variant $i failed: $e');
        } finally {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
        }
      }

      if (candidates.isEmpty) return '';
      candidates.sort((a, b) => b.score.compareTo(a.score));
      final best = candidates.first;

      for (final candidate in candidates.skip(1)) {
        if (_similar(candidate.text, best.text) >= 0.72) {
          return _preferReadable(best.text, candidate.text);
        }
      }
      return best.text;
    } catch (e) {
      debugPrint('OCR error: $e');
      return '';
    }
  }

  img.Image? _safeCrop(img.Image image, List<double> bbox) {
    var x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
    if (x2 <= x1 || y2 <= y1) return null;

    final width = x2 - x1;
    final height = y2 - y1;
    final padX = width * 0.12;
    final padY = height * 0.20;

    x1 = (x1 - padX).clamp(0.0, image.width.toDouble());
    y1 = (y1 - padY).clamp(0.0, image.height.toDouble());
    x2 = (x2 + padX).clamp(0.0, image.width.toDouble());
    y2 = (y2 + padY).clamp(0.0, image.height.toDouble());

    final cropWidth = (x2 - x1).round();
    final cropHeight = (y2 - y1).round();
    if (cropWidth < 12 || cropHeight < 12) return null;

    return _upscaleForText(
      img.copyCrop(
        image,
        x1.round(),
        y1.round(),
        cropWidth,
        cropHeight,
      ),
    );
  }

  img.Image _upscaleForText(img.Image source) {
    final targetHeight = source.height < 180
        ? 600
        : source.height < 320
            ? 720
            : source.height;
    final scale = (targetHeight / source.height).clamp(1.0, 3.5).toDouble();
    if (scale <= 1.01) return source;

    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  List<img.Image> _buildVariants(img.Image crop) {
    final gray = img.grayscale(crop);
    return [
      crop,
      gray,
      img.adjustColor(gray, contrast: 1.35, brightness: 1.02),
      img.adjustColor(gray, contrast: 1.75, brightness: 1.00),
      img.adjustColor(gray, contrast: 2.15, brightness: 1.05),
    ];
  }

  double _score(String text) {
    final value = _cleanText(text);
    if (value.isEmpty) return -1000;

    final compact = value.replaceAll(RegExp(r'\s+'), '');
    final readable = RegExp(r'[A-Za-z0-9\u0900-\u0CFF]')
        .allMatches(compact)
        .length;
    final ratio = compact.isEmpty ? 0.0 : readable / compact.length;
    final words = value.split(' ').where((e) => e.isNotEmpty).length;
    final suspicious = RegExp(
      r'[^A-Za-z0-9\u0900-\u0CFF\s.,:/&()\-+#%]',
    ).allMatches(value).length;

    return (compact.length * 0.55) +
        (ratio * 28.0) +
        (words * 2.0) -
        (suspicious * 3.0);
  }

  double _similar(String a, String b) {
    final x = _normalizeForComparison(a);
    final y = _normalizeForComparison(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;

    final maxLength = x.length > y.length ? x.length : y.length;
    return 1.0 - (_levenshtein(x, y) / maxLength);
  }

  String _preferReadable(String a, String b) =>
      _score(b) > _score(a) ? b : a;

  int _levenshtein(String a, String b) {
    final row = List<int>.generate(b.length + 1, (i) => i);

    for (var i = 0; i < a.length; i++) {
      var diagonal = row[0];
      row[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final above = row[j + 1];
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        row[j + 1] = [
          row[j + 1] + 1,
          row[j] + 1,
          diagonal + cost,
        ].reduce((x, y) => x < y ? x : y);
        diagonal = above;
      }
    }
    return row[b.length];
  }

  String _normalizeForComparison(String text) {
    return _cleanText(text)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u0CFF]'), '');
  }

  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> dispose() async {
    for (final recognizer in _recognizers.values) {
      try {
        await recognizer.close();
      } catch (_) {}
    }
    _recognizers.clear();
  }
}

class _OCRCandidate {
  final String text;
  final int variant;
  final double score;

  const _OCRCandidate({
    required this.text,
    required this.variant,
    required this.score,
  });
}
