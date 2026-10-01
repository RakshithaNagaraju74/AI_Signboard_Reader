# signboard_reader_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Accessibility and Spatial Intelligence

The app is designed as a voice-first signboard assistant for blind and visually impaired users.

### Current intelligent features
- Camera-first live scanning with periodic frame analysis.
- YOLO/TFLite sign detection with confidence filtering and NMS.
- OCR is triggered selectively instead of blindly running on every frame.
- Five-zone spatial guidance: far left, slightly left, directly ahead, slightly right, far right.
- Consecutive-frame tracking for sign stability and relative movement.
- Relative proximity estimation: far, approaching, nearby.
- Duplicate announcement suppression and temporal stabilization.
- Focus mode: voice command **"find sign"** selects the highest-priority visible sign and provides spoken alignment feedback.
- Scene mode: voice commands **"scan surroundings"** and **"what signs"** summarize multiple visible signs.
- Voice commands for scan, stop, repeat, focus, surroundings, history, language and navigation context.
- Multilingual TTS/voice-command support for English, Hindi and Kannada.
- GPS tagging of detections in history.
- Haptic feedback after important detections.
- Safety-aware prioritization for warning, construction, stop and road-blocked classes.

### Spatial guidance model

The system compares a sign across consecutive camera frames using its bounding-box center, size and stability. For example:

**left → slightly left → directly ahead**

can become spoken guidance such as:

> "Hospital sign slightly left."

followed by:

> "Hospital sign directly ahead. Hold steady."

Bounding-box growth is used only for **relative** proximity such as "getting closer" or "approaching"; the app does not claim an exact physical distance unless a reliable depth source is available.

### Important limitation

GPS records the phone's location when a sign is detected. GPS alone does not provide the exact sign's position, bearing or distance. Compass-grade orientation and metric sign distance require additional sensors/calibration and are intentionally not fabricated.


## Judge-ready demonstration mode

- **Voice-first onboarding:** a welcome message is spoken before scanning. On first launch, Hindi is offered first; if there is no meaningful response after a short listening window, Kannada is offered, followed by English as a safe fallback.
- **Language lock:** once a language is selected, application-generated guidance, commands, status messages, spatial guidance and location narration use that language.
- **Rich detection results:** each detection can expose the predicted class, class ID, confidence, relative five-zone position, OCR text, motion/proximity cue and current GPS/place context.
- **Reverse-geocoded place context:** current coordinates are converted to a human-readable street/area/city description when the platform geocoder is available.
- **Judge/demo upload:** the upload button on the live screen lets a presenter select a saved signboard image. The image goes through the same YOLO/TFLite detection and OCR pipeline and presents a detailed result card plus spoken summary.
- **Location-aware history:** detections continue to be stored with the current GPS coordinates when permission is available.
- **Safe claims:** GPS identifies the phone's current location; it does not by itself prove the exact physical location, compass bearing or metric distance of a detected sign. Relative proximity is inferred from consecutive visual observations.

The reverse-geocoding layer uses the Flutter geocoding plugin's native platform services; availability and rate limits depend on the device/platform.
