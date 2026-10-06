import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../services/ai_speech_service.dart';
import '../services/place_verification_service.dart';

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  State<LiveCameraScreen> createState() =>
      _LiveCameraScreenState();
}

class _LiveCameraScreenState
    extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
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
  bool languageChosen = false;
  File? pendingRecoveredImage;

  File? demoImage;

  LocationSnapshot? currentLocation;

  String status = 'Starting camera';
  String last = '';
  DateTime? _lastNoSignAnnouncement;

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
  final aiSpeech = AISpeechService();
  final placeVerifier = PlaceVerificationService();

  PlaceVerification? lastVerifiedPlace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recoverLostImage());
    start();
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await picker.retrieveLostData();
      if (response.isEmpty || response.file == null) return;

      pendingRecoveredImage = File(response.file!.path);
      debugPrint('Recovered image from Android image picker.');
    } catch (e) {
      debugPrint('Lost image recovery failed: $e');
    }
  }

  Future<void> start() async {
    try {
      status = 'Starting SightToSound';
      if (mounted) setState(() {});

      final saved = await lang.load();
      if (saved == null) {
        await chooseLanguage();
        final selected = await lang.load();
        if (selected == null) return;
        language = selected;
        await tts.setLanguage(language.speechLocale);
      } else {
        language = saved;
        await tts.setLanguage(language.speechLocale);
      }

      if (pendingRecoveredImage != null) {
        final recovered = pendingRecoveredImage!;
        pendingRecoveredImage = null;

        onboarding = false;
        demoMode = true;
        demoImage = recovered;
        ready = false;

        if (mounted) {
          setState(() {
            status = copy('analyzingImage');
          });
        }

        final recoveredContexts = await _analyzeFile(
          recovered,
          demo: true,
        );

        visibleContexts = recoveredContexts;
        if (mounted) setState(() {});

        // The user can return to camera explicitly after recovery.
        return;
      }

      await _initializeCamera();
      if (!mounted) return;

      unawaited(_refreshLocationInBackground());

      TFLiteService().initialize().then(
        (_) {},
        onError: (Object error, StackTrace stack) {
          debugPrint('Background model warm-up failed: $error');
        },
      );

      await speak(copy('scanning'));

      timer?.cancel();
      timer = Timer.periodic(
        const Duration(milliseconds: 2500),
        (_) => scan(),
      );
    } catch (e) {
      debugPrint('Camera start error: $e');
      if (mounted) {
        setState(() {
          onboarding = false;
          status = copy('cameraError');
        });
      }
      await speak(copy('cameraError'));
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera found');

    final backCamera = cameras.firstWhere(
      (item) => item.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    camera = controller;
    ready = true;
    onboarding = false;
    setState(() => status = copy('scanning'));
  }

  Future<void> _refreshLocationInBackground() async {
    try {
      final value = await location.current(
        localeIdentifier: _locationLocale(),
        refreshPlace: true,
      );
      if (mounted && value != null) {
        setState(() => currentLocation = value);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      timer?.cancel();
      timer = null;
      final controller = camera;
      camera = null;
      ready = false;
      if (controller != null) {
        unawaited(controller.dispose());
      }
      return;
    }

    if (state == AppLifecycleState.resumed &&
        !onboarding &&
        !demoMode) {
      unawaited(_resumeCameraSafely());
    }
  }

  Future<void> _resumeCameraSafely() async {
    if (!mounted || onboarding || demoMode || camera != null) return;

    try {
      await _initializeCamera();
      if (!mounted) return;
      if (!stopped) {
        timer?.cancel();
        timer = Timer.periodic(
          const Duration(milliseconds: 2000),
          (_) => scan(),
        );
      }
    } catch (e) {
      debugPrint('Camera resume error: $e');
      if (mounted) setState(() => status = copy('cameraError'));
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
    languageChosen = false;

    await voice.initialize();
    await voice.stop();
    await tts.initialize();
    await tts.stop();

    if (mounted) {
      setState(() => status = 'Choose your language');
    }

    // Keep the first interaction extremely simple. English speech
    // recognition is used only for the numeric choice because numbers are
    // generally more robust than multilingual language-name recognition.
    for (var attempt = 0; attempt < 4; attempt++) {
      await tts.setLanguage('en-US');

      final prompt = attempt == 0
          ? 'Choose your language. Say one for English, two for Hindi, or three for Kannada.'
          : 'Please say only one, two, or three.';

      await speakRaw(prompt);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final answer = await voice.listen(
        localeId: 'en-US',
        timeout: const Duration(seconds: 12),
      );

      // A large language button can be pressed while speech recognition is
      // still waiting. In that case the button choice wins and onboarding
      // must not start another prompt cycle.
      if (languageChosen) return;

      final detected = LanguageService.detectCommand(answer ?? '');
      if (detected == null) continue;

      final selected = LanguageService.fromCode(detected);
      if (selected == null) continue;

      // The spoken number is the user's language choice. Do not ask for a
      // second confirmation: requiring another speech turn can trap a blind
      // user in onboarding when Android STT misses the confirmation.
      await setLanguage(selected.code);
      await speak(copy('languageSelected'));
      return;
    }

    // Never trap a blind user in speech onboarding.
    await tts.setLanguage('en-US');
    await speakRaw(
      'Voice selection was not clear. The three large buttons below can be used to choose your language.',
    );

    if (mounted) {
      setState(() => status = 'Choose English, Hindi, or Kannada');
    }
  }

  Future<void> setLanguage(String code) async {
    final selected = LanguageService.fromCode(code);
    if (selected == null) return;

    languageChosen = true;
    await voice.stop();
    language = selected;
    await lang.save(language);
    await tts.setLanguage(language.speechLocale);

    if (mounted) {
      setState(() {
        onboarding = false;
        status = copy('languageSelected');
      });
    }

    await speak(copy('languageSelected'));
  }

  Future<List<DetectionContext>> _analyzeFile(File file, {required bool demo}) async {
    var raw = await TFLiteService().predictImage(file);
    if (raw.isEmpty) {
      lastDetections = [];
      return [];
    }

    // Keep all useful detections instead of exposing only the highest one.
    raw = raw.take(8).toList();

    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded != null) {
      final oriented = img.bakeOrientation(decoded);
      intel.setFrameSize(oriented.width, oriented.height);
    }

    // Track once per frame. OCR is attached to those same contexts so one
    // camera frame does not artificially advance stability twice.
    final preliminary = intel.analyze(raw);
    final ocrLimit = demo ? 6 : 4;
    final ocrKeys = preliminary
        .take(ocrLimit)
        .where((context) => context.detection.confidence >= 0.45)
        .map((context) => intel.detectionKey(context.detection))
        .toSet();

    final enriched = <DetectionContext>[];

    for (final context in preliminary) {
      var text = '';

      if (ocrKeys.contains(
        intel.detectionKey(context.detection),
      )) {
        try {
          text = await ocr.extractText(
            file,
            context.detection.bbox,
            languageCode: language.code,
          );
        } catch (e) {
          debugPrint('OCR error: $e');
        }
      }

      final enrichedContext = intel.withText(
        context,
        text,
      );

      if (text.trim().isNotEmpty) {
        intel.markOcrRead(enrichedContext.detection);
      }

      enriched.add(enrichedContext);
    }

    enriched.sort(
      (a, b) => b.priority.compareTo(a.priority),
    );

    lastDetections = enriched.map((e) => e.detection).toList();
    return enriched;
  }

  Future<void> scan() async {
    if (!ready ||
        processing ||
        stopped ||
        listening ||
        demoMode ||
        camera == null ||
        !camera!.value.isInitialized) {
      return;
    }

    if (!TFLiteService().isInitialized) return;

    processing = true;

    try {
      try {
        final refreshed = await location.current(
          localeIdentifier: _locationLocale(),
          refreshPlace: false,
        );
        if (refreshed != null) currentLocation = refreshed;
      } catch (e) {
        debugPrint('Pre-scan location refresh failed: $e');
      }

      final shot = await camera!.takePicture();
      final shotFile = File(shot.path);
      final contexts = await _analyzeFile(
        shotFile,
        demo: false,
      );

      // Camera captures are temporary inputs. Remove them after analysis so
      // repeated live scanning does not gradually fill the app cache.
      try {
        if (await shotFile.exists()) {
          await shotFile.delete();
        }
      } catch (_) {}

      try {
        final refreshed = await location.current(
          localeIdentifier: _locationLocale(),
          refreshPlace: false,
        );
        if (refreshed != null) {
          currentLocation = refreshed;
        }
      } catch (_) {}

      lastVerifiedPlace = null;
      visibleContexts = contexts;

      if (mounted) setState(() {});

      if (contexts.isEmpty) {
        final now = DateTime.now();
        final canAnnounce = _lastNoSignAnnouncement == null ||
            now.difference(_lastNoSignAnnouncement!) >=
                const Duration(seconds: 12);
        if (canAnnounce) {
          _lastNoSignAnnouncement = now;
          await speak(copy('noSigns'));
        }
        return;
      }

      _lastNoSignAnnouncement = null;

      if (sceneScanMode) {
        await speakScene(contexts);
        sceneScanMode = false;
        return;
      }

      // Announce every newly useful sign in the frame, not just the top one.
      final announceable = contexts
          .where(
            (context) => intel.shouldAnnounce(
              context,
              cooldown: focusMode
                  ? const Duration(seconds: 2)
                  : const Duration(seconds: 8),
            ),
          )
          .toList();

      if (announceable.isEmpty) return;

      final speech = await composeDetectionSpeech(
        announceable,
        useGroq: true,
      );

      await speak(speech);

      for (final context in announceable) {
        intel.markAnnounced(context);

        history.add(
          DetectionHistoryEntry(
            label: context.detection.className,
            text: context.detection.ocrText,
            position: context.position.label,
            confidence: context.detection.confidence,
            latitude: currentLocation?.latitude,
            longitude: currentLocation?.longitude,
            timestamp: DateTime.now(),
          ),
        ).catchError((_) {});
      }

      await HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('scan error: $e');
    } finally {
      processing = false;
      if (mounted) setState(() {});
    }
  }

  Future<String> composeDetectionSpeech(
    List<DetectionContext> contexts, {
    bool useGroq = true,
  }) async {
    final inputs = <SpeechDetectionInput>[];

    for (final context in contexts.take(4)) {
      final text = context.detection.ocrText.trim();
      var placeContext = '';

      if (currentLocation != null && placeVerifier.isPlaceLikeText(text)) {
        final verification = await placeVerifier.verify(
          visibleText: text,
          location: currentLocation!,
        );

        if (verification != null && verification.reliable) {
          lastVerifiedPlace = verification;

          // Only expose a mapped place as a signboard-location candidate when
          // it is on-site or genuinely nearby. An "elsewhere" match can be an
          // advertisement or a destination mentioned by the sign.
          if (verification.relation == PlaceRelation.onSite ||
              verification.relation == PlaceRelation.nearby) {
            placeContext = placeVerifier.spokenContext(verification);
          }
        }
      }

      if (placeContext.isEmpty && _looksLikeAdvertisement(text)) {
        placeContext = localizedAdvertisementWarning();
      }

      inputs.add(
        SpeechDetectionInput(
          // Preserve the detector's semantic class for Groq.
          label: context.detection.className,
          position: localizedPosition(context.position),
          text: text,
          movement: context.movement,
          proximity: context.proximity,
          guidance: localizedGuidance(context.position),
          placeContext: placeContext,
          safety: _isSafetyClass(context.detection.className),
        ),
      );
    }

    debugPrint(
      '[Groq] live_camera -> sending detection(s): '
      + inputs.length.toString()
      + ', language=' + language.code
      + ', currentPlace=' + (currentLocation?.displayAddress ?? 'unknown')
      + ', gpsAccuracy=' + (currentLocation?.accuracy.toStringAsFixed(1) ?? 'unknown')
      + ', useGroq=' + useGroq.toString()
      + ', keyLoaded=' + aiSpeech.groqEnabled.toString(),
    );

    return aiSpeech.compose(
      detections: inputs,
      languageCode: language.code,
      place: currentLocation == null
          ? ''
          : 'CURRENT USER LOCATION: ' +
              currentLocation!.displayAddress +
              ' (GPS accuracy about ' +
              currentLocation!.accuracy.toStringAsFixed(0) +
              ' metres). ' +
              'This is the user\'s current GPS-derived address context, not the signboard location.',
      useGroq: useGroq,
    );
  }

  String localizedGuidance(SignPosition position) {
    if (language.code == 'hi') {
      const map = <SignPosition, String>{
        SignPosition.left:
            'इसे देखने के लिए कैमरा और सिर धीरे से बाईं ओर घुमाएँ।',
        SignPosition.slightlyLeft:
            'इसे देखने के लिए थोड़ा बाईं ओर देखें।',
        SignPosition.front:
            'संकेत सीधे सामने है। कैमरा स्थिर रखें।',
        SignPosition.slightlyRight:
            'इसे देखने के लिए थोड़ा दाईं ओर देखें।',
        SignPosition.right:
            'इसे देखने के लिए कैमरा और सिर धीरे से दाईं ओर घुमाएँ।',
      };
      return map[position]!;
    }

    if (language.code == 'kn') {
      const map = <SignPosition, String>{
        SignPosition.left:
            'ಇದನ್ನು ನೋಡಲು ಕ್ಯಾಮೆರಾ ಮತ್ತು ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ.',
        SignPosition.slightlyLeft:
            'ಇದನ್ನು ನೋಡಲು ಸ್ವಲ್ಪ ಎಡಕ್ಕೆ ನೋಡಿ.',
        SignPosition.front:
            'ಫಲಕ ನೇರವಾಗಿ ಮುಂದೆ ಇದೆ. ಕ್ಯಾಮೆರಾವನ್ನು ಸ್ಥಿರವಾಗಿ ಹಿಡಿಯಿರಿ.',
        SignPosition.slightlyRight:
            'ಇದನ್ನು ನೋಡಲು ಸ್ವಲ್ಪ ಬಲಕ್ಕೆ ನೋಡಿ.',
        SignPosition.right:
            'ಇದನ್ನು ನೋಡಲು ಕ್ಯಾಮೆರಾ ಮತ್ತು ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ.',
      };
      return map[position]!;
    }

    const map = <SignPosition, String>{
      SignPosition.left:
          'Turn your head and camera gently to the left to face it.',
      SignPosition.slightlyLeft:
          'Look slightly left to face it.',
      SignPosition.front:
          'It is directly ahead. Keep the camera steady.',
      SignPosition.slightlyRight:
          'Look slightly right to face it.',
      SignPosition.right:
          'Turn your head and camera gently to the right to face it.',
    };
    return map[position]!;
  }

  bool _looksLikeAdvertisement(String text) {
    final value = text.toLowerCase();
    const markers = [
      'offer',
      'offers',
      'sale',
      'discount',
      'opening',
      'visit us',
      'available at',
      'branch',
      'branches',
      'call now',
      'contact',
      'book now',
      'near',
      'opposite',
      'coming soon',
      'deal',
      'limited time',
    ];

    return markers.any(value.contains);
  }

  String localizedAdvertisementWarning() {
    if (language.code == 'hi') {
      return 'यह पाठ विज्ञापन जैसा लगता है। इसे देखकर यह न मानें कि दुकान या सेवा यहीं स्थित है।';
    }

    if (language.code == 'kn') {
      return 'ಈ ಪಠ್ಯ ಜಾಹೀರಾತಿನಂತೆ ಕಾಣುತ್ತದೆ. ಇದನ್ನು ನೋಡಿ ಅಂಗಡಿ ಅಥವಾ ಸೇವೆ ಇಲ್ಲಿಯೇ ಇದೆ ಎಂದು ಊಹಿಸಬೇಡಿ.';
    }

    return 'This text looks like an advertisement. Do not assume the shop or service is located here just because it appears on the sign.';
  }

  String localizedPlaceContext(PlaceVerification value) {
    final name = value.matchedName;
    final distance = value.shortDistance;

    if (language.code == 'hi') {
      if (value.relation == PlaceRelation.onSite) {
        return 'मानचित्र के अनुसार $name लगभग $distance दूर है। फिर भी यह बोर्ड उस जगह के प्रवेश द्वार का प्रमाण नहीं है।';
      }
      if (value.relation == PlaceRelation.nearby) {
        return 'मानचित्र में $name लगभग $distance दूर है। यह बोर्ड उस जगह की ओर संकेत या विज्ञापन हो सकता है।';
      }
      return 'मानचित्र में $name लगभग $distance दूर मिला। इसलिए यह बोर्ड किसी दूसरी जगह का विज्ञापन हो सकता है, यहाँ की जगह का नहीं।';
    }

    if (language.code == 'kn') {
      if (value.relation == PlaceRelation.onSite) {
        return 'ನಕ್ಷೆಯ ಪ್ರಕಾರ $name ಸುಮಾರು $distance ದೂರದಲ್ಲಿದೆ. ಆದರೂ ಈ ಫಲಕವೇ ಆ ಸ್ಥಳದ ಪ್ರವೇಶದ್ವಾರ ಎಂದು ಖಚಿತಪಡಿಸುವುದಿಲ್ಲ.';
      }
      if (value.relation == PlaceRelation.nearby) {
        return 'ನಕ್ಷೆಯಲ್ಲಿ $name ಸುಮಾರು $distance ದೂರದಲ್ಲಿದೆ. ಈ ಫಲಕ ಆ ಸ್ಥಳದ ಜಾಹೀರಾತು ಅಥವಾ ದಿಕ್ಕು ಸೂಚನೆ ಆಗಿರಬಹುದು.';
      }
      return 'ನಕ್ಷೆಯಲ್ಲಿ $name ಸುಮಾರು $distance ದೂರದಲ್ಲಿದೆ. ಆದ್ದರಿಂದ ಈ ಫಲಕ ಇಲ್ಲಿನ ಸ್ಥಳವಲ್ಲ, ಬೇರೆ ಸ್ಥಳದ ಜಾಹೀರಾತು ಆಗಿರಬಹುದು.';
    }

    if (value.relation == PlaceRelation.onSite) {
      return 'Map data suggests $name is about $distance away. The sign itself does not prove that this is the entrance.';
    }

    if (value.relation == PlaceRelation.nearby) {
      return 'Map data places $name about $distance away. This sign may advertise or point to that place.';
    }

    return 'Map data found $name about $distance away. This sign may advertise a different location rather than this exact place.';
  }

  String buildSpeech(DetectionContext context) {
    final label = localizedClass(context.detection.className);
    final position = localizedPosition(context.position);
    final text = context.detection.ocrText.trim();

    if (language.code == 'hi') {
      return text.isEmpty
          ? '$label $position है।'
          : '$label $position है। इस पर "$text" लिखा है।';
    }

    if (language.code == 'kn') {
      return text.isEmpty
          ? '$label $position ಇದೆ.'
          : '$label $position ಇದೆ. ಅದರಲ್ಲಿ "$text" ಎಂದು ಬರೆಯಲಾಗಿದೆ.';
    }

    return text.isEmpty
        ? '$label is $position.'
        : '$label is $position, with the text "$text".';
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
    final visible = contexts.toList();

    if (visible.isEmpty) {
      await speak(copy('noSigns'));
      return;
    }

    final speech = await composeDetectionSpeech(
      visible,
      useGroq: true,
    );

    await speak(speech);
  }

  Future<void> maybeSpeak(
    String text,
  ) async {
    if (last != text) {
      await speak(text);
    }
  }

  Future<void> pickDemoImage() async {
    if (processing) return;

    processing = true;
    timer?.cancel();
    timer = null;

    final oldCamera = camera;
    camera = null;
    ready = false;

    try {
      await oldCamera?.dispose();

      if (mounted) setState(() => status = copy('upload'));

      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1280,
        maxHeight: 1280,
        requestFullMetadata: false,
      );

      if (picked == null) {
        processing = false;
        await _resumeCameraSafely();
        return;
      }

      final file = File(picked.path);
      demoMode = true;
      demoImage = file;
      visibleContexts = [];

      if (mounted) setState(() => status = copy('analyzingImage'));
      await speak(copy('analyzingImage'));

      final contexts = await _analyzeFile(file, demo: true);
      visibleContexts = contexts;
      if (mounted) setState(() {});

      if (contexts.isEmpty) {
        await speak(copy('noSigns'));
        return;
      }

      final speech = await composeDetectionSpeech(
        contexts.toList(),
        useGroq: true,
      );

      await speak(speech);
      await HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('demo image error: $e');
      if (mounted) setState(() => status = copy('analysisFailed'));
      await speak(copy('analysisFailed'));
    } finally {
      processing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> closeDemo() async {
    demoMode = false;
    demoImage = null;
    visibleContexts = [];
    processing = false;

    if (mounted) setState(() => status = copy('scanning'));

    await _resumeCameraSafely();

    if (camera != null) await speak(copy('scanning'));
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

  String copy(
    String key,
  ) {
    if (language.code == 'hi') {
      const map =
          <String, String>{
        'scanning':
            'लाइव स्कैनिंग शुरू है। कैमरे के सामने संकेत लाएँ।',
        'languageSelected':
            'भाषा चुन ली गई है। अब से सभी ऐप निर्देश इसी भाषा में होंगे।',
        'detected': 'पहचाना गया',
        'result': 'अभी का परिणाम',
        'scanningNow': 'स्कैन किया जा रहा है',
        'waitingForScan': 'कैमरा तैयार है। संकेत के सामने रखें।',
        'retryCamera': 'कैमरा फिर शुरू करें',
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
        'lastSeen':
            'अंतिम बार देखा गया',
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
        'result': 'ಈಗಿನ ಫಲಿತಾಂಶ',
        'scanningNow': 'ಸ್ಕ್ಯಾನ್ ಮಾಡಲಾಗುತ್ತಿದೆ',
        'waitingForScan': 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧವಾಗಿದೆ. ಫಲಕವನ್ನು ಮುಂದೆ ಹಿಡಿಯಿರಿ.',
        'retryCamera': 'ಕ್ಯಾಮೆರಾ ಮತ್ತೆ ಪ್ರಾರಂಭಿಸಿ',
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
        'lastSeen':
            'ಕೊನೆಯದಾಗಿ ಕಂಡದ್ದು',
      };

      return map[key] ?? key;
    }

    const map =
        <String, String>{
      'scanning':
          'Live scanning is on. Hold a signboard in front of the camera.',
      'languageSelected':
          'Language selected. From now on, all app guidance will use this language.',
      'detected':
          'Detected',
      'result':
          'Current result',
      'scanningNow':
          'Scanning',
      'waitingForScan':
          'Camera is ready. Hold a signboard in front of it.',
      'retryCamera':
          'Restart camera',
      'position':
          'Position',
      'text':
          'Text',
      'warning':
          'Warning.',
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
      'items':
          'items',
      'visible':
          'I can see',
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
      'lastSeen':
          'Last seen',
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
        speech.contains('फोकस') ||
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
        speech.contains('सುತ್ತ')) {
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
      await _navigateToVerifiedPlace();
      return;
    }

    await speak(
      copy('notUnderstood'),
    );
  }

  Future<void> _navigateToVerifiedPlace() async {
    final place = lastVerifiedPlace;

    if (place == null || !place.reliable) {
      await speak(
        language.code == 'hi'
            ? 'मैं अभी इस बोर्ड से किसी जगह की विश्वसनीय पुष्टि नहीं कर पाया।'
            : language.code == 'kn'
                ? 'ಈ ಫಲಕದಿಂದ ಯಾವುದೇ ಸ್ಥಳವನ್ನು ವಿಶ್ವಾಸಾರ್ಹವಾಗಿ ಖಚಿತಪಡಿಸಲು ನನಗೆ ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
                : 'I could not reliably verify a destination from this sign yet.',
      );
      return;
    }

    final destination = '${place.latitude},${place.longitude}';

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(destination)}&travelmode=walking&dir_action=navigate',
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (opened) {
      await speak(
        language.code == 'hi'
? 'मैंने ${place.matchedName} के लिए पैदल नेविगेशन खोला है।'
            : language.code == 'kn'
                ? '${place.matchedName} ಗೆ ನಡೆದುಹೋಗುವ ನ್ಯಾವಿಗೇಶನ್ ತೆರೆಯಲಾಗಿದೆ.'
                : 'I opened walking navigation to ${place.matchedName}.',
      );
    } else {
      await speak(copy('navigationLimit'));
    }
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
    final hasDetections = visibleContexts.isNotEmpty;
    final headline = status.trim().isEmpty ? copy('waitingForScan') : status.trim();

    return Container(
      constraints: const BoxConstraints(minHeight: 118, maxHeight: 330),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(blurRadius: 20, offset: Offset(0, 8), color: Colors.black54),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Row(
            children: [
              Icon(
                hasDetections ? Icons.record_voice_over_rounded : Icons.radar_rounded,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  hasDetections ? copy('result') : copy('scanningNow'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (currentLocation != null)
                const Icon(Icons.location_on_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              headline,
              style: const TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w700),
            ),
          ),
          if (hasDetections) ...[
            const SizedBox(height: 10),
            ...visibleContexts.take(8).map((context) {
              final d = context.detection;
              final text = d.ocrText.trim();
              var detail =
                  '${localizedClass(d.className)} • ${localizedPosition(context.position)}';
              if (text.isNotEmpty) {
                detail += '\n${copy('text')}: $text';
              }
              if (context.movement.isNotEmpty) {
                detail += '\n${localizedMovement(context.movement)}';
              } else {
                detail += '\n${localizedProximity(context.proximity)}';
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  detail,
                  style: const TextStyle(fontSize: 13.5, height: 1.3),
                ),
              );
            }),
            if (currentLocation != null) ...[
              const Divider(color: Colors.white24),
              Text(
                localizedLocationSentence(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            if (lastVerifiedPlace != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.indigo.withValues(alpha: 0.20),
                ),
                child: Text(
                  localizedPlaceContext(lastVerifiedPlace!),
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ],
          const SizedBox(height: 7),
          Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectLanguageFromButton(String code) async {
    // start() owns camera startup. Do not initialize another controller here.
    await setLanguage(code);
  }

  Widget _languageButton(String label, String code) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: () => _selectLanguageFromButton(code),
        child: Text(label, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (onboarding) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 42,
                    child: Icon(Icons.record_voice_over_rounded, size: 42),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Choose your language',
                    style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    status,
                    style: const TextStyle(fontSize: 17, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  _languageButton('English', 'en'),
                  const SizedBox(height: 12),
                  _languageButton('हिन्दी  •  Hindi', 'hi'),
                  const SizedBox(height: 12),
                  _languageButton('ಕನ್ನಡ  •  Kannada', 'kn'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!ready || camera == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 42, height: 42, child: CircularProgressIndicator()),
                  const SizedBox(height: 20),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _resumeCameraSafely,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(copy('retryCamera')),
                  ),
                ],
              ),
            ),
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
          Positioned(
            left: 10,
            right: 10,
            bottom: 150,
            child: Semantics(
              liveRegion: true,
              label: status,
              child: _resultPanel(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            stopped
                                ? Icons.pause_circle_outline
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            stopped
                                ? 'Paused'
                                : 'Live • ${language.name}${focusMode ? ' • Focus' : ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
                Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: pickDemoImage,
                          icon: const Icon(Icons.image_search),
                          label: Text(copy('upload')),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: commands,
                          icon: Icon(
                            listening
                                ? Icons.hearing
                                : Icons.mic_none_rounded,
                          ),
                          label: Text(
                            listening
                                ? 'Listening…'
                                : copy('voiceCommands'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
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
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    camera?.dispose();
    voice.stop();
    tts.stop();
    super.dispose();
  }
}