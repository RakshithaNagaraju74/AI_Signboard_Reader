import 'dart:async';
import 'dart:ui';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationSnapshot {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final String? placeName;
  final String? addressLine;
  final String? street;
  final String? area;
  final String? city;

  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.placeName,
    this.addressLine,
    this.street,
    this.area,
    this.city,
  });

  String get displayPlace {
    final parts = <String>[];
    if (street != null && street!.trim().isNotEmpty) parts.add(street!.trim());
    if (area != null && area!.trim().isNotEmpty && !parts.contains(area!.trim())) {
      parts.add(area!.trim());
    }
    if (city != null && city!.trim().isNotEmpty && !parts.contains(city!.trim())) {
      parts.add(city!.trim());
    }
    if (parts.isNotEmpty) return parts.join(', ');
    if (placeName != null && placeName!.trim().isNotEmpty) return placeName!.trim();
    return 'GPS location available';
  }

  // More useful for spoken orientation than coordinates. This is still an
  // address derived from reverse geocoding, so the spoken accuracy is always
  // paired with the phone's measured GPS accuracy.
  String get displayAddress {
    final parts = <String>[];
    if (addressLine != null && addressLine!.trim().isNotEmpty) {
      parts.add(addressLine!.trim());
    }
    if (area != null &&
        area!.trim().isNotEmpty &&
        !parts.any((item) => item.contains(area!.trim()))) {
      parts.add(area!.trim());
    }
    if (city != null &&
        city!.trim().isNotEmpty &&
        !parts.any((item) => item.contains(city!.trim()))) {
      parts.add(city!.trim());
    }
    if (parts.isNotEmpty) return parts.join(', ');
    return displayPlace;
  }
}

class LocationService {
  
  LocationSnapshot? _cached;
  DateTime? _lastLocationFetch;
  DateTime? _lastGeocoded;

  Geocoding _geocodingFor(String localeIdentifier) =>
      Geocoding(locale: _toLocale(localeIdentifier));

  Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[GPS] location service enabled=

