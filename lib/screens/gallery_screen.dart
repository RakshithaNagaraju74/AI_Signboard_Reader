
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a photo'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF173A4A), Color(0xFF17233C)],
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF59D6C8).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.add_photo_alternate_rounded, size: 30, color: Color(0xFF7FE4D8)),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Bring a sign into focus',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontSize: 28,
                              ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Choose a photo and SightToSound will look for signboards and read the useful text aloud.',
                          style: TextStyle(color: Color(0xFFD0D9E8), height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text('For the clearest result', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _GalleryTip(
                    icon: Icons.crop_free_rounded,
                    title: 'Keep the sign in frame',
                    subtitle: 'Try to include the full board and its text.',
                  ),
                  const SizedBox(height: 10),
                  _GalleryTip(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Choose a well-lit photo',
                    subtitle: 'Avoid glare, heavy shadows, and blur.',
                  ),
                  const SizedBox(height: 10),
                  _GalleryTip(
                    icon: Icons.text_fields_rounded,
                    title: 'Make the text readable',
                    subtitle: 'A closer, sharper image usually works best.',
                  ),
                  const SizedBox(height: 26),
                  if (_isProcessing) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 14),
                    const Center(
                      child: Text('Analyzing your photo…', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _pickAndDetectImage,
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text('Choose from gallery'),
                    ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'Your photo is used for this analysis.',
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            if (_isProcessing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTip extends StatelessWidget {
  const _GalleryTip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: colors.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}