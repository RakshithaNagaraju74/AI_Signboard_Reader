
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

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
  State<LiveCameraScreen> createState() =>
      _LiveCameraScreenState();
}

class _LiveCameraScreenState
    extends State<LiveCameraScreen> {
  CameraController? camera;

  Timer? timer;

  bool ready = false;
  bool processing = false;
  bool stopped = false;
  bool listening = false;
  bool focusMode = false;
  bool sceneScanMode = false;
  bool onboarding = true;
  bool demoMode = false;

  File? demoImage;

  LocationSnapshot? currentLocation;

  String status = 'Starting camera';
  String last = '';

  AppLanguage language =
      LanguageService.languages.first;

  List<DetectionResult> lastDetections = [];

  List<DetectionContext> visibleContexts = [];

  final tts = TTSService();
  final voice = VoiceCommandService();
  final lang = LanguageService();
  final location = LocationService();
  final history = HistoryService();
  final ocr = OCRService();
  final intel = DetectionIntelligence();
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      final saved = await lang.load();

      if (saved == null) {
        await speakRaw(
          'Welcome to AI Signboard Reader. '
          'I am your voice-first assistant.',
        );

        await chooseLanguage();
      } else {
        language = saved;

        await tts.setLanguage(
          language.speechLocale,
        );
      }

      final cameras =
          await availableCameras();

      if (cameras.isEmpty) {
        throw StateError(
          'No camera found',
        );
      }

      final backCamera =
          cameras.firstWhere(
        (item) =>
            item.lensDirection ==
            CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      camera = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await camera!.initialize();

      currentLocation =
          await location.current(
        localeIdentifier:
            _locationLocale(),
        refreshPlace: true,
      );

      if (mounted) {
        setState(() {
          ready = true;
          onboarding = false;
        });
      }

      await speak(
        copy('scanning'),
      );

      timer = Timer.periodic(
        const Duration(
          milliseconds: 1300,
        ),
        (_) => scan(),
      );
    } catch (e) {
      debugPrint(
        'Camera start error: $e',
      );

      if (mounted) {
        setState(() {
          onboarding = false;
          status = copy('cameraError');
        });
      }

      await speak(
        copy('cameraError'),
      );
    }
  }

  String _locationLocale() {
    if (language.code == 'hi') {
      return 'hi_IN';
    }

    if (language.code == 'kn') {
      return 'kn_IN';
    }

    return 'en_US';
  }

  Future<void> chooseLanguage() async {
    await tts.setLanguage('hi-IN');

    await speakRaw(
      'हिंदी में जारी रखने के लिए हाँ कहें। '
      'अगर जवाब नहीं मिलता है, मैं कन्नड़ पूछूँगा।',
    );

    final hindi = await voice.listen(
      localeId: 'hi-IN',
      timeout:
          const Duration(seconds: 4),
    );

    if (_affirmative(hindi, 'hi') ||
        LanguageService.detectCommand(
              hindi ?? '',
            ) ==
            'hi') {
      await setLanguage('hi');
      return;
    }

    await tts.setLanguage('kn-IN');

    await speakRaw(
      'ಕನ್ನಡದಲ್ಲಿ ಮುಂದುವರಿಸಲು ಹೌದು ಎಂದು ಹೇಳಿ. '
      'ಕೆಲವು ಸೆಕೆಂಡುಗಳಲ್ಲಿ ಉತ್ತರಿಸದಿದ್ದರೆ '
      'ಇಂಗ್ಲಿಷ್ ಕೇಳುತ್ತೇನೆ.',
    );

    final kannada = await voice.listen(
      localeId: 'kn-IN',
      timeout:
          const Duration(seconds: 4),
    );

    if (_affirmative(kannada, 'kn') ||
        LanguageService.detectCommand(
              kannada ?? '',
            ) ==
            'kn') {
      await setLanguage('kn');
      return;
    }

    await tts.setLanguage('en-US');

    await speakRaw(
      'Say yes for English to continue.',
    );

    final english = await voice.listen(
      localeId: 'en-US',
      timeout:
          const Duration(seconds: 4),
    );

    await setLanguage(
      (_affirmative(english, 'en') ||
              LanguageService.detectCommand(
                    english ?? '',
                  ) ==
                  'en')
          ? 'en'
          : 'en',
    );
  }

  bool _affirmative(
    String? value,
    String code,
  ) {
    final v =
        LanguageService.normalize(
      value ?? '',
    );

    if (code == 'hi') {
      return v.contains('हाँ') ||
          v.contains('हां') ||
          v.contains('haan') ||
          v.contains('yes') ||
          v.contains('हिंदी') ||
          v.contains('hindi');
    }

    if (code == 'kn') {
      return v.contains('ಹೌದು') ||
          v.contains('ಹೌದ') ||
          v.contains('yes') ||
          v.contains('ಕನ್ನಡ') ||
          v.contains('kannada');
    }

    return v.contains('yes') ||
        v.contains('yeah') ||
        v.contains('english');
  }

  Future<void> setLanguage(
    String code,
  ) async {
    language =
        LanguageService.fromCode(code) ??
            LanguageService.languages.first;

    await lang.save(language);

    await tts.setLanguage(
      language.speechLocale,
    );

    await speak(
      copy('languageSelected'),
    );
  }

  Future<void> scan() async {
    if (!ready ||
        processing ||
        stopped ||
        listening ||
        camera == null ||
        !camera!.value.isInitialized) {
      return;
    }

    processing = true;

    try {
      final shot =
          await camera!.takePicture();

      final file = File(shot.path);

      var raw =
          await TFLiteService()
              .predictImage(file);

      if (raw.isEmpty) {
        if (focusMode) {
          await maybeSpeak(
            'I lost the focused sign. '
            'Move the camera slowly.',
          );
        }

        return;
      }

      final previewSize =
          camera!.value.previewSize;

      intel.setFrameSize(
        previewSize?.width.toInt() ?? 416,
        previewSize?.height.toInt() ?? 416,
      );

      raw = raw.take(5).toList();

      final enriched =
          <DetectionResult>[];

      for (final detection in raw) {
        var text = '';

        if (detection.confidence >=
                0.45 &&
            (focusMode ||
                intel.shouldReadText(
                  detection,
                ))) {
          try {
            text = await ocr.extractText(
              file,
              detection.bbox,
            );
          } catch (e) {
            debugPrint(
              'OCR error: $e',
            );
          }
        }

        final enrichedDetection =
            DetectionResult(
          className:
              detection.className,
          confidence:
              detection.confidence,
          bbox: detection.bbox,
          ocrText: text,
          classId:
              detection.classId,
        );

        if (text.trim().isNotEmpty) {
          intel.markOcrRead(
            enrichedDetection,
          );
        }

        enriched.add(
          enrichedDetection,
        );
      }

      lastDetections = enriched;

      final contexts =
          intel.analyze(enriched);

      visibleContexts = contexts;

      currentLocation =
          await location.current(
        localeIdentifier:
            _locationLocale(),
      );

      if (mounted) {
        setState(() {});
      }

      if (contexts.isEmpty) {
        return;
      }

      if (sceneScanMode) {
        await speakScene(contexts);
        sceneScanMode = false;
        return;
      }

      final context =
          _chooseContext(contexts);

      if (!intel.shouldAnnounce(
        context,
        cooldown: focusMode
            ? const Duration(seconds: 2)
            : const Duration(seconds: 8),
      )) {
        return;
      }

      final speech =
          buildSpeech(context);

      await speak(speech);

      intel.markAnnounced(context);

      await HapticFeedback
          .mediumImpact();

      await history.add(
        DetectionHistoryEntry(
          label:
              context.detection.className,
          text:
              context.detection.ocrText,
          position:
              context.position.label,
          confidence:
              context.detection.confidence,
          latitude:
              currentLocation?.latitude,
          longitude:
              currentLocation?.longitude,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint(
        'scan error: $e',
      );
    } finally {
      processing = false;
    }
  }

  DetectionContext _chooseContext(
    List<DetectionContext> contexts,
  ) {
    if (intel.focusedKey != null) {
      for (final context in contexts) {
        final key = intel.key0(
          context.detection,
        );

        if (key == intel.focusedKey) {
          return context;
        }
      }
    }

    return contexts.first;
  }

  String buildSpeech(
    DetectionContext context,
  ) {
    final detection =
        context.detection;

    final label = localizedClass(
      detection.className,
    );

    var speech =
        '${copy('detected')} '
        '$label. '
        '${copy('position')}: '
        '${localizedPosition(context.position)}';

    if (focusMode &&
        context.position ==
            SignPosition.front) {
      speech =
          '${copy('detected')} '
          '$label. '
          '${copy('aheadHold')}';
    }

    if (detection.ocrText
        .trim()
        .isNotEmpty) {
      speech +=
          '. ${copy('text')}: '
          '${detection.ocrText.trim()}';
    }

    if (context.movement
        .isNotEmpty) {
      speech +=
          '. ${localizedMovement(context.movement)}';
    } else {
      speech +=
          '. ${localizedProximity(context.proximity)}';
    }

    speech +=
        '. ${localizedLocationSentence()}';

    if (_isSafetyClass(
      detection.className,
    )) {
      speech =
          '${copy('warning')} $speech';
    }

    return speech;
  }

  bool _isSafetyClass(
    String label,
  ) {
    final value =
        label.toLowerCase();

    return value.contains('warning') ||
        value.contains('construction') ||
        value.contains('pedestrian_dont') ||
        value.contains('stop') ||
        value.contains('road_blocked');
  }

  Future<void> speakScene(
    List<DetectionContext> contexts,
  ) async {
    final visible =
        contexts.take(4).toList();

    if (visible.isEmpty) {
      await speak(
        copy('noSigns'),
      );
      return;
    }

    final parts = <String>[];

    for (final context in visible) {
      final label = localizedClass(
        context.detection.className,
      );

      var item =
          '$label '
          '${localizedPosition(context.position)}';

      if (context.detection.ocrText
          .trim()
          .isNotEmpty) {
        item +=
            ', ${context.detection.ocrText.trim()}';
      }

      parts.add(item);
    }

    await speak(
      '${copy('visible')} '
      '${parts.length} '
      '${copy('items')}. '
      '${parts.join('. ')}. '
      '${localizedLocationSentence()}',
    );
  }

  Future<void> maybeSpeak(
    String text,
  ) async {
    if (last != text) {
      await speak(text);
    }
  }

  Future<void> pickDemoImage() async {
    try {
      final picked =
          await picker.pickImage(
        source:
            ImageSource.gallery,
        imageQuality: 95,
      );

      if (picked == null) {
        return;
      }

      final file =
          File(picked.path);

      final bytes =
          await file.readAsBytes();

      final image =
          img.decodeImage(bytes);

      if (image == null) {
        await speak(
          copy('analysisFailed'),
        );
        return;
      }

      processing = true;
      demoMode = true;
      demoImage = file;
      visibleContexts = [];

      if (mounted) {
        setState(() {});
      }

      await speak(
        copy('analyzingImage'),
      );

      var raw =
          await TFLiteService()
              .predictImage(file);

      raw = raw.take(8).toList();

      final enriched =
          <DetectionResult>[];

      intel.setFrameSize(
        image.width,
        image.height,
      );

      for (final detection in raw) {
        var text = '';

        if (detection.confidence >=
            0.40) {
          try {
            text = await ocr.extractText(
              file,
              detection.bbox,
            );
          } catch (_) {}
        }

        final item =
            DetectionResult(
          className:
              detection.className,
          confidence:
              detection.confidence,
          bbox: detection.bbox,
          ocrText: text,
          classId:
              detection.classId,
        );

        if (text.trim().isNotEmpty) {
          intel.markOcrRead(item);
        }

        enriched.add(item);
      }

      lastDetections = enriched;

      final contexts =
          intel.analyze(enriched);

      visibleContexts = contexts;

      currentLocation =
          await location.current(
        localeIdentifier:
            _locationLocale(),
        refreshPlace: true,
      );

      if (mounted) {
        setState(() {});
      }

      if (contexts.isEmpty) {
        await speak(
          copy('noSigns'),
        );
        return;
      }

      final parts = <String>[];

      for (final context
          in contexts.take(6)) {
        final d =
            context.detection;

        var part =
            '${localizedClass(d.className)}, '
            '${copy('class')} ${d.classId}, '
            '${copy('confidence')} '
            '${(d.confidence * 100).toStringAsFixed(0)} '
            'percent, '
            '${copy('position')} '
            '${localizedPosition(context.position)}';

        if (d.ocrText
            .trim()
            .isNotEmpty) {
          part +=
              '. ${copy('text')} '
              '${d.ocrText.trim()}';
        }

        parts.add(part);
      }

      await speak(
        '${copy('demoComplete')}. '
        '${parts.join('. ')}. '
        '${localizedLocationSentence()}',
      );

      await HapticFeedback
          .mediumImpact();
    } catch (e) {
      debugPrint(
        'demo image error: $e',
      );

      await speak(
        copy('analysisFailed'),
      );
    } finally {
      processing = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> closeDemo() async {
    demoMode = false;
    demoImage = null;
    visibleContexts = [];

    if (mounted) {
      setState(() {});
    }

    await speak(
      copy('scanning'),
    );
  }

  String localizedClass(
    String raw,
  ) {
    final value =
        raw.toLowerCase()
            .replaceAll('_', ' ');

    if (language.code == 'hi') {
      const map =
          <String, String>{
        'hospital': 'अस्पताल',
        'bus': 'बस',
        'bus stop': 'बस स्टॉप',
        'railway': 'रेलवे',
        'train': 'ट्रेन',
        'traffic': 'ट्रैफिक संकेत',
        'warning': 'चेतावनी संकेत',
        'construction': 'निर्माण संकेत',
        'road blocked':
            'सड़क बंद संकेत',
        'shop': 'दुकान',
        'street': 'सड़क संकेत',
        'notice': 'सूचना संकेत',
      };

      return map[value] ?? value;
    }

    if (language.code == 'kn') {
      const map =
          <String, String>{
        'hospital': 'ಆಸ್ಪತ್ರೆ',
        'bus': 'ಬಸ್',
        'bus stop': 'ಬಸ್ ನಿಲ್ದಾಣ',
        'railway': 'ರೈಲ್ವೆ',
        'train': 'ರೈಲು',
        'traffic': 'ಟ್ರಾಫಿಕ್ ಸೂಚನೆ',
        'warning': 'ಎಚ್ಚರಿಕೆ ಸೂಚನೆ',
        'construction':
            'ನಿರ್ಮಾಣ ಸೂಚನೆ',
        'road blocked':
            'ರಸ್ತೆ ಬಂದ್ ಸೂಚನೆ',
        'shop': 'ಅಂಗಡಿ',
        'street': 'ರಸ್ತೆ ಸೂಚನೆ',
        'notice': 'ಸೂಚನಾ ಫಲಕ',
      };

      return map[value] ?? value;
    }

    return value;
  }

  String localizedPosition(
    SignPosition position,
  ) {
    if (language.code == 'hi') {
      const map =
          <SignPosition, String>{
        SignPosition.left:
            'बहुत बाईं ओर',
        SignPosition.slightlyLeft:
            'थोड़ा बाईं ओर',
        SignPosition.front:
            'सीधे सामने',
        SignPosition.slightlyRight:
            'थोड़ा दाईं ओर',
        SignPosition.right:
            'बहुत दाईं ओर',
      };

      return map[position]!;
    }

    if (language.code == 'kn') {
      const map =
          <SignPosition, String>{
        SignPosition.left:
            'ತುಂಬಾ ಎಡಕ್ಕೆ',
        SignPosition.slightlyLeft:
            'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ',
        SignPosition.front:
            'ನೇರವಾಗಿ ಮುಂದೆ',
        SignPosition.slightlyRight:
            'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ',
        SignPosition.right:
            'ತುಂಬಾ ಬಲಕ್ಕೆ',
      };

      return map[position]!;
    }

    return position.label;
  }

  String localizedMovement(
    String movement,
  ) {
    if (language.code == 'hi') {
      return movement
          .replaceAll(
            'getting closer',
            'संकेत पास आ रहा है',
          )
          .replaceAll(
            'moving farther away',
            'संकेत दूर जा रहा है',
          )
          .replaceAll(
            'moving to your left',
            'संकेत आपकी बाईं ओर जा रहा है',
          )
          .replaceAll(
            'moving to your right',
            'संकेत आपकी दाईं ओर जा रहा है',
          );
    }

    if (language.code == 'kn') {
      return movement
          .replaceAll(
            'getting closer',
            'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ',
          )
          .replaceAll(
            'moving farther away',
            'ಸಂಕೇತ ದೂರವಾಗುತ್ತಿದೆ',
          )
          .replaceAll(
            'moving to your left',
            'ಸಂಕೇತ ನಿಮ್ಮ ಎಡಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ',
          )
          .replaceAll(
            'moving to your right',
            'ಸಂಕೇತ ನಿಮ್ಮ ಬಲಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ',
          );
    }

    return movement;
  }

  String localizedProximity(
    String proximity,
  ) {
    if (language.code == 'hi') {
      if (proximity == 'far') {
        return 'संकेत दूर है';
      }

      if (proximity == 'approaching') {
        return 'संकेत पास आ रहा है';
      }

      return 'संकेत पास है';
    }

    if (language.code == 'kn') {
      if (proximity == 'far') {
        return 'ಸಂಕೇತ ದೂರದಲ್ಲಿದೆ';
      }

      if (proximity == 'approaching') {
        return 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ';
      }

      return 'ಸಂಕೇತ ಹತ್ತಿರದಲ್ಲಿದೆ';
    }

    if (proximity == 'far') {
      return 'The sign is far away';
    }

    if (proximity == 'approaching') {
      return 'The sign is approaching';
    }

    return 'The sign is nearby';
  }

  String localizedLocationSentence() {
    final snapshot =
        currentLocation;

    if (snapshot == null) {
      return copy(
        'locationUnavailable',
      );
    }

    final place =
        snapshot.displayPlace;

    if (language.code == 'hi') {
      return 'वर्तमान स्थान: $place. '
          'GPS सटीकता लगभग '
          '${snapshot.accuracy.toStringAsFixed(0)} '
          'मीटर।';
    }

    if (language.code == 'kn') {
      return 'ಪ್ರಸ್ತುತ ಸ್ಥಳ: $place. '
          'GPS ನಿಖರತೆ ಸುಮಾರು '
          '${snapshot.accuracy.toStringAsFixed(0)} '
          'ಮೀಟರ್.';
    }

    return 'Current location: $place. '
        'GPS accuracy is about '
        '${snapshot.accuracy.toStringAsFixed(0)} '
        'metres.';
  }

  String copy(String key) {
    if (language.code == 'hi') {
      const map =
          <String, String>{
        'scanning':
            'लाइव स्कैनिंग शुरू है। कैमरे के सामने संकेत लाएँ।',
        'languageSelected':
            'भाषा चुन ली गई है। अब से सभी ऐप निर्देश इसी भाषा में होंगे।',
        'detected': 'पहचाना गया',
        'position': 'स्थिति',
        'class': 'क्लास',
        'confidence': 'विश्वास',
        'text': 'पाठ',
        'warning': 'चेतावनी।',
        'aheadHold':
            'सीधे सामने है। कैमरा स्थिर रखें।',
        'locationUnavailable':
            'वर्तमान GPS स्थान उपलब्ध नहीं है।',
        'analyzingImage':
            'अपलोड की गई तस्वीर का विश्लेषण किया जा रहा है।',
        'noSigns':
            'कोई स्पष्ट संकेत नहीं मिला।',
        'analysisFailed':
            'तस्वीर का विश्लेषण नहीं हो सका। दूसरी तस्वीर आज़माएँ।',
        'cameraError':
            'कैमरा उपलब्ध नहीं है। कैमरा और माइक्रोफ़ोन की अनुमति दें और ऐप फिर से खोलें।',
        'voicePrompt': 'आदेश बोलें।',
        'stopDone':
            'स्कैनिंग रोक दी गई है।',
        'nothingToRepeat':
            'दोहराने के लिए कुछ नहीं है।',
        'noFocus':
            'अभी फोकस करने के लिए कोई संकेत नहीं मिला।',
        'focusOn': 'फोकस किया गया',
        'focusGuide':
            'संकेत को बीच में लाने के लिए कैमरा धीरे से घुमाएँ।',
        'focusStopped':
            'फोकस मोड बंद है।',
        'scanningSurroundings':
            'आसपास के संकेत स्कैन किए जा रहे हैं।',
        'noHistory':
            'हाल के कोई संकेत नहीं हैं।',
        'historyHas':
            'इतिहास में हाल की पहचानें हैं:',
        'navigationLimit':
            'GPS स्थान उपलब्ध है। सटीक दूरी और कम्पास दिशा तभी बताई जाएगी जब विश्वसनीय रूप से अनुमानित हो सके।',
        'notUnderstood':
            'मैं समझ नहीं पाया। मदद के लिए हेल्प बोलें।',
        'demoComplete':
            'डेमो विश्लेषण पूरा हुआ।',
        'items': 'आइटम',
        'visible':
            'मुझे दिखाई दे रहे हैं',
        'help':
            'स्कैन, रोकें, दोहराएँ, फोकस, आसपास के संकेत, इतिहास, भाषा बदलें या नेविगेट बोलें।',
        'upload': 'तस्वीर चुनें',
        'backCamera':
            'कैमरा पर लौटें',
        'voiceCommands':
            'वॉइस कमांड',
        'demoResults':
            'डेमो परिणाम',
      };

      return map[key] ?? key;
    }

    if (language.code == 'kn') {
      const map =
          <String, String>{
        'scanning':
            'ಲೈವ್ ಸ್ಕ್ಯಾನಿಂಗ್ ಪ್ರಾರಂಭವಾಗಿದೆ. ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಫಲಕವನ್ನು ಹಿಡಿಯಿರಿ.',
        'languageSelected':
            'ಭಾಷೆಯನ್ನು ಆಯ್ಕೆ ಮಾಡಲಾಗಿದೆ. ಇನ್ನು ಮುಂದೆ ಎಲ್ಲಾ ಆಪ್ ಸೂಚನೆಗಳು ಇದೇ ಭಾಷೆಯಲ್ಲಿ ಇರುತ್ತವೆ.',
        'detected': 'ಗುರುತಿಸಲಾಗಿದೆ',
        'position': 'ಸ್ಥಾನ',
        'class': 'ವರ್ಗ',
        'confidence': 'ವಿಶ್ವಾಸ',
        'text': 'ಪಠ್ಯ',
        'warning': 'ಎಚ್ಚರಿಕೆ.',
        'aheadHold':
            'ನೇರವಾಗಿ ಮುಂದೆ ಇದೆ. ಕ್ಯಾಮೆರಾವನ್ನು ಸ್ಥಿರವಾಗಿ ಹಿಡಿಯಿರಿ.',
        'locationUnavailable':
            'ಪ್ರಸ್ತುತ GPS ಸ್ಥಳ ಲಭ್ಯವಿಲ್ಲ.',
        'analyzingImage':
            'ಅಪ್‌ಲೋಡ್ ಮಾಡಿದ ಚಿತ್ರವನ್ನು ವಿಶ್ಲೇಷಿಸಲಾಗುತ್ತಿದೆ.',
        'noSigns':
            'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಫಲಕ ಕಂಡುಬಂದಿಲ್ಲ.',
        'analysisFailed':
            'ಚಿತ್ರವನ್ನು ವಿಶ್ಲೇಷಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ. ಮತ್ತೊಂದು ಚಿತ್ರ ಪ್ರಯತ್ನಿಸಿ.',
        'cameraError':
            'ಕ್ಯಾಮೆರಾ ಲಭ್ಯವಿಲ್ಲ. ಕ್ಯಾಮೆರಾ ಮತ್ತು ಮೈಕ್ರೋಫೋನ್ ಅನುಮತಿ ನೀಡಿ ಮತ್ತು ಆಪ್ ಅನ್ನು ಮತ್ತೆ ತೆರೆಯಿರಿ.',
        'voicePrompt':
            'ಆಜ್ಞೆಯನ್ನು ಹೇಳಿ.',
        'stopDone':
            'ಸ್ಕ್ಯಾನಿಂಗ್ ನಿಲ್ಲಿಸಲಾಗಿದೆ.',
        'nothingToRepeat':
            'ಮತ್ತೆ ಹೇಳಲು ಏನೂ ಇಲ್ಲ.',
        'noFocus':
            'ಈಗ ಫೋಕಸ್ ಮಾಡಲು ಯಾವುದೇ ಫಲಕ ಕಂಡುಬಂದಿಲ್ಲ.',
        'focusOn':
            'ಫೋಕಸ್ ಮಾಡಲಾಗಿದೆ',
        'focusGuide':
            'ಫಲಕವನ್ನು ಮಧ್ಯದಲ್ಲಿ ತರಲು ಕ್ಯಾಮೆರಾವನ್ನು ನಿಧಾನವಾಗಿ ಸರಿಸಿ.',
        'focusStopped':
            'ಫೋಕಸ್ ಮೋಡ್ ನಿಲ್ಲಿಸಲಾಗಿದೆ.',
        'scanningSurroundings':
            'ಸುತ್ತಮುತ್ತಲಿನ ಫಲಕಗಳನ್ನು ಸ್ಕ್ಯಾನ್ ಮಾಡಲಾಗುತ್ತಿದೆ.',
        'noHistory':
            'ಇತ್ತೀಚಿನ ಫಲಕಗಳಿಲ್ಲ.',
        'historyHas':
            'ಇತಿಹಾಸದಲ್ಲಿ ಇತ್ತೀಚಿನ ಗುರುತಿಸುವಿಕೆಗಳ ಸಂಖ್ಯೆ:',
        'navigationLimit':
            'GPS ಸ್ಥಳ ಲಭ್ಯವಿದೆ. ನಿಖರ ದೂರ ಮತ್ತು ಕಂಪಾಸ್ ದಿಕ್ಕನ್ನು ವಿಶ್ವಾಸಾರ್ಹವಾಗಿ ಅಂದಾಜಿಸಲು ಸಾಧ್ಯವಾದಾಗ ಮಾತ್ರ ಹೇಳಲಾಗುತ್ತದೆ.',
        'notUnderstood':
            'ನನಗೆ ಅರ್ಥವಾಗಲಿಲ್ಲ. ಸಹಾಯಕ್ಕಾಗಿ ಹೆಲ್ಪ್ ಎಂದು ಹೇಳಿ.',
        'demoComplete':
            'ಡೆಮೊ ವಿಶ್ಲೇಷಣೆ ಪೂರ್ಣಗೊಂಡಿದೆ.',
        'items': 'ಐಟಂಗಳು',
        'visible':
            'ನನಗೆ ಕಾಣುತ್ತಿರುವುದು',
        'help':
            'ಸ್ಕ್ಯಾನ್, ನಿಲ್ಲಿಸು, ಮತ್ತೆ ಹೇಳು, ಫೋಕಸ್, ಸುತ್ತಮುತ್ತಲಿನ ಫಲಕಗಳು, ಇತಿಹಾಸ, ಭಾಷೆ ಬದಲಾಯಿಸು ಅಥವಾ ನ್ಯಾವಿಗೇಟ್ ಎಂದು ಹೇಳಿ.',
        'upload':
            'ಚಿತ್ರ ಆಯ್ಕೆಮಾಡಿ',
        'backCamera':
            'ಕ್ಯಾಮೆರಾಕ್ಕೆ ಹಿಂತಿರುಗಿ',
        'voiceCommands':
            'ವಾಯ್ಸ್ ಕಮಾಂಡ್',
        'demoResults':
            'ಡೆಮೊ ಫಲಿತಾಂಶಗಳು',
      };

      return map[key] ?? key;
    }

    const map =
        <String, String>{
      'scanning':
          'Live scanning is on. Hold a signboard in front of the camera.',
      'languageSelected':
          'Language selected. From now on, all app guidance will use this language.',
      'detected': 'Detected',
      'position': 'Position',
      'class': 'class',
      'confidence': 'confidence',
      'text': 'Text',
      'warning': 'Warning.',
      'aheadHold':
          'directly ahead. Hold the camera steady.',
      'locationUnavailable':
          'Current GPS location is unavailable.',
      'analyzingImage':
          'Analyzing the uploaded image.',
      'noSigns':
          'I could not find a clear signboard.',
      'analysisFailed':
          'I could not analyze that image. Please try another image.',
      'cameraError':
          'Camera is unavailable. Allow camera and microphone permissions and reopen the app.',
      'voicePrompt':
          'Say a command.',
      'stopDone':
          'Scanning stopped.',
      'nothingToRepeat':
          'Nothing to repeat.',
      'noFocus':
          'I do not currently see a sign to focus on.',
      'focusOn':
          'Focused on',
      'focusGuide':
          'Move the camera slowly until the sign is centered.',
      'focusStopped':
          'Focus mode stopped.',
      'scanningSurroundings':
          'Scanning the surroundings.',
      'noHistory':
          'No recent signs.',
      'historyHas':
          'There are recent detections in history:',
      'navigationLimit':
          'GPS context is available. Exact distance and compass direction will only be stated when they can be estimated reliably.',
      'notUnderstood':
          'I did not understand. Say help for available commands.',
      'demoComplete':
          'Demo analysis complete.',
      'items': 'items',
      'visible': 'I can see',
      'help':
          'Say scan, stop, repeat, find sign, stop focus, scan surroundings, what signs, where, change language, history, or navigate.',
      'upload':
          'Upload image',
      'backCamera':
          'Back to camera',
      'voiceCommands':
          'Voice commands',
      'demoResults':
          'Demo results',
    };

    return map[key] ?? key;
  }

  Future<void> commands() async {
    if (listening) {
      return;
    }

    listening = true;

    await tts.stop();

    await speak(
      copy('voicePrompt'),
    );

    final result =
        await voice.listen(
      localeId:
          language.speechLocale,
    );

    listening = false;

    if (result == null ||
        result.trim().isEmpty) {
      return;
    }

    await command(result);
  }

  Future<void> command(
    String raw,
  ) async {
    final speech =
        LanguageService.normalize(raw);

    if (speech.contains('stop') ||
        speech.contains('रुको') ||
        speech.contains('निल्') ||
        speech.contains('ನಿಲ್ಲಿಸು')) {
      stopped = true;

      await speak(
        copy('stopDone'),
      );

      return;
    }

    if (speech.contains('scan') ||
        speech.contains('continue') ||
        speech.contains('स्कैन') ||
        speech.contains('ಮುಂದುವರ') ||
        speech.contains('ಸ್ಕ್ಯಾನ್')) {
      stopped = false;

      await speak(
        copy('scanning'),
      );

      return;
    }

    if (speech.contains('repeat') ||
        speech.contains('दोहर') ||
        speech.contains('ಮತ್ತೆ')) {
      await speak(
        last.isEmpty
            ? copy('nothingToRepeat')
            : last,
      );

      return;
    }

    if (speech.contains('release focus') ||
        speech.contains('stop focus') ||
        speech.contains('unfocus')) {
      focusMode = false;

      intel.clearFocus();

      await speak(
        copy('focusStopped'),
      );

      return;
    }

    if (speech.contains('find') ||
        speech.contains('focus') ||
        speech.contains('लक्ष्य') ||
        speech.contains('ಫೋಕಸ್')) {
      if (lastDetections.isEmpty) {
        await speak(
          copy('noFocus'),
        );
      } else {
        final context =
            intel.select(lastDetections);

        intel.focus(context);

        focusMode = true;

        await speak(
          '${copy('focusOn')} '
          '${localizedClass(context.detection.className)}. '
          '${copy('focusGuide')}',
        );
      }

      return;
    }

    if (speech.contains('around') ||
        speech.contains('surroundings') ||
        speech.contains('what do you see') ||
        speech.contains('क्या है') ||
        speech.contains('सिर्फ आसपास') ||
        speech.contains('ಸುತ್ತ')) {
      sceneScanMode = true;

      await speak(
        copy('scanningSurroundings'),
      );

      return;
    }

    if (speech.contains('what signs') ||
        speech.contains('nearby signs') ||
        speech.contains('signs around')) {
      if (lastDetections.isEmpty) {
        await speak(
          copy('noSigns'),
        );
      } else {
        await speakScene(
          intel.analyze(
            lastDetections,
          ),
        );
      }

      return;
    }

    if (speech.contains('where') ||
        speech.contains('last seen') ||
        speech.contains('कहाँ') ||
        speech.contains('ಎಲ್ಲಿ')) {
      if (lastDetections.isEmpty) {
        await speak(
          copy('locationUnavailable'),
        );
      } else {
        final context =
            intel.select(
          lastDetections,
        );

        await speak(
          '${copy('lastSeen')} '
          '${localizedClass(context.detection.className)} '
          '${localizedPosition(context.position)}. '
          '${localizedLocationSentence()}',
        );
      }

      return;
    }

    if (speech.contains('help') ||
        speech.contains('मदद') ||
        speech.contains('ಸಹಾಯ')) {
      await speak(
        copy('help'),
      );

      return;
    }

    if (speech.contains('change language') ||
        speech.contains('language') ||
        speech.contains('भाषा') ||
        speech.contains('ಭಾಷೆ')) {
      await chooseLanguage();

      return;
    }

    if (speech.contains('history') ||
        speech.contains('इतिहास') ||
        speech.contains('ಇತಿಹಾಸ')) {
      final entries =
          await history.read();

      await speak(
        entries.isEmpty
            ? copy('noHistory')
            : '${copy('historyHas')} '
              '${entries.length} '
              '${copy('items')}.',
      );

      return;
    }

    if (speech.contains('navigate') ||
        speech.contains('direction') ||
        speech.contains('दिशा') ||
        speech.contains('ನ್ಯಾವಿಗೇಟ್')) {
      await speak(
        copy('navigationLimit'),
      );

      return;
    }

    await speak(
      copy('notUnderstood'),
    );
  }

  String localize(
    String speech,
  ) {
    if (language.code == 'en') {
      return speech;
    }

    if (language.code == 'hi') {
      return speech
          .replaceAll(
            'far left',
            'बहुत बाईं ओर',
          )
          .replaceAll(
            'slightly left',
            'थोड़ा बाईं ओर',
          )
          .replaceAll(
            'directly ahead',
            'सीधे सामने',
          )
          .replaceAll(
            'slightly right',
            'थोड़ा दाईं ओर',
          )
          .replaceAll(
            'far right',
            'बहुत दाईं ओर',
          )
          .replaceAll(
            'Warning',
            'चेतावनी',
          )
          .replaceAll(
            'Text:',
            'पाठ:',
          )
          .replaceAll(
            'getting closer',
            'पास आ रहा है',
          )
          .replaceAll(
            'moving farther away',
            'दूर जा रहा है',
          )
          .replaceAll(
            'moving to your left',
            'आपकी बाईं ओर जा रहा है',
          )
          .replaceAll(
            'moving to your right',
            'आपकी दाईं ओर जा रहा है',
          )
          .replaceAll(
            'The sign is far away',
            'संकेत दूर है',
          )
          .replaceAll(
            'The sign is approaching',
            'संकेत पास आ रहा है',
          )
          .replaceAll(
            'The sign is nearby',
            'संकेत पास है',
          );
    }

    return speech
        .replaceAll(
          'far left',
          'ತುಂಬಾ ಎಡಕ್ಕೆ',
        )
        .replaceAll(
          'slightly left',
          'ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ',
        )
        .replaceAll(
          'directly ahead',
          'ನೇರವಾಗಿ ಮುಂದೆ',
        )
        .replaceAll(
          'slightly right',
          'ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ',
        )
        .replaceAll(
          'far right',
          'ತುಂಬಾ ಬಲಕ್ಕೆ',
        )
        .replaceAll(
          'Warning',
          'ಎಚ್ಚರಿಕೆ',
        )
        .replaceAll(
          'Text:',
          'ಪಠ್ಯ:',
        )
        .replaceAll(
          'getting closer',
          'ಹತ್ತಿರವಾಗುತ್ತಿದೆ',
        )
        .replaceAll(
          'moving farther away',
          'ದೂರವಾಗುತ್ತಿದೆ',
        )
        .replaceAll(
          'moving to your left',
          'ನಿಮ್ಮ ಎಡಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ',
        )
        .replaceAll(
          'moving to your right',
          'ನಿಮ್ಮ ಬಲಕ್ಕೆ ಚಲಿಸುತ್ತಿದೆ',
        )
        .replaceAll(
          'The sign is far away',
          'ಸಂಕೇತ ದೂರದಲ್ಲಿದೆ',
        )
        .replaceAll(
          'The sign is approaching',
          'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ',
        )
        .replaceAll(
          'The sign is nearby',
          'ಸಂಕೇತ ಹತ್ತಿರದಲ್ಲಿದೆ',
        );
  }

  Future<void> speakRaw(
    String speech,
  ) async {
    last = speech;

    if (mounted) {
      setState(() {
        status = speech;
      });
    }

    await tts.speak(speech);
  }

  Future<void> speak(
    String speech,
  ) async {
    last = speech;

    final localizedSpeech =
        localize(speech);

    if (mounted) {
      setState(() {
        status =
            localizedSpeech;
      });
    }

    await tts.speak(
      localizedSpeech,
    );
  }

  Widget _resultPanel() {
    if (visibleContexts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints:
          const BoxConstraints(
        maxHeight: 250,
      ),
      padding:
          const EdgeInsets.all(14),
      decoration:
          BoxDecoration(
        color: Colors.black
            .withValues(alpha: 0.90),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white24,
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 20,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  demoMode
                      ? copy(
                          'demoResults',
                        )
                      : copy(
                          'detected',
                        ),
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              const Icon(
                Icons.location_on,
                size: 18,
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          ...visibleContexts
              .take(5)
              .map(
            (context) {
              final d =
                  context.detection;

              var detail =
                  '${localizedClass(d.className)}'
                  ' • '
                  '${localizedPosition(context.position)}\n'
                  '${copy('class')}: '
                  '${d.classId} • '
                  '${copy('confidence')}: '
                  '${(d.confidence * 100).toStringAsFixed(0)}%';

              if (d.ocrText
                  .trim()
                  .isNotEmpty) {
                detail +=
                    '\n${copy('text')}: '
                    '${d.ocrText.trim()}';
              }

              if (context.movement
                  .isNotEmpty) {
                detail +=
                    '\n${localizedMovement(context.movement)}';
              }

              return Container(
                margin:
                    const EdgeInsets.only(
                  bottom: 7,
                ),
                padding:
                    const EdgeInsets.all(9),
                decoration:
                    BoxDecoration(
                  color: Colors.white
                      .withValues(
                    alpha: 0.08,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child: Text(
                  detail,
                  style:
                      const TextStyle(
                    fontSize: 12.5,
                  ),
                ),
              );
            },
          ),
          const Divider(
            color: Colors.white24,
          ),
          Text(
            currentLocation == null
                ? copy(
                    'locationUnavailable',
                  )
                : '${currentLocation!.displayPlace}\n'
                  '${currentLocation!.latitude.toStringAsFixed(5)}, '
                  '${currentLocation!.longitude.toStringAsFixed(5)} '
                  '• ±${currentLocation!.accuracy.toStringAsFixed(0)}m',
            style:
                const TextStyle(
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (onboarding) {
      return Scaffold(
        backgroundColor:
            Colors.black,
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.record_voice_over,
                  size: 72,
                ),
                const SizedBox(
                  height: 24,
                ),
                const Text(
                  'AI Signboard Reader',
                  style:
                      TextStyle(
                    fontSize: 28,
                    fontWeight:
                        FontWeight.bold,
                  ),
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  status,
                  textAlign:
                      TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!ready ||
        camera == null) {
      return Scaffold(
        backgroundColor:
            Colors.black,
        body: Center(
          child: Text(
            status,
            textAlign:
                TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: demoMode &&
                    demoImage != null
                ? Image.file(
                    demoImage!,
                    fit: BoxFit.contain,
                  )
                : CameraPreview(
                    camera!,
                  ),
          ),
          if (visibleContexts
              .isNotEmpty)
            Positioned(
              left: 10,
              right: 10,
              bottom: 160,
              child: _resultPanel(),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      margin:
                          const EdgeInsets.all(
                        12,
                      ),
                      padding:
                          const EdgeInsets.all(
                        10,
                      ),
                      color: Colors.black87,
                      child: Text(
                        language.name +
                            (focusMode
                                ? ' • Focus mode'
                                : ''),
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: copy(
                        'upload',
                      ),
                      child: Container(
                        margin:
                            const EdgeInsets.only(
                          right: 12,
                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors
                              .indigo
                              .shade700,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                        ),
                        child:
                            IconButton(
                          tooltip: copy(
                            'upload',
                          ),
                          onPressed:
                              pickDemoImage,
                          icon:
                              const Icon(
                            Icons.upload_file,
                          ),
                          iconSize: 28,
                        ),
                      ),
                    ),
                  ],
                ),
                if (demoMode)
                  Align(
                    alignment:
                        Alignment.topRight,
                    child: Padding(
                      padding:
                          const EdgeInsets.only(
                        right: 12,
                      ),
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            closeDemo,
                        icon:
                            const Icon(
                          Icons.camera_alt,
                        ),
                        label: Text(
                          copy(
                            'backCamera',
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    color: Colors.black87,
                    child: Text(
                      status,
                      style:
                          const TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child:
                            ElevatedButton.icon(
                          onPressed:
                              commands,
                          icon:
                              const Icon(
                            Icons.mic,
                          ),
                          label: Text(
                            copy(
                              'voiceCommands',
                            ),
                          ),
                          style:
                              ElevatedButton
                                  .styleFrom(
                            minimumSize:
                                const Size(
                              0,
                              58,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      IconButton.filled(
                        onPressed: () =>
                            command(
                          stopped
                              ? 'scan'
                              : 'stop',
                        ),
                        icon: Icon(
                          stopped
                              ? Icons.play_arrow
                              : Icons.stop,
                        ),
                        iconSize: 30,
                        padding:
                            const EdgeInsets
                                .all(14),
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
