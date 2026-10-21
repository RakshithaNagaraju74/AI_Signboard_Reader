import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
import '../services/announcement_queue_service.dart';
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
  bool pickingImage = false;
  DateTime? _lastHoldStillAnnouncement;
  DateTime? _lastAnalysisAnnouncement;
  DateTime? _lastBusyAnnouncement;
  bool stopped = false;
  bool listening = false;
  bool _voiceSessionActive = false;
  bool _executingVoiceCommand = false;
  bool focusMode = false;
  bool sceneScanMode = false;
  bool safetyMode = true;
  String _lastSceneFingerprint = '';
  DateTime? _lastSceneNarration;
  bool onboarding = true;
  bool demoMode = false;
  bool languageChosen = false;
  File? pendingRecoveredImage;

  File? demoImage;

  LocationSnapshot? currentLocation;

  String status = 'Starting camera';
  String last = '';
  DateTime? _lastNoSignAnnouncement;
  DateTime? _lastLocationAnnouncement;

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
  late final AnnouncementQueueService announcements = AnnouncementQueueService(_speakQueued);
  final placeVerifier = PlaceVerificationService();

  PlaceVerification? lastVerifiedPlace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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


  String _permissionPrompt(String feature) {
    if (language.code == 'ta') {
      switch (feature) {
        case 'camera': return 'இப்போது கேமரா அனுமதி கேட்கப்படும். பலகைகளைப் படிக்க அனுமதியளிக்கவும்.';
        case 'microphone': return 'குரல் கட்டளைகளுக்காக மைக்ரோஃபோன் அனுமதியளிக்கவும்.';
        default: return 'இடம் சார்ந்த வழிகாட்டுதலுக்காக இருப்பிட அனுமதியளிக்கவும்.';
      }
    }
    if (language.code == 'te') {
      switch (feature) {
        case 'camera': return 'ఇప్పుడు కెమెరా అనుమతి అడుగుతుంది. బోర్డులను చదవడానికి అనుమతించండి.';
        case 'microphone': return 'వాయిస్ ఆదేశాల కోసం మైక్రోఫోన్ అనుమతించండి.';
        default: return 'స్థాన ఆధారిత సూచనల కోసం లొకేషన్ అనుమతించండి.';
      }
    }
    if (language.code == 'ml') {
      switch (feature) {
        case 'camera': return 'ഇപ്പോൾ ക്യാമറ അനുമതി ചോദിക്കും. ബോർഡുകൾ വായിക്കാൻ അനുവദിക്കുക.';
        case 'microphone': return 'വോയ്സ് കമാൻഡുകൾക്കായി മൈക്രോഫോൺ അനുവദിക്കുക.';
        default: return 'സ്ഥലത്തെ അടിസ്ഥാനമാക്കിയുള്ള നിർദ്ദേശങ്ങൾക്കായി ലൊക്കേഷൻ അനുവദിക്കുക.';
      }
    }
    if (language.code == 'kn') {
      switch (feature) {
        case 'camera':
          return 'ಈಗ ಕ್ಯಾಮೆರಾ ಅನುಮತಿ ಕೇಳಲಾಗುತ್ತದೆ. ಫಲಕಗಳನ್ನು ಓದಲು ದಯವಿಟ್ಟು ಅನುಮತಿಸಿ.';
        case 'microphone':
          return 'ಈಗ ಮೈಕ್ರೊಫೋನ್ ಅನುಮತಿ ಕೇಳಲಾಗುತ್ತದೆ. ಧ್ವನಿ ಆಜ್ಞೆಗಳನ್ನು ಬಳಸಲು ದಯವಿಟ್ಟು ಅನುಮತಿಸಿ.';
        default:
          return 'ಈಗ ಸ್ಥಳದ ಅನುಮತಿ ಕೇಳಲಾಗುತ್ತದೆ. ಸ್ಥಳ ಆಧಾರಿತ ಮಾರ್ಗದರ್ಶನಕ್ಕಾಗಿ ದಯವಿಟ್ಟು ಅನುಮತಿಸಿ.';
      }
    }
    if (language.code == 'hi') {
      switch (feature) {
        case 'camera':
          return 'अब कैमरे की अनुमति मांगी जाएगी। संकेत पढ़ने के लिए कृपया अनुमति दें।';
        case 'microphone':
          return 'अब माइक्रोफ़ोन की अनुमति मांगी जाएगी। आवाज़ से आदेश देने के लिए कृपया अनुमति दें।';
        default:
          return 'अब स्थान की अनुमति मांगी जाएगी। स्थान आधारित मार्गदर्शन के लिए कृपया अनुमति दें।';
      }
    }
    switch (feature) {
      case 'camera':
        return 'Android will now ask for camera permission. Please tap Allow so I can read signboards.';
      case 'microphone':
        return 'Android will now ask for microphone permission. Please tap Allow to use voice commands.';
      default:
        return 'Android will now ask for location permission. Please tap Allow for location-aware guidance.';
    }
  }

  String _permissionDeniedMessage(String feature, {bool settingsRequired = false}) {
    if (language.code == 'ta') {
      return settingsRequired
          ? 'இந்த அனுமதியை செயலி அமைப்புகளில் இயக்கவும்.'
          : 'அனுமதி வழங்கப்படவில்லை. இந்த வசதி செயல்படாது.';
    }
    if (language.code == 'te') {
      return settingsRequired
          ? 'యాప్ సెట్టింగ్‌లలో ఈ అనుమతిని ప్రారంభించండి.'
          : 'అనుమతి ఇవ్వలేదు. ఈ ఫీచర్ పనిచేయదు.';
    }
    if (language.code == 'ml') {
      return settingsRequired
          ? 'ആപ്പ് ക്രമീകരണങ്ങളിൽ ഈ അനുമതി പ്രവർത്തനക്ഷമമാക്കുക.'
          : 'അനുമതി നൽകിയില്ല. ഈ സൗകര്യം പ്രവർത്തിക്കില്ല.';
    }
    final action = settingsRequired
        ? (language.code == 'kn'
            ? 'ದಯವಿಟ್ಟು ಅಪ್ಲಿಕೇಶನ್ ಸೆಟ್ಟಿಂಗ್‌ಗಳಲ್ಲಿ ಈ ಅನುಮತಿಯನ್ನು ಸಕ್ರಿಯಗೊಳಿಸಿ.'
            : language.code == 'hi'
                ? 'कृपया ऐप की सेटिंग में यह अनुमति चालू करें।'
                : 'Please enable this permission in the app settings.')
        : (language.code == 'kn'
            ? 'ಅನುಮತಿ ನೀಡಲಾಗಿಲ್ಲ. ಈ ವೈಶಿಷ್ಟ್ಯ ಕಾರ್ಯನಿರ್ವಹಿಸುವುದಿಲ್ಲ.'
            : language.code == 'hi'
                ? 'अनुमति नहीं मिली। यह सुविधा काम नहीं करेगी।'
                : 'Permission was not granted, so this feature will not work.');
    final featureName = language.code == 'kn'
        ? (feature == 'camera' ? 'ಕ್ಯಾಮೆರಾ' : feature == 'microphone' ? 'ಮೈಕ್ರೊಫೋನ್' : 'ಸ್ಥಳ')
        : language.code == 'hi'
            ? (feature == 'camera' ? 'कैमरा' : feature == 'microphone' ? 'माइक्रोफ़ोन' : 'स्थान')
            : feature;
    return '$featureName. $action';
  }

  Future<bool> _requestPermissionWithVoice(
    Permission permission,
    String feature,
  ) async {
    var current = await permission.status;
    if (current.isGranted || current.isLimited) return true;

    if (current.isPermanentlyDenied || current.isRestricted) {
      await speakRaw(_permissionDeniedMessage(feature, settingsRequired: true));
      return false;
    }

    await speakRaw(_permissionPrompt(feature));
    current = await permission.request();

    if (current.isGranted || current.isLimited) {
      final confirmation = language.code == 'kn'
          ? 'ಅನುಮತಿ ದೊರೆತಿದೆ.'
          : language.code == 'hi'
              ? 'अनुमति मिल गई।'
              : language.code == 'ta'
                  ? 'அனுமதி வழங்கப்பட்டது.'
                  : language.code == 'te'
                      ? 'అనుమతి ఇచ్చారు.'
                      : language.code == 'ml'
                          ? 'അനുമതി നൽകി.'
                          : '$feature permission granted.';
      await speakRaw(confirmation);
      return true;
    }

    await speakRaw(_permissionDeniedMessage(
      feature,
      settingsRequired: current.isPermanentlyDenied,
    ));
    return false;
  }

  Future<void> start() async {
    try {
      // Wait for Android's lost-picker recovery before checking whether a
      // recovered image should be analyzed instead of starting the camera.
      await _recoverLostImage();
      status = 'Starting SightToSound';
      if (mounted) setState(() {});

      final saved = await lang.load();
      if (saved == null) {
        // First-run onboarding only.
        onboarding = true;
        if (mounted) setState(() {});
        await chooseLanguage();
        final selected = await lang.load();
        if (selected == null) return;
        language = selected;
        onboarding = false;
        await tts.setLanguage(language.speechLocale);
      } else {
        // A saved language must never flash the onboarding screen during
        // normal startup. It is shown again only after an explicit
        // "change language" command.
        language = saved;
        onboarding = false;
        if (mounted) setState(() {});
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

        unawaited(speak(copy('analyzingImage')));
        final recoveredContexts = await _analyzeFile(
          recovered,
          demo: true,
        );

        visibleContexts = recoveredContexts;
        if (mounted) {
          setState(() => status = recoveredContexts.isEmpty
              ? copy('noSigns')
              : copy('resultReady'));
        }
        if (recoveredContexts.isEmpty) {
          await speak(copy('noSigns'));
        } else {
          final recoveredSpeech = await composeDetectionSpeech(
            recoveredContexts,
            useGroq: true,
          );
          await speak(recoveredSpeech);
        }

        // The user can return to camera explicitly after recovery.
        return;
      }

      final cameraAllowed = await _requestPermissionWithVoice(
        Permission.camera,
        'camera',
      );
      if (!cameraAllowed) {
        throw StateError('Camera permission was not granted.');
      }
      await _initializeCamera();
      if (!mounted) return;

      // Start GPS immediately after camera initialization so the first
      // useful detection can already carry location context.
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
      final locationAllowed = await _requestPermissionWithVoice(
        Permission.locationWhenInUse,
        'location',
      );
      if (!locationAllowed) return;
      final value = await location.current(
        localeIdentifier: _locationLocale(),
        refreshPlace: true,
      );
      if (mounted && value != null) {
        setState(() => currentLocation = value);
        await _announceLocationIfNeeded(value);
      }
    } catch (error) {
      debugPrint('[Location] background refresh failed: $error');
    }
  }

  Future<void> _announceLocationIfNeeded(LocationSnapshot value) async {
    final now = DateTime.now();
    final shouldAnnounce = _lastLocationAnnouncement == null ||
        now.difference(_lastLocationAnnouncement!) >=
            const Duration(minutes: 2);

    if (!shouldAnnounce) return;

    _lastLocationAnnouncement = now;
    await speak(
      localizedLocationSentenceFor(value),
      priority: true,
    );
  }

  String localizedLocationSentenceFor(LocationSnapshot snapshot) {
    final place = snapshot.displayPlace;

    if (language.code == 'ta') {
      return 'தற்போதைய இடம்: $place. GPS துல்லியம் சுமார் ${snapshot.accuracy.toStringAsFixed(0)} மீட்டர்.';
    }
    if (language.code == 'te') {
      return 'ప్రస్తుత స్థానం: $place. GPS ఖచ్చితత్వం సుమారు ${snapshot.accuracy.toStringAsFixed(0)} మీటర్లు.';
    }
    if (language.code == 'ml') {
      return 'നിലവിലെ സ്ഥലം: $place. GPS കൃത്യത ഏകദേശം ${snapshot.accuracy.toStringAsFixed(0)} മീറ്റർ.';
    }

    if (language.code == 'hi') {
      return 'वर्तमान स्थान: ' + place + '। GPS सटीकता लगभग ' +
          snapshot.accuracy.toStringAsFixed(0) + ' मीटर।';
    }

    if (language.code == 'kn') {
      return 'ಪ್ರಸ್ತುತ ಸ್ಥಳ: ' + place + '. GPS ನಿಖರತೆ ಸುಮಾರು ' +
          snapshot.accuracy.toStringAsFixed(0) + ' ಮೀಟರ್.';
    }

    return 'Current location: ' + place + '. GPS accuracy is about ' +
        snapshot.accuracy.toStringAsFixed(0) + ' metres.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The gallery picker backgrounds the app on Android; avoid racing it
    // by creating or disposing a second camera controller while it is open.
    if (pickingImage) return;

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
        !demoMode &&
        !pickingImage) {
      unawaited(_resumeCameraSafely());
    }
  }

  Future<void> _restartCamera() async {
    if (!mounted || onboarding || demoMode) return;
    timer?.cancel();
    timer = null;
    final controller = camera;
    camera = null;
    ready = false;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (!mounted) return;
    await _resumeCameraSafely();
  }

  Future<void> _resumeCameraSafely() async {
    if (!mounted || onboarding || demoMode || pickingImage || camera != null) return;

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
    switch (language.code) {
      case 'hi': return 'hi_IN';
      case 'kn': return 'kn_IN';
      case 'ta': return 'ta_IN';
      case 'te': return 'te_IN';
      case 'ml': return 'ml_IN';
      default: return 'en_US';
    }
  }

  Future<void> chooseLanguage({bool force = false}) async {
    // A saved language is the normal startup state. Only an explicit
    // "change language" command may reopen this screen.
    if (!force) {
      final saved = await lang.load();
      if (saved != null) {
        language = saved;
        languageChosen = true;
        onboarding = false;
        if (mounted) setState(() {});
        return;
      }
    }

    languageChosen = false;
    onboarding = true;
    if (mounted) setState(() {});

    final microphoneAllowed = await _requestPermissionWithVoice(
      Permission.microphone,
      'microphone',
    );
    if (microphoneAllowed) {
      await voice.initialize();
      await voice.stop();
    }
    await tts.initialize();
    await tts.stop();

    if (mounted) {
      setState(() => status = 'Choose your language');
    }

    // Keep the first interaction extremely simple. English speech
    // recognition is used only for the numeric choice because numbers are
    // generally more robust than multilingual language-name recognition.
    for (var attempt = 0; microphoneAllowed && attempt < 4; attempt++) {
      await tts.setLanguage('en-US');

      final prompt = attempt == 0
          ? 'Choose your language. Say one for English, two for Hindi, three for Kannada, four for Tamil, five for Telugu, or six for Malayalam.'
          : 'Please say a number from one to six.';

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
      return;
    }

    // Never trap a blind user in speech onboarding.
    await tts.setLanguage('en-US');
    await speakRaw(
      'Voice selection was not clear. Use one of the six language buttons to choose your language.',
    );

    if (mounted) {
      setState(() => status = 'Choose English, Hindi, Kannada, Tamil, Telugu, or Malayalam');
    }
  }

  Future<void> setLanguage(String code) async {
    final selected = LanguageService.fromCode(code);
    if (selected == null) return;

    // Flip the UI state immediately. Do not wait for speech recognition
    // or TTS cleanup before leaving onboarding.
    languageChosen = true;
    onboarding = false;
    language = selected;

    if (mounted) {
      setState(() {
        status = copy('languageSelected');
      });
    }

    await voice.stop();
    await lang.save(language);
    await tts.setLanguage(language.speechLocale);
    await speak(copy('languageSelected'));
  }

  Future<List<DetectionContext>> _analyzeFile(File file, {required bool demo}) async {
    var raw = await TFLiteService().predictImage(file);
    if (raw.isEmpty) {
      lastDetections = [];
      return [];
    }

    // Tell the user to keep the phone still when a live sign is detected.
    // Throttle the voice prompt so it does not repeat on every camera frame.
    if (!demo) {
      final now = DateTime.now();
      if (_lastHoldStillAnnouncement == null ||
          now.difference(_lastHoldStillAnnouncement!) >= const Duration(seconds: 15)) {
        _lastHoldStillAnnouncement = now;
        final message = language.code == 'hi'
            ? 'संकेत मिल गया है। कृपया फोन को इसी दिशा में स्थिर रखें। मैं इसे पढ़ने की कोशिश कर रहा हूँ।'
            : language.code == 'kn'
                ? 'ಫಲಕ ಕಂಡುಬಂದಿದೆ. ದಯವಿಟ್ಟು ಫೋನ್ ಅನ್ನು ಇದೇ ದಿಕ್ಕಿನಲ್ಲಿ ಸ್ಥಿರವಾಗಿ ಹಿಡಿಯಿರಿ. ನಾನು ಅದನ್ನು ಓದಲು ಪ್ರಯತ್ನಿಸುತ್ತಿದ್ದೇನೆ.'
                : language.code == 'ta'
                    ? 'பலகை கண்டறியப்பட்டது. தயவுசெய்து தொலைபேசியை இதே திசையில் அசைக்காமல் பிடியுங்கள். நான் அதைப் படிக்க முயற்சிக்கிறேன்.'
                    : language.code == 'te'
                        ? 'బోర్డు కనిపించింది. దయచేసి ఫోన్‌ను ఇదే దిశలో కదపకుండా స్థిరంగా పట్టుకోండి. నేను దాన్ని చదవడానికి ప్రయత్నిస్తున్నాను.'
                        : language.code == 'ml'
                            ? 'ബോർഡ് കണ്ടെത്തി. ദയവായി ഫോൺ ഇതേ ദിശയിൽ അനക്കാതെ പിടിക്കുക. ഞാൻ അത് വായിക്കാൻ ശ്രമിക്കുകയാണ്.'
                            : 'I detected a sign. Please hold the phone steady in this direction while I try to read it.';
        if (mounted) setState(() => status = message);
        unawaited(speak(message, priority: true));
      }
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
    final ocrLimit = demo ? 8 : 8;
    final ocrKeys = preliminary
        .take(ocrLimit)
        .where((context) {
          final label = context.detection.className.toLowerCase();
          final textRich = label.contains('shop') ||
              label.contains('signboard') ||
              label.contains('public_info') ||
              label.contains('notice') ||
              label.contains('bus') ||
              label.contains('mrt') ||
              label.contains('speed_limit');
          // Text-rich signs are valuable even when the detector confidence
          // is a little lower; OCR can turn a generic category into useful
          // information for the blind user.
          return context.detection.confidence >= (textRich ? 0.35 : 0.45);
        })
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
        _executingVoiceCommand ||
        demoMode ||
        camera == null ||
        !camera!.value.isInitialized) {
      return;
    }

    if (!TFLiteService().isInitialized) return;

    processing = true;
    if (mounted) {
      setState(() => status = copy('analyzingNearby'));
    }

    // Give immediate spoken feedback, but throttle it so continuous live
    // scanning does not become noisy for the user.
    final now = DateTime.now();
    if (_lastAnalysisAnnouncement == null ||
        now.difference(_lastAnalysisAnnouncement!) >=
            const Duration(seconds: 15)) {
      _lastAnalysisAnnouncement = now;
      unawaited(
        speak(
          language.code == 'hi'
              ? 'मैं आपके आसपास संकेत बोर्ड खोज रहा हूँ। कृपया थोड़ी देर प्रतीक्षा करें।'
              : language.code == 'kn'
                  ? 'ನಿಮ್ಮ ಸುತ್ತಮುತ್ತಲಿನ ಫಲಕಗಳನ್ನು ಹುಡುಕುತ್ತಿದ್ದೇನೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಕಾಯಿರಿ.'
                  : language.code == 'ta'
                      ? 'உங்களைச் சுற்றியுள்ள பலகைகளைத் தேடுகிறேன். சிறிது நேரம் காத்திருக்கவும்.'
                      : language.code == 'te'
                          ? 'మీ చుట్టూ ఉన్న బోర్డుల కోసం చూస్తున్నాను. దయచేసి కొద్దిసేపు వేచి ఉండండి.'
                          : language.code == 'ml'
                              ? 'നിങ്ങളുടെ ചുറ്റുമുള്ള ബോർഡുകൾ പരിശോധിക്കുന്നു. ദയവായി അല്പസമയം കാത്തിരിക്കുക.'
                              : 'I’m checking for signboards around you. Please wait a moment.',
        ).catchError((Object speechError) {
          debugPrint('Progress announcement failed: $speechError');
        }),
      );
    }

    try {
      try {
        final refreshed = await location.current(
          localeIdentifier: _locationLocale(),
          refreshPlace: false,
        );
        if (refreshed != null) {
          currentLocation = refreshed;
          await _announceLocationIfNeeded(refreshed);
        }
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
          await _announceLocationIfNeeded(refreshed);
        }
      } catch (_) {}

      lastVerifiedPlace = null;
      visibleContexts = contexts;

      if (mounted) setState(() {});

      if (contexts.isEmpty) {
        if (mounted) setState(() => status = copy('noSigns'));
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
      if (mounted) setState(() => status = copy('resultReady'));

      if (sceneScanMode) {
        await speakScene(contexts);
        sceneScanMode = false;
        return;
      }

      // Announce every newly useful sign in the frame, not just the top one.
      var announceable = contexts
          .where(
            (context) => intel.shouldAnnounce(
              context,
              cooldown: focusMode
                  ? const Duration(seconds: 2)
                  : const Duration(seconds: 8),
            ),
          )
          .toList();

      // Focus mode follows only the selected sign while it moves.
      if (focusMode && announceable.isNotEmpty) {
        announceable = announceable.where(intel.isFocused).toList();
      }

      // Safety information always outranks ordinary shop/business narration.
      if (safetyMode) {
        final safety = contexts.where(_isSafetyContext).toList();
        if (safety.isNotEmpty) {
          // Safety information goes first, but do not throw away useful
          // non-safety signs from the same frame.
          final normal = announceable
              .where((context) => !_isSafetyContext(context))
              .toList();
          announceable = <DetectionContext>[
            ...safety,
            ...normal,
          ];
        }
      }

      // Scene memory: suppress an unchanged scene for a short period.
      final fingerprint = contexts.take(5).map((c) {
        return '${c.detection.className}|${c.detection.ocrText.trim().toLowerCase()}|${c.position.name}';
      }).join('||');
      final now = DateTime.now();
      final unchangedScene = fingerprint.isNotEmpty &&
          fingerprint == _lastSceneFingerprint &&
          _lastSceneNarration != null &&
          now.difference(_lastSceneNarration!) < const Duration(seconds: 12);

      if (unchangedScene && !announceable.any(_isSafetyContext)) {
        announceable = [];
      }

      if (announceable.isEmpty) return;

      _lastSceneFingerprint = fingerprint;
      _lastSceneNarration = now;

      final speech = await composeDetectionSpeech(
        announceable,
        useGroq: true,
      );

      await speak(
        speech,
        priority: announceable.any(_isSafetyContext),
      );

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
      if (mounted) setState(() => status = copy('analysisFailed'));

      // A camera plugin failure can leave the controller present but unable
      // to render frames. Recover it instead of leaving the user with a
      // silent/blank camera surface.
      if (camera != null &&
          camera!.value.hasError &&
          mounted &&
          !onboarding &&
          !demoMode) {
        unawaited(_restartCamera());
      }
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
    final seenSignText = <String>{};
    final seenSignKeys = <String>{};

    for (final context in contexts) {
      final cleanedText = context.detection.ocrText
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final textKey = cleanedText
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\u0900-\u0d7f]'), '');
      final signKey = context.detection.className.toLowerCase();
      // Preserve every distinct OCR result for Groq. Repeated text can be
      // deduplicated, but do not cap the payload to only the first four signs.
      if (textKey.isNotEmpty && !seenSignText.add(textKey)) continue;
      if (textKey.isEmpty && !seenSignKeys.add(signKey)) continue;
      final text = context.detection.ocrText.trim();
      var placeContext = '';

      if (currentLocation != null && placeVerifier.isPlaceLikeText(text)) {
        final verification = await placeVerifier.verify(
          visibleText: text,
          location: currentLocation!,
        );

        if (verification != null && verification.reliable) {
          lastVerifiedPlace = verification;

          // A sign may point to a destination that is not physically nearby.
          // Keep that mapped destination and its estimated distance, but say
          // clearly that it is the destination referred to by the sign, not
          // proof of the sign's own physical location.
          placeContext = localizedPlaceContext(verification);
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
          safety: _isSafetyContext(context),
          confidence: context.detection.confidence,
        ),
      );
    }

    final totalOcrChars = inputs.fold<int>(
      0,
      (sum, input) => sum + input.text.length,
    );
    debugPrint('[OCR->Groq] forwarding ${inputs.length} unique detections; total OCR chars=$totalOcrChars');
    for (var i = 0; i < inputs.length; i++) {
      debugPrint('[OCR->Groq] item=${i + 1} label=${inputs[i].label} chars=${inputs[i].text.length} text=${inputs[i].text}');
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
    if (language.code == 'ta') {
      const map = <SignPosition, String>{
        SignPosition.left: 'அதை நோக்க தொலைபேசியை மெதுவாக இடப்புறம் திருப்புங்கள்.',
        SignPosition.slightlyLeft: 'சற்று இடப்புறம் திருப்புங்கள்.',
        SignPosition.front: 'பலகை நேராக முன்னால் உள்ளது. தொலைபேசியை அசைக்காமல் பிடியுங்கள்.',
        SignPosition.slightlyRight: 'சற்று வலப்புறம் திருப்புங்கள்.',
        SignPosition.right: 'அதை நோக்க தொலைபேசியை மெதுவாக வலப்புறம் திருப்புங்கள்.',
      };
      return map[position]!;
    }
    if (language.code == 'te') {
      const map = <SignPosition, String>{
        SignPosition.left: 'దాన్ని చూడటానికి ఫోన్‌ను నెమ్మదిగా ఎడమవైపు తిప్పండి.',
        SignPosition.slightlyLeft: 'కొద్దిగా ఎడమవైపు చూడండి.',
        SignPosition.front: 'బోర్డు నేరుగా ఎదురుగా ఉంది. ఫోన్‌ను స్థిరంగా పట్టుకోండి.',
        SignPosition.slightlyRight: 'కొద్దిగా కుడివైపు చూడండి.',
        SignPosition.right: 'దాన్ని చూడటానికి ఫోన్‌ను నెమ్మదిగా కుడివైపు తిప్పండి.',
      };
      return map[position]!;
    }
    if (language.code == 'ml') {
      const map = <SignPosition, String>{
        SignPosition.left: 'അത് കാണാൻ ഫോൺ പതുക്കെ ഇടത്തേക്ക് തിരിക്കുക.',
        SignPosition.slightlyLeft: 'അൽപ്പം ഇടത്തേക്ക് നോക്കുക.',
        SignPosition.front: 'ബോർഡ് നേരെ മുന്നിലാണ്. ഫോൺ സ്ഥിരമായി പിടിക്കുക.',
        SignPosition.slightlyRight: 'അൽപ്പം വലത്തേക്ക് നോക്കുക.',
        SignPosition.right: 'അത് കാണാൻ ഫോൺ പതുക്കെ വലത്തേക്ക് തിരിക്കുക.',
      };
      return map[position]!;
    }
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
    if (language.code == 'ta') {
      return 'இந்த உரை விளம்பரமாக இருக்கலாம். கடை அல்லது சேவை இங்கேயே உள்ளது என்று கருத வேண்டாம்.';
    }
    if (language.code == 'te') {
      return 'ఈ వచనం ప్రకటనలా ఉంది. దుకాణం లేదా సేవ ఇక్కడే ఉందని అనుకోకండి.';
    }
    if (language.code == 'ml') {
      return 'ഈ വാചകം പരസ്യമായിരിക്കാം. കടയോ സേവനമോ ഇവിടെ തന്നെയാണെന്ന് കരുതരുത്.';
    }
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

    if (language.code == 'ta') {
      if (value.relation == PlaceRelation.onSite) {
        return 'வரைபடத் தகவலின்படி $name சுமார் $distance தொலைவில் உள்ளது. இந்தப் பலகை நுழைவாயில் என்பதை மட்டும் இது உறுதிப்படுத்தாது.';
      }
      if (value.relation == PlaceRelation.nearby) {
        return 'வரைபடத்தில் $name சுமார் $distance தொலைவில் உள்ளது. இந்தப் பலகை அந்த இடத்தைக் குறிக்கலாம் அல்லது விளம்பரப்படுத்தலாம்.';
      }
      return 'வரைபடத்தில் $name சுமார் $distance தொலைவில் உள்ளது. இந்தப் பலகை வேறு இடத்திற்கான விளம்பரமாக இருக்கலாம்.';
    }
    if (language.code == 'te') {
      if (value.relation == PlaceRelation.onSite) {
        return 'మ్యాప్ ప్రకారం $name సుమారు $distance దూరంలో ఉంది. ఈ బోర్డు ప్రవేశద్వారాన్ని నిర్ధారించదు.';
      }
      if (value.relation == PlaceRelation.nearby) {
        return 'మ్యాప్‌లో $name సుమారు $distance దూరంలో ఉంది. ఈ బోర్డు ఆ ప్రదేశాన్ని సూచించవచ్చు లేదా ప్రకటన కావచ్చు.';
      }
      return 'మ్యాప్‌లో $name సుమారు $distance దూరంలో ఉంది. ఈ బోర్డు వేరే ప్రదేశానికి సంబంధించిన ప్రకటన కావచ్చు.';
    }
    if (language.code == 'ml') {
      if (value.relation == PlaceRelation.onSite) {
        return 'മാപ്പ് പ്രകാരം $name ഏകദേശം $distance അകലെയാണ്. ഈ ബോർഡ് പ്രവേശന കവാടമാണെന്ന് ഇതു മാത്രം ഉറപ്പാക്കുന്നില്ല.';
      }
      if (value.relation == PlaceRelation.nearby) {
        return 'മാപ്പിൽ $name ഏകദേശം $distance അകലെയാണ്. ഈ ബോർഡ് ആ സ്ഥലത്തെ സൂചിപ്പിക്കുകയോ പരസ്യപ്പെടുത്തുകയോ ചെയ്യാം.';
      }
      return 'മാപ്പിൽ $name ഏകദേശം $distance അകലെയാണ്. ഈ ബോർഡ് മറ്റൊരു സ്ഥലത്തിന്റെ പരസ്യമായിരിക്കാം.';
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

  bool _isSafetyContext(DetectionContext context) {
    if (_isSafetyClass(context.detection.className)) return true;
    final text = context.detection.ocrText.toLowerCase();
    const words = [
      'no parking',
      'no entry',
      'road closed',
      'road block',
      'do not enter',
      'stop',
      'danger',
      'warning',
      'construction',
      'speed limit',
      'pedestrian crossing',
      'keep left',
      'keep right',
    ];
    return words.any(text.contains);
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

  String _busyMessage(String activity) {
    switch (language.code) {
      case 'kn':
        switch (activity) {
          case 'gallery': return 'ಗ್ಯಾಲರಿ ತೆರೆಯುತ್ತಿದೆ. ದಯವಿಟ್ಟು ಕಾಯಿರಿ.';
          case 'image': return 'ನಿಮ್ಮ ಚಿತ್ರವನ್ನು ವಿಶ್ಲೇಷಿಸಲಾಗುತ್ತಿದೆ. ದಯವಿಟ್ಟು ಕಾಯಿರಿ.';
          default: return 'ಲೈವ್ ಕ್ಯಾಮೆರಾ ಫಲಕಗಳನ್ನು ಪತ್ತೆಹಚ್ಚುತ್ತಿದೆ. ದಯವಿಟ್ಟು ಕಾಯಿರಿ.';
        }
      case 'hi':
        switch (activity) {
          case 'gallery': return 'गैलरी खुल रही है। कृपया प्रतीक्षा करें।';
          case 'image': return 'आपकी तस्वीर का विश्लेषण हो रहा है। कृपया प्रतीक्षा करें।';
          default: return 'लाइव कैमरा संकेतों का पता लगा रहा है। कृपया प्रतीक्षा करें।';
        }
      case 'ta':
        switch (activity) {
          case 'gallery': return 'படத்தொகுப்பு திறக்கப்படுகிறது. காத்திருக்கவும்.';
          case 'image': return 'உங்கள் படம் பகுப்பாய்வு செய்யப்படுகிறது. காத்திருக்கவும்.';
          default: return 'நேரடி கேமரா பலகைகளைக் கண்டறிகிறது. காத்திருக்கவும்.';
        }
      case 'te':
        switch (activity) {
          case 'gallery': return 'గ్యాలరీ తెరుచుకుంటోంది. దయచేసి వేచి ఉండండి.';
          case 'image': return 'మీ చిత్రాన్ని విశ్లేషిస్తున్నాము. దయచేసి వేచి ఉండండి.';
          default: return 'లైవ్ కెమెరా బోర్డులను గుర్తిస్తోంది. దయచేసి వేచి ఉండండి.';
        }
      case 'ml':
        switch (activity) {
          case 'gallery': return 'ഗാലറി തുറക്കുന്നു. ദയവായി കാത്തിരിക്കുക.';
          case 'image': return 'നിങ്ങളുടെ ചിത്രം വിശകലനം ചെയ്യുന്നു. ദയവായി കാത്തിരിക്കുക.';
          default: return 'ലൈവ് ക്യാമറ ബോർഡുകൾ കണ്ടെത്തുന്നു. ദയവായി കാത്തിരിക്കുക.';
        }
      default:
        switch (activity) {
          case 'gallery': return 'Opening your gallery. Please wait.';
          case 'image': return 'Your picture is being analyzed. Please wait.';
          default: return 'Live camera is detecting signboards. Please wait.';
        }
    }
  }

  Future<void> pickDemoImage() async {
    if (processing || pickingImage) {
      debugPrint(
        '[Gallery] repeated tap: processing=$processing pickingImage=$pickingImage demoMode=$demoMode',
      );

      // Never leave repeated taps feeling like the button is broken. Update
      // the visible status immediately and throttle speech so rapid taps do
      // not flood the announcement queue.
      final message = pickingImage
          ? _busyMessage('gallery')
          : demoMode
              ? _busyMessage('image')
              : _busyMessage('camera');
      if (mounted) setState(() => status = message);

      final now = DateTime.now();
      if (_lastBusyAnnouncement == null ||
          now.difference(_lastBusyAnnouncement!) >=
              const Duration(seconds: 3)) {
        _lastBusyAnnouncement = now;
        unawaited(speak(message, priority: true));
      }
      return;
    }

    processing = true;
    pickingImage = true;
    timer?.cancel();
    timer = null;

    final oldCamera = camera;
    camera = null;
    ready = false;

    try {
      if (mounted) {
        setState(() => status = copy('upload'));
      }
      debugPrint('[Gallery] opening Android image picker');
      // A camera disposal failure should not prevent the user from choosing a
      // photo. Log it and continue into the picker.
      try {
        await oldCamera?.dispose();
      } catch (cameraError) {
        debugPrint('[Gallery] camera dispose failed: $cameraError');
      }

      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
        requestFullMetadata: false,
      );
      debugPrint('[Gallery] picker returned: ${picked?.path ?? 'cancelled'}');

      if (picked == null) {
        pickingImage = false;
        processing = false;
        await _resumeCameraSafely();
        return;
      }

      final file = File(picked.path);
      // Keep the lifecycle guard active during the asynchronous file checks.
      // Only switch out of picker mode once the image is known to be readable.
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('The selected image could not be read.');
      }
      demoMode = true;
      demoImage = file;
      pickingImage = false;
      visibleContexts = [];

      if (mounted) setState(() => status = copy('analyzingImage'));
      // Start voice feedback without blocking image decoding and detection.
      unawaited(speak(copy('analyzingImage')));

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
      pickingImage = false;
      processing = false;
      if (mounted) setState(() {});
      if (mounted && !onboarding && !demoMode && camera == null) {
        unawaited(_resumeCameraSafely());
      }
      debugPrint(
        '[Gallery] finished: demoMode=$demoMode cameraReady=${camera != null}',
      );
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
    final value = raw.toLowerCase().replaceAll('_', ' ');

    if (language.code == 'ta') {
      const map = <String, String>{
        'warning sign': 'எச்சரிக்கை பலகை',
        'construction sign': 'கட்டுமான பலகை',
        'turn left sign': 'இடதுபுறம் திரும்பும் பலகை',
        'turn right sign': 'வலதுபுறம் திரும்பும் பலகை',
        'junction or merge sign': 'சாலை சந்திப்பு பலகை',
        'school zone sign': 'பள்ளி பகுதி பலகை',
        'speed limit sign': 'வேக வரம்பு பலகை',
        'bus stop sign': 'பேருந்து நிறுத்தப் பலகை',
        'shop sign': 'கடைப் பலகை',
        'public info sign': 'பொது தகவல் பலகை',
        'mrt sign': 'மெட்ரோ ரயில் பலகை',
        'traffic sign': 'போக்குவரத்து பலகை',
        'stop request bell sign': 'நிறுத்தக் கோரிக்கை பொத்தான்',
        'wet floor sign': 'ஈரமான தரை எச்சரிக்கை',
        'pedestrian crossing sign': 'பாதசாரி கடக்கும் பலகை',
        'accessibility sign': 'அணுகல் வசதி பலகை',
        'restroom ladies': 'பெண்கள் கழிப்பறை பலகை',
        'restroom men': 'ஆண்கள் கழிப்பறை பலகை',
        'pedestrian dont walk sign': 'பாதசாரிகள் செல்ல வேண்டாம் என்ற பலகை',
        'tactile paving': 'தொட்டுணர்வு நடைபாதை',
        'hospital': 'மருத்துவமனை பலகை',
        'bus': 'பேருந்து',
        'bus stop': 'பேருந்து நிறுத்தம்',
        'railway': 'ரயில்வே',
        'train': 'ரயில்',
        'traffic': 'போக்குவரத்து பலகை',
        'warning': 'எச்சரிக்கை பலகை',
        'construction': 'கட்டுமான பலகை',
        'road blocked': 'சாலை மூடப்பட்டுள்ளது',
        'shop': 'கடைப் பலகை',
        'street': 'தெருப் பலகை',
        'notice': 'அறிவிப்பு பலகை',
      };
      return map[value] ?? (value.endsWith('sign') ? 'பலகை' : value);
    }
    if (language.code == 'te') {
      const map = <String, String>{
        'warning sign': 'హెచ్చరిక బోర్డు',
        'construction sign': 'నిర్మాణ బోర్డు',
        'turn left sign': 'ఎడమవైపు తిరగండి బోర్డు',
        'turn right sign': 'కుడివైపు తిరగండి బోర్డు',
        'junction or merge sign': 'రోడ్డు కూడలి బోర్డు',
        'school zone sign': 'పాఠశాల ప్రాంత బోర్డు',
        'speed limit sign': 'వేగ పరిమితి బోర్డు',
        'bus stop sign': 'బస్ స్టాప్ బోర్డు',
        'shop sign': 'దుకాణం బోర్డు',
        'public info sign': 'ప్రజా సమాచార బోర్డు',
        'mrt sign': 'మెట్రో రైలు బోర్డు',
        'traffic sign': 'ట్రాఫిక్ బోర్డు',
        'stop request bell sign': 'ఆపమని కోరే బటన్',
        'wet floor sign': 'తడి నేల హెచ్చరిక',
        'pedestrian crossing sign': 'పాదచారుల దాటే బోర్డు',
        'accessibility sign': 'అందుబాటు సౌకర్యాల బోర్డు',
        'restroom ladies': 'మహిళల మరుగుదొడ్డి బోర్డు',
        'restroom men': 'పురుషుల మరుగుదొడ్డి బోర్డు',
        'pedestrian dont walk sign': 'పాదచారులు వెళ్లవద్దు బోర్డు',
        'tactile paving': 'స్పర్శ ద్వారా గుర్తించే పాదచారి మార్గం',
        'hospital': 'ఆసుపత్రి బోర్డు',
        'bus': 'బస్సు',
        'bus stop': 'బస్ స్టాప్',
        'railway': 'రైల్వే',
        'train': 'రైలు',
        'traffic': 'ట్రాఫిక్ బోర్డు',
        'warning': 'హెచ్చరిక బోర్డు',
        'construction': 'నిర్మాణ బోర్డు',
        'road blocked': 'రోడ్డు మూసివేయబడింది',
        'shop': 'దుకాణం బోర్డు',
        'street': 'వీధి బోర్డు',
        'notice': 'సమాచార బోర్డు',
      };
      return map[value] ?? (value.endsWith('sign') ? 'బోర్డు' : value);
    }
    if (language.code == 'ml') {
      const map = <String, String>{
        'warning sign': 'മുന്നറിയിപ്പ് ബോർഡ്',
        'construction sign': 'നിർമാണ ബോർഡ്',
        'turn left sign': 'ഇടത്തേക്ക് തിരിയുക ബോർഡ്',
        'turn right sign': 'വലത്തേക്ക് തിരിയുക ബോർഡ്',
        'junction or merge sign': 'റോഡ് ജംഗ്ഷൻ ബോർഡ്',
        'school zone sign': 'സ്കൂൾ മേഖല ബോർഡ്',
        'speed limit sign': 'വേഗപരിധി ബോർഡ്',
        'bus stop sign': 'ബസ് സ്റ്റോപ്പ് ബോർഡ്',
        'shop sign': 'കടയുടെ ബോർഡ്',
        'public info sign': 'പൊതു വിവര ബോർഡ്',
        'mrt sign': 'മെട്രോ റെയിൽ ബോർഡ്',
        'traffic sign': 'ട്രാഫിക് ബോർഡ്',
        'stop request bell sign': 'നിർത്താൻ ആവശ്യപ്പെടുന്ന ബട്ടൺ',
        'wet floor sign': 'നനഞ്ഞ നില മുന്നറിയിപ്പ്',
        'pedestrian crossing sign': 'കാൽനട ക്രോസിംഗ് ബോർഡ്',
        'accessibility sign': 'പ്രവേശന സൗകര്യ ബോർഡ്',
        'restroom ladies': 'സ്ത്രീകളുടെ ശൗചാലയ ബോർഡ്',
        'restroom men': 'പുരുഷന്മാരുടെ ശൗചാലയ ബോർഡ്',
        'pedestrian dont walk sign': 'കാൽനടക്കാർ കടക്കരുത് ബോർഡ്',
        'tactile paving': 'സ്പർശിച്ച് തിരിച്ചറിയാവുന്ന നടപ്പാത',
        'hospital': 'ആശുപത്രി ബോർഡ്',
        'bus': 'ബസ്',
        'bus stop': 'ബസ് സ്റ്റോപ്പ്',
        'railway': 'റെയിൽവേ',
        'train': 'ട്രെയിൻ',
        'traffic': 'ട്രാഫിക് ബോർഡ്',
        'warning': 'മുന്നറിയിപ്പ് ബോർഡ്',
        'construction': 'നിർമാണ ബോർഡ്',
        'road blocked': 'റോഡ് അടച്ചിരിക്കുന്നു',
        'shop': 'കടയുടെ ബോർഡ്',
        'street': 'തെരുവ് ബോർഡ്',
        'notice': 'അറിയിപ്പ് ബോർഡ്',
      };
      return map[value] ?? (value.endsWith('sign') ? 'ബോർഡ്' : value);
    }

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
    if (language.code == 'ta') {
      const map = <SignPosition, String>{
        SignPosition.left: 'மிகவும் இடப்புறம்',
        SignPosition.slightlyLeft: 'சற்று இடப்புறம்',
        SignPosition.front: 'நேராக முன்னால்',
        SignPosition.slightlyRight: 'சற்று வலப்புறம்',
        SignPosition.right: 'மிகவும் வலப்புறம்',
      };
      return map[position]!;
    }
    if (language.code == 'te') {
      const map = <SignPosition, String>{
        SignPosition.left: 'చాలా ఎడమవైపు',
        SignPosition.slightlyLeft: 'కొద్దిగా ఎడమవైపు',
        SignPosition.front: 'నేరుగా ఎదురుగా',
        SignPosition.slightlyRight: 'కొద్దిగా కుడివైపు',
        SignPosition.right: 'చాలా కుడివైపు',
      };
      return map[position]!;
    }
    if (language.code == 'ml') {
      const map = <SignPosition, String>{
        SignPosition.left: 'വളരെ ഇടതുവശത്ത്',
        SignPosition.slightlyLeft: 'അൽപ്പം ഇടതുവശത്ത്',
        SignPosition.front: 'നേരെ മുന്നിൽ',
        SignPosition.slightlyRight: 'അൽപ്പം വലതുവശത്ത്',
        SignPosition.right: 'വളരെ വലതുവശത്ത്',
      };
      return map[position]!;
    }
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
    if (language.code == 'ta') {
      return movement
          .replaceAll('getting closer', 'பலகை அருகில் வருகிறது')
          .replaceAll('moving farther away', 'பலகை விலகிச் செல்கிறது')
          .replaceAll('moving to your left', 'உங்கள் இடப்புறமாக நகர்கிறது')
          .replaceAll('moving to your right', 'உங்கள் வலப்புறமாக நகர்கிறது');
    }
    if (language.code == 'te') {
      return movement
          .replaceAll('getting closer', 'బోర్డు దగ్గరగా వస్తోంది')
          .replaceAll('moving farther away', 'బోర్డు దూరంగా వెళుతోంది')
          .replaceAll('moving to your left', 'మీ ఎడమవైపుకు కదులుతోంది')
          .replaceAll('moving to your right', 'మీ కుడివైపుకు కదులుతోంది');
    }
    if (language.code == 'ml') {
      return movement
          .replaceAll('getting closer', 'ബോർഡ് അടുത്തേക്ക് വരുന്നു')
          .replaceAll('moving farther away', 'ബോർഡ് അകന്നുപോകുന്നു')
          .replaceAll('moving to your left', 'നിങ്ങളുടെ ഇടത്തേക്ക് നീങ്ങുന്നു')
          .replaceAll('moving to your right', 'നിങ്ങളുടെ വലത്തേക്ക് നീങ്ങുന്നു');
    }
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
    if (language.code == 'ta') {
      if (proximity == 'far') return 'பலகை தொலைவில் உள்ளது';
      if (proximity == 'approaching') return 'பலகை அருகில் வருகிறது';
      return 'பலகை அருகில் உள்ளது';
    }
    if (language.code == 'te') {
      if (proximity == 'far') return 'బోర్డు దూరంగా ఉంది';
      if (proximity == 'approaching') return 'బోర్డు దగ్గరగా వస్తోంది';
      return 'బోర్డు దగ్గరలో ఉంది';
    }
    if (language.code == 'ml') {
      if (proximity == 'far') return 'ബോർഡ് ദൂരെയാണ്';
      if (proximity == 'approaching') return 'ബോർഡ് അടുത്തേക്ക് വരുന്നു';
      return 'ബോർഡ് സമീപത്തുണ്ട്';
    }
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

  Future<void> _speakCurrentLocationNow() async {
    final snapshot = currentLocation;
    if (snapshot != null) {
      await speak(
        localizedLocationSentenceFor(snapshot),
        priority: true,
      );
      return;
    }

    try {
      final refreshed = await location.current(
        localeIdentifier: _locationLocale(),
        refreshPlace: true,
      );
      if (refreshed != null) {
        currentLocation = refreshed;
        await speak(
          localizedLocationSentenceFor(refreshed),
          priority: true,
        );
        if (mounted) setState(() {});
        return;
      }
    } catch (error) {
      debugPrint('[Location] on-demand refresh failed: $error');
    }

    await speak(copy('locationUnavailable'), priority: true);
  }

  String localizedLocationSentence() {
    final snapshot =
        currentLocation;

    if (snapshot == null) {
      return copy('locationUnavailable');
    }

    final place = snapshot.displayPlace;

    if (language.code == 'ta') {
      return 'தற்போதைய இடம்: $place. GPS துல்லியம் சுமார் ${snapshot.accuracy.toStringAsFixed(0)} மீட்டர்.';
    }
    if (language.code == 'te') {
      return 'ప్రస్తుత స్థానం: $place. GPS ఖచ్చితత్వం సుమారు ${snapshot.accuracy.toStringAsFixed(0)} మీటర్లు.';
    }
    if (language.code == 'ml') {
      return 'നിലവിലെ സ്ഥലം: $place. GPS കൃത്യത ഏകദേശം ${snapshot.accuracy.toStringAsFixed(0)} മീറ്റർ.';
    }

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
    if (language.code == 'ta') {
      return 'தற்போதைய இடம்: $place. GPS துல்லியம் சுமார் ${snapshot.accuracy.toStringAsFixed(0)} மீட்டர்.';
    }
    if (language.code == 'te') {
      return 'ప్రస్తుత స్థానం: $place. GPS ఖచ్చితత్వం సుమారు ${snapshot.accuracy.toStringAsFixed(0)} మీటర్లు.';
    }
    if (language.code == 'ml') {
      return 'നിലവിലെ സ്ഥലം: $place. GPS കൃത്യത ഏകദേശം ${snapshot.accuracy.toStringAsFixed(0)} മീറ്റർ.';
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
        'live': 'लाइव',
        'paused': 'रोका गया',
        'focusMode': 'फ़ोकस',
        'safetyMode': 'सुरक्षा',
        'scanning':
            'लाइव स्कैनिंग शुरू है। वॉइस कमांड के लिए वॉइस कमांड बटन दबाएँ और माइक्रोफ़ोन की अनुमति दें। तस्वीर पढ़ने के लिए तस्वीर चुनें, और स्थान की जानकारी के लिए लोकेशन की अनुमति दें।',
        'languageSelected':
            'भाषा चुन ली गई है। अब से सभी ऐप निर्देश इसी भाषा में होंगे।',
        'detected': 'पहचाना गया',
        'result': 'अभी का परिणाम',
        'scanningNow': 'स्कैन किया जा रहा है',
        'analyzingNearby': 'मैं आसपास के संकेत बोर्ड देख रहा हूँ। कृपया थोड़ी देर प्रतीक्षा करें।',
        'resultReady': 'संकेत बोर्ड मिल गया। परिणाम तैयार है।',
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
        'voicePrompt': 'वॉइस कमांड तैयार हैं। स्कैन, संकेत खोजें, मैं कहाँ हूँ, या मदद बोलें।',
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
        'safetyOn':
            'सुरक्षा मोड चालू है। महत्वपूर्ण चेतावनियों को पहले बताया जाएगा।',
        'safetyOff':
            'सुरक्षा प्राथमिकता बंद है। सामान्य संकेत भी बताए जाएंगे।',
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
        'live': 'ಲೈವ್',
        'paused': 'ವಿರಾಮಗೊಳಿಸಲಾಗಿದೆ',
        'focusMode': 'ಫೋಕಸ್',
        'safetyMode': 'ಸುರಕ್ಷತೆ',
        'scanning':
            'ಲೈವ್ ಸ್ಕ್ಯಾನಿಂಗ್ ಪ್ರಾರಂಭವಾಗಿದೆ. ಧ್ವನಿ ಆಜ್ಞೆಗಳಿಗೆ ವಾಯ್ಸ್ ಕಮಾಂಡ್ ಬಟನ್ ಒತ್ತಿ ಮೈಕ್ರೋಫೋನ್ ಅನುಮತಿ ನೀಡಿ. ಚಿತ್ರ ಓದಲು ಚಿತ್ರ ಆಯ್ಕೆಮಾಡಿ; ಸ್ಥಳದ ಮಾಹಿತಿ ಪಡೆಯಲು ಸ್ಥಳ ಅನುಮತಿ ನೀಡಿ.',
        'languageSelected':
            'ಭಾಷೆಯನ್ನು ಆಯ್ಕೆ ಮಾಡಲಾಗಿದೆ. ಇನ್ನು ಮುಂದೆ ಎಲ್ಲಾ ಆಪ್ ಸೂಚನೆಗಳು ಇದೇ ಭಾಷೆಯಲ್ಲಿ ಇರುತ್ತವೆ.',
        'detected': 'ಗುರುತಿಸಲಾಗಿದೆ',
        'result': 'ಈಗಿನ ಫಲಿತಾಂಶ',
        'scanningNow': 'ಸ್ಕ್ಯಾನ್ ಮಾಡಲಾಗುತ್ತಿದೆ',
        'analyzingNearby': 'ನಿಮ್ಮ ಸುತ್ತಮುತ್ತಲಿನ ಫಲಕಗಳನ್ನು ಹುಡುಕುತ್ತಿದ್ದೇನೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಕಾಯಿರಿ.',
        'resultReady': 'ಫಲಕ ಕಂಡುಬಂದಿದೆ. ಫಲಿತಾಂಶ ಸಿದ್ಧವಾಗಿದೆ.',
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
            'ಧ್ವನಿ ಆಜ್ಞೆಗಳು ಸಿದ್ಧವಾಗಿವೆ. ಸ್ಕ್ಯಾನ್, ಫಲಕ ಹುಡುಕಿ, ನಾನು ಎಲ್ಲಿದ್ದೇನೆ, ಅಥವಾ ಸಹಾಯ ಎಂದು ಹೇಳಿ.',
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
        'safetyOn':
            'ಸುರಕ್ಷತಾ ಮೋಡ್ ಆನ್ ಆಗಿದೆ. ಪ್ರಮುಖ ಎಚ್ಚರಿಕೆಗಳನ್ನು ಮೊದಲು ತಿಳಿಸಲಾಗುತ್ತದೆ.',
        'safetyOff':
            'ಸುರಕ್ಷತಾ ಆದ್ಯತೆ ಆಫ್ ಆಗಿದೆ. ಸಾಮಾನ್ಯ ಫಲಕ ಮಾಹಿತಿಯನ್ನೂ ತಿಳಿಸಲಾಗುತ್ತದೆ.',
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
            'ಸ್ಕ್ಯಾನ್, ನಿಲ್ಲಿಸು, ಮತ್ತೆ ಹೇಳು, ಫೋಕಸ್, ಫೋಕಸ್ ನಿಲ್ಲಿಸು, ಸುತ್ತಮುತ್ತಲಿನ ಫಲಕಗಳು, ಸುರಕ್ಷತಾ ಮೋಡ್, ಇತಿಹಾಸ, ಭಾಷೆ ಬದಲಾಯಿಸು ಅಥವಾ ನ್ಯಾವಿಗೇಟ್ ಎಂದು ಹೇಳಿ.',
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

    if (language.code == 'ta') {
      const map = <String, String>{
        'live': 'நேரடி',
        'paused': 'இடைநிறுத்தப்பட்டது',
        'focusMode': 'கவனம்',
        'safetyMode': 'பாதுகாப்பு',
        'scanning': 'நேரடி ஸ்கேன் தொடங்கியுள்ளது. பலகையை கேமரா முன் வைத்து நிலையாகப் பிடியுங்கள்.',
        'languageSelected': 'மொழி தேர்ந்தெடுக்கப்பட்டது. இனி அனைத்து வழிகாட்டுதல்களும் இந்த மொழியில் இருக்கும்.',
        'detected': 'கண்டறியப்பட்டது',
        'result': 'தற்போதைய முடிவு',
        'scanningNow': 'ஸ்கேன் செய்கிறது',
        'analyzingNearby': 'உங்களைச் சுற்றியுள்ள பலகைகளைத் தேடுகிறேன். சிறிது நேரம் காத்திருக்கவும்.',
        'resultReady': 'பலகை கண்டறியப்பட்டது. முடிவு தயாராக உள்ளது.',
        'waitingForScan': 'கேமரா தயாராக உள்ளது. பலகையை முன்புறம் காட்டுங்கள்.',
        'retryCamera': 'கேமராவை மீண்டும் தொடங்கு',
        'position': 'இடம்',
        'class': 'வகை',
        'confidence': 'நம்பகத்தன்மை',
        'text': 'உரை',
        'warning': 'எச்சரிக்கை.',
        'aheadHold': 'நேராக முன்னால் உள்ளது. கேமராவை அசைக்காமல் பிடியுங்கள்.',
        'locationUnavailable': 'தற்போதைய GPS இடம் கிடைக்கவில்லை.',
        'analyzingImage': 'தேர்ந்தெடுத்த படத்தை ஆய்வு செய்கிறேன். தயவுசெய்து காத்திருக்கவும்.',
        'noSigns': 'தெளிவான பலகை எதுவும் கிடைக்கவில்லை.',
        'analysisFailed': 'படத்தை ஆய்வு செய்ய முடியவில்லை. வேறொரு படத்தைத் தேர்ந்தெடுக்கவும்.',
        'cameraError': 'கேமரா கிடைக்கவில்லை. அனுமதிகளைச் சரிபார்த்து செயலியை மீண்டும் திறக்கவும்.',
        'voicePrompt': 'குரல் கட்டளைக்குத் தயாராக உள்ளது. ஸ்கேன், நிறுத்து, மீண்டும் சொல், உதவி அல்லது மொழியை மாற்று என்று சொல்லுங்கள்.',
        'stopDone': 'ஸ்கேனிங் நிறுத்தப்பட்டது.',
        'nothingToRepeat': 'மீண்டும் சொல்ல எதுவும் இல்லை.',
        'noFocus': 'கவனம் செலுத்த பலகை எதுவும் கிடைக்கவில்லை.',
        'focusOn': 'கவனம் செலுத்தப்பட்டது',
        'focusGuide': 'பலகையை நடுவில் வைக்க தொலைபேசியை மெதுவாக நகர்த்துங்கள்.',
        'focusStopped': 'கவனம் செலுத்தும் முறை நிறுத்தப்பட்டது.',
        'safetyOn': 'பாதுகாப்பு முறை இயக்கப்பட்டுள்ளது. முக்கிய எச்சரிக்கைகள் முதலில் சொல்லப்படும்.',
        'safetyOff': 'பாதுகாப்பு முன்னுரிமை நிறுத்தப்பட்டுள்ளது.',
        'scanningSurroundings': 'சுற்றியுள்ள பலகைகளை ஸ்கேன் செய்கிறேன்.',
        'noHistory': 'சமீபத்திய பலகைகள் இல்லை.',
        'historyHas': 'வரலாற்றில் சமீபத்திய கண்டறிதல்கள் உள்ளன:',
        'navigationLimit': 'நம்பகமான தூரம் கிடைக்கும்போது மட்டுமே திசை கூறப்படும்.',
        'notUnderstood': 'புரியவில்லை. உதவி என்று சொல்லுங்கள்.',
        'demoComplete': 'பட ஆய்வு முடிந்தது.',
        'items': 'உருப்படிகள்',
        'visible': 'எனக்குத் தெரிகிறது',
        'help': 'ஸ்கேன், நிறுத்து, மீண்டும் சொல், கவனம், சுற்றியுள்ள பலகைகள், வரலாறு, மொழியை மாற்று அல்லது வழிசெலுத்து என்று சொல்லுங்கள்.',
        'upload': 'படத்தைத் தேர்ந்தெடு',
        'backCamera': 'கேமராவுக்குத் திரும்பு',
        'voiceCommands': 'குரல் கட்டளைகள்',
        'demoResults': 'பட முடிவுகள்',
        'lastSeen': 'கடைசியாகக் கண்டது',
      };
      return map[key] ?? key;
    }

    if (language.code == 'te') {
      const map = <String, String>{
        'live': 'లైవ్',
        'paused': 'నిలిపివేయబడింది',
        'focusMode': 'ఫోకస్',
        'safetyMode': 'భద్రత',
        'scanning': 'లైవ్ స్కానింగ్ ప్రారంభమైంది. బోర్డును కెమెరా ముందు స్థిరంగా పట్టుకోండి.',
        'languageSelected': 'భాష ఎంపికైంది. ఇకపై అన్ని సూచనలు ఈ భాషలో ఉంటాయి.',
        'detected': 'గుర్తించబడింది',
        'result': 'ప్రస్తుత ఫలితం',
        'scanningNow': 'స్కాన్ చేస్తోంది',
        'analyzingNearby': 'మీ చుట్టూ ఉన్న బోర్డుల కోసం చూస్తున్నాను. దయచేసి కొద్దిసేపు వేచి ఉండండి.',
        'resultReady': 'బోర్డు గుర్తించబడింది. ఫలితం సిద్ధంగా ఉంది.',
        'waitingForScan': 'కెమెరా సిద్ధంగా ఉంది. బోర్డును ముందుగా చూపించండి.',
        'retryCamera': 'కెమెరాను మళ్లీ ప్రారంభించండి',
        'position': 'స్థానం',
        'class': 'వర్గం',
        'confidence': 'నమ్మకం',
        'text': 'వచనం',
        'warning': 'హెచ్చరిక.',
        'aheadHold': 'నేరుగా ఎదురుగా ఉంది. ఫోన్‌ను స్థిరంగా పట్టుకోండి.',
        'locationUnavailable': 'ప్రస్తుత GPS స్థానం అందుబాటులో లేదు.',
        'analyzingImage': 'ఎంచుకున్న చిత్రాన్ని విశ్లేషిస్తున్నాను. దయచేసి వేచి ఉండండి.',
        'noSigns': 'స్పష్టమైన బోర్డు కనిపించలేదు.',
        'analysisFailed': 'చిత్రాన్ని విశ్లేషించలేకపోయాను. మరో చిత్రాన్ని ప్రయత్నించండి.',
        'cameraError': 'కెమెరా అందుబాటులో లేదు. అనుమతులను తనిఖీ చేసి యాప్‌ను మళ్లీ తెరవండి.',
        'voicePrompt': 'వాయిస్ ఆదేశాలు సిద్ధంగా ఉన్నాయి. స్కాన్, ఆపు, మళ్లీ చెప్పు, సహాయం లేదా భాష మార్చు అని చెప్పండి.',
        'stopDone': 'స్కానింగ్ ఆపబడింది.',
        'nothingToRepeat': 'మళ్లీ చెప్పడానికి ఏమీ లేదు.',
        'noFocus': 'ఫోకస్ చేయడానికి బోర్డు కనిపించలేదు.',
        'focusOn': 'ఫోకస్ చేయబడింది',
        'focusGuide': 'బోర్డును మధ్యలోకి తీసుకురావడానికి ఫోన్‌ను నెమ్మదిగా కదపండి.',
        'focusStopped': 'ఫోకస్ మోడ్ ఆపబడింది.',
        'safetyOn': 'భద్రతా మోడ్ ఆన్‌లో ఉంది. ముఖ్యమైన హెచ్చరికలు ముందుగా చెబుతాను.',
        'safetyOff': 'భద్రతా ప్రాధాన్యత ఆఫ్‌లో ఉంది.',
        'scanningSurroundings': 'చుట్టుపక్కల బోర్డులను స్కాన్ చేస్తున్నాను.',
        'noHistory': 'ఇటీవలి బోర్డులు లేవు.',
        'historyHas': 'చరిత్రలో ఇటీవలి గుర్తింపులు ఉన్నాయి:',
        'navigationLimit': 'నమ్మదగిన దూరం లభించినప్పుడు మాత్రమే దిశను చెబుతాను.',
        'notUnderstood': 'నాకు అర్థం కాలేదు. సహాయం అని చెప్పండి.',
        'demoComplete': 'చిత్ర విశ్లేషణ పూర్తయింది.',
        'items': 'అంశాలు',
        'visible': 'నాకు కనిపిస్తున్నవి',
        'help': 'స్కాన్, ఆపు, మళ్లీ చెప్పు, ఫోకస్, చుట్టుపక్కల బోర్డులు, చరిత్ర, భాష మార్చు లేదా నావిగేట్ అని చెప్పండి.',
        'upload': 'చిత్రాన్ని ఎంచుకోండి',
        'backCamera': 'కెమెరాకు తిరిగి వెళ్ళండి',
        'voiceCommands': 'వాయిస్ ఆదేశాలు',
        'demoResults': 'చిత్ర ఫలితాలు',
        'lastSeen': 'చివరిగా కనిపించింది',
      };
      return map[key] ?? key;
    }

    if (language.code == 'ml') {
      const map = <String, String>{
        'live': 'ലൈവ്',
        'paused': 'താൽക്കാലികമായി നിർത്തി',
        'focusMode': 'ഫോക്കസ്',
        'safetyMode': 'സുരക്ഷ',
        'scanning': 'ലൈവ് സ്കാനിംഗ് ആരംഭിച്ചു. ബോർഡ് ക്യാമറയ്ക്ക് മുന്നിൽ സ്ഥിരമായി പിടിക്കുക.',
        'languageSelected': 'ഭാഷ തിരഞ്ഞെടുത്തു. ഇനി എല്ലാ നിർദ്ദേശങ്ങളും ഈ ഭാഷയിലായിരിക്കും.',
        'detected': 'കണ്ടെത്തി',
        'result': 'നിലവിലെ ഫലം',
        'scanningNow': 'സ്കാൻ ചെയ്യുന്നു',
        'analyzingNearby': 'നിങ്ങളുടെ ചുറ്റുമുള്ള ബോർഡുകൾ പരിശോധിക്കുന്നു. ദയവായി അല്പസമയം കാത്തിരിക്കുക.',
        'resultReady': 'ബോർഡ് കണ്ടെത്തി. ഫലം തയ്യാറാണ്.',
        'waitingForScan': 'ക്യാമറ തയ്യാറാണ്. ബോർഡ് മുന്നിൽ പിടിക്കുക.',
        'retryCamera': 'ക്യാമറ വീണ്ടും ആരംഭിക്കുക',
        'position': 'സ്ഥാനം',
        'class': 'വിഭാഗം',
        'confidence': 'വിശ്വാസനില',
        'text': 'വാചകം',
        'warning': 'മുന്നറിയിപ്പ്.',
        'aheadHold': 'നേരെ മുന്നിലാണ്. ഫോൺ സ്ഥിരമായി പിടിക്കുക.',
        'locationUnavailable': 'നിലവിലെ GPS സ്ഥലം ലഭ്യമല്ല.',
        'analyzingImage': 'തിരഞ്ഞെടുത്ത ചിത്രം പരിശോധിക്കുന്നു. ദയവായി കാത്തിരിക്കുക.',
        'noSigns': 'വ്യക്തമായ ബോർഡ് കണ്ടെത്താനായില്ല.',
        'analysisFailed': 'ചിത്രം പരിശോധിക്കാൻ കഴിഞ്ഞില്ല. മറ്റൊരു ചിത്രം തിരഞ്ഞെടുക്കുക.',
        'cameraError': 'ക്യാമറ ലഭ്യമല്ല. അനുമതികൾ പരിശോധിച്ച് ആപ്പ് വീണ്ടും തുറക്കുക.',
        'voicePrompt': 'വോയ്സ് കമാൻഡുകൾ തയ്യാറാണ്. സ്കാൻ, നിർത്തുക, വീണ്ടും പറയുക, സഹായം അല്ലെങ്കിൽ ഭാഷ മാറ്റുക എന്ന് പറയുക.',
        'stopDone': 'സ്കാനിംഗ് നിർത്തി.',
        'nothingToRepeat': 'വീണ്ടും പറയാൻ ഒന്നുമില്ല.',
        'noFocus': 'ഫോക്കസ് ചെയ്യാൻ ബോർഡ് കണ്ടെത്തിയില്ല.',
        'focusOn': 'ഫോക്കസ് ചെയ്തു',
        'focusGuide': 'ബോർഡ് നടുവിലാക്കാൻ ഫോൺ പതുക്കെ നീക്കുക.',
        'focusStopped': 'ഫോക്കസ് മോഡ് നിർത്തി.',
        'safetyOn': 'സുരക്ഷാ മോഡ് ഓണാണ്. പ്രധാന മുന്നറിയിപ്പുകൾ ആദ്യം അറിയിക്കും.',
        'safetyOff': 'സുരക്ഷാ മുൻഗണന ഓഫാക്കി.',
        'scanningSurroundings': 'ചുറ്റുമുള്ള ബോർഡുകൾ സ്കാൻ ചെയ്യുന്നു.',
        'noHistory': 'സമീപകാല ബോർഡുകളില്ല.',
        'historyHas': 'ചരിത്രത്തിൽ സമീപകാല കണ്ടെത്തലുകൾ ഉണ്ട്:',
        'navigationLimit': 'വിശ്വസനീയമായ ദൂരം ലഭിക്കുമ്പോൾ മാത്രമേ ദിശ അറിയിക്കൂ.',
        'notUnderstood': 'മനസ്സിലായില്ല. സഹായം എന്ന് പറയുക.',
        'demoComplete': 'ചിത്ര പരിശോധന പൂർത്തിയായി.',
        'items': 'ഇനങ്ങൾ',
        'visible': 'എനിക്ക് കാണുന്നത്',
        'help': 'സ്കാൻ, നിർത്തുക, വീണ്ടും പറയുക, ഫോക്കസ്, ചുറ്റുമുള്ള ബോർഡുകൾ, ചരിത്രം, ഭാഷ മാറ്റുക അല്ലെങ്കിൽ നാവിഗേറ്റ് എന്ന് പറയുക.',
        'upload': 'ചിത്രം തിരഞ്ഞെടുക്കുക',
        'backCamera': 'ക്യാമറയിലേക്ക് മടങ്ങുക',
        'voiceCommands': 'വോയ്സ് കമാൻഡുകൾ',
        'demoResults': 'ചിത്ര ഫലങ്ങൾ',
        'lastSeen': 'അവസാനം കണ്ടത്',
      };
      return map[key] ?? key;
    }

    const map =
        <String, String>{
      'live': 'Live',
      'paused': 'Paused',
      'focusMode': 'Focus',
      'safetyMode': 'Safety',
      'scanning':
          'Live scanning is on. To use voice commands, tap Voice Commands and allow microphone access. Choose Upload Image to read a photo, and allow location access for location-aware guidance.',
      'languageSelected':
          'Language selected. From now on, all app guidance will use this language.',
      'detected':
          'Detected',
      'result':
          'Current result',
      'scanningNow':
          'Scanning',
      'analyzingNearby': 'I’m checking for signboards around you. Please wait a moment.',
      'resultReady': 'I found a signboard. Your result is ready.',
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
      'safetyOn':
          'Safety mode is on. Important warnings will be prioritized.',
      'safetyOff':
          'Safety priority is off. Normal sign information will be announced.',
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
          'Say scan, stop, repeat, find sign, stop focus, scan surroundings, what signs, where, safety mode, normal mode, change language, history, or navigate.',
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
    // The microphone button toggles a voice-command session. Each command
    // gets a fresh recognition turn, and listening resumes after its reply.
    if (_voiceSessionActive) {
      _voiceSessionActive = false;
      listening = false;
      await voice.stop();
      if (mounted) setState(() {});
      return;
    }

    _voiceSessionActive = true;
    if (mounted) setState(() {});

    await announcements.stopAndClear();
    await tts.stop();

    try {
      final microphoneAllowed = await _requestPermissionWithVoice(
        Permission.microphone,
        'microphone',
      );
      if (!microphoneAllowed || !mounted) return;

      _executingVoiceCommand = true;
      await speakRaw(copy('voicePrompt'));
      _executingVoiceCommand = false;

      while (_voiceSessionActive && mounted) {
        listening = true;
        if (mounted) setState(() {});

        final result = await voice.listen(
          localeId: language.speechLocale,
          timeout: const Duration(seconds: 10),
        );

        listening = false;
        if (mounted) setState(() {});

        // A button tap cancels the active listen and exits the loop.
        if (!_voiceSessionActive || !mounted) break;

        if (result == null || result.trim().isEmpty) {
          // Keep the session active without spinning rapidly when Android
          // returns no transcript for a listening turn.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // Pause new camera scans only while the command response is being
        // handled, so speech output and live detection do not compete.
        _executingVoiceCommand = true;
        try {
          await command(result);
        } finally {
          _executingVoiceCommand = false;
        }
      }
    } catch (error) {
      debugPrint('[VoiceCommand] session failed: $error');
    } finally {
      listening = false;
      _voiceSessionActive = false;
      _executingVoiceCommand = false;
      if (mounted) setState(() {});
    }
  }

  String _normalizeVoiceCommand(String raw) {
    var value = raw.toLowerCase();

    // Some Android recognizers return phonetic Chinese characters when the
    // requested Indic language pack is missing or ignored. Normalize the
    // common transcript seen for "Sahaya" before the normal script filter.
    const phoneticFixes = <String, String>{
      '萨哈亚沙哈药': 'sahaya',
      '萨哈亚': 'sahaya',
      '萨哈雅': 'sahaya',
      '萨哈亚哈': 'sahaya',
      '我在哪里': 'where am i',
      '我在哪': 'where am i',
      '我在哪儿': 'where am i',
    };
    for (final entry in phoneticFixes.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    return LanguageService.normalize(value);
  }

  bool _matchesVoiceIntent(String speech, String intent) {
    final aliases = intent == 'help'
        ? <String>[
            'help', 'sahaya', 'sahaaya', 'sahayya', 'sahaiya',
            'sahayam', 'sahaya maadi', 'sahaya madi', 'sahaya please',
            'madad', 'madat', 'sahaaya maadi', 'ಸಹಾಯ', 'ಮદદ',
            'मदद', 'मदद करो', 'உதவி', 'సహాయం', 'സഹായം',
          ]
        : <String>[
            'where am i', 'where am', 'where', 'last seen',
            'yelli', 'elli', 'elli iddini', 'elli iddene',
            'nanu elli', 'naanu elli', 'nanu elli iddini',
            'naanu elli iddini', 'nanu elli iddene', 'elli idiya',
            'ellide', 'naan enga', 'nenu ekkada', 'njan evide',
            'कहाँ', 'मैं कहाँ', 'நான் எங்கே', 'நான் எங்கு',
            'నేను ఎక్కడ', 'ഞാൻ എവിടെ', 'ಎಲ್ಲಿ', 'ನಾನು ಎಲ್ಲಿದ್ದೇನೆ',
          ];

    final compactSpeech = speech.replaceAll(' ', '');
    for (final alias in aliases) {
      if (speech.contains(alias) ||
          (alias.replaceAll(' ', '').length >= 5 &&
              compactSpeech.contains(alias.replaceAll(' ', '')))) {
        return true;
      }
    }

    // Allow small speech-to-text spelling mistakes in the key command words
    // without requiring the whole sentence to match exactly.
    final words = speech.split(' ').where((word) => word.isNotEmpty).toList();
    final fuzzyTargets = intent == 'help'
        ? <String>['help', 'sahaya', 'sahaaya', 'madad']
        : <String>['where', 'yelli', 'elli', 'ekka', 'evide'];
    for (final word in words) {
      for (final target in fuzzyTargets) {
        final maxDistance = target.length >= 6 ? 2 : 1;
        if ((word.length - target.length).abs() <= maxDistance &&
            _voiceEditDistance(word, target) <= maxDistance) {
          return true;
        }
      }
    }
    return false;
  }

  int _voiceEditDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  Future<void> command(
    String raw,
  ) async {
    final speech = _normalizeVoiceCommand(raw);
    debugPrint('[VoiceCommand] raw="$raw" normalized="$speech"');

    if (speech.contains('stop focus') ||
        speech.contains('release focus') ||
        speech.contains('unfocus')) {
      focusMode = false;
      intel.clearFocus();
      await speak(copy('focusStopped'), priority: true);
      return;
    }

    if (speech.contains('safety mode') ||
        speech.contains('safety on') ||
        speech.contains('सुरक्षा') ||
        speech.contains('ಸುರಕ್ಷತೆ')) {
      safetyMode = true;
      await speak(copy('safetyOn'), priority: true);
      return;
    }

    if (speech.contains('normal mode') ||
        speech.contains('safety off') ||
        speech.contains('सामान्य मोड') ||
        speech.contains('ಸಾಮಾನ್ಯ')) {
      safetyMode = false;
      await speak(copy('safetyOff'), priority: true);
      return;
    }

    if (speech.contains('stop') ||
        speech.contains('रुको') ||
        speech.contains('निल्') ||
        speech.contains('ನಿಲ್ಲಿಸು')) {
      stopped = true;
      await announcements.stopAndClear();
      await tts.stop();
      await speakRaw(copy('stopDone'));
      return;
    }

    if (speech.contains('scan') ||
        speech.contains('continue') ||
        speech.contains('स्कैन') ||
        speech.contains('ಮುಂದುವರ') ||
        speech.contains('ಸ್ಕ್ಯಾನ್')) {
      stopped = false;
      await announcements.stopAndClear();
      await speak(copy('scanning'), priority: true);
      return;
    }

    if (speech.contains('repeat') ||
        speech.contains('दोहर') ||
        speech.contains('மீண்டும்') ||
        speech.contains('మళ్లీ') ||
        speech.contains('വീണ്ടും') ||
        speech.contains('ಮತ್ತೆ') ||
        speech.contains('ಹೇಳು') ||
        speech == 'matte' ||
        speech == 'matte helu' ||
        speech == 'matte heli' ||
        speech == 'mattelu' ||
        speech == 'mathe helu' ||
        speech == 'matte helu matte') {
      final repeatText = last.isEmpty ? copy('nothingToRepeat') : last;
      await announcements.stopAndClear();
      await tts.stop();
      await speakRaw(repeatText);
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

    if (_matchesVoiceIntent(speech, 'where')) {
      if (lastDetections.isEmpty) {
        await _speakCurrentLocationNow();
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

    // Accept regional words, Latin transliterations, and minor STT errors.
    if (_matchesVoiceIntent(speech, 'help') ||
        speech == 'help' ||
        speech == 'ಸಹಾಯ' ||
        speech == 'sahaya' ||
        speech == 'sahaaya' ||
        speech == 'madad') {
      await speak(copy('help'));
      return;
    }

    if (speech.contains('change language') ||
        speech.contains('language') ||
        speech.contains('भाषा') ||
        speech.contains('ಭಾಷೆ')) {
      await chooseLanguage(force: true);

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
                : language.code == 'ta'
                    ? 'இந்தப் பலகையிலிருந்து ஒரு இடத்தை நம்பகமாக உறுதிப்படுத்த முடியவில்லை.'
                    : language.code == 'te'
                        ? 'ఈ బోర్డు ఆధారంగా గమ్యస్థానాన్ని నమ్మకంగా నిర్ధారించలేకపోయాను.'
                        : language.code == 'ml'
                            ? 'ഈ ബോർഡിൽ നിന്ന് ഒരു ലക്ഷ്യസ്ഥാനം വിശ്വസനീയമായി സ്ഥിരീകരിക്കാനായില്ല.'
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
                : language.code == 'ta'
                    ? '${place.matchedName} இடத்திற்கு நடந்து செல்லும் வழிகாட்டுதலைத் திறந்துள்ளேன்.'
                    : language.code == 'te'
                        ? '${place.matchedName}కు నడక మార్గదర్శకాన్ని తెరిచాను.'
                        : language.code == 'ml'
                            ? '${place.matchedName} ലേക്കുള്ള നടപ്പാത നാവിഗേഷൻ തുറന്നു.'
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

    if (language.code == 'ta') {
      return speech
          .replaceAll('far left', 'மிகவும் இடப்புறம்')
          .replaceAll('slightly left', 'சற்று இடப்புறம்')
          .replaceAll('directly ahead', 'நேராக முன்னால்')
          .replaceAll('slightly right', 'சற்று வலப்புறம்')
          .replaceAll('far right', 'மிகவும் வலப்புறம்')
          .replaceAll('Warning', 'எச்சரிக்கை')
          .replaceAll('Text:', 'உரை:')
          .replaceAll('getting closer', 'அருகில் வருகிறது')
          .replaceAll('moving farther away', 'விலகிச் செல்கிறது')
          .replaceAll('The sign is far away', 'பலகை தொலைவில் உள்ளது')
          .replaceAll('The sign is approaching', 'பலகை அருகில் வருகிறது')
          .replaceAll('The sign is nearby', 'பலகை அருகில் உள்ளது');
    }
    if (language.code == 'te') {
      return speech
          .replaceAll('far left', 'చాలా ఎడమవైపు')
          .replaceAll('slightly left', 'కొద్దిగా ఎడమవైపు')
          .replaceAll('directly ahead', 'నేరుగా ఎదురుగా')
          .replaceAll('slightly right', 'కొద్దిగా కుడివైపు')
          .replaceAll('far right', 'చాలా కుడివైపు')
          .replaceAll('Warning', 'హెచ్చరిక')
          .replaceAll('Text:', 'వచనం:')
          .replaceAll('getting closer', 'దగ్గరగా వస్తోంది')
          .replaceAll('moving farther away', 'దూరంగా వెళుతోంది')
          .replaceAll('The sign is far away', 'బోర్డు దూరంగా ఉంది')
          .replaceAll('The sign is approaching', 'బోర్డు దగ్గరగా వస్తోంది')
          .replaceAll('The sign is nearby', 'బోర్డు దగ్గరలో ఉంది');
    }
    if (language.code == 'ml') {
      return speech
          .replaceAll('far left', 'വളരെ ഇടതുവശത്ത്')
          .replaceAll('slightly left', 'അൽപ്പം ഇടതുവശത്ത്')
          .replaceAll('directly ahead', 'നേരെ മുന്നിൽ')
          .replaceAll('slightly right', 'അൽപ്പം വലതുവശത്ത്')
          .replaceAll('far right', 'വളരെ വലതുവശത്ത്')
          .replaceAll('Warning', 'മുന്നറിയിപ്പ്')
          .replaceAll('Text:', 'വാചകം:')
          .replaceAll('getting closer', 'അടുത്തേക്ക് വരുന്നു')
          .replaceAll('moving farther away', 'അകന്നുപോകുന്നു')
          .replaceAll('The sign is far away', 'ബോർഡ് ദൂരെയാണ്')
          .replaceAll('The sign is approaching', 'ബോർഡ് അടുത്തേക്ക് വരുന്നു')
          .replaceAll('The sign is nearby', 'ബോർഡ് സമീപത്തുണ്ട്');
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
    String speech, {
    bool priority = false,
  }) async {
    last = speech;

    final localizedSpeech =
        localize(speech);

    if (mounted) {
      setState(() {
        status =
            localizedSpeech;
      });
    }

    if (priority) {
      // Safety/location/action feedback should not wait behind an old,
      // lengthy sign narration. Stop the active utterance and discard stale
      // queued speech before announcing the new priority message.
      await announcements.stopAndClear();
      await tts.stop();
    }

    await announcements.enqueue(
      localizedSpeech,
      priority: priority,
      interrupt: priority,
    );
  }

  Future<void> _speakQueued(
    String text, {
    bool interrupt = false,
  }) async {
    await tts.speak(text, interrupt: interrupt);
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
      height: 58,
      child: FilledButton.tonal(
        onPressed: () => _selectLanguageFromButton(code),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF202D43),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF59D6C8).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.language_rounded, size: 19, color: Color(0xFF7FE4D8)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF9CAAC0)),
          ],
        ),
      ),
    );
  }

  String _quickActionText(String key) {
    const labels = <String, Map<String, String>>{
      'en': {
        'title': 'Quick actions',
        'history': 'History',
        'repeat': 'Repeat',
        'scan': 'Scan',
        'find': 'Find sign',
        'language': 'Change language',
      },
      'hi': {
        'title': 'त्वरित विकल्प',
        'history': 'इतिहास',
        'repeat': 'फिर से सुनें',
        'scan': 'स्कैन करें',
        'find': 'संकेत खोजें',
        'language': 'भाषा बदलें',
      },
      'kn': {
        'title': 'ತ್ವರಿತ ಆಯ್ಕೆಗಳು',
        'history': 'ಇತಿಹಾಸ',
        'repeat': 'ಮತ್ತೆ ಹೇಳಿ',
        'scan': 'ಸ್ಕ್ಯಾನ್',
        'find': 'ಫಲಕ ಹುಡುಕಿ',
        'language': 'ಭಾಷೆ ಬದಲಾಯಿಸಿ',
      },
      'ta': {
        'title': 'விரைவு செயல்கள்',
        'history': 'வரலாறு',
        'repeat': 'மீண்டும் சொல்லவும்',
        'scan': 'ஸ்கேன்',
        'find': 'பலகையைத் தேடு',
        'language': 'மொழியை மாற்று',
      },
      'te': {
        'title': 'త్వరిత చర్యలు',
        'history': 'చరిత్ర',
        'repeat': 'మళ్లీ చెప్పు',
        'scan': 'స్కాన్',
        'find': 'బోర్డును కనుగొను',
        'language': 'భాష మార్చు',
      },
      'ml': {
        'title': 'ദ്രുത പ്രവർത്തനങ്ങൾ',
        'history': 'ചരിത്രം',
        'repeat': 'വീണ്ടും പറയുക',
        'scan': 'സ്കാൻ',
        'find': 'ബോർഡ് കണ്ടെത്തുക',
        'language': 'ഭാഷ മാറ്റുക',
      },
    };
    return labels[language.code]?[key] ?? labels['en']![key]!;
  }

  Future<void> _showQuickActions() async {
    final actions = <Map<String, Object>>[
      {
        'label': _quickActionText('history'),
        'command': 'history',
        'icon': Icons.history_rounded,
      },
      {
        'label': _quickActionText('repeat'),
        'command': 'repeat',
        'icon': Icons.replay_rounded,
      },
      {
        'label': _quickActionText('scan'),
        'command': 'scan',
        'icon': Icons.document_scanner_rounded,
      },
      {
        'label': _quickActionText('find'),
        'command': 'find sign',
        'icon': Icons.center_focus_strong_rounded,
      },
      {
        'label': _quickActionText('language'),
        'command': 'change language',
        'icon': Icons.language_rounded,
      },
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF101A2B),
      barrierColor: Colors.black.withValues(alpha: 0.68),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF59D6C8).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.grid_view_rounded, color: Color(0xFF7FE4D8)),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _quickActionText('title'),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Tap an action if you prefer not to use voice.',
                          style: TextStyle(fontSize: 12, color: Color(0xFFB8C4D8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: actions.map((action) {
                  return SizedBox(
                    width: 155,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await command(action['command'] as String);
                      },
                      icon: Icon(action['icon'] as IconData),
                      label: Text(
                        action['label'] as String,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF202D43),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 58),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _demoResultView() {
    final image = demoImage;
    if (image == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              image,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            right: 18,
            bottom: 94,
            child: Semantics(
              button: true,
              label: _quickActionText('title'),
              child: Tooltip(
                message: _quickActionText('title'),
                child: FloatingActionButton.small(
                  heroTag: 'quickHelpButton',
                  onPressed: _showQuickActions,
                  child: const Icon(Icons.help_outline_rounded),
                ),
              ),
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
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                        onPressed: processing ? null : closeDemo,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: Text(copy('backCamera')),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 58),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: const Color(0xFF0A1220),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF122B3A), Color(0xFF0A1220), Color(0xFF171B35)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: const Color(0xFF59D6C8).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF59D6C8).withValues(alpha: 0.24)),
                        ),
                        child: const Icon(Icons.record_voice_over_rounded, size: 34, color: Color(0xFF7FE4D8)),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Welcome to\nSightToSound',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.08,
                          letterSpacing: -0.8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Let’s start with the language you feel most comfortable hearing.',
                        style: TextStyle(fontSize: 16, height: 1.5, color: Color(0xFFD0D9E8)),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hearing_rounded, color: colors.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                status,
                                style: const TextStyle(fontSize: 13, color: Color(0xFFB8C4D8), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'CHOOSE YOUR LANGUAGE',
                        style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xFF8CE9DE)),
                      ),
                      const SizedBox(height: 14),
                      _languageButton('English', 'en'),
                      const SizedBox(height: 10),
                      _languageButton('हिन्दी  •  Hindi', 'hi'),
                      const SizedBox(height: 10),
                      _languageButton('ಕನ್ನಡ  •  Kannada', 'kn'),
                      const SizedBox(height: 10),
                      _languageButton('தமிழ்  •  Tamil', 'ta'),
                      const SizedBox(height: 10),
                      _languageButton('తెలుగు  •  Telugu', 'te'),
                      const SizedBox(height: 10),
                      _languageButton('മലയാളം  •  Malayalam', 'ml'),
                      const SizedBox(height: 18),
                      const Center(
                        child: Text(
                          'You can change this later from Quick Actions.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF8D9CB4), height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Uploaded-image mode does not need a live camera controller.
    // Render it before the camera-ready guard so the result remains visible
    // and the user can upload a second image without a blank screen.
    if (demoMode && demoImage != null) {
      return _demoResultView();
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
                    onPressed: _restartCamera,
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
            right: 18,
            bottom: 94,
            child: Semantics(
              button: true,
              label: _quickActionText('title'),
              child: Tooltip(
                message: _quickActionText('title'),
                child: FloatingActionButton.small(
                  heroTag: 'liveQuickHelpButton',
                  onPressed: _showQuickActions,
                  child: const Icon(Icons.help_outline_rounded),
                ),
              ),
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
                                ? copy('paused')
                                : '${copy('live')} • ${language.name}${focusMode ? ' • ' + copy('focusMode') : ''}${safetyMode ? ' • ' + copy('safetyMode') : ''}',
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
                      label: safetyMode ? copy('safetyOff') : copy('safetyOn'),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: safetyMode
                              ? Colors.orange.shade800
                              : Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          tooltip: safetyMode ? copy('safetyOff') : copy('safetyOn'),
                          onPressed: () async {
                            setState(() => safetyMode = !safetyMode);
                            await speak(
                              safetyMode ? copy('safetyOn') : copy('safetyOff'),
                              priority: true,
                            );
                          },
                          icon: Icon(
                            safetyMode
                                ? Icons.health_and_safety_rounded
                                : Icons.shield_outlined,
                          ),
                        ),
                      ),
                    ),
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
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1728).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: commands,
                            icon: Icon(
                              _voiceSessionActive ? Icons.hearing_rounded : Icons.mic_rounded,
                            ),
                            label: Text(
                              _voiceSessionActive
                                  ? 'Voice commands on · tap to stop'
                                  : copy('voiceCommands'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: const Color(0xFF59D6C8),
                              foregroundColor: const Color(0xFF062A2A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: pickDemoImage,
                                icon: const Icon(Icons.add_photo_alternate_rounded),
                                label: Text(copy('upload'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => command(stopped ? 'scan' : 'stop'),
                                icon: Icon(stopped ? Icons.play_arrow_rounded : Icons.pause_rounded),
                                label: Text(
                                  stopped ? copy('scan') : copy('paused'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
    announcements.clear();
    tts.stop();
    super.dispose();
  }
}