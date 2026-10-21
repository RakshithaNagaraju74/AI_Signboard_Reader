
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sign_model.dart';
import '../services/tflite_service.dart';
import '../services/tts_service.dart';
import '../services/ocr_service.dart';
import './result_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool _isCameraInitialized = false;
  bool _isProcessing = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // ============================================================
  // CAMERA INITIALIZATION
  // ============================================================

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No camera found');
      }

      final backCamera = _cameras!.firstWhere(
        (camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Failed to initialize camera: $e';
      });
    }
  }

  // ============================================================
  // CAPTURE
  // ============================================================

  Future<void> _captureAndDetect() async {
    if (_isProcessing ||
        !_isCameraInitialized ||
        _controller == null) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final imageFile =
          await _controller!.takePicture();

      final file = File(imageFile.path);

      await _processImage(file);
    } catch (e) {
      debugPrint('Capture error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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

  Future<void> _processImage(File imageFile) async {
    final tflite = TFLiteService();
    final tts = TTSService();
    final ocr = OCRService();

    final signModel =
        Provider.of<SignModel>(
      context,
      listen: false,
    );

    signModel.setProcessing(true);
    signModel.setImagePath(imageFile.path);

    try {
      // --------------------------------------------------------
      // STEP 1: YOLO
      // --------------------------------------------------------

      debugPrint('Starting YOLO detection...');

      final detections =
          await tflite.predictImage(imageFile);

      debugPrint(
        'YOLO detections: ${detections.length}',
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
      // ONLY USE THE BEST DETECTION
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
        'BEST DETECTION: $className',
      );

      debugPrint(
        'CONFIDENCE: '
        '${bestDetection.confidence}',
      );

      debugPrint(
        'BBOX: ${bestDetection.bbox}',
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

      // ONE TTS CALL ONLY
      await tts.speak(speech);

      // --------------------------------------------------------
      // STEP 4: NAVIGATE ONLY ONCE
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
  // MAKE CLASS NAME READABLE
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
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live camera')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(Icons.videocam_off_rounded, size: 40, color: colors.error),
                  ),
                  const SizedBox(height: 22),
                  Text('Camera unavailable', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(
                    'SightToSound needs camera access to detect signboards. Check the permission and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.error, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() => _errorMessage = null);
                      _initializeCamera();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live camera')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('Getting your camera ready…', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(18),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: Color(0xFF59D6C8), size: 9),
                              SizedBox(width: 9),
                              Text('LIVE CAMERA', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_isProcessing)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        SizedBox(width: 14),
                        Expanded(child: Text('Looking for signboards…', style: TextStyle(fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101A2B).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ready when you are', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                        'Point your camera at a signboard, then capture to hear what it says.',
                        style: TextStyle(color: Color(0xFFB8C4D8), height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isProcessing ? null : _captureAndDetect,
                          icon: const Icon(Icons.center_focus_strong_rounded),
                          label: Text(_isProcessing ? 'Analyzing…' : 'Capture and read'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            backgroundColor: const Color(0xFF59D6C8),
                            foregroundColor: const Color(0xFF062A2A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}