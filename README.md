<div align="center">

<img src="assets/images/app_logo.png" alt="SightToSound app logo" width="140" />

# SightToSound

### From Sight to Sound. From Sound to Freedom.

**An AI-powered, voice-first signboard reader that helps blind and low-vision users access the information printed on everyday signs.**

[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![On-device inference](https://img.shields.io/badge/Inference-On--device-6C5CE7)](#system-architecture)
[![Accessibility](https://img.shields.io/badge/Designed%20for-Accessibility-168B65)](#accessibility-by-design)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)

[Repository](https://github.com/RakshithaNagaraju74/AI_Signboard_Reader) · [Issues and feedback](https://github.com/RakshithaNagaraju74/AI_Signboard_Reader/issues)

</div>

---

## 1. Project overview

A signboard can tell someone where a destination is, which direction to follow, whether an area is restricted, or where a public service is located. When that information is available only visually, blind and low-vision people can face an avoidable barrier.

**SightToSound is a voice-first accessibility prototype that turns signboard images into spoken information and contextual guidance.** It combines an on-device sign detector, multilingual text recognition, relative-position analysis, speech commands, text-to-speech, optional AI narration, and location-aware place lookup.

The design goal is to communicate *what the sign says*, *where it appears in the camera view*, and—when evidence is sufficient—*whether the text may refer to a known place*. It aims to be useful with minimal interaction, while still offering a visual interface for sighted users, evaluators, and caregivers.

SightToSound is an assistive aid, not a certified navigation system. It does not replace a cane, guide dog, accessible pedestrian signals, or independent safety judgement.

## 2. Project at a glance

| Area | Implementation |
|---|---|
| App | SightToSound / AI Signboard Reader |
| Framework | Flutter and Dart |
| App state | Provider |
| Sign detection | Bundled TensorFlow Lite model through `flutter_litert` |
| Local OCR | Google ML Kit Text Recognition, crop expansion, image upscaling and contrast variants |
| Multilingual OCR | Optional OCR.Space API, Engine 3, with automatic language detection |
| Indic-script OCR path | OCR.Space is attempted first for Hindi, Kannada, Tamil and Telugu language codes |
| AI narration | Optional Groq-compatible chat-completions API |
| Offline/low-connectivity narration | Deterministic local narration fallback |
| Voice input/output | `speech_to_text` and `flutter_tts` |
| Location | `geolocator`, `geocoding`, OpenStreetMap Nominatim place lookup |
| Local persistence | SharedPreferences for preferences and detection history |
| Version in `pubspec.yaml` | `2.6.0+10` |

### Current language scope

- **App language and narration choices:** English, Hindi, Kannada, Tamil, Telugu and Malayalam. Voice quality and language availability depend on the Android TTS/STT engines installed on the device.
- **OCR language detection:** OCR.Space is configured for automatic language detection and is used for Kannada, Tamil, Telugu and Hindi paths; the service may also be used as a fallback for other scripts or weak local OCR.
- **Important distinction:** recognizing Tamil or Telugu text does not mean the app currently offers a complete Tamil or Telugu voice-command/onboarding experience. Speech recognition and TTS support also depend on the Android device and its installed language resources.

## 3. Features

### Live camera and saved-image scanning

- Opens the device camera and periodically analyzes frames.
- Detects supported sign categories with the bundled TensorFlow Lite model.
- Draws bounding-box overlays and exposes readable results in the interface.
- Supports selecting a saved image for analysis, useful for testing and demonstrations.
- Tracks detections across frames and applies stability/cooldown logic to reduce repeated announcements.

### Multilingual OCR for real-world signboards

A sign can use a regional script, stylized lettering, mixed-language text, or a combination of local and English names. SightToSound therefore uses a layered OCR approach rather than relying on one recognizer for every case.

1. **Locate the sign.** Use the detected sign bounding box to extract a region of interest.
2. **Preserve context.** Expand the crop slightly so edge characters are less likely to be clipped.
3. **Prepare the image.** Decode and orient the image, enlarge small text, and generate grayscale/contrast-oriented variants.
4. **Use the appropriate OCR path.** The app keeps Google ML Kit as the fast local recognizer for supported scripts. When the selected OCR language is Hindi, Kannada, Tamil or Telugu, it attempts OCR.Space Engine 3 with automatic language detection on the cropped sign. For other language selections, it tries local OCR first and can ask OCR.Space to help when the local result is empty, weak or inconsistent.
5. **Compare candidates.** Text candidates are normalized and scored; the app considers results from the sign crop and nearby/full-frame text rather than blindly accepting the first partial result.
6. **Narrate the result.** OCR text is passed as evidence to the narration layer, alongside the detected sign class and visual context.

OCR.Space is an **online service**. It requires an internet connection, a valid `OCR_SPACE_API_KEY`, and available plan quota. The crop is sent to OCR.Space for recognition. If the API key is missing or the request fails, the app attempts the available local OCR path; local script coverage is not equivalent for every language. OCR can still fail on motion blur, glare, low contrast, perspective distortion, tiny lettering, decorative fonts, occlusion, or a poorly framed sign.

### Relative position and changing visual context

The app describes the sign's location in the camera frame using relative zones such as far left, slightly left, directly ahead, slightly right and far right. Tracking can provide cues when a sign shifts in the frame or appears larger/smaller over time.

These cues describe the **camera view**, not a calibrated compass direction or a reliable physical distance. A sign on the left side of the image is not automatically a command to turn left.

### Focus mode, scene mode and safety prioritization

- **Focus mode:** the user can ask the app to find a sign and receive alignment-oriented feedback.
- **Scene mode:** the user can request a summary of visible signs.
- Detection confidence, sign size in the frame, OCR availability, stability and configured safety priority can influence which result is announced.
- Cooldowns and an announcement queue help reduce duplicate or overlapping speech.

### Voice-first interaction and spoken permissions

The app offers first-run language selection and remembers the chosen language. It uses speech recognition for supported voice commands and text-to-speech for responses. Permission prompts are preceded by a spoken explanation, where applicable, so the user can hear why Android is about to ask for camera, microphone or location access. If a permission is permanently denied, the app can explain that it must be enabled in system settings.

The available commands and recognition quality depend on the selected language, the device's speech service, microphone permission, ambient noise and installed language packs. On-screen controls remain available as an alternative.

### Natural-language narration with local fallback

When configured, the Groq-compatible API receives structured evidence such as the predicted sign category, OCR text, relative position, motion/proximity cues, safety relevance and available place context. It is asked to produce concise, user-friendly narration in the selected language.

The app validates the returned language/script and uses a deterministic local narration path if the API key is absent, a request fails, or the generated answer is unsuitable. OCR wrapper/debug markers are cleaned before narration, and the fallback avoids mixing unnecessary Latin-heavy OCR fragments into Kannada speech where possible.

AI narration is optional. It can improve phrasing, but it can also omit or misinterpret evidence. Treat OCR and AI-generated descriptions as fallible; the recognized sign text should remain the source evidence rather than allowing a language model to invent a destination or safety instruction.

### Location-aware place context

- Requests phone location when the feature is used and permission is available.
- Reverse-geocodes coordinates into a readable address/place context.
- Can query OpenStreetMap Nominatim to check whether text read from a sign resembles a known place.
- Can provide/open directions for a sufficiently verified destination when the app has enough information.

A GPS fix identifies the **phone**, not the signboard. A place-name match is approximate and may be wrong or incomplete. GPS accuracy, map coverage, network availability and OCR quality all affect the result. The app should not state an exact distance to a sign unless it has reliable coordinates for that sign; text on a sign alone is not proof of the sign's physical location.

### Detection history and visual interface

- Saves local detection-history information for later review.
- Shows detection overlays, status messages, recognized text, relative-position details and available place context.
- Provides controls for live scanning, uploaded-image analysis, voice commands and safety/focus modes.
- Uses a high-contrast dark interface with large touch targets and semantic labels as accessibility aids.

## 4. Supported sign categories

The label files configure 21 classes:

| ID | Class | ID | Class |
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

The source of truth for class order is `assets/models/labels.txt` and `assets/models/classes.json`. These labels describe the classes the model was configured to predict; they do not guarantee that every real-world sign will be recognized correctly. A model update must preserve the expected tensor format and label ordering.

## 5. System architecture

### End-to-end data flow

```text
┌─────────────────────────────┐
│ Live camera frame / gallery │
│ image                       │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ Decode, orient and prepare  │
│ image                       │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ TensorFlow Lite detector    │
│ class + confidence + box    │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│ Filter detections, suppress │
│ overlaps, track stable signs│
└──────────────┬──────────────┘
               │
        ┌──────┴────────┐
        ▼               ▼
┌───────────────┐ ┌─────────────────────────┐
│ Relative      │ │ OCR on expanded sign    │
│ position and  │ │ crop + preprocessed     │
│ motion cues   │ │ image variants          │
└───────┬───────┘ └────────────┬────────────┘
        │                      ▼
        │         ┌─────────────────────────┐
        │         │ Indic language selected?│
        │         └────────────┬────────────┘
        │                 Yes  │  No
        │           ┌──────────┴─────────┐
        │           ▼                    ▼
        │  ┌────────────────┐  ┌─────────────────┐
        │  │ OCR.Space      │  │ Google ML Kit   │
        │  │ Engine 3       │  │ local OCR first │
        │  │ online OCR     │  │ + cloud fallback│
        │  └───────┬────────┘  └────────┬────────┘
        │          └──────────┬─────────┘
        └─────────────────────┤
                              ▼
                 ┌────────────────────────┐
                 │ Optional location and  │
                 │ OpenStreetMap place    │
                 │ verification context   │
                 └────────────┬───────────┘
                              ▼
                 ┌────────────────────────┐
                 │ Groq narration when    │
                 │ configured and valid;  │
                 │ otherwise local text   │
                 └────────────┬───────────┘
                              ▼
                 ┌────────────────────────┐
                 │ TTS + accessible UI +  │
                 │ optional local history │
                 └────────────────────────┘

<img width="1299" height="897" alt="image" src="https://github.com/user-attachments/assets/2f38ce8d-11db-4f24-a465-a7fda1f66f40" />

<img width="1266" height="893" alt="image" src="https://github.com/user-attachments/assets/03bf6f08-bfe0-45f3-b097-a58a63acb555" />

<img width="1266" height="893" alt="image" src="https://github.com/user-attachments/assets/77d03821-4595-4b7b-a7a7-27d498b91de4" />

```

### Architectural principles

- **Local-first inference:** sign detection runs on the device using the bundled TFLite model.
- **Hybrid OCR:** local ML Kit recognition avoids network latency for supported scripts; OCR.Space is the cloud route for selected Indic scripts and a fallback for weak local results.
- **Evidence-aware narration:** the narration layer receives structured sign/OCR/context fields instead of only an unstructured prompt.
- **Graceful degradation:** missing API configuration or cloud failure should leave the local OCR/narration paths available where supported.
- **Accessibility before decoration:** voice feedback, permission explanations, queued announcements, readable status and large controls are core interaction paths.
- **Separate phone and sign location:** GPS is treated as phone context; place lookup is a candidate verification step, not proof.

## 6. Repository structure

| Path | Responsibility |
|---|---|
| `lib/main.dart` | App startup, optional `.env` loading, theme and Provider setup |
| `lib/screens/splash_screen.dart` | Startup/onboarding entry |
| `lib/screens/live_camera_screen.dart` | Main voice-first camera experience, permissions, language selection, image demo, result narration and controls |
| `lib/screens/camera_screen.dart` | Camera screen entry/flow |
| `lib/screens/gallery_screen.dart` | Saved-image selection flow |
| `lib/screens/home_screen.dart` | Home/navigation UI |
| `lib/screens/result_screen.dart` | Result presentation |
| `lib/models/detection_result.dart` | Structured detection result |
| `lib/models/sign_model.dart` | App state for detections and image processing |
| `lib/services/tflite_service.dart` | TFLite model loading, image preprocessing, inference and output parsing |
| `lib/services/ocr_service.dart` | ML Kit OCR, OCR.Space Engine 3 requests, sign crops, image variants, normalization, scoring and fallback |
| `lib/services/detection_intelligence.dart` | Detection tracking, relative position, proximity/movement cues, prioritization and stability |
| `lib/services/ai_speech_service.dart` | Optional Groq API narration, language checks, OCR cleanup and local fallback narration |
| `lib/services/tts_service.dart` | Text-to-speech output |
| `lib/services/voice_command_service.dart` | Speech recognition lifecycle and command capture |
| `lib/services/language_service.dart` | Supported app language choices and saved preference |
| `lib/services/location_service.dart` | Phone GPS, reverse geocoding and location snapshot |
| `lib/services/place_verification_service.dart` | Nominatim place-name verification and destination context |
| `lib/services/history_service.dart` | Local detection history |
| `lib/services/announcement_queue_service.dart` | Ordered/priority speech announcements |
| `lib/widgets/detection_overlay.dart` | Bounding-box visualization |
| `lib/widgets/sign_card.dart` | Reusable sign-result UI |
| `assets/models/best.tflite` | Bundled sign detection model |
| `assets/models/labels.txt` | Label ordering |
| `assets/models/classes.json` | Numeric class-to-label mapping |
| `assets/models/best.pt` | Model artifact used during development |
| `assets/images/app_logo.png` | App logo |
| `android/app/src/main/AndroidManifest.xml` | Android app/platform declarations |
| `android/app/build.gradle.kts` | Android application build configuration and ML Kit dependency |
| `.env.example` | Placeholder configuration for optional APIs |
| `test/widget_test.dart` | Flutter widget test |
| `.github/workflows/flutter_ci.yml` | CI checks for analysis, tests and Android debug build |
| `LICENSE` | Project license |

## 7. Technology stack

- **Flutter / Dart:** app UI and application logic.
- **`flutter_litert` + TensorFlow Lite:** local sign detection.
- **Google ML Kit Text Recognition:** local OCR for supported scripts.
- **OCR.Space Engine 3:** optional online multilingual OCR with automatic language detection.
- **Camera / image picker / image package:** frame capture, saved-image input and image preprocessing.
- **`speech_to_text` + `flutter_tts`:** voice commands and spoken feedback.
- **Geolocator + Geocoding:** phone position and reverse-geocoded address.
- **OpenStreetMap Nominatim:** optional text-based place lookup.
- **Groq-compatible chat-completions API:** optional natural-language narration.
- **Provider + SharedPreferences:** state management and local persistence.
- **GitHub Actions:** automated quality checks.

## 8. Getting started

### Prerequisites

Install:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) on the stable channel.
- [Android Studio](https://developer.android.com/studio) or Android SDK command-line tools.
- Android SDK/platform tools and a compatible JDK. The Android app build targets Java 17.
- A physical Android device with developer options and USB debugging enabled, or an emulator with camera support.

Verify the development environment:

```powershell
flutter doctor
flutter --version
```

### Clone and install

```powershell
git clone https://github.com/RakshithaNagaraju74/AI_Signboard_Reader.git
cd AI_Signboard_Reader
flutter pub get
```

The model and label assets are referenced in `pubspec.yaml`. If replacing the model, verify its input/output tensor layout and label ordering against `lib/services/tflite_service.dart`.

### Configure optional APIs

Create a local `.env` file from the template:

```powershell
Copy-Item .env.example .env
notepad .env
```

Configure only the services you intend to use:

```dotenv
# Optional natural-language narration
GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=openai/gpt-oss-20b
GROQ_BASE_URL=https://api.groq.com/openai/v1

# Optional multilingual OCR
OCR_SPACE_API_KEY=your_ocr_space_api_key
```

#### OCR.Space setup

1. Request a key from the [OCR.Space free API page](https://ocr.space/ocrapi/freekey).
2. Put it in the local `.env` as `OCR_SPACE_API_KEY=...`.
3. Make sure the app has internet access and run it again.

The key is optional: without it, the app skips cloud OCR and uses local recognition where supported. OCR.Space free-plan quota and Engine 3 availability can change; check the provider's current terms and limits. Do not assume unlimited requests.

#### Groq setup

Set `GROQ_API_KEY` and, if needed, `GROQ_MODEL` / `GROQ_BASE_URL`. When the key is missing or a request is rejected, the local narration fallback is used.

**API-key security:** this is a student/demo client configuration. The app bundles `.env` as an asset for runtime loading, so any real key packaged into a mobile build may be extracted from the APK. Never commit your actual `.env` file to GitHub. For a public release, route authenticated API requests through a backend you control, apply quotas, and avoid distributing provider secrets inside the app. Cloud OCR sends the selected sign crop to OCR.Space; Groq receives the structured data needed to create narration.

### Run on Android

```powershell
flutter devices
flutter run
```

If Gradle or Flutter reports a build error, fix the first actionable error before chasing secondary warnings. Some dependencies may emit Gradle/Kotlin migration or Android SDK metadata warnings; these warnings are not necessarily the cause of a failed build.

### Build a debug APK

```powershell
flutter build apk --debug
```

Expected output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

This is a debug APK, not a signed production release.

## 9. Using the app

1. Launch the app and select English, Hindi or Kannada when first prompted.
2. Allow camera access when the app explains that permission is needed to read signs.
3. Allow microphone access if you want to issue voice commands.
4. Allow location access if you want phone-location context, place verification or location-aware history.
5. Aim the camera at a sign and keep the phone as steady as practical.
6. Listen to the spoken result. If text is missing or incomplete, move closer, improve lighting, reduce glare, and keep the full sign inside the camera frame.
7. Use image selection to test saved signboard photographs.
8. Try supported commands such as **“find sign,” “scan surroundings,”** and **“what signs.”** The exact set recognized depends on language and device speech support.
9. Treat any suggested place match or direction as additional context, and independently verify the physical route.

## 10. Accessibility by design

Accessibility affects both the user experience and the system architecture:

- Spoken onboarding/permission explanations reduce dependence on reading dialogs.
- Language choice is saved so users do not need to repeat onboarding every time.
- Large controls, high contrast, semantic labels and visible detection status support touch and screen-reader use.
- Priority queuing helps prevent overlapping announcements.
- Detection stability/cooldowns help avoid repeatedly announcing the same unchanged sign.
- The local narration path provides useful feedback when the optional AI service is unavailable.
- Saved-image analysis supports repeatable testing without requiring the user to stand in front of a sign during every demo.

These features are design intentions and implementation aids, not a claim of accessibility certification. Testing with blind and low-vision users, Android TalkBack, different speech engines, outdoor noise and varied lighting is still essential.

## 11. Privacy, safety and limitations

SightToSound is a prototype and can misread signs or provide incomplete context.

- **Not a certified navigation or obstacle-avoidance system.** Do not rely on it alone around traffic, road crossings or hazards.
- **OCR can be wrong.** Always treat recognized wording as a candidate reading, especially for restrictions, warnings, names and numbers.
- **Object detection is limited to its trained classes.** A sign not represented in the model may not be detected or may be assigned the wrong class.
- **Camera-relative position is not a turn instruction.** The position label describes the image, not the street layout.
- **No reliable physical distance to a sign is inferred from bounding-box size.** A verified map destination and signboard location coordinates would be required for a defensible distance estimate.
- **GPS refers to the phone.** It does not automatically reveal where the photographed sign is installed.
- **Place-name verification is approximate.** OCR text can contain spelling errors, and Nominatim may return a similar but incorrect location.
- **Cloud features require network access.** OCR.Space, Groq and online place lookup can fail, time out or hit quota limits.
- **Cloud data handling:** OCR.Space receives the sign crop sent for OCR; the configured narration API receives the structured detection/context data it needs. Do not scan sensitive documents or private information without considering provider policies.
- **API keys in client apps are not secrets.** Keep real keys out of source control and use a trusted backend for production.
- **Permissions are user-controlled.** Camera, microphone and location features depend on Android permissions and system settings.
- **Speech support varies by device.** Recognition and synthesis depend on installed language packs, engine quality, settings and ambient noise.
- **History and location are sensitive.** Review stored history before sharing a device or diagnostic logs.

### Data-flow summary

| Data | Where it is processed |
|---|---|
| Camera/image input | On device for sign detection and preprocessing |
| Sign category and bounding box | On-device TFLite inference |
| OCR image crop | Sent to OCR.Space only when cloud OCR is attempted and configured |
| Narration context | Sent to the configured Groq-compatible API when AI narration is enabled |
| Phone coordinates | Obtained through location services; may be reverse-geocoded or used for place context |
| Preferences and detection history | Stored locally using SharedPreferences |

## 12. Testing and continuous integration

The repository contains a GitHub Actions workflow at `.github/workflows/flutter_ci.yml` configured to run Flutter dependency resolution, static analysis, tests and an Android debug build on the configured branch events.

Run the checks locally before submitting a change:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Automated checks cannot establish real-world OCR accuracy or navigation safety. Also test on a physical Android device with representative English, Kannada, Hindi, Tamil and Telugu signboard photos, including different fonts, lighting, angles and image sizes. Test both with and without API keys/network access to verify fallback behavior.

## 13. Working on the project

| Goal | Start here |
|---|---|
| Change sign detection/model parsing | `lib/services/tflite_service.dart` |
| Change OCR behavior, OCR.Space request or image preprocessing | `lib/services/ocr_service.dart` |
| Change narration prompts, response checks or local fallback | `lib/services/ai_speech_service.dart` |
| Tune tracking, relative position and announcement stability | `lib/services/detection_intelligence.dart` |
| Adjust voice command capture | `lib/services/voice_command_service.dart` |
| Add/adjust app language settings | `lib/services/language_service.dart` |
| Change speech output | `lib/services/tts_service.dart` |
| Change GPS or reverse geocoding | `lib/services/location_service.dart` |
| Adjust map-place verification | `lib/services/place_verification_service.dart` |
| Change saved detection history | `lib/services/history_service.dart` |
| Change announcement ordering | `lib/services/announcement_queue_service.dart` |
| Change bounding-box UI | `lib/widgets/detection_overlay.dart` |
| Change result cards | `lib/widgets/sign_card.dart` |

When changing the detector, update the model and both label files together and verify the tensor shapes and class order. When changing OCR, test both crop and full-frame paths and verify behavior when the API key is missing, the network fails, and the OCR result is empty. When changing narration, ensure that sign text, negation (for example, “no parking”), names and safety wording are not dropped or reversed.

## 14. Contributing

Bug reports, implementation contributions and accessibility feedback are welcome.

1. Open an issue with a clear description and reproduction steps.
2. Make changes on a focused branch.
3. Run analysis, tests and an Android debug build where possible.
4. Test the change on a device and include OS/device details.
5. Never attach API keys, personal addresses, private location history or sensitive camera images to issues.

## 15. License

This project is distributed under the [MIT License](LICENSE).

---

<div align="center">

**SightToSound**  
*From Sight to Sound. From Sound to Freedom.*

**Technology should make the world more accessible—not add another barrier.**

</div>
