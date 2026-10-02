import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'location_service.dart';

enum PlaceRelation { onSite, nearby, elsewhere, uncertain }

class PlaceVerification {
  final String query;
  final String matchedName;
  final String displayName;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final double matchScore;
  final PlaceRelation relation;

  const PlaceVerification({
    required this.query,
    required this.matchedName,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.matchScore,
    required this.relation,
  });

  // Only speak a mapped place as verified when the name match is strong.
  bool get reliable =>
      matchScore >= 0.80 &&
      relation != PlaceRelation.uncertain &&
      displayName.trim().isNotEmpty;

  String get shortDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} metres';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} kilometres';
  }
}

class PlaceVerificationService {
  static final PlaceVerificationService _instance =
      PlaceVerificationService._internal();

  factory PlaceVerificationService() => _instance;

  PlaceVerificationService._internal();

  final Map<String, _CachedVerification> _cache = {};
  DateTime? _lastRequestAt;

  bool isPlaceLikeText(String text) {
    final value = _cleanQuery(text);
    if (value.length < 4 || _looksGeneric(value)) return false;
    return RegExp(r'[A-Za-z]').hasMatch(value) ||
        RegExp(r'[\u0900-\u097F]').hasMatch(value) ||
        RegExp(r'[\u0C80-\u0CFF]').hasMatch(value);
  }

  String spokenContext(PlaceVerification verification) {
    final distance = verification.shortDistance;
    final mappedAddress = verification.displayName.trim();
    final addressPart = mappedAddress.isEmpty
        ? ''
        : ' Mapped address: ${verification.displayName}.';

    switch (verification.relation) {
      case PlaceRelation.onSite:
        return 'VERIFIED SIGN-RELATED PLACE. ${verification.matchedName} is mapped about $distance from the user.$addressPart This is a map location for the named place, not proof of the exact physical sign position.';
      case PlaceRelation.nearby:
        return 'VERIFIED NEARBY SIGN-RELATED PLACE. ${verification.matchedName} is mapped about $distance from the user.$addressPart This is a map location for the named place, not proof of the exact physical sign position.';
      case PlaceRelation.elsewhere:
        return 'The sign refers to ${verification.matchedName}, mapped about $distance from the user.$addressPart This appears to be a different location, not the current sign position.';
      case PlaceRelation.uncertain:
        return '';
    }
  }

