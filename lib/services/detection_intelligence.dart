import 'dart:math' as math;

import '../models/detection_result.dart';

<<<<<<< HEAD
enum SignPosition {
  left,
  slightlyLeft,
  front,
  slightlyRight,
  right,
}
=======
enum SignPosition { left, slightlyLeft, front, slightlyRight, right }
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9

extension SignPositionSpeech on SignPosition {
  String get label {
    switch (this) {
<<<<<<< HEAD
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
=======
      case SignPosition.left: return 'far left';
      case SignPosition.slightlyLeft: return 'slightly left';
      case SignPosition.front: return 'directly ahead';
      case SignPosition.slightlyRight: return 'slightly right';
      case SignPosition.right: return 'far right';
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
    }
  }
}

class DetectionContext {
  final DetectionResult detection;
  final SignPosition position;
  final double priority;
  final String movement;
<<<<<<< HEAD
=======
  final String proximity;
  final int stableFrames;
  final bool isNew;
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9

  const DetectionContext({
    required this.detection,
    required this.position,
    required this.priority,
    required this.movement,
<<<<<<< HEAD
=======
    required this.proximity,
    required this.stableFrames,
    required this.isNew,
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
  });
}

class DetectionIntelligence {
  final Map<String, _Track> _tracks = {};
<<<<<<< HEAD

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
=======
  double _frameWidth = 416;
  double _frameArea = 173056;
  String? _focusedKey;

  void setFrameSize(int width, int height) {
    _frameWidth = math.max(1, width).toDouble();
    _frameArea = math.max(1, width * height).toDouble();
  }

  DetectionContext select(List<DetectionResult> detections) {
    final contexts = analyze(detections);
    if (contexts.isEmpty) throw StateError('No detections');

    if (_focusedKey != null) {
      for (final context in contexts) {
        if (_key(context.detection) == _focusedKey) return context;
      }
    }
    return contexts.first;
  }

  List<DetectionContext> analyze(List<DetectionResult> detections) {
    final contexts = <DetectionContext>[];

    for (final detection in detections) {
      final centerX = (detection.bbox[0] + detection.bbox[2]) / 2;
      final width = math.max(1.0, detection.bbox[2] - detection.bbox[0]);
      final height = math.max(1.0, detection.bbox[3] - detection.bbox[1]);
      final area = (width * height) / _frameArea;
      final key = _key(detection);
      final previous = _tracks[key];

      var movement = '';
      if (previous != null) {
        final deltaX = centerX / _frameWidth - previous.centerX;
        if (deltaX.abs() > 0.08) {
          movement = deltaX > 0 ? 'moving to your right' : 'moving to your left';
        } else if (area > previous.area * 1.15) {
          movement = 'getting closer';
        } else if (area < previous.area * 0.85) {
          movement = 'moving farther away';
        }
      }

      final position = _position(centerX / _frameWidth);
      final stableFrames =
          previous != null && previous.position == position
              ? previous.stableFrames + 1
              : 1;

      _tracks[key] = _Track(
        area: area,
        centerX: centerX / _frameWidth,
        position: position,
        lastSeen: DateTime.now(),
        lastAnnounced: previous?.lastAnnounced,
        lastOcrAt: previous?.lastOcrAt,
        stableFrames: stableFrames,
      );

      final ocrBoost = detection.ocrText.trim().isNotEmpty ? 0.15 : 0.0;
      final focusBoost = key == _focusedKey ? 0.20 : 0.0;
      final priority = detection.confidence * 0.50 +
          area.clamp(0.0, 0.75).toDouble() * 0.25 +
          _safetyBoost(detection.className) +
          ocrBoost +
          focusBoost;

      contexts.add(
        DetectionContext(
          detection: detection,
          position: position,
          priority: priority,
          movement: movement,
          proximity: _proximity(area),
          stableFrames: stableFrames,
          isNew: previous == null,
        ),
      );
    }

    contexts.sort((a, b) => b.priority.compareTo(a.priority));
    _pruneOldTracks();
    return contexts;
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
  }

  bool shouldAnnounce(
    DetectionContext context, {
    Duration cooldown = const Duration(seconds: 8),
  }) {
    final track = _tracks[_key(context.detection)];
<<<<<<< HEAD

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
=======
    if (track == null) return false;
    if (track.lastAnnounced == null) {
      return context.stableFrames >= 2 || _isSafety(context.detection.className);
    }
    return DateTime.now().difference(track.lastAnnounced!) >= cooldown;
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
  }

  void markAnnounced(DetectionContext context) {
    final track = _tracks[_key(context.detection)];
<<<<<<< HEAD

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
=======
    if (track != null) track.lastAnnounced = DateTime.now();
  }

  bool shouldReadText(DetectionResult detection) {
    final track = _tracks[_key(detection)];
    if (track == null) return true;
    return track.stableFrames >= 2 && track.lastOcrAt == null;
  }

  void markOcrRead(DetectionResult detection) {
    final key = _key(detection);
    final track = _tracks[key] ?? _Track.empty();
    track.lastOcrAt = DateTime.now();
    _tracks[key] = track;
  }

  void focus(DetectionContext context) {
    _focusedKey = _key(context.detection);
  }

  void clearFocus() {
    _focusedKey = null;
  }

  String? get focusedKey => _focusedKey;

  SignPosition _position(double x) {
    if (x < 0.20) return SignPosition.left;
    if (x < 0.40) return SignPosition.slightlyLeft;
    if (x < 0.60) return SignPosition.front;
    if (x < 0.80) return SignPosition.slightlyRight;
    return SignPosition.right;
  }

  String _proximity(double area) {
    if (area < 0.025) return 'far';
    if (area < 0.10) return 'approaching';
    return 'nearby';
  }

  double _safetyBoost(String label) {
    final value = label.toLowerCase();
    if (_isSafety(value)) return 0.30;
    if (value.contains('bus') ||
        value.contains('rail') ||
        value.contains('mrt') ||
        value.contains('school') ||
        value.contains('hospital')) {
      return 0.20;
    }
    return 0.05;
  }

  bool _isSafety(String label) {
    final value = label.toLowerCase();
    return value.contains('warning') ||
        value.contains('construction') ||
        value.contains('pedestrian_dont') ||
        value.contains('stop') ||
        value.contains('wet_floor') ||
        value.contains('road_blocked');
  }

  String _key(DetectionResult detection) {
    final centerX = (detection.bbox[0] + detection.bbox[2]) / 2;
    final position = _position(centerX / _frameWidth);
    return detection.className + '|' + position.name;
  }

  void _pruneOldTracks() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    _tracks.removeWhere((_, track) => track.lastSeen.isBefore(cutoff));
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
  }
}

class _Track {
<<<<<<< HEAD
  final double area;
  DateTime? lastAnnounced;

  _Track(
    this.area,
    this.lastAnnounced,
  );
=======
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

  factory _Track.empty() => _Track(
        area: 0,
        centerX: 0,
        position: SignPosition.front,
        lastSeen: DateTime.now(),
        lastAnnounced: null,
        lastOcrAt: null,
        stableFrames: 1,
      );
>>>>>>> fd5c36653e084654373566e07d3be2de1cdf1eb9
}
