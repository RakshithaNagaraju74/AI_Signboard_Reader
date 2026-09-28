class DetectionResult {
  final String className;
  final double confidence;
  final List<double> bbox; // [x1, y1, x2, y2]
  final String ocrText;
  final int classId;

  DetectionResult({
    required this.className,
    required this.confidence,
    required this.bbox,
    this.ocrText = '',
    required this.classId,
  });

  Map<String, dynamic> toJson() => {
    'class_name': className,
    'confidence': confidence,
    'bbox': bbox,
    'ocr_text': ocrText,
    'class_id': classId,
  };

  factory DetectionResult.fromJson(Map<String, dynamic> json) => DetectionResult(
    className: json['class_name'],
    confidence: json['confidence'].toDouble(),
    bbox: List<double>.from(json['bbox']),
    ocrText: json['ocr_text'] ?? '',
    classId: json['class_id'],
  );
}