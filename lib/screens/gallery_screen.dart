
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/sign_model.dart';
import '../services/tflite_service.dart';
import '../services/tts_service.dart';
import '../services/ocr_service.dart';
import '../screens/result_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() =>
      _GalleryScreenState();
}

class _GalleryScreenState
    extends State<GalleryScreen> {
  bool _isProcessing = false;

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> _pickAndDetectImage() async {
    if (_isProcessing) return;

    final picker = ImagePicker();

    final pickedFile =
        await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 90,
    );

    if (pickedFile == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final file =
          File(pickedFile.path);

      await _processImage(file);
    } catch (e) {
      debugPrint(
        'Gallery error: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // PROCESS IMAGE
  // ============================================================

  Future<void> _processImage(
    File imageFile,
  ) async {
    final tflite = TFLiteService();
    final tts = TTSService();
    final ocr = OCRService();

    final signModel =
        Provider.of<SignModel>(
      context,
      listen: false,
    );

    signModel.setProcessing(true);
    signModel.setImagePath(
      imageFile.path,
    );

    try {
      // --------------------------------------------------------
      // STEP 1: YOLO DETECTION
      // --------------------------------------------------------

      debugPrint(
        'Starting YOLO detection...',
      );

      final detections =
          await tflite.predictImage(
        imageFile,
      );

      debugPrint(
        'YOLO detections: '
        '${detections.length}',
      );

      // --------------------------------------------------------
      // NO DETECTION
      // --------------------------------------------------------

      if (detections.isEmpty) {
        await tts.stop();

        await tts.speak(
          'No sign detected in this image',
        );

        return;
      }

      // --------------------------------------------------------
      // IMPORTANT:
      // ONLY BEST DETECTION
      // NO LOOP
      // --------------------------------------------------------

      final bestDetection =
          detections.first;

      signModel.setDetections(
        [bestDetection],
      );

      final className =
          bestDetection.className;

      debugPrint(
        'BEST DETECTION: '
        '$className',
      );

      debugPrint(
        'CONFIDENCE: '
        '${bestDetection.confidence}',
      );

      debugPrint(
        'BBOX: '
        '${bestDetection.bbox}',
      );

      // --------------------------------------------------------
      // STEP 2: OCR
      // --------------------------------------------------------

      String ocrText = '';

      try {
        ocrText =
            await ocr.extractText(
          imageFile,
          bestDetection.bbox,
        );

        debugPrint(
          'OCR TEXT: "$ocrText"',
        );
      } catch (e) {
        debugPrint(
          'OCR failed: $e',
        );
      }

      // --------------------------------------------------------
      // STEP 3: SPEAK ONLY ONCE
      // --------------------------------------------------------

      await tts.stop();

      final readableName =
          _makeReadableClassName(
        className,
      );

      String speech;

      if (ocrText.trim().isNotEmpty) {
        speech =
            '$readableName detected. '
            'The text says $ocrText';
      } else {
        speech =
            '$readableName detected. '
            'No readable text found.';
      }

      debugPrint(
        'FINAL SPEECH: $speech',
      );

      // ONE TTS CALL
      await tts.speak(
        speech,
      );

      // --------------------------------------------------------
      // STEP 4: OPEN RESULT SCREEN ONCE
      // --------------------------------------------------------

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const ResultScreen(),
        ),
      );
    } catch (e) {
      debugPrint(
        'Error processing image: $e',
      );

      await tts.stop();

      await tts.speak(
        'Error processing image',
      );
    } finally {
      signModel.setProcessing(false);
    }
  }

  // ============================================================
  // READABLE CLASS NAME
  // ============================================================

  String _makeReadableClassName(
    String className,
  ) {
    return className
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Image',
        ),
      ),

      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              if (_isProcessing) ...[
                const CircularProgressIndicator(),

                const SizedBox(height: 20),

                const Text(
                  'Analyzing image...',
                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.photo_library,
                  size: 80,
                  color:
                      Colors.grey.shade400,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Select an image from your gallery',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 30),

                ElevatedButton.icon(
                  onPressed:
                      _pickAndDetectImage,

                  icon: const Icon(
                    Icons.image,
                  ),

                  label: const Text(
                    'Choose Image',
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
