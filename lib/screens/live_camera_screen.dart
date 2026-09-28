import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/detection_result.dart';
import '../services/detection_intelligence.dart';
import '../services/history_service.dart';
import '../services/language_service.dart';
import '../services/location_service.dart';
import '../services/ocr_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';
import '../services/tflite_service.dart';

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  CameraController? camera;
  Timer? timer;

  bool ready = false;
  bool processing = false;
  bool stopped = false;
  bool listening = false;

  String status = 'Starting camera';
  String last = '';

  AppLanguage language = LanguageService.languages.first;

  final tts = TTSService();
  final voice = VoiceCommandService();
  final lang = LanguageService();
  final location = LocationService();
  final history = HistoryService();
  final ocr = OCRService();
  final intel = DetectionIntelligence();

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      final saved = await lang.load();

      if (saved != null) {
        language = saved;
      }

      final cameras = await availableCameras();

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      camera = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await camera!.initialize();

      if (mounted) {
        setState(() {
          ready = true;
        });
      }

      if (saved == null) {
        await chooseLanguage();
      } else {
        await speak(
          'AI Signboard Reader is ready. Live scanning is on.',
        );
      }

      timer = Timer.periodic(
        const Duration(milliseconds: 1800),
        (_) => scan(),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'Camera unavailable';
        });
      }

      await speak(
        'Camera permission is required. Please allow camera access and restart the app.',
      );
    }
  }

  Future<void> chooseLanguage() async {
    await speak(
      'Welcome. Say English, Hindi, or Kannada.',
    );

    final heard = await voice.listen(
      localeId: 'en-US',
      timeout: const Duration(seconds: 6),
    );

    final code =
        LanguageService.detectCommand(heard ?? '') ?? 'en';

    language =
        LanguageService.fromCode(code) ??
        LanguageService.languages.first;

    await lang.save(language);
    await tts.setLanguage(language.speechLocale);

    await speak(
      '${language.name} selected. Live scanning is starting.',
    );
  }

  Future<void> scan() async {
    if (!ready ||
        processing ||
        stopped ||
        listening ||
        camera == null) {
      return;
    }

    processing = true;

    try {
      final shot = await camera!.takePicture();
      final file = File(shot.path);

      final raw = await TFLiteService().predictImage(file);

      if (raw.isEmpty) {
        return;
      }

      final list = <DetectionResult>[];

      for (final detection in raw.take(3)) {
        String text = '';

        if (detection.confidence >= 0.45) {
          // OCRService currently determines the OCR configuration
          // internally, so no languageCode parameter is passed here.
          text = await ocr.extractText(
            file,
            detection.bbox,
          );
        }

        list.add(
          DetectionResult(
            className: detection.className,
            confidence: detection.confidence,
            bbox: detection.bbox,
            ocrText: text,
            classId: detection.classId,
          ),
        );
      }

      intel.setFrameSize(
        camera!.value.previewSize?.width.toInt() ?? 416,
        camera!.value.previewSize?.height.toInt() ?? 416,
      );

      final context = intel.select(list);

      if (!intel.shouldAnnounce(context)) {
        return;
      }

      final currentLocation = await location.current();
      final speech = buildSpeech(context);

      await speak(speech);

      intel.markAnnounced(context);

      await HapticFeedback.mediumImpact();

      await history.add(
        DetectionHistoryEntry(
          label: context.detection.className,
          text: context.detection.ocrText,
          position: context.position.label,
          confidence: context.detection.confidence,
          latitude: currentLocation?.latitude,
          longitude: currentLocation?.longitude,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('scan error: $e');
    } finally {
      processing = false;
    }
  }

  String buildSpeech(DetectionContext context) {
    final detection = context.detection;

    var speech =
        '${detection.className.replaceAll('_', ' ')} '
        '${context.position.label}';

    if (detection.ocrText.isNotEmpty) {
      speech += '. Text: ${detection.ocrText}';
    }

    if (context.movement.isNotEmpty) {
      speech += '. ${context.movement}';
    }

    final className = detection.className;

    if (className.contains('warning') ||
        className.contains('construction') ||
        className.contains('pedestrian_dont') ||
        className.contains('stop')) {
      speech = 'Warning. $speech';
    }

    return '$speech.';
  }

  String localize(String speech) {
    if (language.code == 'en') {
      return speech;
    }

    if (language.code == 'hi') {
      return speech
          .replaceAll('ahead', 'आगे')
          .replaceAll('left', 'बाईं ओर')
          .replaceAll('right', 'दाईं ओर')
          .replaceAll('Warning', 'चेतावनी')
          .replaceAll('Text:', 'पाठ:')
          .replaceAll('getting closer', 'पास आ रहा है')
          .replaceAll('moving farther', 'दूर जा रहा है');
    }

    return speech
        .replaceAll('ahead', 'ಮುಂದೆ')
        .replaceAll('left', 'ಎಡಕ್ಕೆ')
        .replaceAll('right', 'ಬಲಕ್ಕೆ')
        .replaceAll('Warning', 'ಎಚ್ಚರಿಕೆ')
        .replaceAll('Text:', 'ಪಠ್ಯ:')
        .replaceAll('getting closer', 'ಹತ್ತಿರವಾಗುತ್ತಿದೆ')
        .replaceAll('moving farther', 'ದೂರವಾಗುತ್ತಿದೆ');
  }

  Future<void> speak(String speech) async {
    last = speech;

    final localizedSpeech = localize(speech);

    if (mounted) {
      setState(() {
        status = localizedSpeech;
      });
    }

    await tts.speak(localizedSpeech);
  }

  Future<void> commands() async {
    if (listening) {
      return;
    }

    listening = true;

    await tts.stop();

    if (language.code == 'hi') {
      await speak('आदेश बोलें।');
    } else if (language.code == 'kn') {
      await speak('ಆಜ್ಞೆಯನ್ನು ಹೇಳಿ.');
    } else {
      await speak('Say a command.');
    }

    final result = await voice.listen(
      localeId: language.speechLocale,
    );

    listening = false;

    if (result == null) {
      return;
    }

    await command(result);
  }

  Future<void> command(String raw) async {
    final speech = LanguageService.normalize(raw);

    if (speech.contains('stop') ||
        speech.contains('रुको') ||
        speech.contains('ನಿಲ್ಲಿಸು')) {
      stopped = true;
      await speak('Scanning stopped.');
    } else if (speech.contains('scan') ||
        speech.contains('continue') ||
        speech.contains('स्कैन') ||
        speech.contains('ಸ್ಕ್ಯಾನ್')) {
      stopped = false;
      await speak('Scanning resumed.');
    } else if (speech.contains('repeat') ||
        speech.contains('दोहर') ||
        speech.contains('ಮತ್ತೆ')) {
      await speak(
        last.isEmpty ? 'Nothing to repeat.' : last,
      );
    } else if (speech.contains('help') ||
        speech.contains('मदद') ||
        speech.contains('ಸಹಾಯ')) {
      await speak(
        'Say scan, stop, repeat, change language, history, navigate, or help.',
      );
    } else if (speech.contains('change language') ||
        speech.contains('भाषा') ||
        speech.contains('ಭಾಷೆ')) {
      await chooseLanguage();
    } else if (speech.contains('history') ||
        speech.contains('इतिहास') ||
        speech.contains('ಇತಿಹಾಸ')) {
      final entries = await history.read();

      if (entries.isEmpty) {
        await speak('No recent signs.');
      } else {
        await speak(
          'There are ${entries.length} recent detections.',
        );
      }
    } else if (speech.contains('navigate') ||
        speech.contains('दिशा') ||
        speech.contains('ನ್ಯಾವಿಗೇಟ್')) {
      await speak(
        'GPS context is available. Exact sign distance is not claimed unless it can be estimated reliably.',
      );
    } else {
      await speak(
        'I did not understand. Say help for commands.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready || camera == null) {
      return Scaffold(
        body: Center(
          child: Text(status),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(camera!),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(10),
                    color: Colors.black87,
                    child: Text(language.name),
                  ),
                ),
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.black87,
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: commands,
                          icon: const Icon(Icons.mic),
                          label: const Text('Voice commands'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 58),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: () =>
                            command(stopped ? 'scan' : 'stop'),
                        icon: Icon(
                          stopped
                              ? Icons.play_arrow
                              : Icons.stop,
                        ),
                        iconSize: 30,
                        padding: const EdgeInsets.all(14),
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

  @override
  void dispose() {
    timer?.cancel();
    camera?.dispose();
    voice.stop();
    tts.stop();
    super.dispose();
  }
}

