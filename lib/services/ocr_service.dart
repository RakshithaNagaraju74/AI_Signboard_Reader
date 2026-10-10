import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};
  String? _fullFrameCachePath;
  TextRecognitionScript? _fullFrameCacheScript;
  List<_OCRBlock> _fullFrameCacheBlocks = [];

  TextRecognizer _recognizerFor(TextRecognitionScript script) =>
      _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));

  Future<String> extractText(
    File imageFile,
    List<double> bbox, {
    String languageCode = 'en',
  }) async {
    final normalizedLanguage = languageCode.toLowerCase();
    final script = normalizedLanguage == 'hi'
        ? TextRecognitionScript.devanagiri
        : TextRecognitionScript.latin;

    if (bbox.length < 4) return '';

    try {
      final decoded = img.decodeImage(await imageFile.readAsBytes());
      if (decoded == null) return '';
      final image = img.bakeOrientation(decoded);
      final crop = _safeCrop(image, bbox);
      if (crop == null) return await _recognizeFullImage(image, script);

      // Keep full-frame OCR as one candidate, but do not return it immediately.
      // A partial full-frame result can be worse than OCR on the enlarged sign crop.
      final candidates = <_OCRCandidate>[];
      final fullFrameText = await _recognizeBlocksNearBox(
        imageFile.path,
        image,
        bbox,
        script,
      );
      if (fullFrameText.isNotEmpty) {
        candidates.add(_OCRCandidate(
          text: fullFrameText,
          variant: -1,
          score: _score(fullFrameText),
        ));
      }

      final variants = _buildVariants(crop);
      final recognizer = _recognizerFor(script);

      for (var i = 0; i < variants.length; i++) {
        final tempFile = File(
          '${Directory.systemTemp.path}/s2s_ocr_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
        );

        try {
          await tempFile.writeAsBytes(
            img.encodeJpg(variants[i], quality: 96),
            flush: true,
          );
          final recognized = await recognizer.processImage(
            InputImage.fromFile(tempFile),
          );
          final cleaned = _normalizeOCRText(recognized.text);
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

      if (candidates.isEmpty) {
        debugPrint('OCR: sign crop returned no text; trying full frame.');
        return await _recognizeFullImage(image, script);
      }
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

  Future<String> _recognizeFullImage(
    img.Image image,
    TextRecognitionScript script,
  ) async {
    final recognizer = _recognizerFor(script);
    final variants = _buildVariants(_upscaleForText(image));
    final candidates = <_OCRCandidate>[];

    for (var i = 0; i < variants.length; i++) {
      final tempFile = File(
        '${Directory.systemTemp.path}/s2s_full_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
      );
      try {
        await tempFile.writeAsBytes(
          img.encodeJpg(variants[i], quality: 96),
          flush: true,
        );
        final result = await recognizer.processImage(InputImage.fromFile(tempFile));
        final text = _normalizeOCRText(result.text);
        if (text.isNotEmpty) {
          candidates.add(_OCRCandidate(text: text, variant: i, score: _score(text)));
        }
      } catch (e) {
        debugPrint('Full-image OCR variant $i failed: $e');
      } finally {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    }

    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.text;
  }

  img.Image? _safeCrop(img.Image image, List<double> bbox) {
    var x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
    if (x2 <= x1 || y2 <= y1) return null;

    final width = x2 - x1;
    final height = y2 - y1;

    // Decorative/stylized lettering often extends close to the sign edge.
    // A little more context helps keep whole words and punctuation in the crop.
    final padX = width * 0.18;
    final padY = height * 0.28;

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

  Future<String> _recognizeBlocksNearBox(
    String sourcePath,
    img.Image image,
    List<double> bbox,
    TextRecognitionScript script,
  ) async {
    try {
      if (_fullFrameCachePath != sourcePath ||
          _fullFrameCacheScript != script) {
        final recognizer = _recognizerFor(script);
        final tempFile = File(
          Directory.systemTemp.path + '/s2s_ocr_full_' +
              DateTime.now().microsecondsSinceEpoch.toString() + '.jpg',
        );

        try {
          await tempFile.writeAsBytes(
            img.encodeJpg(image, quality: 98),
            flush: true,
          );
          final result = await recognizer.processImage(
            InputImage.fromFile(tempFile),
          );

          _fullFrameCacheBlocks = result.blocks
              .map(
                (block) => _OCRBlock(
                  text: _normalizeOCRText(block.text),
                  box: block.boundingBox,
                ),
              )
              .where((block) => block.text.isNotEmpty)
              .toList();
          _fullFrameCachePath = sourcePath;
          _fullFrameCacheScript = script;
        } finally {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
        }
      }

      final target = ui.Rect.fromLTRB(
        bbox[0], bbox[1], bbox[2], bbox[3],
      );
      final matching = <String>[];
      for (final block in _fullFrameCacheBlocks) {
        final intersection = target.intersect(block.box);
        final targetArea = target.width * target.height;
        final intersectionArea =
            intersection.width > 0 && intersection.height > 0
                ? intersection.width * intersection.height
                : 0.0;
        final overlap = targetArea <= 0
            ? 0.0
            : intersectionArea / targetArea;
        if (overlap >= 0.08 || target.contains(block.box.center)) {
          matching.add(block.text);
        }
      }
      return _normalizeOCRText(matching.join(' '));
    } catch (e) {
      debugPrint('OCR full-frame block matching failed: ' + e.toString());
      return '';
    }
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

    // Signboards vary widely: thin decorative lettering, glossy paint,
    // shadows, bright backgrounds and low-light captures all benefit from
    // different image preparations. Keep the original in every OCR batch.
    final softContrast = img.adjustColor(
      gray,
      contrast: 1.25,
      brightness: 1.04,
    );
    final mediumContrast = img.adjustColor(
      gray,
      contrast: 1.65,
      brightness: 1.02,
    );
    final strongContrast = img.adjustColor(
      gray,
      contrast: 2.25,
      brightness: 1.06,
    );
    final darkText = img.adjustColor(
      gray,
      contrast: 1.85,
      brightness: 0.88,
    );
    final brightText = img.adjustColor(
      gray,
      contrast: 1.75,
      brightness: 1.16,
    );

    // Multiple passes help the recognizer with stylized, thin, low-contrast
    // and light-on-dark fonts without introducing a new native dependency.
    return [
      crop,
      gray,
      softContrast,
      mediumContrast,
      strongContrast,
      darkText,
      brightText,
      img.invert(strongContrast),
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

  String _normalizeOCRText(String text) {
    var value = _cleanText(text);
    if (value.isEmpty) return '';

    // Repair common ML OCR substitutions without trying to invent text.
    final replacements = <String, String>{
      'pharnacy': 'pharmacy',
      'pharmasy': 'pharmacy',
      'pharmecy': 'pharmacy',
      'pharmcy': 'pharmacy',
      'med1cal': 'medical',
      'medlcal': 'medical',
      'h0spital': 'hospital',
      'hospita1': 'hospital',
      'restarunt': 'restaurant',
      'resturant': 'restaurant',
      'restraunt': 'restaurant',
      'bakary': 'bakery',
      'bakkery': 'bakery',
      'supermarke': 'supermarket',
      'martket': 'market',
      'park1ng': 'parking',
      'parklng': 'parking',
      'sch00l': 'school',
    };

    final words = value.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length; i++) {
      final key = words[i].toLowerCase();
      final corrected = replacements[key];
      if (corrected != null) {
        words[i] = corrected;
      }
    }
    value = words.join(' ');

    // ML OCR often separates letters in a sign name.
    final parts = value.split(' ');
    if (parts.length >= 4 && parts.every(_isSingleAsciiLetter)) {
      final compact = parts.join().toLowerCase();
      const knownWords = <String, String>{
        'pharmacy': 'pharmacy',
        'hospital': 'hospital',
        'medical': 'medical',
        'parking': 'parking',
        'school': 'school',
        'restaurant': 'restaurant',
        'bakery': 'bakery',
        'market': 'market',
        'railway': 'railway',
      };
      value = knownWords[compact] ?? value;
    }

    return value;
  }

  bool _isSingleAsciiLetter(String value) {
    if (value.length != 1) return false;
    final code = value.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
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

class _OCRBlock {
  final String text;
  final ui.Rect box;

  const _OCRBlock({
    required this.text,
    required this.box,
  });
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