  Future<PlaceVerification?> verify({
    required String visibleText,
    required LocationSnapshot location,
  }) async {
    // Do not attempt a confident map match when the phone's GPS fix is too
    // uncertain. The user should hear "location uncertain", not a false shop.
    if (location.accuracy > 60) return null;

    final query = _correctCommonOCR(_cleanQuery(visibleText));
    if (query.length < 4 || _looksGeneric(query)) return null;

    final cacheKey = '${query.toLowerCase()}|${location.latitude.toStringAsFixed(3)}|${location.longitude.toStringAsFixed(3)}';

    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) <
            const Duration(minutes: 10)) {
      return cached.value;
    }

    final last = _lastRequestAt;
    if (last != null) {
      final wait = const Duration(seconds: 2) -
          DateTime.now().difference(last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }

    _lastRequestAt = DateTime.now();

    HttpClient? client;
    try {
      final city = location.city?.trim() ?? '';
      final searchQuery = city.isEmpty ? query : '$query, $city';

      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=5&addressdetails=1&q=${Uri.encodeQueryComponent(searchQuery)}',
      );

      final request =
          await client.getUrl(uri).timeout(
                const Duration(seconds: 4),
              );

      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AI-Signboard-Reader/2.4 accessibility project',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json',
      );

      final response =
          await request.close().timeout(
                const Duration(seconds: 5),
              );

      if (response.statusCode != 200) return null;

      final body =
          await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);

      if (decoded is! List) return null;

      PlaceVerification? best;

      for (final raw in decoded) {
        if (raw is! Map<String, dynamic>) continue;

        final lat =
            double.tryParse(raw['lat']?.toString() ?? '');
        final lon =
            double.tryParse(raw['lon']?.toString() ?? '');

        if (lat == null || lon == null) continue;

        final display =
            (raw['display_name']?.toString() ?? '').trim();
        final name =
            (raw['name']?.toString() ?? '').trim();

        final candidateName =
            name.isEmpty ? _firstDisplayPart(display) : name;

        final score =
            _nameSimilarity(query, candidateName);

        if (score < 0.35) continue;

        final distance = _distanceMeters(
          location.latitude,
          location.longitude,
          lat,
          lon,
        );

        final candidate = PlaceVerification(
          query: query,
          matchedName: candidateName,
          displayName: display,
          latitude: lat,
          longitude: lon,
          distanceMeters: distance,
          matchScore: score,
          relation: _relation(distance),
        );

        if (best == null ||
            _candidateRank(candidate) >
                _candidateRank(best)) {
          best = candidate;
        }
      }

      _cache[cacheKey] = _CachedVerification(
        time: DateTime.now(),
        value: best,
      );

      return best;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  String _correctCommonOCR(String value) {
    var result = value.trim();
    if (result.isEmpty) return result;

    const replacements = <String, String>{
      'pharnacy': 'pharmacy',
      'pharmasy': 'pharmacy',
      'pharmecy': 'pharmacy',
      'pharmcy': 'pharmacy',
      'med1cal': 'medical',
      'medlcal': 'medical',
      'h0spital': 'hospital',
      'hospita1': 'hospital',
      'restarunt': 'restaurant',
      'resturant': 'restaurant',
      'restraunt': 'restaurant',
      'bakary': 'bakery',
      'bakkery': 'bakery',
      'supermarke': 'supermarket',
      'martket': 'market',
    };

    final words = result.split(RegExp(r'\\s+'));
    for (var i = 0; i < words.length; i++) {
      final replacement = replacements[words[i].toLowerCase()];
      if (replacement != null) words[i] = replacement;
    }
    result = words.join(' ');

    final letters = result.split(' ');
    if (letters.length >= 4 &&
        letters.every(_isSingleAsciiLetter)) {
      final compact = letters.join().toLowerCase();
      const knownWords = <String, String>{
        'pharmacy': 'pharmacy',
        'hospital': 'hospital',
        'medical': 'medical',
        'parking': 'parking',
        'school': 'school',
        'restaurant': 'restaurant',
        'bakery': 'bakery',
        'market': 'market',
        'railway': 'railway',
      };
      final corrected = knownWords[compact];
      if (corrected != null) return corrected;
    }

    return result;
  }

  bool _isSingleAsciiLetter(String word) {
    if (word.length != 1) return false;
    final code = word.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
  }

  String _cleanQuery(String value) {
    return value
        .replaceAll(RegExp(r'[|•]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(RegExp(r'(?<=[.!?])\s+'))
        .take(2)
        .join(' ')
        .trim();
  }

  bool _looksGeneric(String value) {
    final normalized = value.toLowerCase();

    const generic = {
      'stop',
      'hospital',
      'medical',
      'medicine',
      'shop',
      'store',
      'welcome',
      'notice',
      'warning',
      'school',
      'bus',
      'railway',
      'road',
    };

    if (generic.contains(normalized)) return true;

    return normalized.split(' ').length == 1 &&
        normalized.length < 5;
  }

  String _firstDisplayPart(String value) {
    final comma = value.indexOf(',');
    return comma > 0
        ? value.substring(0, comma).trim()
        : value;
  }

  double _nameSimilarity(
    String query,
    String candidate,
  ) {
    final q = _tokens(query);
    final c = _tokens(candidate);

    if (q.isEmpty || c.isEmpty) return 0.0;

    var overlap = 0;
    for (final token in q) {
      if (c.contains(token)) overlap++;
    }

    final tokenScore =
        overlap / q.length;

    final compactQuery = q.join();
    final compactCandidate = c.join();

    if (compactQuery.isEmpty ||
        compactCandidate.isEmpty) {
      return tokenScore;
    }

    final substringScore =
        compactCandidate.contains(compactQuery) ||
                compactQuery.contains(compactCandidate)
            ? 0.85
            : 0.0;

    return math.max(
      tokenScore,
      substringScore,
    );
  }

  Set<String> _tokens(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'[^a-z0-9\u0900-\u097f\u0c80-\u0cff ]',
          ),
          ' ',
        )
        .split(RegExp(r'\s+'))
        .where((e) => e.length >= 2)
        .toSet();
  }

  PlaceRelation _relation(double meters) {
    if (meters <= 80) return PlaceRelation.onSite;
    if (meters <= 300) return PlaceRelation.nearby;
    return PlaceRelation.elsewhere;
  }

  double _candidateRank(PlaceVerification value) {
    final distanceScore =
        1.0 / (1.0 + value.distanceMeters / 100.0);

    return value.matchScore * 0.75 +
        distanceScore * 0.25;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) *
            math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadius *
        2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(1 - a),
        );
  }

  double _toRadians(double value) =>
      value * math.pi / 180.0;
}

class _CachedVerification {
  final DateTime time;
  final PlaceVerification? value;

  const _CachedVerification({
    required this.time,
    required this.value,
  });
}
