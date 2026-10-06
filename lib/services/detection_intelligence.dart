import 'dart:math' as math;

import '../models/detection_result.dart';

enum SignPosition {
  left,
  slightlyLeft,
  front,
  slightlyRight,
  right,
}

extension SignPositionSpeech on SignPosition {
  String get label {
    switch (this) {
      case SignPosition.left:
        return 'far left';
      case SignPosition.slightlyLeft:
        return 'slightly left';
      case SignPosition.front:
        return 'directly ahead';
      case SignPosition.slightlyRight:
        return 'slightly right';
      case SignPosition.right:
        return 'far right';
    }
  }
}

class DetectionContext {
  final DetectionResult detection;
  final SignPosition position;
  final double priority;
  final String movement;
  final String proximity;
  final int stableFrames;
  final bool isNew;

  const DetectionContext({
    required this.detection,
    required this.position,
    required this.priority,
    required this.movement,
    required this.proximity,
    required this.stableFrames,
    required this.isNew,
  });
}

class DetectionIntelligence {
  final Map<String, _Track> _tracks = {};

  double _frameWidth = 416.0;
  double _frameArea = 416.0 * 416.0;

  String? focusedKey;

  void setFrameSize(
    int width,
    int height,
  ) {
    final safeWidth = math.max(1, width);
    final safeHeight = math.max(1, height);

    _frameWidth = safeWidth.toDouble();
    _frameArea =
        safeWidth.toDouble() * safeHeight.toDouble();
  }

  DetectionContext select(
    List<DetectionResult> detections,
  ) {
    final contexts = analyze(detections);

    if (contexts.isEmpty) {
      throw StateError('No detections');
    }

    if (focusedKey != null) {
      for (final context in contexts) {
        if (detectionKey(context.detection) ==
            focusedKey) {
          return context;
        }
      }
    }

    return contexts.first;
  }

  List<DetectionContext> analyze(
    List<DetectionResult> detections,
  ) {
    final contexts = <DetectionContext>[];

    for (final detection in detections) {
      if (detection.bbox.length < 4) {
        continue;
      }

      final centerX =
          (detection.bbox[0] +
                  detection.bbox[2]) /
              2.0;

      final width = math.max(
        1.0,
        detection.bbox[2] -
            detection.bbox[0],
      );

      final height = math.max(
        1.0,
        detection.bbox[3] -
            detection.bbox[1],
      );

      final area =
          (width * height) / _frameArea;

      final normalizedX =
          (centerX / _frameWidth)
              .clamp(0.0, 1.0)
              .toDouble();

      final position =
          position0(normalizedX);

      final key =
          detectionKey(detection);

      final previous = _tracks[key];

      var movement = '';

      if (previous != null) {
        final deltaX =
            normalizedX -
                previous.centerX;

        if (deltaX.abs() > 0.08) {
          movement = deltaX > 0
              ? 'moving to your right'
              : 'moving to your left';
        } else if (area >
            previous.area * 1.15) {
          movement = 'getting closer';
        } else if (area <
            previous.area * 0.85) {
          movement = 'moving farther away';
        }
      }

      final stableFrames =
          previous != null &&
                  previous.position == position
              ? previous.stableFrames + 1
              : 1;

      _tracks[key] = _Track(
        area: area,
        centerX: normalizedX,
        position: position,
        lastSeen: DateTime.now(),
        lastAnnounced:
            previous?.lastAnnounced,
        lastOcrAt:
            previous?.lastOcrAt,
        stableFrames: stableFrames,
      );

      final hasOcr =
          detection.ocrText.trim().isNotEmpty;

      final ocrBoost =
          hasOcr ? 0.15 : 0.0;

      final focusBoost =
          key == focusedKey ? 0.20 : 0.0;

      final priority =
          detection.confidence * 0.50 +
          area
                  .clamp(0.0, 0.75)
                  .toDouble() *
              0.25 +
          safetyBoost(
            detection.className,
          ) +
          ocrBoost +
          focusBoost;

      contexts.add(
        DetectionContext(
          detection: detection,
          position: position,
          priority: priority,
          movement: movement,
          proximity: proximity(area),
          stableFrames: stableFrames,
          isNew: previous == null,
        ),
      );
    }

    contexts.sort(
      (a, b) =>
          b.priority.compareTo(a.priority),
    );

    pruneOldTracks();

    return contexts;
  }

  bool shouldAnnounce(
    DetectionContext context, {
    Duration cooldown =
        const Duration(seconds: 8),
  }) {
    final key =
        detectionKey(context.detection);

    final track = _tracks[key];

    if (track == null) {
      return false;
    }

    if (track.lastAnnounced == null) {
      return context.stableFrames >= 2 ||
          isSafety(
            context.detection.className,
          );
    }

    final elapsed =
        DateTime.now().difference(
      track.lastAnnounced!,
    );

    return elapsed >= cooldown;
  }

