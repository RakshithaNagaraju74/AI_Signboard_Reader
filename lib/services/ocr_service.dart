
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();

  factory OCRService() => _instance;

  OCRService._internal();

  // ============================================================
  // EXTRACT TEXT FROM YOLO BOUNDING BOX
  //
  // bbox format:
  // [x1, y1, x2, y2]
  //
  // IMPORTANT:
  // TFLiteService already converts YOLO coordinates to
  // ORIGINAL IMAGE PIXELS.
  //
  // Therefore DO NOT multiply bbox coordinates again.
  // ============================================================

  Future<String> extractText(
    File imageFile,
    List<double> bbox,
  ) async {
    if (bbox.length < 4) {
      debugPrint('OCR: Invalid bbox length');
      return '';
    }

    File? tempFile;
    TextRecognizer? textRecognizer;

    try {
      // ----------------------------------------------------------
      // READ ORIGINAL IMAGE
      // ----------------------------------------------------------

      final imageBytes = await imageFile.readAsBytes();

      final image = img.decodeImage(imageBytes);

      if (image == null) {
        debugPrint('OCR: Could not decode image');
        return '';
      }

      debugPrint(
        'OCR original image: '
        '${image.width}x${image.height}',
      );

      debugPrint(
        'OCR YOLO bbox: $bbox',
      );

      // ----------------------------------------------------------
      // YOLO BBOX IS ALREADY IN PIXELS
      //
      // DO NOT DO:
      // bbox * image.width
      // bbox * image.height
      // ----------------------------------------------------------

      double x1 = bbox[0];
      double y1 = bbox[1];
      double x2 = bbox[2];
      double y2 = bbox[3];

      debugPrint(
        'OCR pixel bbox BEFORE padding: '
        '[$x1, $y1, $x2, $y2]',
      );

      // ----------------------------------------------------------
      // SAFETY CHECK
      // ----------------------------------------------------------

      if (x2 <= x1 || y2 <= y1) {
        debugPrint('OCR: Invalid bbox coordinates');
        return '';
      }

      // ----------------------------------------------------------
      // ADD PADDING
      //
      // A little extra area helps OCR capture text near edges.
      // ----------------------------------------------------------

      const double padding = 10.0;

      x1 = (x1 - padding).clamp(
        0.0,
        image.width.toDouble(),
      );

      y1 = (y1 - padding).clamp(
        0.0,
        image.height.toDouble(),
      );

      x2 = (x2 + padding).clamp(
        0.0,
        image.width.toDouble(),
      );

      y2 = (y2 + padding).clamp(
        0.0,
        image.height.toDouble(),
      );

      // ----------------------------------------------------------
      // INTEGER CROP COORDINATES
      // ----------------------------------------------------------

      final cropX = x1.round();
      final cropY = y1.round();

      final cropWidth = (x2 - x1).round();
      final cropHeight = (y2 - y1).round();

      debugPrint(
        'OCR crop: '
        'x=$cropX '
        'y=$cropY '
        'width=$cropWidth '
        'height=$cropHeight',
      );

      // ----------------------------------------------------------
      // CHECK CROP
      // ----------------------------------------------------------

      if (cropWidth < 10 || cropHeight < 10) {
        debugPrint('OCR: Crop is too small');
        return '';
      }

      // ----------------------------------------------------------
      // CROP IMAGE
      // ----------------------------------------------------------

      final cropped = img.copyCrop(
  image,
  cropX,
  cropY,
  cropWidth,
  cropHeight,
);

      debugPrint(
        'OCR cropped image: '
        '${cropped.width}x${cropped.height}',
      );

      // ----------------------------------------------------------
      // UPSCALE
      //
      // Small sign text becomes much easier for ML Kit to read.
      // ----------------------------------------------------------

      const int scale = 3;

      final enlarged = img.copyResize(
        cropped,
        width: cropped.width * scale,
        height: cropped.height * scale,
        interpolation: img.Interpolation.cubic,
      );

      debugPrint(
        'OCR enlarged image: '
        '${enlarged.width}x${enlarged.height}',
      );

      // ----------------------------------------------------------
      // SAVE TEMP IMAGE
      // ----------------------------------------------------------

      final tempDir = Directory.systemTemp;

      tempFile = File(
        '${tempDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      await tempFile.writeAsBytes(
        img.encodeJpg(
          enlarged,
          quality: 95,
        ),
        flush: true,
      );

      debugPrint(
        'OCR temp file: ${tempFile.path}',
      );

      // ----------------------------------------------------------
      // ML KIT OCR
      // ----------------------------------------------------------

      final inputImage = InputImage.fromFile(
        tempFile,
      );

      textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final recognizedText =
          await textRecognizer.processImage(
        inputImage,
      );

      final text = recognizedText.text.trim();

      debugPrint(
        'ML KIT OCR RESULT: "$text"',
      );

      // ----------------------------------------------------------
      // CLEAN RESULT
      // ----------------------------------------------------------

      final cleaned = _cleanText(text);

      debugPrint(
        'CLEAN OCR RESULT: "$cleaned"',
      );

      return cleaned;
    } catch (e, stackTrace) {
      debugPrint(
        'OCR ERROR: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      return '';
    } finally {
      // ----------------------------------------------------------
      // CLOSE OCR
      // ----------------------------------------------------------

      if (textRecognizer != null) {
        try {
          await textRecognizer.close();
        } catch (_) {}
      }

      // ----------------------------------------------------------
      // DELETE TEMP FILE
      // ----------------------------------------------------------

      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  // ============================================================
  // CLEAN OCR TEXT
  // ============================================================

  String _cleanText(String text) {
    if (text.trim().isEmpty) {
      return '';
    }

    return text
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
