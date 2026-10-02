import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

class SpeechDetectionInput {
  final String label;
  final String position;
  final String text;
  final String movement;
  final String proximity;
  final String guidance;
  final String placeContext;
  final bool safety;

  const SpeechDetectionInput({
    required this.label,
    required this.position,
    this.text = '',
    this.movement = '',
    this.proximity = '',
    this.guidance = '',
    this.placeContext = '',
    this.safety = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'sign': label,
      'position': position,
      if (text.isNotEmpty) 'visible_text': text,
      if (movement.isNotEmpty) 'movement': movement,
      if (proximity.isNotEmpty) 'proximity': proximity,
      if (guidance.isNotEmpty) 'guidance': guidance,
      if (placeContext.isNotEmpty) 'place_context': placeContext,
      'safety': safety,
    };
  }
}

class AISpeechService {
  String get _endpoint {
    final value = dotenv.env['NARA_BASE_URL']?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'https://router.bynara.id/v1';
  }

  String get _apiKey {
    return dotenv.env['NARA_API_KEY']?.trim() ?? '';
  }

  String get _model {
    final value = dotenv.env['NARA_MODEL']?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'auto/bynara';
  }

  bool get naraEnabled => _apiKey.isNotEmpty;

  Future<String> compose({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
    bool useNara = true,
  }) async {
    if (detections.isEmpty) {
      return _fallback(
        detections,
        languageCode,
        place,
      );
    }

    if (useNara && naraEnabled) {
      final generated = await _composeWithNara(
        detections: detections,
        languageCode: languageCode,
        place: place,
      );

      if (generated != null &&
          generated.trim().isNotEmpty) {
        return _clean(generated);
      }
    }

    return _fallback(
      detections,
      languageCode,
      place,
    );
  }

  Future<String?> _composeWithNara({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
  }) async {
    HttpClient? client;

    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final base = _endpoint.endsWith('/')
          ? _endpoint.substring(0, _endpoint.length - 1)
          : _endpoint;

      final request = await client
          .postUrl(Uri.parse('$base/chat/completions'))
          .timeout(const Duration(seconds: 7));

      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_apiKey',
      );

      final languageName = languageCode == 'hi'
          ? 'Hindi'
          : languageCode == 'kn'
              ? 'Kannada'
              : 'English';

      final evidence = detections.map((d) => d.toJson()).toList();

      final payload = {
        'model': _model,
        'temperature': 0.0,
        'max_tokens': 220,
        'messages': [
          {
            'role': 'system',
            'content': '''
You are SightToSound, an accessibility narration engine for a blind pedestrian.

Your ONLY job is to convert visual detection evidence into one short, accurate, natural sentence that can be spoken aloud.

CRITICAL RULES:
1. NEVER output class IDs, confidence scores, bounding boxes, JSON, OCR terminology, model terminology, debugging text, or words such as "class 0".
2. NEVER simply repeat the detected label. Interpret the label together with all visible text and context.
3. visible_text is noisy OCR. Correct obvious OCR errors only when the evidence strongly supports the correction.
4. Combine fragments. "M E D I C A L" -> "Medical". "H" on a hospital sign may mean Hospital. "P" on a parking/no-parking sign may mean Parking when the sign context supports it.
5. Do NOT invent missing words. If evidence is uncertain, describe only what is reliably known.
6. Preserve numbers exactly. "50M" means "50 metres". Do not turn 2, 4, 6, 8 into an invented rule. Explain numbers only when their surrounding sign evidence establishes their meaning.
7. If a sign says or clearly indicates NO PARKING, say "No parking" rather than merely "parking".
8. If several OCR fragments belong to one sign, combine them into one meaning instead of reading each fragment separately.
9. Position is important. Use the supplied position exactly: far left, slightly left, directly ahead, slightly right, or far right.
10. Mention movement or proximity only when supplied.
11. Safety information comes first.
12. Do not give crossing, turning, route, or navigation instructions unless explicit guidance is supplied.
13. Do not mention place context unless it is useful to understanding the sign.
14. Prefer meaning over literal OCR. Never spell ordinary words letter by letter.
15. Output ONLY the final spoken sentence. No quotes, headings, labels, explanations, or alternatives.
16. Keep it natural and concise, normally one or two sentences.
17. Speak in $languageName.

REASONING PROCEDURE (do silently):
A. Identify the strongest sign category.
B. Collect every OCR fragment and number belonging to that detection.
C. Repair obvious spacing, character substitutions, and partial words.
D. Check whether fragments change the meaning of the sign, especially NOT/NO, arrows, distances, restrictions, and warnings.
E. Combine category + readable meaning + position + relevant distance/proximity.
F. Produce the safest useful narration supported by the evidence.

EXAMPLES:
- sign=parking, visible_text=P, position=directly ahead -> "There is a parking sign directly ahead."
- sign=no parking, visible_text=P 50M -> "No parking ahead, with the restriction indicated for 50 metres." 
- sign=hospital, visible_text=H -> "There is a hospital sign ahead."
- sign=shop, visible_text=M E D I C A L -> "There is a medical shop sign ahead."
- sign=stop, visible_text=STOP -> "There is a stop sign ahead."
- uncertain OCR such as XQ7 -> do not invent a word; describe the detected sign category and position.
''',
          },
          {
            'role': 'user',
            'content': jsonEncode({
              'language': languageName,
              'location_context': place ?? '',
              'detections': evidence,
            }),
          },
        ],
      };

      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;

