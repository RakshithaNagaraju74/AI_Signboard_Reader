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