  Future<LocationSnapshot?> current({
    String localeIdentifier = 'en_US',
    bool refreshPlace = false,
  }) async {
    if (!await ensurePermission()) return _cached;

    final now = DateTime.now();
    final locationIsFresh = _cached != null &&
        _lastLocationFetch != null &&
        now.difference(_lastLocationFetch!) < const Duration(seconds: 5);

    if (locationIsFresh && !refreshPlace) {
      return _cached;
    }

    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('[GPS] last-known accuracy=' +
            lastKnown.accuracy.toStringAsFixed(1) + 'm');
      }
    } catch (e) {
      debugPrint('[GPS] last-known lookup failed: ' + e.toString());
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Location request timed out'),
      );
      debugPrint('[GPS] fresh position accuracy=' +
          position.accuracy.toStringAsFixed(1) + 'm');
    } catch (e) {
      if (lastKnown != null) {
        debugPrint('[GPS] current fix failed; using last-known position: ' + e.toString());
        position = lastKnown;
      } else if (_cached != null) {
        debugPrint('[GPS] current fix failed; using cached snapshot: ' + e.toString());
        return _cached;
      } else {
        rethrow;
      }
    }

    _lastLocationFetch = now;
    final shouldGeocode = refreshPlace ||
        _lastGeocoded == null ||
        now.difference(_lastGeocoded!) > const Duration(seconds: 30) ||
        _cached == null;

    String? placeName = _cached?.placeName;
    String? addressLine = _cached?.addressLine;
    String? street = _cached?.street;
    String? area = _cached?.area;
    String? city = _cached?.city;

    if (shouldGeocode) {
      try {
        final placemarks = await _geocodingFor(localeIdentifier)
            .placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = _firstNonEmpty([p.name, p.subLocality, p.locality]);
          addressLine = _firstNonEmpty([
            _joinAddressParts([
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ]),
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]);
          street = _firstNonEmpty([p.street, p.thoroughfare]);
          area = _firstNonEmpty([p.subLocality, p.subAdministrativeArea]);
          city = _firstNonEmpty([p.locality, p.administrativeArea]);
        }
        _lastGeocoded = now;
      } catch (_) {
        // GPS should still work when native reverse geocoding is unavailable.
      }
    }

    _cached = LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      placeName: placeName,
      addressLine: addressLine,
      street: street,
      area: area,
      city: city,
    );

    return _cached;
  }

  Locale _toLocale(String identifier) {
    final parts = identifier.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts.first);
  }

  String? _joinAddressParts(List<String?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = value?.trim();
      if (cleaned == null || cleaned.isEmpty) continue;
      if (!parts.any((part) => part.toLowerCase() == cleaned.toLowerCase())) {
        parts.add(cleaned);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
 + serviceEnabled.toString());
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    debugPrint('[GPS] permission before request=

  Future<LocationSnapshot?> current({
    String localeIdentifier = 'en_US',
    bool refreshPlace = false,
  }) async {
    if (!await ensurePermission()) return _cached;

    final now = DateTime.now();
    final locationIsFresh = _cached != null &&
        _lastLocationFetch != null &&
        now.difference(_lastLocationFetch!) < const Duration(seconds: 5);

    if (locationIsFresh && !refreshPlace) {
      return _cached;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('Location request timed out'),
    );

    _lastLocationFetch = now;
    final shouldGeocode = refreshPlace ||
        _lastGeocoded == null ||
        now.difference(_lastGeocoded!) > const Duration(seconds: 30) ||
        _cached == null;

    String? placeName = _cached?.placeName;
    String? addressLine = _cached?.addressLine;
    String? street = _cached?.street;
    String? area = _cached?.area;
    String? city = _cached?.city;

    if (shouldGeocode) {
      try {
        final placemarks = await _geocodingFor(localeIdentifier)
            .placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = _firstNonEmpty([p.name, p.subLocality, p.locality]);
          addressLine = _firstNonEmpty([
            _joinAddressParts([
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ]),
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]);
          street = _firstNonEmpty([p.street, p.thoroughfare]);
          area = _firstNonEmpty([p.subLocality, p.subAdministrativeArea]);
          city = _firstNonEmpty([p.locality, p.administrativeArea]);
        }
        _lastGeocoded = now;
      } catch (_) {
        // GPS should still work when native reverse geocoding is unavailable.
      }
    }

    _cached = LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      placeName: placeName,
      addressLine: addressLine,
      street: street,
      area: area,
      city: city,
    );

    return _cached;
  }

  Locale _toLocale(String identifier) {
    final parts = identifier.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts.first);
  }

  String? _joinAddressParts(List<String?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = value?.trim();
      if (cleaned == null || cleaned.isEmpty) continue;
      if (!parts.any((part) => part.toLowerCase() == cleaned.toLowerCase())) {
        parts.add(cleaned);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
 + permission.toString());

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[GPS] permission after request=

  Future<LocationSnapshot?> current({
    String localeIdentifier = 'en_US',
    bool refreshPlace = false,
  }) async {
    if (!await ensurePermission()) return _cached;

    final now = DateTime.now();
    final locationIsFresh = _cached != null &&
        _lastLocationFetch != null &&
        now.difference(_lastLocationFetch!) < const Duration(seconds: 5);

    if (locationIsFresh && !refreshPlace) {
      return _cached;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('Location request timed out'),
    );

    _lastLocationFetch = now;
    final shouldGeocode = refreshPlace ||
        _lastGeocoded == null ||
        now.difference(_lastGeocoded!) > const Duration(seconds: 30) ||
        _cached == null;

    String? placeName = _cached?.placeName;
    String? addressLine = _cached?.addressLine;
    String? street = _cached?.street;
    String? area = _cached?.area;
    String? city = _cached?.city;

    if (shouldGeocode) {
      try {
        final placemarks = await _geocodingFor(localeIdentifier)
            .placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = _firstNonEmpty([p.name, p.subLocality, p.locality]);
          addressLine = _firstNonEmpty([
            _joinAddressParts([
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ]),
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]);
          street = _firstNonEmpty([p.street, p.thoroughfare]);
          area = _firstNonEmpty([p.subLocality, p.subAdministrativeArea]);
          city = _firstNonEmpty([p.locality, p.administrativeArea]);
        }
        _lastGeocoded = now;
      } catch (_) {
        // GPS should still work when native reverse geocoding is unavailable.
      }
    }

    _cached = LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      placeName: placeName,
      addressLine: addressLine,
      street: street,
      area: area,
      city: city,
    );

    return _cached;
  }

  Locale _toLocale(String identifier) {
    final parts = identifier.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts.first);
  }

  String? _joinAddressParts(List<String?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = value?.trim();
      if (cleaned == null || cleaned.isEmpty) continue;
      if (!parts.any((part) => part.toLowerCase() == cleaned.toLowerCase())) {
        parts.add(cleaned);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
 + permission.toString());
    }

    final allowed = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
    debugPrint('[GPS] permission allowed=

  Future<LocationSnapshot?> current({
    String localeIdentifier = 'en_US',
    bool refreshPlace = false,
  }) async {
    if (!await ensurePermission()) return _cached;

    final now = DateTime.now();
    final locationIsFresh = _cached != null &&
        _lastLocationFetch != null &&
        now.difference(_lastLocationFetch!) < const Duration(seconds: 5);

    if (locationIsFresh && !refreshPlace) {
      return _cached;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('Location request timed out'),
    );

    _lastLocationFetch = now;
    final shouldGeocode = refreshPlace ||
        _lastGeocoded == null ||
        now.difference(_lastGeocoded!) > const Duration(seconds: 30) ||
        _cached == null;

    String? placeName = _cached?.placeName;
    String? addressLine = _cached?.addressLine;
    String? street = _cached?.street;
    String? area = _cached?.area;
    String? city = _cached?.city;

    if (shouldGeocode) {
      try {
        final placemarks = await _geocodingFor(localeIdentifier)
            .placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = _firstNonEmpty([p.name, p.subLocality, p.locality]);
          addressLine = _firstNonEmpty([
            _joinAddressParts([
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ]),
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]);
          street = _firstNonEmpty([p.street, p.thoroughfare]);
          area = _firstNonEmpty([p.subLocality, p.subAdministrativeArea]);
          city = _firstNonEmpty([p.locality, p.administrativeArea]);
        }
        _lastGeocoded = now;
      } catch (_) {
        // GPS should still work when native reverse geocoding is unavailable.
      }
    }

    _cached = LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      placeName: placeName,
      addressLine: addressLine,
      street: street,
      area: area,
      city: city,
    );

    return _cached;
  }

  Locale _toLocale(String identifier) {
    final parts = identifier.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts.first);
  }

  String? _joinAddressParts(List<String?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = value?.trim();
      if (cleaned == null || cleaned.isEmpty) continue;
      if (!parts.any((part) => part.toLowerCase() == cleaned.toLowerCase())) {
        parts.add(cleaned);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
 + allowed.toString());
    return allowed;
  }

  Future<LocationSnapshot?> current({
    String localeIdentifier = 'en_US',
    bool refreshPlace = false,
  }) async {
    if (!await ensurePermission()) return _cached;

    final now = DateTime.now();
    final locationIsFresh = _cached != null &&
        _lastLocationFetch != null &&
        now.difference(_lastLocationFetch!) < const Duration(seconds: 5);

    if (locationIsFresh && !refreshPlace) {
      return _cached;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('Location request timed out'),
    );

    _lastLocationFetch = now;
    final shouldGeocode = refreshPlace ||
        _lastGeocoded == null ||
        now.difference(_lastGeocoded!) > const Duration(seconds: 30) ||
        _cached == null;

    String? placeName = _cached?.placeName;
    String? addressLine = _cached?.addressLine;
    String? street = _cached?.street;
    String? area = _cached?.area;
    String? city = _cached?.city;

    if (shouldGeocode) {
      try {
        final placemarks = await _geocodingFor(localeIdentifier)
            .placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          placeName = _firstNonEmpty([p.name, p.subLocality, p.locality]);
          addressLine = _firstNonEmpty([
            _joinAddressParts([
              p.name,
              p.street,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ]),
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ]);
          street = _firstNonEmpty([p.street, p.thoroughfare]);
          area = _firstNonEmpty([p.subLocality, p.subAdministrativeArea]);
          city = _firstNonEmpty([p.locality, p.administrativeArea]);
        }
        _lastGeocoded = now;
      } catch (_) {
        // GPS should still work when native reverse geocoding is unavailable.
      }
    }

    _cached = LocationSnapshot(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
      placeName: placeName,
      addressLine: addressLine,
      street: street,
      area: area,
      city: city,
    );

    return _cached;
  }

  Locale _toLocale(String identifier) {
    final parts = identifier.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return Locale(parts.first);
  }

  String? _joinAddressParts(List<String?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = value?.trim();
      if (cleaned == null || cleaned.isEmpty) continue;
      if (!parts.any((part) => part.toLowerCase() == cleaned.toLowerCase())) {
        parts.add(cleaned);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
