import 'package:flutter/material.dart';
import '../models/detection_result.dart';

class SignModel extends ChangeNotifier {
  List<DetectionResult> _detections = [];
  bool _isProcessing = false;
  String _lastImagePath = '';

  List<DetectionResult> get detections => _detections;
  bool get isProcessing => _isProcessing;
  String get lastImagePath => _lastImagePath;

  void setDetections(List<DetectionResult> detections) {
    _detections = detections;
    notifyListeners();
  }

  void setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  void setImagePath(String path) {
    _lastImagePath = path;
    notifyListeners();
  }

  void clearDetections() {
    _detections = [];
    notifyListeners();
  }

  // Get spoken description for a detection
  String getSpokenDescription(DetectionResult detection) {
    final className = detection.className;
    final ocrText = detection.ocrText;

    // Map class to speech
    switch (className) {
      case 'wayfinding_sign':
        return ocrText.isNotEmpty ? 'Wayfinding: $ocrText' : 'Wayfinding sign ahead';
      case 'turn_left_sign':
        return 'Turn left ahead';
      case 'turn_right_sign':
        return 'Turn right ahead';
      case 'junction_or_merge_sign':
        return 'Road junction ahead';
      case 'school_zone_sign':
        return 'School zone, caution';
      case 'speed_limit_sign':
        return ocrText.isNotEmpty ? 'Speed limit: $ocrText' : 'Speed limit sign';
      case 'warning_sign':
        return ocrText.isNotEmpty ? 'Warning: $ocrText' : 'Caution ahead';
      case 'construction_sign':
        return 'Construction ahead';
      case 'bus_stop_sign':
        return ocrText.isNotEmpty ? 'Bus stop: $ocrText' : 'Bus stop';
      case 'shop_sign':
        return ocrText.isNotEmpty ? 'Shop: $ocrText' : 'Shop ahead';
      case 'public_info_sign':
        return ocrText.isNotEmpty ? 'Public information: $ocrText' : 'Public information sign';
      case 'mrt_sign':
        return ocrText.isNotEmpty ? 'MRT: $ocrText' : 'MRT sign ahead';
      case 'tra_sign':
        return ocrText.isNotEmpty ? 'Railway: $ocrText' : 'Railway sign ahead';
      case 'bicycle_sign':
        return 'Bicycle lane ahead';
      case 'stop_request_bell_sign':
        return 'Stop request bell here';
      case 'wet_floor_sign':
        return 'Caution, wet floor';
      case 'pedestrian_crossing_sign':
        return 'Pedestrian crossing ahead';
      case 'accessibility_sign':
        return 'Accessible facility sign';
      case 'restroom_sign_ladies':
        return 'Ladies restroom';
      case 'restroom_sign_men':
        return 'Men\'s restroom';
      case 'pedestrian_dont_walk_sign':
        return 'Do not cross, pedestrian signal red';
      case 'tactile_paving':
        return 'Tactile paving underfoot';
      default:
        return ocrText.isNotEmpty ? '$className: $ocrText' : '$className ahead';
    }
  }
}