      if (choices == null || choices.isEmpty) {
        return null;
      }

      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      final content = message?['content']?.toString().trim();

      if (content == null || content.isEmpty) {
        return null;
      }

      return content;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  String _fallback(
    List<SpeechDetectionInput> detections,
    String languageCode,
    String? place,
  ) {
    if (detections.isEmpty) {
      if (languageCode == 'hi') {
        return 'मुझे कोई स्पष्ट संकेत नहीं मिला।';
      }

      if (languageCode == 'kn') {
        return 'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಫಲಕ ಕಂಡುಬಂದಿಲ್ಲ.';
      }

      return 'I cannot see a clear signboard.';
    }

    final safety =
        detections.any((e) => e.safety);

    final count = detections.length;

    if (languageCode == 'hi') {
      final parts =
          detections.map(_hindiItem).join('। ');

      final prefix =
          safety ? 'सावधान। ' : '';

      final placePart =
          place == null || place.isEmpty
              ? ''
              : ' आप अभी $place के पास हैं।';

      return '$prefix'
          'मुझे $count संकेत दिखाई दे रहे हैं। '
          '$parts।'
          '$placePart';
    }

    if (languageCode == 'kn') {
      final parts =
          detections.map(_kannadaItem).join('. ');

      final prefix =
          safety ? 'ಎಚ್ಚರಿಕೆ. ' : '';

      final placePart =
          place == null || place.isEmpty
              ? ''
              : ' ನೀವು ಈಗ $place ಬಳಿ ಇದ್ದೀರಿ.';

      return '$prefix'
          'ನನಗೆ $count ಫಲಕಗಳು ಕಾಣುತ್ತಿವೆ. '
          '$parts.'
          '$placePart';
    }

    final parts =
        detections.map(_englishItem).join('. ');

    final prefix =
        safety ? 'Warning. ' : '';

    final placePart =
        place == null || place.isEmpty
            ? ''
            : ' You are near $place.';

    final signWord =
        count == 1 ? 'sign' : 'signs';

    return '$prefix'
        'I can see $count $signWord. '
        '$parts.'
        '$placePart';
  }

  String _englishItem(
    SpeechDetectionInput e,
  ) {
    var result =
        '${e.label} ${e.position}';

    if (e.guidance.isNotEmpty) {
      result += '. ${e.guidance}';
    }

    if (e.placeContext.isNotEmpty) {
      result += '. ${e.placeContext}';
    }

    if (e.text.isNotEmpty) {
      result +=
          ', with the text "${e.text}"';
    }

    if (e.movement.isNotEmpty) {
      result +=
          '. ${_englishMovement(e.movement)}';
    } else if (e.proximity.isNotEmpty) {
      result +=
          '. ${_englishProximity(e.proximity)}';
    }

    return result;
  }

  String _hindiItem(
    SpeechDetectionInput e,
  ) {
    var result =
        '${e.label} ${_hindiPosition(e.position)}';

    if (e.guidance.isNotEmpty) {
      result += '। ${e.guidance}';
    }

    if (e.placeContext.isNotEmpty) {
      result += '। ${e.placeContext}';
    }

    if (e.text.isNotEmpty) {
      result +=
          ', जिस पर "${e.text}" लिखा है';
    }

    if (e.movement.isNotEmpty) {
      result +=
          '। ${_hindiMovement(e.movement)}';
    } else if (e.proximity.isNotEmpty) {
      result +=
          '। ${_hindiProximity(e.proximity)}';
    }

    return result;
  }

  String _kannadaItem(
    SpeechDetectionInput e,
  ) {
    var result =
        '${e.label} ${_kannadaPosition(e.position)}';

    if (e.guidance.isNotEmpty) {
      result += '. ${e.guidance}';
    }

    if (e.placeContext.isNotEmpty) {
      result += '. ${e.placeContext}';
    }

    if (e.text.isNotEmpty) {
      result +=
          ', ಅದರಲ್ಲಿ "${e.text}" ಎಂದು ಬರೆಯಲಾಗಿದೆ';
    }

    if (e.movement.isNotEmpty) {
      result +=
          '. ${_kannadaMovement(e.movement)}';
    } else if (e.proximity.isNotEmpty) {
      result +=
          '. ${_kannadaProximity(e.proximity)}';
    }

    return result;
  }

