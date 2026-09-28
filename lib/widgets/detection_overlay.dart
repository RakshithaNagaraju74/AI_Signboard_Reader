import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:signboard_reader/models/detection_result.dart';

class DetectionOverlay extends StatelessWidget {
  final List<DetectionResult> detections;
  final Size imageSize;
  final Size screenSize;

  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.imageSize,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DetectionPainter(
        detections: detections,
        imageSize: imageSize,
        screenSize: screenSize,
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size imageSize;
  final Size screenSize;

  DetectionPainter({
    required this.detections,
    required this.imageSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // Calculate scale and offset to fit image in screen
    final scaleX = screenSize.width / imageSize.width;
    final scaleY = screenSize.height / imageSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    
    final offsetX = (screenSize.width - imageSize.width * scale) / 2;
    final offsetY = (screenSize.height - imageSize.height * scale) / 2;

    for (var detection in detections) {
      final bbox = detection.bbox;
      final x1 = bbox[0] * scale + offsetX;
      final y1 = bbox[1] * scale + offsetY;
      final x2 = bbox[2] * scale + offsetX;
      final y2 = bbox[3] * scale + offsetY;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      
      // Draw bounding box with gradient
      final paint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawRect(rect, paint);

      // Draw solid box on top
      final solidPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      canvas.drawRect(rect, solidPaint);

      // Draw label background
      final label = '${detection.className.replaceAll('_', ' ')} ${(detection.confidence * 100).toStringAsFixed(1)}%';
      
      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Draw background for text
      final bgPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;
      
      final textRect = Rect.fromLTWH(
        x1,
        y1 - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );
      
      canvas.drawRect(textRect, bgPaint);
      
      // Draw text
      textPainter.paint(canvas, Offset(x1 + 4, y1 - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}