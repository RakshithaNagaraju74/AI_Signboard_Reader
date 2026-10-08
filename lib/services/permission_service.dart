import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<PermissionStatus> requestCamera() async {
    final status = await Permission.camera.status;
    if (status == PermissionStatus.granted) return status;
    return Permission.camera.request();
  }

  Future<PermissionStatus> requestMicrophone() async {
    final status = await Permission.microphone.status;
    if (status == PermissionStatus.granted) return status;
    return Permission.microphone.request();
  }

  Future<PermissionStatus> requestLocation() async {
    final status = await Permission.locationWhenInUse.status;
    if (status == PermissionStatus.granted) return status;
    return Permission.locationWhenInUse.request();
  }

  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (error) {
      debugPrint('[Permissions] openAppSettings failed: ' + error.toString());
      return false;
    }
  }

  Future<bool> cameraGranted() async =>
      (await Permission.camera.status).isGranted;

  Future<bool> microphoneGranted() async =>
      (await Permission.microphone.status).isGranted;

  Future<bool> locationGranted() async =>
      (await Permission.locationWhenInUse.status).isGranted;

  Future<bool> anyCorePermissionPermanentlyDenied() async {
    final statuses = await Future.wait([
      Permission.camera.status,
      Permission.microphone.status,
      Permission.locationWhenInUse.status,
    ]);

    return statuses.any(
      (status) => status == PermissionStatus.permanentlyDenied,
    );
  }
}