  String _englishMovement(String value) {
    if (value == 'getting closer') {
      return 'It appears to be getting closer';
    }

    if (value == 'moving farther away') {
      return 'It appears to be getting farther away';
    }

    if (value == 'moving to your left') {
      return 'It is moving toward your left';
    }

    if (value == 'moving to your right') {
      return 'It is moving toward your right';
    }

    return value;
  }

  String _englishProximity(String value) {
    if (value == 'far') {
      return 'It appears far away';
    }

    if (value == 'approaching') {
      return 'It appears to be getting closer';
    }

    if (value == 'nearby') {
      return 'It is nearby';
    }

    return '';
  }

  String _hindiPosition(String value) {
    if (value == 'far left') {
      return 'बहुत बाईं ओर है';
    }

    if (value == 'slightly left') {
      return 'थोड़ा बाईं ओर है';
    }

    if (value == 'directly ahead') {
      return 'सीधे सामने है';
    }

    if (value == 'slightly right') {
      return 'थोड़ा दाईं ओर है';
    }

    return 'बहुत दाईं ओर है';
  }

  String _kannadaPosition(String value) {
    if (value == 'far left') {
      return 'ತುಂಬಾ ಎಡಭಾಗದಲ್ಲಿದೆ';
    }

    if (value == 'slightly left') {
      return 'ಸ್ವಲ್ಪ ಎಡಭಾಗದಲ್ಲಿದೆ';
    }

    if (value == 'directly ahead') {
      return 'ನೇರವಾಗಿ ಮುಂದೆ ಇದೆ';
    }

    if (value == 'slightly right') {
      return 'ಸ್ವಲ್ಪ ಬಲಭಾಗದಲ್ಲಿದೆ';
    }

    return 'ತುಂಬಾ ಬಲಭಾಗದಲ್ಲಿದೆ';
  }

  String _hindiMovement(String value) {
    if (value == 'getting closer') {
      return 'संकेत पास आता हुआ लग रहा है';
    }

    if (value == 'moving farther away') {
      return 'संकेत दूर जाता हुआ लग रहा है';
    }

    if (value == 'moving to your left') {
      return 'संकेत बाईं ओर जा रहा है';
    }

    if (value == 'moving to your right') {
      return 'संकेत दाईं ओर जा रहा है';
    }

    return value;
  }

  String _kannadaMovement(String value) {
    if (value == 'getting closer') {
      return 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ';
    }

    if (value == 'moving farther away') {
      return 'ಸಂಕೇತ ದೂರವಾಗುತ್ತಿದೆ';
    }

    if (value == 'moving to your left') {
      return 'ಸಂಕೇತ ಎಡಕ್ಕೆ ಸರಿಯುತ್ತಿದೆ';
    }

    if (value == 'moving to your right') {
      return 'ಸಂಕೇತ ಬಲಕ್ಕೆ ಸರಿಯುತ್ತಿದೆ';
    }

    return value;
  }

  String _hindiProximity(String value) {
    if (value == 'far') {
      return 'संकेत दूर है';
    }

    if (value == 'approaching') {
      return 'संकेत पास आ रहा है';
    }

    if (value == 'nearby') {
      return 'संकेत पास है';
    }

    return '';
  }

  String _kannadaProximity(String value) {
    if (value == 'far') {
      return 'ಸಂಕೇತ ದೂರದಲ್ಲಿದೆ';
    }

    if (value == 'approaching') {
      return 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ';
    }

    if (value == 'nearby') {
      return 'ಸಂಕೇತ ಹತ್ತಿರದಲ್ಲಿದೆ';
    }

    return '';
  }

  String _clean(String value) {
    var result = value.trim();

    // Remove common prefixes such as:
    // "assistant: ..."
    // "response: ..."
    result = result.replaceFirst(
      RegExp(
        r'^(assistant|response):\s*',
        caseSensitive: false,
      ),
      '',
    );

    // Remove one pair of surrounding quotes.
    if (result.length >= 2) {
      final startsWithQuote =
          result.startsWith('"') ||
              result.startsWith("'");

      final endsWithQuote =
          result.endsWith('"') ||
              result.endsWith("'");

      if (startsWithQuote &&
          endsWithQuote) {
        result = result.substring(
          1,
          result.length - 1,
        );
      }
    }

    return result.trim();
  }
}