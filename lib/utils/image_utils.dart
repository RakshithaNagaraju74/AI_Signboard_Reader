import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'logger.dart';

class ImageUtils {
  static Future<File> resizeImage(File file, {int maxWidth = 800, int maxHeight = 800}) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) return file;
      
      final resized = img.copyResize(
        image,
        width: maxWidth,
        height: maxHeight,
      );
      
      final resizedBytes = img.encodeJpg(resized, quality: 85);
      await file.writeAsBytes(resizedBytes);
      return file;
    } catch (e) {
      Logger.log('Error resizing image: $e');
      return file;
    }
  }

  static Future<Uint8List> imageToByteList(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) return Uint8List(0);
    
    final resized = img.copyResize(image, width: 416, height: 416);
    
    final Float32List input = Float32List(3 * 416 * 416);
    int idx = 0;
    
    for (int y = 0; y < 416; y++) {
      for (int x = 0; x < 416; x++) {
        final pixel = resized.getPixel(x, y);
        // Use getRed/Green/Blue functions
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);
        input[idx++] = (r / 255.0 - 0.5) * 2;
        input[idx++] = (g / 255.0 - 0.5) * 2;
        input[idx++] = (b / 255.0 - 0.5) * 2;
      }
    }
    
    return input.buffer.asUint8List();
  }

  static File? getImageFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file;
      }
      return null;
    } catch (e) {
      Logger.log('Error getting image file: $e');
      return null;
    }
  }
}