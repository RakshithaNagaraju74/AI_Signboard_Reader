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
  bool focusMode = false;
  bool sceneScanMode = false;

  String status = 'Starting camera';
  String last = '';
  AppLanguage language = LanguageService.languages.first;
  List<DetectionResult> lastDetections = [];

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
        await tts.setLanguage(language.speechLocale);
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera found');

      final backCamera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      camera = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await camera!.initialize();
      if (mounted) setState(() => ready = true);

      if (saved == null) {
        await chooseLanguage();
      } else {
        await speak('AI Signboard Reader is ready. Live scanning is on.');
      }

      timer = Timer.periodic(
        const Duration(milliseconds: 1300),
        (_) => scan(),
      );
    } catch (e) {
      debugPrint('Camera start error: $e');
      if (mounted) setState(() => status = 'Camera unavailable');
      await speak(
        'Camera permission is required. Please allow camera access and restart the app.',
      );
    }
  }

  Future<void> chooseLanguage() async {
    await speak('Welcome. Say English, Hindi, or Kannada.');
    final heard = await voice.listen(
      localeId: 'en-US',
      timeout: const Duration(seconds: 6),
    );

    final code = LanguageService.detectCommand(heard ?? '') ?? 'en';
    language = LanguageService.fromCode(code) ??
        LanguageService.languages.first;

    await lang.save(language);
    await tts.setLanguage(language.speechLocale);
    await speak(
      language.name + ' selected. Live scanning is starting.',
    );
  }

  Future<void> scan() async {
    if (!ready || processing || stopped || listening || camera == null) {
      return;
    }

    processing = true;

    try {
      final shot = await camera!.takePicture();
      final file = File(shot.path);
      var raw = await TFLiteService().predictImage(file);

      if (raw.isEmpty) {
        if (focusMode) {
          await maybeSpeak(
            'I lost the focused sign. Move the camera slowly.',
          );
        }
        return;
      }

      intel.setFrameSize(
        camera!.value.previewSize?.width.toInt() ?? 416,
        camera!.value.previewSize?.height.toInt() ?? 416,
      );

      raw = raw.take(5).toList();
      final enriched = <DetectionResult>[];

      for (final detection in raw) {
        var text = '';
        if (detection.confidence >= 0.45 &&
            (focusMode || intel.shouldReadText(detection))) {
          text = await ocr.extractText(file, detection.bbox);
        }

        final enrichedDetection = DetectionResult(
          className: detection.className,
          confidence: detection.confidence,
          bbox: detection.bbox,
          ocrText: text,
          classId: detection.classId,
        );

        if (text.isNotEmpty) intel.markOcrRead(enrichedDetection);
        enriched.add(enrichedDetection);
      }

      lastDetections = enriched;
      final contexts = intel.analyze(enriched);
      if (contexts.isEmpty) return;

      if (sceneScanMode) {
        await speakScene(contexts);
        sceneScanMode = false;
        return;
      }

      final context = intel.select(enriched);
      if (!intel.shouldAnnounce(
        context,
        cooldown: focusMode
            ? const Duration(seconds: 2)
            : const Duration(seconds: 8),
      )) {
        return;
      }

      final currentLocation = await location.current();
      await speak(buildSpeech(context));
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
    final label = detection.className.replaceAll('_', ' ');
    var speech = label + ' ' + context.position.label;

    if (focusMode && context.position == SignPosition.front) {
      speech = label + ' directly ahead. Hold steady.';
    }

    if (detection.ocrText.isNotEmpty) {
      speech += '. Text: ' + detection.ocrText;
    }

    if (context.movement.isNotEmpty) {
      speech += '. ' + context.movement;
    } else if (context.proximity == 'far') {
      speech += '. The sign is far away';
    } else if (context.proximity == 'approaching') {
      speech += '. The sign is approaching';
    }

    if (detection.className.contains('warning') ||
        detection.className.contains('construction') ||
        detection.className.contains('pedestrian_dont') ||
        detection.className.contains('stop') ||
        detection.className.contains('road_blocked')) {
      speech = 'Warning. ' + speech;
    }

    return speech + '.';
  }

  Future<void> speakScene(List<DetectionContext> contexts) async {
    final visible = contexts.take(4).toList();
    if (visible.isEmpty) {
      await speak('I do not see any clear signs.');
      return;
    }

    final parts = <String>[];
    for (final context in visible) {
      final label = context.detection.className.replaceAll('_', ' ');
      var item = label + ' ' + context.position.label;
      if (context.detection.ocrText.isNotEmpty) {
        item += ', ' + context.detection.ocrText;
      }
      parts.add(item);
    }

    final countWord = parts.length == 1 ? 'sign' : 'signs';
    await speak(
      'I can see ' + parts.length.toString() + ' ' +
      countWord + '. ' + parts.join('. ') + '.',
    );
  }

  Future<void> maybeSpeak(String text) async {
    if (last != text) await speak(text);
  }

  Future<void> commands() async {
    if (listening) return;
    listening = true;
    await tts.stop();

    if (language.code == 'hi') {
      await speak('आदेश बोलें।');
    } else if (language.code == 'kn') {
      await speak('ಆಜ್ಞೆಯನ್ನು ಹೇಳಿ.');
    } else {
      await speak('Say a command.');
    }

    final result = await voice.listen(localeId: language.speechLocale);
    listening = false;
    if (result == null || result.trim().isEmpty) return;
    await command(result);
  }

  Future<void> command(String raw) async {
    final speech = LanguageService.normalize(raw);

    if (speech.contains('stop') ||
        speech.contains('रुको') ||
        speech.contains('ನಿಲ್ಲಿಸು')) {
      stopped = true;
      await speak('Scanning stopped.');
      return;
    }

    if (speech.contains('scan') ||
        speech.contains('continue') ||
        speech.contains('स्कैन') ||
        speech.contains('ಸ್ಕ್ಯಾನ್')) {
      stopped = false;
      await speak('Scanning resumed.');
      return;
    }

    if (speech.contains('repeat') ||
        speech.contains('दोहर') ||
        speech.contains('ಮತ್ತೆ')) {
      await speak(last.isEmpty ? 'Nothing to repeat.' : last);
      return;
    }

    if (speech.contains('find') ||
        speech.contains('focus') ||
        speech.contains('लक्ष्य') ||
        speech.contains('ಫೋಕಸ್')) {
      if (lastDetections.isEmpty) {
        await speak('I do not currently see a sign to focus on.');
      } else {
        final context = intel.select(lastDetections);
        intel.focus(context);
        focusMode = true;
        await speak(
          'Focused on ' +
          context.detection.className.replaceAll('_', ' ') +
          '. I will guide you until the sign is centered.',
        );
      }
      return;
    }

    if (speech.contains('release focus') ||
        speech.contains('stop focus') ||
        speech.contains('unfocus')) {
      focusMode = false;
      intel.clearFocus();
      await speak('Focus mode stopped.');
      return;
    }

    if (speech.contains('around') ||
        speech.contains('surroundings') ||
        speech.contains('what do you see') ||
        speech.contains('क्या है') ||
        speech.contains('ಸುತ್ತ')) {
      sceneScanMode = true;
      await speak('Scanning the surroundings.');
      return;
    }

    if (speech.contains('what signs') ||
        speech.contains('nearby signs') ||
        speech.contains('signs around')) {
      if (lastDetections.isEmpty) {
        await speak('No signs are currently visible.');
      } else {
        await speakScene(intel.analyze(lastDetections));
      }
      return;
    }

    if (speech.contains('where') ||
        speech.contains('last seen') ||
        speech.contains('कहाँ') ||
        speech.contains('ಎಲ್ಲಿ')) {
      if (lastDetections.isEmpty) {
        await speak('No current sign position is available.');
      } else {
        final context = intel.select(lastDetections);
        await speak(
          context.detection.className.replaceAll('_', ' ') +
          ' was last seen ' + context.position.label + '.',
        );
      }
      return;
    }

    if (speech.contains('help') ||
        speech.contains('मदद') ||
        speech.contains('ಸಹಾಯ')) {
      await speak(
        'Say scan, stop, repeat, find sign, stop focus, scan surroundings, '
        'what signs, where, change language, history, or navigate.',
      );
      return;
    }

    if (speech.contains('change language') ||
        speech.contains('भाषा') ||
        speech.contains('ಭಾಷೆ')) {
      await chooseLanguage();
      return;
    }

    if (speech.contains('history') ||
        speech.contains('इतिहास') ||
        speech.contains('ಇತಿಹಾಸ')) {
      final entries = await history.read();
      await speak(
        entries.isEmpty
            ? 'No recent signs.'
            : 'There are ' + entries.length.toString() +
              ' recent detections in history.',
      );
      return;
    }

    if (speech.contains('navigate') ||
        speech.contains('दिशा') ||
        speech.contains('ನ್ಯಾವಿಗೇಟ್')) {
      await speak(
        'GPS context is available. Exact sign distance and compass direction '
        'are not claimed unless they can be estimated reliably.',
      );
      return;
    }

    await speak('I did not understand. Say help for available commands.');
  }

  String localize(String speech) {
    if (language.code == 'en') return speech;

    if (language.code == 'hi') {
      return speech
          .replaceAll('far left', 'बहुत बाईं ओर')
          .replaceAll('slightly left', 'थोड़ा बाईं ओर')
          .replaceAll('directly ahead', 'सीधे सामने')
          .replaceAll('slightly right', 'थोड़ा दाईं ओर')
          .replaceAll('far right', 'बहुत दाईं ओर')
          .replaceAll('Warning', 'चेतावनी')
          .replaceAll('Text:', 'पाठ:')
          .replaceAll('getting closer', 'पास आ रहा है')
          .replaceAll('moving farther away', 'दूर जा रहा है')
          .replaceAll('moving to your left', 'आपकी बाईं ओर जा रहा है')
          .replaceAll('moving to your right', 'आपकी दाईं ओर जा रहा है')
          .replaceAll('The sign is far away', 'संकेत दूर है')
          .replaceAll('The sign is approaching', 'संकेत पास आ रहा है');
    }

    return speech
        .replaceAll('far left', 'ತುಂಬಾ ಎಡಕ್ಕೆ')
        .replaceAll('slightly left', 'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ')
        .replaceAll('directly ahead', 'ನೇರವಾಗಿ ಮುಂದೆ')
        .replaceAll('slightly right', 'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ')
        .replaceAll('far right', 'ತುಂಬಾ ಬಲಕ್ಕೆ')
        .replaceAll('Warning', 'ಎಚ್ಚರಿಕೆ')
        .replaceAll('Text:', 'ಪಠ್ಯ:')
        .replaceAll('getting closer', 'ಹತ್ತಿರವಾಗುತ್ತಿದೆ')
        .replaceAll('moving farther away', 'ದೂರವಾಗುತ್ತಿದೆ')
        .replaceAll('moving to your left', 'ನಿಮ್ಮ ಎಡಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ')
        .replaceAll('moving to your right', 'ನಿಮ್ಮ ಬಲಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ')
        .replaceAll('The sign is far away', 'ಸಂಕೇತ ದೂರದಲ್ಲಿದೆ')
        .replaceAll('The sign is approaching', 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ');
  }

  Future<void> speak(String speech) async {
    last = speech;
    final localizedSpeech = localize(speech);
    if (mounted) setState(() => status = localizedSpeech);
    await tts.speak(localizedSpeech);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready || camera == null) {
      return Scaffold(body: Center(child: Text(status)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(camera!)),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(10),
                    color: Colors.black87,
                    child: Text(
                      language.name + (focusMode ? ' • Focus mode' : ''),
                    ),
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
                          stopped ? Icons.play_arrow : Icons.stop,
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
