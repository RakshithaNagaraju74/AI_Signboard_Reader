import 'package:geolocator/geolocator.dart';

class LocationSnapshot {
  final double latitude, longitude, accuracy;
  final DateTime timestamp;
  const LocationSnapshot({required this.latitude, required this.longitude, required this.accuracy, required this.timestamp});
}

class LocationService {
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p != LocationPermission.denied && p != LocationPermission.deniedForever;
  }

  Future<LocationSnapshot?> current() async {
    if (!await ensurePermission()) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter:5),
    );
    return LocationSnapshot(latitude:p.latitude, longitude:p.longitude, accuracy:p.accuracy, timestamp:p.timestamp);
  }
}
