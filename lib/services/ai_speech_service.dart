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
    final value = dotenv.env['GROQ_BASE_URL']?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'https://api.groq.com/openai/v1';
  }

  String get _apiKey {
    return dotenv.env['GROQ_API_KEY']?.trim() ?? '';
  }

  String get _model {
    final value = dotenv.env['GROQ_MODEL']?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'openai/gpt-oss-120b';
  }

  bool get groqEnabled => _apiKey.isNotEmpty;

  Future<String> compose({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
    bool useGroq = true,
  }) async {
    if (detections.isEmpty) {
      return _fallback(
        detections,
        languageCode,
        place,
      );
    }

    if (useGroq && groqEnabled) {
      final generated = await _composeWithGroq(
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

  Future<String?> _composeWithGroq({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
  }) async {
    HttpClient? client;

    try {
      client = HttpClient()
        ..connectionTimeout =
            const Duration(seconds: 2);

      final base = _endpoint.endsWith('/')
          ? _endpoint.substring(
              0,
              _endpoint.length - 1,
            )
          : _endpoint;

      final request = await client
          .postUrl(
            Uri.parse(
              '$base/chat/completions',
            ),
          )
          .timeout(
            const Duration(seconds: 3),
          );

      request.headers.contentType =
          ContentType.json;

      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_apiKey',
      );

      final languageName =
          languageCode == 'hi'
              ? 'Hindi'
              : languageCode == 'kn'
                  ? 'Kannada'
                  : 'English';

      final payload = {
        'model': _model,
        'temperature': 0.1,
        'reasoning_effort': 'high',
        'max_completion_tokens': 180,
        'messages': [
          {
            'role': 'system',
            'content':
                'You are the accessibility voice assistant for a blind pedestrian. '
                'Transform the supplied visual detections into a calm, helpful spoken description in $languageName. '
                'The user needs useful information, not technical analysis. '
                'Treat visible_text as noisy OCR, not as ground truth. First silently correct obvious OCR spelling and spacing mistakes when the intended word is clear. ' +
                'For letter-spaced text such as M E D I C A L, combine it into a normal word when context makes that clear. ' +
                'Do not blindly preserve OCR errors, but never invent or guess a word when the evidence is insufficient. ' +
                'Use the sign category, OCR text, visible letters, numbers, position, and place context together as evidence. Do not treat a single OCR character literally when it is clearly a sign abbreviation. ' +
                'Context examples: P or a partial P on a parking/no-parking sign can mean Parking or No Parking when the sign category and surrounding evidence support it; H on a hospital/medical sign can mean Hospital; a single B, M, S, etc. may be a shortened word only when the sign context strongly supports it. ' +
                'If OCR returns only one or two characters, first ask what real-world sign meaning best explains those characters together with the detected sign class and other OCR fragments. ' +
                'For a No Parking sign, combine fragments such as P, NO, 50 M, and vehicle/type markings into one useful meaning instead of reading them as separate letters and numbers. ' +
                'If the sign contains a distance such as 50M, interpret it as a distance and say "50 metres" rather than reading each character. ' +
                'If vehicle classes or counts such as 2, 4, 6, or 8 appear, treat them as sign restrictions or vehicle categories when the sign context indicates that, and explain the meaning naturally without inventing a rule that is not supported by the sign. ' +
                'Prioritize the corrected readable sign meaning over the generic sign category. If OCR text exists, say what the sign means in context. '
                'Example style: There is a shop sign directly ahead. It says Medical Store. '
                'If there is no readable text, briefly describe the sign category and where it is. '
                'Use position words such as left, slightly left, ahead, slightly right, and right exactly as supplied. '
                'Only mention getting closer, farther away, or other movement when supplied. '
                'Do not give road-crossing or turning instructions unless explicit guidance says so. '
                'Never invent text, places, distances, objects, destinations, or hazards. Only correct OCR when the correction is strongly supported by the detected characters and context. '
                'Never mention class IDs, confidence, bounding boxes, JSON, OCR, model names, or developer language. '
                'For a safety sign, start with a clear warning. '
                'If a place_context warns that a sign advertises a place elsewhere, say that clearly. '
                'Read words as normal human language, never as a sequence of letters unless the sign genuinely contains an acronym or initials. ' +
                'Treat phone numbers, PIN codes, OTPs, house numbers, route numbers, prices, dates, and other numeric strings as meaningful numbers, not arithmetic. ' +
                'For phone numbers and PIN codes, preserve every digit and present them in small natural groups so text-to-speech reads the digits clearly. ' +
                'Never pronounce a word letter-by-letter merely because OCR supplied isolated characters. Prefer the complete human-readable word or meaning whenever context makes it reliable. ' +
                'Do not drop, reorder, merge, or invent digits. For ordinary numbers, use natural spoken-number wording when appropriate. ' +
                'Avoid repetitive wording and combine related information into a short natural sentence. '
                'Keep the narration concise, ideally one or two sentences. Return only the spoken narration, with no quotation marks, labels, bullet points, markdown, or explanations.',
          },
          {
            'role': 'user',
            'content': jsonEncode({
              'language': languageName,
              'location_context': place ?? '',
              'detections': detections
                  .map((e) => e.toJson())
                  .toList(),
            }),
          },
        ],
      };

      request.add(
        utf8.encode(
          jsonEncode(payload),
        ),
      );

      final response = await request
          .close()
          .timeout(
            const Duration(seconds: 4),
          );

      final body = await utf8.decoder
          .bind(response)
          .join();

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }

      final decoded =
          jsonDecode(body)
              as Map<String, dynamic>;

      final choices =
          decoded['choices'] as List<dynamic>?;

      if (choices == null ||
          choices.isEmpty) {
        return null;
      }

      final firstChoice =
          choices.first as Map<String, dynamic>;

      final message =
          firstChoice['message']
              as Map<String, dynamic>?;

      return message?['content']?.toString();
    } catch (e) {
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