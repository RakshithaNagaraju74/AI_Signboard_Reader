import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'AI Signboard Reader';
  static const String appVersion = '1.0.0';
  
  static const int modelInputSize = 416;
  static const double confidenceThreshold = 0.25;
  static const double iouThreshold = 0.5;
  
  static const double speechRate = 0.5;
  static const double speechPitch = 1.0;
  
  static const double cameraAspectRatio = 16 / 9;
  
  // Remove const keyword from list since Colors are not constant
  static final List<Color> detectionColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
  ];
}