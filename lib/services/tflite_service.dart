import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../models/detection_result.dart';
import '../utils/logger.dart';

class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();

  factory TFLiteService() => _instance;

  TFLiteService._internal();

  Interpreter? _interpreter;

  List<String> _labels = [];

  bool _isInitialized = false;

  static const int inputSize = 416;

  // Do NOT accept extremely tiny predictions.
  static const double confidenceThreshold = 0.40;

  static const double nmsThreshold = 0.45;

  bool get isInitialized => _isInitialized;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_isInitialized && _interpreter != null) {
      return;
    }

    try {
      // ----------------------------------------------------------
      // LOAD LABELS
      // ----------------------------------------------------------

      final labelString = await rootBundle.loadString(
        'assets/models/labels.txt',
      );

      _labels = labelString
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      Logger.log(
        'Loaded ${_labels.length} labels',
      );

      if (_labels.length != 21) {
        Logger.log(
          'WARNING: Expected 21 labels, '
          'but found ${_labels.length}',
        );
      }

      // ----------------------------------------------------------
      // LOAD MODEL
      // ----------------------------------------------------------

      final modelFile = await _getModelFile();

      final options = InterpreterOptions()
        ..threads = 4;

      _interpreter = await Interpreter.fromFile(
        modelFile,
        options: options,
      );

      _interpreter!.allocateTensors();

      final inputTensor =
          _interpreter!.getInputTensor(0);

      final outputTensor =
          _interpreter!.getOutputTensor(0);

      Logger.log(
        '===============================================',
      );

      Logger.log(
        'TFLite model loaded successfully',
      );

      Logger.log(
        'Input shape: ${inputTensor.shape}',
      );

      Logger.log(
        'Input type: ${inputTensor.type}',
      );

      Logger.log(
        'Output shape: ${outputTensor.shape}',
      );

      Logger.log(
        'Output type: ${outputTensor.type}',
      );

      Logger.log(
        '===============================================',
      );

      // ----------------------------------------------------------
      // INPUT VALIDATION
      // ----------------------------------------------------------

      if (inputTensor.shape.length != 4) {
        throw Exception(
          'Unexpected input shape: '
          '${inputTensor.shape}',
        );
      }

      /*
       * Your exported model is NHWC:
       *
       * [1, 416, 416, 3]
       */

      if (inputTensor.shape[0] != 1 ||
          inputTensor.shape[1] != inputSize ||
          inputTensor.shape[2] != inputSize ||
          inputTensor.shape[3] != 3) {
        throw Exception(
          'Expected input shape '
          '[1,416,416,3], '
          'but found ${inputTensor.shape}',
        );
      }

      if (inputTensor.type != TensorType.float32) {
        throw Exception(
          'Expected float32 input, '
          'found ${inputTensor.type}',
        );
      }

      // ----------------------------------------------------------
      // OUTPUT VALIDATION
      // ----------------------------------------------------------

      final outputShape = outputTensor.shape;

      if (outputShape.length != 3) {
        throw Exception(
          'Expected 3D YOLO output, '
          'found $outputShape',
        );
      }

      /*
       * For 21 classes:
       *
       * 4 box values + 21 classes = 25
       *
       * Therefore one dimension must be 25.
       */

      if (!outputShape.contains(25)) {
        throw Exception(
          'Unexpected YOLO output shape: '
          '$outputShape. '
          'Expected one dimension to be 25 '
          '(4 + 21 classes).',
        );
      }

      _isInitialized = true;

      Logger.log(
        'TFLite Service ready',
      );
    } catch (e) {
      Logger.log(
        'TFLite initialization error: $e',
      );

      _interpreter?.close();

      _interpreter = null;

      _isInitialized = false;

      rethrow;
    }
  }

  // ============================================================
  // MODEL FILE
  // ============================================================

  Future<File> _getModelFile() async {
    final directory =
        await getApplicationDocumentsDirectory();

    final modelPath =
        '${directory.path}/best.tflite';

    final modelFile = File(modelPath);

    final modelData = await rootBundle.load(
      'assets/models/best.tflite',
    );

    final bytes = modelData.buffer.asUint8List(
      modelData.offsetInBytes,
      modelData.lengthInBytes,
    );

    final needsRewrite =
        !await modelFile.exists() ||
        await modelFile.length() != bytes.length;

    if (needsRewrite) {
      await modelFile.writeAsBytes(
        bytes,
        flush: true,
      );

      Logger.log(
        'Model copied to application directory',
      );
    }

    return modelFile;
  }

  // ============================================================
  // PREDICT IMAGE
  // ============================================================

  Future<List<DetectionResult>> predictImage(
    File imageFile,
  ) async {
    if (!_isInitialized ||
        _interpreter == null) {
      Logger.log(
        'TFLite is not initialized',
      );

      return [];
    }

    try {
      final bytes =
          await imageFile.readAsBytes();

      final image =
          img.decodeImage(bytes);

      if (image == null) {
        Logger.log(
          'Could not decode image',
        );

        return [];
      }

      Logger.log(
        'Original image: '
        '${image.width}x${image.height}',
      );

      // ----------------------------------------------------------
      // PREPROCESS
      // ----------------------------------------------------------

      final input =
          _preprocessImage(image);

      // ----------------------------------------------------------
      // INFERENCE
      // ----------------------------------------------------------

      final output =
          _runInference(input);

      // ----------------------------------------------------------
      // PARSE
      // ----------------------------------------------------------

      final detections =
          _parseDetections(
        output,
        image.width,
        image.height,
      );

      Logger.log(
        'FINAL DETECTIONS: '
        '${detections.length}',
      );

      return detections;
    } catch (e) {
      Logger.log(
        'Prediction error: $e',
      );

      return [];
    }
  }

  // ============================================================
  // PREPROCESS
  // ============================================================

  Float32List _preprocessImage(
    img.Image image,
  ) {
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(
      inputSize *
          inputSize *
          3,
    );

    int index = 0;

    for (int y = 0;
        y < inputSize;
        y++) {
      for (int x = 0;
          x < inputSize;
          x++) {
        final pixel =
            resized.getPixel(x, y);

        input[index++] =
            img.getRed(pixel) / 255.0;

        input[index++] =
            img.getGreen(pixel) / 255.0;

        input[index++] =
            img.getBlue(pixel) / 255.0;
      }
    }

    return input;
  }

  // ============================================================
  // RUN INFERENCE
  // ============================================================

  Float32List _runInference(
    Float32List input,
  ) {
    final interpreter =
        _interpreter!;

    final inputTensor =
        interpreter.getInputTensor(0);

    final outputTensor =
        interpreter.getOutputTensor(0);

    final expectedInput =
        inputTensor.shape.reduce(
      (a, b) => a * b,
    );

    if (input.length != expectedInput) {
      throw Exception(
        'Input size mismatch: '
        '${input.length} vs $expectedInput',
      );
    }

    final outputShape =
        outputTensor.shape;

    final outputSize =
        outputShape.reduce(
      (a, b) => a * b,
    );

    final output =
        Float32List(outputSize);

    Logger.log(
      'Running inference...',
    );

    interpreter.run(
      input,
      output,
    );

    Logger.log(
      'Inference completed',
    );

    return output;
  }

  // ============================================================
  // PARSE YOLO OUTPUT
  //
  // Supports:
  //
  // [1, 25, 3549]
  //
  // AND
  //
  // [1, 3549, 25]
  //
  // 25 = 4 bbox values + 21 classes
  // ============================================================

  List<DetectionResult> _parseDetections(
    Float32List output,
    int imageWidth,
    int imageHeight,
  ) {
    final tensor =
        _interpreter!.getOutputTensor(0);

    final shape =
        tensor.shape;

    Logger.log(
      'Parsing YOLO output: $shape',
    );

    if (shape.length != 3) {
      return [];
    }

    final results =
        <DetectionResult>[];

    // ----------------------------------------------------------
    // DETERMINE OUTPUT LAYOUT
    // ----------------------------------------------------------

    int numPredictions;

    bool channelFirst;

    if (shape[1] == 25) {
      // [1, 25, 3549]

      channelFirst = true;

      numPredictions = shape[2];
    } else if (shape[2] == 25) {
      // [1, 3549, 25]

      channelFirst = false;

      numPredictions = shape[1];
    } else {
      Logger.log(
        'ERROR: Cannot identify YOLO output layout: '
        '$shape',
      );

      return [];
    }

    const numClasses = 21;

    Logger.log(
      'YOLO layout: '
      '${channelFirst ? "CHANNEL-FIRST" : "PREDICTION-FIRST"}',
    );

    Logger.log(
      'Predictions: $numPredictions',
    );

    Logger.log(
      'Classes: $numClasses',
    );

    // ----------------------------------------------------------
    // LOOP
    // ----------------------------------------------------------

    for (int i = 0;
        i < numPredictions;
        i++) {
      double cx;
      double cy;
      double w;
      double h;

      // --------------------------------------------------------
      // READ BBOX
      // --------------------------------------------------------

      if (channelFirst) {
        cx = output[i];

        cy =
            output[numPredictions + i];

        w =
            output[
              (2 * numPredictions) + i
            ];

        h =
            output[
              (3 * numPredictions) + i
            ];
      } else {
        final base =
            i * 25;

        cx = output[base];

        cy = output[base + 1];

        w = output[base + 2];

        h = output[base + 3];
      }

      // --------------------------------------------------------
      // FIND BEST CLASS
      // --------------------------------------------------------

      double bestScore = -1.0;

      int bestClass = -1;

      for (int c = 0;
          c < numClasses;
          c++) {
        double score;

        if (channelFirst) {
          final index =
              ((4 + c) *
                  numPredictions) +
              i;

          score = output[index];
        } else {
          final index =
              (i * 25) +
              4 +
              c;

          score = output[index];
        }

        // Ignore NaN / infinity
        if (!score.isFinite) {
          continue;
        }

        if (score > bestScore) {
          bestScore = score;

          bestClass = c;
        }
      }

      // --------------------------------------------------------
      // CRITICAL CONFIDENCE FILTER
      // --------------------------------------------------------

      if (bestClass < 0) {
        continue;
      }

      if (bestScore < confidenceThreshold) {
        continue;
      }

      if (bestClass >= _labels.length) {
        continue;
      }

      // --------------------------------------------------------
      // DEBUG ONLY VALID DETECTIONS
      // --------------------------------------------------------

      Logger.log(
        'VALID YOLO DETECTION: '
        'classId=$bestClass '
        'confidence=${bestScore.toStringAsFixed(4)} '
        'label=${_labels[bestClass]}',
      );

      // --------------------------------------------------------
      // BBOX
      // --------------------------------------------------------

      /*
       * YOLO output coordinates are normally in
       * 416x416 model coordinates.
       */

      double x1 =
          cx - (w / 2.0);

      double y1 =
          cy - (h / 2.0);

      double x2 =
          cx + (w / 2.0);

      double y2 =
          cy + (h / 2.0);

      // --------------------------------------------------------
      // NORMALIZED COORDINATES SAFETY
      // --------------------------------------------------------

      /*
       * Some exports can produce normalized coordinates
       * between 0 and 1.
       *
       * Detect that case automatically.
       */

      final coordinatesLookNormalized =
          x1.abs() <= 1.5 &&
          y1.abs() <= 1.5 &&
          x2.abs() <= 1.5 &&
          y2.abs() <= 1.5;

      if (coordinatesLookNormalized) {
        x1 *= imageWidth;

        x2 *= imageWidth;

        y1 *= imageHeight;

        y2 *= imageHeight;
      } else {
        x1 =
            (x1 / inputSize) *
                imageWidth;

        x2 =
            (x2 / inputSize) *
                imageWidth;

        y1 =
            (y1 / inputSize) *
                imageHeight;

        y2 =
            (y2 / inputSize) *
                imageHeight;
      }

      // --------------------------------------------------------
      // CLAMP
      // --------------------------------------------------------

      x1 = x1.clamp(
        0.0,
        imageWidth.toDouble(),
      );

      y1 = y1.clamp(
        0.0,
        imageHeight.toDouble(),
      );

      x2 = x2.clamp(
        0.0,
        imageWidth.toDouble(),
      );

      y2 = y2.clamp(
        0.0,
        imageHeight.toDouble(),
      );

      // --------------------------------------------------------
      // VALID BOX
      // --------------------------------------------------------

      if (x2 <= x1 ||
          y2 <= y1) {
        continue;
      }

      // --------------------------------------------------------
      // MINIMUM BOX SIZE
      // --------------------------------------------------------

      final boxWidth =
          x2 - x1;

      final boxHeight =
          y2 - y1;

      if (boxWidth < 5 ||
          boxHeight < 5) {
        continue;
      }

      // --------------------------------------------------------
      // ADD RESULT
      // --------------------------------------------------------

      results.add(
        DetectionResult(
          className:
              _labels[bestClass],
          confidence:
              bestScore,
          bbox: [
            x1,
            y1,
            x2,
            y2,
          ],
          classId:
              bestClass,
          ocrText: '',
        ),
      );
    }

    Logger.log(
      'Detections above confidence threshold: '
      '${results.length}',
    );

    // ----------------------------------------------------------
    // SORT
    // ----------------------------------------------------------

    results.sort(
      (a, b) =>
          b.confidence.compareTo(
        a.confidence,
      ),
    );

    // ----------------------------------------------------------
    // NMS
    // ----------------------------------------------------------

    final finalResults =
        _nonMaxSuppression(
      results,
    );

    Logger.log(
      'Detections after NMS: '
      '${finalResults.length}',
    );

    return finalResults;
  }

  // ============================================================
  // NMS
  // ============================================================

  List<DetectionResult>
      _nonMaxSuppression(
    List<DetectionResult>
        detections,
  ) {
    if (detections.isEmpty) {
      return [];
    }

    final kept =
        <DetectionResult>[];

    final suppressed =
        List<bool>.filled(
      detections.length,
      false,
    );

    for (int i = 0;
        i < detections.length;
        i++) {
      if (suppressed[i]) {
        continue;
      }

      kept.add(
        detections[i],
      );

      for (int j = i + 1;
          j < detections.length;
          j++) {
        if (suppressed[j]) {
          continue;
        }

        // Same class only
        if (detections[i].classId !=
            detections[j].classId) {
          continue;
        }

        final iou =
            _calculateIOU(
          detections[i].bbox,
          detections[j].bbox,
        );

        if (iou >=
            nmsThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  // ============================================================
  // IOU
  // ============================================================

  double _calculateIOU(
    List<double> box1,
    List<double> box2,
  ) {
    final x1 =
        box1[0] > box2[0]
            ? box1[0]
            : box2[0];

    final y1 =
        box1[1] > box2[1]
            ? box1[1]
            : box2[1];

    final x2 =
        box1[2] < box2[2]
            ? box1[2]
            : box2[2];

    final y2 =
        box1[3] < box2[3]
            ? box1[3]
            : box2[3];

    final intersectionWidth =
        x2 - x1;

    final intersectionHeight =
        y2 - y1;

    if (intersectionWidth <= 0 ||
        intersectionHeight <= 0) {
      return 0.0;
    }

    final intersection =
        intersectionWidth *
        intersectionHeight;

    final area1 =
        (box1[2] - box1[0]) *
        (box1[3] - box1[1]);

    final area2 =
        (box2[2] - box2[0]) *
        (box2[3] - box2[1]);

    final union =
        area1 +
        area2 -
        intersection;

    if (union <= 0) {
      return 0.0;
    }

    return intersection / union;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  void dispose() {
    _interpreter?.close();

    _interpreter = null;

    _isInitialized = false;

    Logger.log(
      'TFLite Service disposed',
    );
  }
}