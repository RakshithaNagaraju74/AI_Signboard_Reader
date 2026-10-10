<div align="center">

<img src="assets/images/app_logo.png" alt="SightToSound app logo" width="140" />

# SightToSound

### From Sight to Sound. From Sound to Freedom.

**An AI-powered, voice-first signboard reader designed to make everyday visual information more accessible to blind and visually impaired people.**

[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![On-device AI](https://img.shields.io/badge/AI-On--device%20inference-6C5CE7)](#how-it-works)
[![Accessibility](https://img.shields.io/badge/Focus-Accessibility-168B65)](#accessibility-by-design)
[![License](https://img.shields.io/badge/License-%20MIT-lightgrey)](#license)

[Explore the code](https://github.com/RakshithaNagaraju74/AI_Signboard_Reader) · [Report a bug](https://github.com/RakshithaNagaraju74/AI_Signboard_Reader/issues) · [Request a feature](https://github.com/RakshithaNagaraju74/AI_Signboard_Reader/issues)

</div>

---

## The idea

A signboard can tell someone where to go, what to avoid, or which service is nearby. For a person who cannot easily read visual signs, that information may be difficult to access independently.

**SightToSound turns signboard imagery into spoken, contextual guidance.** It combines a camera, an on-device sign detector, optical character recognition (OCR), spatial reasoning, speech input and output, and optional AI-assisted narration. The goal is not simply to detect an object: it is to communicate useful information in a way that sounds natural and is easier to act on.

The project is built with Flutter and is intended for real-world accessibility exploration as well as academic demonstration. It is an assistive aid—not a replacement for a cane, guide dog, accessible pedestrian signals, or a user's own safety judgement.

## At a glance

| | |
|---|---|
| **Application** | SightToSound — AI Signboard Reader |
| **Platform/framework** | Flutter / Dart |
| **Primary use** | Spoken sign recognition and situational awareness |
| **Vision model** | YOLO-style object detector exported to TensorFlow Lite |
| **Text recognition** | Google ML Kit Text Recognition, with image crop and preprocessing strategies |
| **Voice** | Speech-to-text commands and text-to-speech narration |
| **Languages** | English, Hindi, and Kannada UI/voice flows |
| **Context** | GPS location, reverse-geocoded place names, optional OpenStreetMap/Nominatim place verification |
| **Optional narration service** | Groq-compatible chat-completions API; local fallback when unavailable |
| **State and history** | Provider, SharedPreferences |
| **Current package version** | `2.6.0+10` |

> **Project status:** This repository contains an actively developed Flutter application. Device-specific behavior, model quality, language availability, API access, and Android build compatibility should be verified in the target environment before a public release.

## What it can do

### 📷 Live signboard reading
- Uses the device camera to periodically analyze the scene.
- Runs the bundled TensorFlow Lite model to detect supported sign categories.
- Draws detection overlays and filters weak/duplicate predictions.
- Uses tracking across successive frames to reduce unstable or repetitive announcements.
- Supports an image-upload/demo path so a saved signboard photo can be analyzed through the app.

### 🔎 Read the words on a sign
- Runs OCR on the detected sign region and can fall back to full-image recognition.
- Expands the crop around the detection to avoid clipping text at the edges.
- Tries multiple image variants, including upscaling and contrast-oriented preprocessing, then prefers a readable candidate.
- Combines the detected category with readable sign text when preparing a spoken result.

OCR is best-effort. The current OCR service selects Devanagari recognition for Hindi and Latin recognition for other configured languages; Kannada voice/UI support does **not** currently mean full Kannada-script OCR support. Blur, glare, low contrast, unusual fonts, small text, perspective, occlusion, and language/script support can also affect results.

### 🧭 Spatial and temporal guidance
The live reader estimates where a detected sign appears in the camera frame and describes it using five relative zones:

- **Far left**
- **Slightly left**
- **Directly ahead**
- **Slightly right**
- **Far right**

It also tracks a sign across frames to infer relative visual changes, such as moving left/right in the frame or appearing larger/smaller. Detection priority can take confidence, relative box area, OCR availability, focus, and safety-related categories into account.

**These are visual estimates, not calibrated navigation measurements.** A sign appearing on the left of the camera is not, by itself, an instruction to turn left.

### 🎯 Focus and scene modes
- **Focus mode:** the voice command “find sign” prioritizes a visible sign and can provide alignment feedback.
- **Scene mode:** commands such as “scan surroundings” and “what signs” request a summary of multiple visible signs.
- Safety-oriented categories can receive higher announcement priority.
- Cooldowns and stability checks help avoid repeatedly announcing the same unchanged detection.

### 🗣️ Voice-first interaction
- Offers a first-run language selection flow and remembers the user's preference.
- Supports English, Hindi, and Kannada language choices for the app's voice flows.
- Uses speech recognition for supported commands and text-to-speech for announcements.
- Includes controls/commands for scanning, stopping, repeating information, focusing a sign, scanning the surroundings, checking history, changing language, and requesting navigation context.
- Queues announcements to reduce speech interruptions.

Actual speech-recognition and text-to-speech availability depends on the operating system, installed language packs, device settings, microphone permission, and ambient noise.

### 📍 Location-aware context
- Requests device location when available and can reverse-geocode coordinates into a human-readable place/address.
- Can save a phone-location snapshot with a detection in history.
- Can compare readable place/business text against OpenStreetMap/Nominatim search results when location quality and text are sufficient.
- Can open walking directions for a sufficiently verified destination.

Map matches are supporting evidence, not ground truth. Map coverage, geocoder responses, OCR accuracy, GPS accuracy, and network access vary.

### ✨ Natural narration with a fallback
The app separates structured detection evidence from the final user-facing narration. When configured, the optional Groq-compatible API can compose a concise spoken explanation using fields such as detected category, OCR text, relative position, motion/proximity cues, safety relevance, and available place context.

If the API key is missing, a request fails, or the generated response does not meet the app's language checks, the app can use deterministic local narration instead. **Cloud narration is optional; camera inference and the local narration fallback do not require a Groq API key.**

## Supported sign categories

The bundled label file defines **21 classes**:

| # | Class | # | Class |
|---:|---|---:|---|
| 0 | Warning sign | 11 | TRA sign |
| 1 | Construction sign | 12 | Bicycle sign |
| 2 | Turn-left sign | 13 | Stop-request bell |
| 3 | Turn-right sign | 14 | Wet-floor sign |
| 4 | Junction or merge sign | 15 | Pedestrian crossing |
| 5 | School zone | 16 | Accessibility sign |
| 6 | Speed limit | 17 | Ladies' restroom |
| 7 | Bus stop | 18 | Men's restroom |
| 8 | Shop sign | 19 | Pedestrian “don't walk” |
| 9 | Public information | 20 | Tactile paving |
| 10 | MRT sign | | |

These are the categories configured in `assets/models/labels.txt` and `assets/models/classes.json`. Real-world performance depends on the model's training data and the conditions in which a sign is captured; a listed class is not a guarantee of correct recognition.

## How it works

```text
Camera frame / selected image
            │
            ▼
Image decoding and preprocessing
            │
            ▼
TensorFlow Lite sign detection
            │
            ▼
Confidence filtering + non-maximum suppression
            │
            ▼
Detection tracking and relative-position analysis
            │
            ├──────────────► OCR on sign crop / image variants
            │                         │
            └─────────────────────────┘
                                      ▼
                      Optional location/place context
                                      │
                                      ▼
                 Local narration or optional AI narration
                                      │
                                      ▼
                       Spoken guidance + visual results
                                      │
                                      ▼
                    Optional detection history / directions
```

### Codebase map

| Path | Responsibility |
|---|---|
| `lib/main.dart` | App entry point, theme, Provider setup, optional environment loading |
| `lib/screens/` | Splash/onboarding, home, live camera, gallery, and result screens |
| `lib/models/detection_result.dart` | Structured detection result model |
| `lib/models/sign_model.dart` | UI state for selected images, processing, and detections |
| `lib/services/tflite_service.dart` | Model initialization, image preprocessing, inference, and detection parsing |
| `lib/services/ocr_service.dart` | OCR, sign-region cropping, image variants, and text selection |
| `lib/services/detection_intelligence.dart` | Tracking, relative position, stability, priority, and proximity cues |
| `lib/services/ai_speech_service.dart` | Optional API narration and deterministic fallback |
| `lib/services/tts_service.dart` | Spoken output |
| `lib/services/voice_command_service.dart` | Speech recognition and command input |
| `lib/services/language_service.dart` | Language selection, normalization, and preference persistence |
| `lib/services/location_service.dart` | GPS, reverse geocoding, and location context |
| `lib/services/place_verification_service.dart` | Optional OpenStreetMap/Nominatim place matching |
| `lib/services/history_service.dart` | Local detection-history persistence |
| `lib/services/announcement_queue_service.dart` | Ordered speech announcements |
| `lib/widgets/` | Reusable sign cards and detection overlays |
| `assets/models/best.tflite` | Bundled TensorFlow Lite model |
| `assets/models/labels.txt` | Model label order |
| `assets/models/classes.json` | Numeric class-ID mapping |
| `ai-signboard-reader-with-eval (1).ipynb` | Notebook artifact for model experimentation/evaluation |
| `assets/images/app_logo.png` | App branding |
| `test/` | Flutter tests |
| `.github/workflows/flutter_ci.yml` | Automated analysis, tests, and Android debug build |

## Technology stack

- **Flutter + Dart** — cross-platform application UI and application logic.
- **TensorFlow Lite via `flutter_litert`** — local sign-detection inference.
- **Google ML Kit Text Recognition** — OCR for supported scripts.
- **Camera and image-picker plugins** — live frames and image selection.
- **Flutter TTS + speech-to-text** — spoken output and voice commands.
- **Geolocator + Geocoding** — location retrieval and human-readable place information.
- **OpenStreetMap Nominatim** — optional place-name lookup for verification context.
- **Provider + SharedPreferences** — state management and saved preferences/history.
- **Optional Groq-compatible API** — AI-assisted natural narration.
- **GitHub Actions** — Flutter quality checks and Android debug-build verification.

## Getting started

### 1. Install the prerequisites

Install the following on your development machine:

- [Flutter SDK (stable channel)](https://docs.flutter.dev/get-started/install)
- [Android Studio](https://developer.android.com/studio) or Android SDK command-line tools
- Android SDK / platform tools and a compatible JDK (Java 17 is used by the Android build configuration)
- A physical Android device with developer options and USB debugging enabled, or an Android emulator with camera support

Check the setup:

```powershell
flutter doctor
flutter --version
```

### 2. Clone the repository

```powershell
git clone https://github.com/RakshithaNagaraju74/AI_Signboard_Reader.git
cd AI_Signboard_Reader
```

### 3. Install dependencies

```powershell
flutter pub get
```

The model and its label files are expected at the paths already declared in `pubspec.yaml`. If you replace the model, make sure the input/output tensor shapes and class ordering still match the assumptions in `lib/services/tflite_service.dart`.

### 4. Configure optional AI narration

The app reads these variables from a local `.env` file:

```dotenv
GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=openai/gpt-oss-20b
GROQ_BASE_URL=https://api.groq.com/openai/v1
```

Copy the example configuration into a local `.env` file:

```powershell
Copy-Item .env.example .env
notepad .env
```

Replace `your_groq_api_key` with your own key. The checked-in `.env.example` contains placeholders only. The app loads `.env` on startup; a configured key is **not** required to launch the app or use the local fallback narration.

**Security:** `.env` is intended to remain local and is gitignored. Never commit an API key, paste it into screenshots/logs, or ship a private provider key inside a production APK. For a public production release, move authenticated AI requests behind a trusted backend. If you use `--dart-define` for local experiments, remember that compile-time values embedded in a client app are not a secure secret store.

### 5. Run on a device

Connect an Android device, accept its USB debugging prompt, and run:

```powershell
flutter devices
flutter run
```

For verbose diagnostics:

```powershell
flutter run -v
```

The first run may take longer while Gradle downloads dependencies and Flutter builds the native Android components.

### 6. Build a debug APK

```powershell
flutter build apk --debug
```

The output is normally written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

This is a **debug build**, not a signed production release. A production build needs an appropriate release-signing configuration and release testing.

## Using the app

1. Launch SightToSound and complete the language selection when prompted.
2. Grant camera permission to start live scanning.
3. Grant microphone permission when using voice commands.
4. Grant location permission only if you want location-aware context and history.
5. Point the camera toward a signboard and hold the phone reasonably steady while it is analyzed.
6. Listen to the spoken summary and use the on-screen result/controls for more context.
7. Use the saved-image/demo flow to analyze an existing photo.
8. Try supported voice commands such as **“find sign,” “scan surroundings,”** or **“what signs.”** Exact command recognition depends on the selected language and device speech engine.
9. Use navigation links only as an additional aid and independently verify the route and surroundings.

## Accessibility by design

SightToSound aims to make its own interface easier to use with spoken interaction and clear controls:

- Language selection is available during onboarding and can be revisited.
- Important detections can be spoken without requiring the user to read raw class IDs or confidence values.
- Announcements are prioritized and queued to reduce overlapping speech.
- Repeated detections are stabilized and rate-limited where possible.
- Safety-relevant classes can receive higher priority.
- A local narration fallback helps retain core spoken feedback when the optional AI service is unavailable.

Accessibility is an ongoing engineering goal, not a claim of certification. Please test with screen readers, different speech engines, varied lighting and outdoor noise, and feedback from blind and low-vision users before relying on the app in unfamiliar environments.

## Safety, privacy, and known limitations

This project is an assistive prototype and can make mistakes. Keep these limitations in mind:

- **Not a certified navigation or obstacle-avoidance system.** Never rely on the app alone when crossing roads, navigating traffic, or identifying hazards.
- **Relative position is camera-frame position.** It is not a compass bearing, road direction, or instruction to turn.
- **No exact distance is inferred from bounding-box size.** Apparent size changes provide only relative visual cues unless a calibrated depth source is added.
- **GPS locates the phone, not necessarily the sign.** Phone coordinates do not prove a sign's exact location, direction, or distance.
- **OCR and object detection can be wrong.** Low confidence, clutter, blur, glare, and unfamiliar signs can produce incorrect or incomplete results.
- **Place verification is approximate.** Nominatim results can be missing or outdated and should not override what is physically present.
- **Network features need connectivity.** Optional AI narration and online place lookup may fail offline or be rate-limited.
- **Device permissions matter.** Camera, microphone, and location functionality depends on permissions and system settings.
- **Language support is device-dependent.** The app can request a language, but the operating system must provide compatible recognition and synthesis resources.
- **Location and history are sensitive.** The app may store detection text and phone coordinates locally. Review permissions and stored history before sharing a device or diagnostic data.

### Data and network notes

- The TensorFlow Lite model is bundled with the app and used for local inference.
- Optional AI narration sends structured detection/context data to the configured API provider when enabled.
- Place verification sends a text query to OpenStreetMap Nominatim when the feature is used.
- Location services and reverse geocoding may use platform services.
- Local preferences and detection history are stored using SharedPreferences.

Configure only the permissions and external services you need. Do not submit personal location history or API credentials in bug reports.

## Testing and continuous integration

The repository includes a GitHub Actions workflow at `.github/workflows/flutter_ci.yml`. On pushes and pull requests targeting `main`, it is configured to:

1. Set up Flutter stable.
2. Create an empty optional API configuration for CI.
3. Run `flutter pub get`.
4. Run `flutter analyze`.
5. Run `flutter test`.
6. Build an Android debug APK.

You can run the same core checks locally:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Passing static analysis or a debug build does not prove the app is accurate or safe in every environment. Test on real devices and representative signboards as well.

## Working on the project

Useful places to start:

- **Change detection behavior:** `lib/services/tflite_service.dart`
- **Improve text extraction:** `lib/services/ocr_service.dart`
- **Tune relative positioning and announcement stability:** `lib/services/detection_intelligence.dart`
- **Adjust voice commands and language handling:** `lib/services/voice_command_service.dart`, `lib/services/language_service.dart`
- **Modify narration:** `lib/services/ai_speech_service.dart`
- **Update the sign taxonomy:** update the model, `assets/models/labels.txt`, and `assets/models/classes.json` together, then validate the output shape and class order.
- **Update app branding:** replace `assets/images/app_logo.png` and regenerate launcher assets if necessary.

For changes to the model, verify the expected `[1, 416, 416, 3]` float32 input and the model output layout expected by the parser. A label-order mismatch can silently make otherwise valid detections appear as the wrong class.

## Contributing

Contributions, bug reports, accessibility feedback, and ideas are welcome.

1. Open an issue describing the problem or proposal.
2. Create a focused branch for your change.
3. Keep changes scoped and explain any model, platform, or permission implications.
4. Run analysis and tests, and build the Android debug APK when relevant.
5. Include device/OS details and reproducible steps in bug reports—never include API keys or private location data.

## Roadmap ideas

Potential areas for future work include:

- Broader real-world evaluation across lighting, angles, sign types, and distances.
- More robust OCR for additional scripts and languages.
- Better accessibility testing with blind and low-vision participants.
- Improved on-device performance and power usage.
- A safer backend architecture for production AI narration.
- Clearer model evaluation metrics, sample demonstrations, and release packaging.

These are possible directions, not promises about current functionality.

## License

This project is licensed under the MIT License.

---

<div align="center">

**SightToSound**  
*From Sight to Sound. From Sound to Freedom.*

Built to make visual information more accessible—one sign at a time.

</div>


## Multilingual OCR with OCR.Space

SightToSound can use the OCR.Space API's Engine 3 for Kannada, Tamil, Telugu, Hindi, and stylized signboard text. Engine 3 supports more than 200 languages and is the cloud OCR path for these Indic scripts. English and other supported Latin-language scans continue using fast on-device OCR first, with OCR.Space as a fallback when local text is empty or weak. Images are cropped and enlarged locally before upload.

### Configure the API key

1. Get a key from [OCR.Space's free API page](https://ocr.space/ocrapi/freekey).
2. Copy `.env.example` to `.env` if you do not already have one:
   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```
3. Set `OCR_SPACE_API_KEY=your_real_key` in your local `.env` file. Keep the key private and do not commit `.env`.
4. Run:
   ```powershell
   flutter pub get
   flutter clean
   flutter run
   ```

OCR.Space's free plan has monthly limits, including a smaller quota for Engine 3. Cloud OCR requires internet and sends the cropped sign image to OCR.Space. If the API key or network is unavailable, the app falls back to the existing on-device recognizer. API keys embedded in a mobile app can be extracted from a built APK, so use a trusted backend proxy for a public production release. Never commit your personal key to GitHub.

The previous native Tesseract Android dependency has been removed because the configured artifact could not be resolved by Gradle. This avoids that build failure. The GitHub connector cannot execute Flutter or Android builds, so run the commands above on your computer before merging.

## Accessible permission prompts and narration

Before Android displays camera, microphone, or location permission dialogs, SightToSound speaks what the permission is for and asks the user to choose Allow. If a permission was permanently denied, the app explains that it must be enabled in Android app settings. Microphone permission is requested when voice commands are used; location permission is requested for location-aware guidance.

Groq narration validation allows useful Latin-script brand names inside otherwise Hindi/Kannada narration instead of rejecting the entire answer. OCR debug wrappers such as `--- OCR Start ---` and `--- OCR End ---` are removed before narration, and the offline fallback avoids reading long Latin-heavy OCR fragments as Kannada.

Keep your actual `.env` file private. Add your personal `OCR_SPACE_API_KEY` and optional Groq credentials locally; do not commit real keys to GitHub. OCR.Space sends the selected sign crop to its API, so cloud OCR requires an internet connection. If the API is unavailable, SightToSound falls back to on-device OCR where supported.
