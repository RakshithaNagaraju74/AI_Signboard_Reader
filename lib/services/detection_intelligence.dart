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
        return 'left';
      case SignPosition.slightlyLeft:
        return 'slightly left';
      case SignPosition.front:
        return 'ahead';
      case SignPosition.slightlyRight:
        return 'slightly right';
      case SignPosition.right:
        return 'right';
    }
  }
}

class DetectionContext {
  final DetectionResult detection;
  final SignPosition position;
  final double priority;
  final String movement;

  const DetectionContext({
    required this.detection,
    required this.position,
    required this.priority,
    required this.movement,
  });
}

class DetectionIntelligence {
  final Map<String, _Track> _tracks = {};

  double _frameWidth = 416;
  double _frameArea = 173056;

  void setFrameSize(int width, int height) {
    _frameWidth = width.toDouble();
    _frameArea = width * height.toDouble();
  }

  DetectionContext select(List<DetectionResult> detections) {
    if (detections.isEmpty) {
      throw StateError('No detections');
    }

    final contexts = detections.map((detection) {
      final centerX =
          (detection.bbox[0] + detection.bbox[2]) / 2;

      final width = math.max(
        1.0,
        detection.bbox[2] - detection.bbox[0],
      );

      final height = math.max(
        1.0,
        detection.bbox[3] - detection.bbox[1],
      );

      final area =
          (width * height) / math.max(1.0, _frameArea);

      final key = _key(detection);
      final previous = _tracks[key];

      String movement = '';

      if (previous != null) {
        if (area > previous.area * 1.12) {
          movement = 'getting closer';
        } else if (area < previous.area * 0.88) {
          movement = 'moving farther';
        }
      }

      _tracks[key] = _Track(
        area,
        previous?.lastAnnounced,
      );

      final ocrBoost =
          detection.ocrText.trim().isNotEmpty ? 0.15 : 0.0;

      final priority =
          detection.confidence * 0.55 +
          area.clamp(0.0, 0.75) * 0.25 +
          _safetyBoost(detection.className) +
          ocrBoost;

      return DetectionContext(
        detection: detection,
        position: _position(centerX / _frameWidth),
        priority: priority,
        movement: movement,
      );
    }).toList();

    contexts.sort(
      (a, b) => b.priority.compareTo(a.priority),
    );

    return contexts.first;
  }

  bool shouldAnnounce(
    DetectionContext context, {
    Duration cooldown = const Duration(seconds: 8),
  }) {
    final track = _tracks[_key(context.detection)];

    if (track == null) {
      return true;
    }

    if (track.lastAnnounced == null) {
      return true;
    }

    return DateTime.now().difference(
          track.lastAnnounced!,
        ) >=
        cooldown;
  }

  void markAnnounced(DetectionContext context) {
    final track = _tracks[_key(context.detection)];

    if (track != null) {
      track.lastAnnounced = DateTime.now();
    }
  }

  SignPosition _position(double x) {
    if (x < 0.20) {
      return SignPosition.left;
    }

    if (x < 0.40) {
      return SignPosition.slightlyLeft;
    }

    if (x < 0.60) {
      return SignPosition.front;
    }

    if (x < 0.80) {
      return SignPosition.slightlyRight;
    }

    return SignPosition.right;
  }

  double _safetyBoost(String label) {
    final value = label.toLowerCase();

    if (value.contains('warning') ||
        value.contains('construction') ||
        value.contains('pedestrian_dont') ||
        value.contains('stop') ||
        value.contains('wet_floor')) {
      return 0.30;
    }

    if (value.contains('bus') ||
        value.contains('rail') ||
        value.contains('mrt') ||
        value.contains('school')) {
      return 0.20;
    }

    return 0.05;
  }

  String _key(DetectionResult detection) {
    return '${detection.className}|'
        '${detection.ocrText.trim().toLowerCase()}';
  }
}

class _Track {
  final double area;
  DateTime? lastAnnounced;

  _Track(
    this.area,
    this.lastAnnounced,
  );
}