  void markAnnounced(
    DetectionContext context,
  ) {
    final key =
        detectionKey(context.detection);

    final track = _tracks[key];

    if (track == null) {
      return;
    }

    track.lastAnnounced =
        DateTime.now();
  }

  bool shouldReadText(
    DetectionResult detection,
  ) {
    final key =
        detectionKey(detection);

    final track = _tracks[key];

    if (track == null) {
      return true;
    }

    if (track.lastOcrAt != null) {
      return false;
    }

    return track.stableFrames >= 2;
  }

  void markOcrRead(
    DetectionResult detection,
  ) {
    final key =
        detectionKey(detection);

    final track =
        _tracks[key] ?? _Track.empty();

    track.lastOcrAt =
        DateTime.now();

    _tracks[key] = track;
  }

  void focus(
    DetectionContext context,
  ) {
    focusedKey =
        detectionKey(context.detection);
  }

  bool isFocused(DetectionContext context) {
    final key = focusedKey;
    if (key == null) return false;
    final exact = detectionKey(context.detection) == key;
    if (exact) return true;

    // Position changes are expected while focusing. Keep the same semantic
    // sign focused even when it moves from left to center/right.
    final prefix = context.detection.className + '|';
    return key.startsWith(prefix);
  }

  void clearFocus() {
    focusedKey = null;
  }

  SignPosition position0(
    double x,
  ) {
    final normalized =
        x.clamp(0.0, 1.0).toDouble();

    if (normalized < 0.16) {
      return SignPosition.left;
    }
    if (normalized < 0.38) {
      return SignPosition.slightlyLeft;
    }
    if (normalized <= 0.62) {
      return SignPosition.front;
    }
    if (normalized <= 0.84) {
      return SignPosition.slightlyRight;
    }
    return SignPosition.right;
  }

  String proximity(
    double area,
  ) {
    if (area < 0.025) {
      return 'far';
    }

    if (area < 0.10) {
      return 'approaching';
    }

    return 'nearby';
  }

  double safetyBoost(
    String label,
  ) {
    final value =
        label.toLowerCase();

    if (isSafety(value)) {
      return 0.30;
    }

    if (value.contains('bus') ||
        value.contains('rail') ||
        value.contains('mrt') ||
        value.contains('school') ||
        value.contains('hospital')) {
      return 0.20;
    }

    return 0.05;
  }

  bool isSafety(
    String label,
  ) {
    final value =
        label.toLowerCase();

    return value.contains('warning') ||
        value.contains('construction') ||
        value.contains('pedestrian_dont') ||
        value.contains('stop') ||
        value.contains('wet_floor') ||
        value.contains('road_blocked');
  }

  /// Creates a stable key for tracking the same
  /// detected sign across consecutive frames.
  ///
  /// Example:
  /// hospital|front
  /// bus|slightlyLeft
  String detectionKey(
    DetectionResult detection,
  ) {
    if (detection.bbox.length < 4) {
      return detection.className;
    }

    final centerX =
        (detection.bbox[0] +
                detection.bbox[2]) /
            2.0;

    final normalizedX =
        (centerX / _frameWidth)
            .clamp(0.0, 1.0)
            .toDouble();

    final position =
        position0(normalizedX);

    return '${detection.className}|${position.name}';
  }

  DetectionContext withText(DetectionContext context, String text) {
    final d = context.detection;
    return DetectionContext(
      detection: DetectionResult(
        className: d.className,
        confidence: d.confidence,
        bbox: d.bbox,
        ocrText: text,
        classId: d.classId,
      ),
      position: context.position,
      priority: context.priority + (text.trim().isNotEmpty ? 0.15 : 0.0),
      movement: context.movement,
      proximity: context.proximity,
      stableFrames: context.stableFrames,
      isNew: context.isNew,
    );
  }

  void pruneOldTracks() {
    final cutoff =
        DateTime.now().subtract(
      const Duration(seconds: 20),
    );

    _tracks.removeWhere(
      (_, track) =>
          track.lastSeen.isBefore(cutoff),
    );
  }
}

class _Track {
  double area;
  double centerX;
  SignPosition position;
  DateTime lastSeen;
  DateTime? lastAnnounced;
  DateTime? lastOcrAt;
  int stableFrames;

  _Track({
    required this.area,
    required this.centerX,
    required this.position,
    required this.lastSeen,
    required this.lastAnnounced,
    required this.lastOcrAt,
    required this.stableFrames,
  });

  factory _Track.empty() {
    return _Track(
      area: 0.0,
      centerX: 0.5,
      position: SignPosition.front,
      lastSeen: DateTime.now(),
      lastAnnounced: null,
      lastOcrAt: null,
      stableFrames: 1,
    );
  }
}