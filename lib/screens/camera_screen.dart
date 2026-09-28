
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
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 60,
                  color: Colors.red,
                ),

                const SizedBox(height: 20),

                Text(
                  _errorMessage!,
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                    });

                    _initializeCamera();
                  },
                  child:
                      const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isCameraInitialized ||
        _controller == null) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(
            _controller!,
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),

                    SizedBox(height: 20),

                    Text(
                      'Analyzing image...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      bottomNavigationBar:
          SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child:
                ElevatedButton.icon(
              onPressed:
                  _isProcessing
                      ? null
                      : _captureAndDetect,

              icon: const Icon(
                Icons.camera,
              ),

              label: const Text(
                'Capture & Detect',
              ),

              style:
                  ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
