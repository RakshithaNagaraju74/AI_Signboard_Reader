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
  List<List<_OCRBlock>> _fullFrameVariantBlocks = [];

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

      // Let ML Kit's text detector inspect the whole oriented frame first.
      // We then keep only blocks that overlap this sign's YOLO box.
      final fullFrameText = await _recognizeBlocksNearBox(
        imageFile.path,
        image,
        bbox,
        script,
      );
      if (fullFrameText.isNotEmpty && _isPlausibleOCR(fullFrameText)) {
        debugPrint('OCR: matched full-frame text block(s): ' + fullFrameText);
        return fullFrameText;
      }

      if (fullFrameText.isNotEmpty) {
        debugPrint('OCR: rejecting low-quality full-frame text; trying sign crop variants.');
      }

      final variants = _buildVariants(crop);
      final recognizer = _recognizerFor(script);
      final candidates = <_OCRCandidate>[];

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

    // Give OCR a little more surrounding context. Signboards often have
    // multiple lines and the detector box can clip the first/last letters.
    // Keep the padding bounded so nearby background text is not pulled in.
    final padX = (width * 0.18).clamp(8.0, 90.0);
    final padY = (height * 0.30).clamp(10.0, 120.0);

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
          // Run a small set of same-size full-frame preprocessing passes.
          // Keeping the dimensions unchanged preserves ML Kit's bounding boxes,
          // so we can still match OCR blocks to the YOLO sign box.
          final fullFrameVariants = <img.Image>[
            image,
            img.adjustColor(
              img.grayscale(image),
              contrast: 1.45,
              brightness: 1.04,
              gamma: 0.90,
            ),
            img.convolution(
              img.grayscale(image),
              <num>[
                0, -1, 0,
                -1, 5, -1,
                0, -1, 0,
              ],
              div: 1.0,
            ),
          ];

          _fullFrameVariantBlocks = [];

          for (var variantIndex = 0;
              variantIndex < fullFrameVariants.length;
              variantIndex++) {
            final variantFile = File(
              Directory.systemTemp.path + '/s2s_ocr_full_' +
                  DateTime.now().microsecondsSinceEpoch.toString() +
                  '_v' +
                  variantIndex.toString() +
                  '.jpg',
            );

            try {
              await variantFile.writeAsBytes(
                img.encodeJpg(fullFrameVariants[variantIndex], quality: 98),
                flush: true,
              );
              final result = await recognizer.processImage(
                InputImage.fromFile(variantFile),
              );

              final blocks = result.blocks
                  .map(
                    (block) => _OCRBlock(
                      text: _normalizeOCRText(block.text),
                      box: block.boundingBox,
                    ),
                  )
                  .where((block) => block.text.isNotEmpty)
                  .toList();

              _fullFrameVariantBlocks.add(blocks);
            } finally {
              try {
                if (await variantFile.exists()) {
                  await variantFile.delete();
                }
              } catch (_) {}
            }
          }

          _fullFrameCacheBlocks = _fullFrameVariantBlocks
              .expand((blocks) => blocks)
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
      final candidates = <_OCRCandidate>[];

      // Evaluate each full-frame preprocessing pass independently. This
      // prevents a weak raw pass from dominating a clearer grayscale/sharp
      // pass while still retaining the original image as a fallback.
      for (var variantIndex = 0;
          variantIndex < _fullFrameVariantBlocks.length;
          variantIndex++) {
        final matching = <String>[];

        for (final block in _fullFrameVariantBlocks[variantIndex]) {
          final intersection = target.intersect(block.box);
          final targetArea = target.width * target.height;
          final intersectionArea =
              intersection.width > 0 && intersection.height > 0
                  ? intersection.width * intersection.height
                  : 0.0;
          final overlap = targetArea <= 0
              ? 0.0
              : intersectionArea / targetArea;

          // Require meaningful overlap with the detected sign. A very
          // small overlap can accidentally attach unrelated background text
          // to the sign and is a common source of gibberish OCR.
          if (overlap >= 0.20 || target.contains(block.box.center)) {
            matching.add(block.text);
          }
        }

        final text = _normalizeOCRText(matching.join(' '));
        if (text.isNotEmpty) {
          candidates.add(
            _OCRCandidate(
              text: text,
              variant: variantIndex,
              score: _score(text),
            ),
          );
        }
      }

      if (candidates.isEmpty) return '';
      candidates.sort((a, b) => b.score.compareTo(a.score));
      return candidates.first.text;
    } catch (e) {
      debugPrint('OCR full-frame block matching failed: ' + e.toString());
      return '';
    }
  }

  img.Image _upscaleForText(img.Image source) {
    // ML Kit benefits when characters contain enough pixels. We upscale
    // small sign crops more aggressively, while keeping a hard limit so
    // mobile OCR does not become excessively slow or memory-heavy.
    final targetHeight = source.height < 140
        ? 720
        : source.height < 220
            ? 840
            : source.height < 360
                ? 960
                : source.height;
    final scale = (targetHeight / source.height).clamp(1.0, 4.0).toDouble();
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

    // Keep several independent preprocessing paths. Different signboards
    // fail for different reasons: glare, shadows, low contrast, coloured
    // backgrounds, small characters, or slightly soft focus.
    final brighter = img.adjustColor(
      img.grayscale(crop),
      contrast: 1.25,
      brightness: 1.14,
      gamma: 0.82,
    );

    final darker = img.adjustColor(
      img.grayscale(crop),
      contrast: 1.35,
      brightness: 0.90,
      gamma: 1.18,
    );

    final mediumContrast = img.adjustColor(
      img.grayscale(crop),
      contrast: 1.60,
      brightness: 1.02,
    );

    final strongContrast = img.adjustColor(
      img.grayscale(crop),
      contrast: 2.20,
      brightness: 1.04,
    );

    // A mild 3x3 sharpening pass can restore character edges after camera
    // compression/resizing without changing the actual words.
    final sharpened = img.convolution(
      img.grayscale(crop),
      <num>[
        0, -1, 0,
        -1, 5, -1,
        0, -1, 0,
      ],
      div: 1.0,
    );

    final sharpenedContrast = img.adjustColor(
      img.convolution(
        img.grayscale(crop),
        <num>[
          0, -1, 0,
          -1, 5, -1,
          0, -1, 0,
        ],
        div: 1.0,
      ),
      contrast: 1.70,
      brightness: 1.03,
    );

    // Multi-pass OCR: preserve the original colour image, then try
    // luminance/brightness/contrast/gamma/sharpened/inverted representations.
    return [
      crop,
      gray,
      brighter,
      darker,
      mediumContrast,
      strongContrast,
      sharpened,
      sharpenedContrast,
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

  bool _isPlausibleOCR(String text) {
    final value = _cleanText(text);
    if (value.isEmpty) return false;

    // Reject obvious OCR hallucinations with repeated mixed-case fragments
    // while preserving normal business names, acronyms, numbers, and Indian
    // script text.
    final words = value.split(' ');
    var suspicious = 0;
    var asciiWords = 0;

    for (final word in words) {
      final cleaned = word.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (cleaned.isEmpty) continue;
      asciiWords++;

      if (RegExp(r'[A-Z]{3,}[a-z]+[A-Z]{2,}').hasMatch(cleaned)) {
        suspicious++;
        continue;
      }

      if (cleaned.length >= 10) {
        final letters = cleaned.replaceAll(RegExp(r'[^A-Za-z]'), '');
        if (letters.length >= 8) {
          final vowels = RegExp(r'[AEIOUaeiou]').allMatches(letters).length;
          if (vowels == 0) suspicious++;
        }
      }
    }

    // One suspicious word may be a genuine brand. Reject only when the
    // overall Latin OCR is dominated by suspicious fragments.
    return asciiWords < 3 || suspicious < 2 || suspicious < (asciiWords / 2);
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
