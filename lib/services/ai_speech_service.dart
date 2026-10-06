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
    var value = dotenv.env['GROQ_BASE_URL']?.trim();
    value = value != null && value.isNotEmpty
        ? value
        : 'https://api.groq.com/openai/v1';

    // Accept an older/mistyped base URL that contains /api.
    value = value.replaceFirst('/api/openai/v1', '/openai/v1');
    return value;
  }

  String get _apiKey {
    return dotenv.env['GROQ_API_KEY']?.trim() ?? '';
  }

  String get _model {
    final value = dotenv.env['GROQ_MODEL']?.trim();

    // Groq removed llama-3.1-8b-instant and llama-3.3-70b-versatile.
    // Normalize older .env values so the app keeps working.
    if (value == 'llama-3.1-8b-instant' ||
        value == 'llama-3.3-70b-versatile') {
      return 'openai/gpt-oss-20b';
    }

    return value != null && value.isNotEmpty
        ? value
        : 'openai/gpt-oss-20b';
  }

  bool get groqEnabled => _apiKey.isNotEmpty;

  void _debug(String message) {
    // Safe diagnostics: never print the API key or Authorization header.
    // ignore: avoid_print
    print('[Groq] $message');
  }

  Future<String> compose({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
    bool useGroq = true,
  }) async {
    _debug(
      'compose() called: useNara=$useNara, keyLoaded=${_apiKey.isNotEmpty}, '
      'model=$_model, endpoint=$_endpoint, language=$languageCode, '
      'detections=${detections.length}',
    );

    if (detections.isEmpty) {
      _debug('No detections -> local fallback.');
      return _fallback(detections, languageCode, place);
    }

    if (useNara && groqEnabled) {
      final generated = await _composeWithGroq(
        detections: detections,
        languageCode: languageCode,
        place: place,
      );

      if (generated != null && generated.trim().isNotEmpty) {
        final cleaned = _clean(generated);
        if (_matchesRequestedLanguage(cleaned, languageCode)) {
          _debug('Groq response ACCEPTED -> language=$languageCode, chars=${cleaned.length}');
          _debug('FINAL SPOKEN RESULT -> $cleaned');
          return cleaned;
        }
        _debug('Groq response REJECTED -> wrong language/script for $languageCode');
      }
    } else if (useNara) {
      _debug('Groq requested but API key is missing -> local fallback.');
    }

    final fallback = _fallback(
      detections,
      languageCode,
      place,
    );
    _debug('LOCAL FALLBACK RESULT -> $fallback');
    return fallback;
  }

  Future<String?> _composeWithGroq({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
  }) async {
    HttpClient? client;

    try {
      _debug('REQUEST START -> POST /chat/completions model=$_model language=$languageCode');
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);

      final base = _endpoint.endsWith('/')
          ? _endpoint.substring(0, _endpoint.length - 1)
          : _endpoint;

      final request = await client
          .postUrl(Uri.parse('$base/chat/completions'))
          .timeout(const Duration(seconds: 15));

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
        'max_completion_tokens': 220,
        'reasoning_effort': 'low',
        'include_reasoning': false,
        'messages': [
          {
            'role': 'system',
            'content': '''
You are SightToSound, an accessibility narration engine for a blind pedestrian.

Your ONLY job is to produce the final spoken narration for a blind pedestrian. Think silently, then output the narration directly. The narration must sound like a helpful human assistant, NOT like a computer vision report.

IMPORTANT EVIDENCE MODEL:
- The input is structured evidence from a detector and OCR. You do NOT see the camera image.
- "sign" is the detector's class/category and is important evidence. Never ignore it.
- "visible_text" is OCR from the sign and may contain spelling errors, split letters, missing spaces, or character substitutions. Treat OCR as evidence, not final text.
- When visible_text contains a recognizable real-world word, business name, warning, restriction, direction, or number, preserve its meaning and correct only obvious OCR mistakes.
- If OCR is noisy or contradictory, prefer the detector category plus the reliable OCR fragments instead of inventing a complete sentence from uncertain text.
- Read the sign as a whole. For example, "P", "NO", "PARKING", "50M", arrows, and restriction symbols can change the meaning when they occur together.
- "proximity" is an estimated relation to the camera. A number such as 50M inside visible_text is NOT the distance from the user.
- Never say a sign is 50 metres away merely because the sign contains 50M. Only use a distance when explicitly supplied by proximity or guidance.

REAL-WORLD NARRATION PRIORITY:
- The user needs useful information, not merely a detector category.
- When readable text is available, tell the user what the sign actually says or means. Do not stop at "there is a shop sign ahead" when OCR contains meaningful words.
- For a business sign, preserve the readable business or service name: "There is a Shree Medicals sign slightly left."
- For a generic service sign such as MEDICALS, PHARMACY, BAKERY, HOTEL, SCHOOL, HOSPITAL, or MARKET, state that service explicitly.
- For warnings, restrictions, directions, destinations, routes, bus numbers, road names, or instructions, explain the useful meaning of the text.
- If OCR contains an action or restriction, say the action naturally: "No parking", "Road closed", "Keep left", "Pedestrian crossing", or "Speed limit 40".
- Do not say "with text" when the text can be meaningfully interpreted.
- If OCR is empty or unreliable, use the detector category and position as the minimum useful description; never invent missing text.
- For a blind pedestrian, prioritize: safety/restriction, useful sign wording/name, position, movement/proximity, then reliable location context.

REAL-WORLD INTERPRETATION:
- Think like a human accessibility assistant standing beside the user, not like an OCR debugger.
- For a business sign, say the corrected business/place name naturally: "There is a pharmacy sign on your left."
- For a warning or restriction, state the restriction clearly: "There is a no-parking sign ahead."
- For a directional sign, preserve the destination and direction if the evidence contains them.
- For a number-only sign, report the number only when it is useful to the pedestrian.
- Treat numbers according to their real-world signboard meaning, not as generic quantities.
- INDIAN PIN CODE: when a six-digit numeric string is clearly a PIN/postal code, preserve all six digits exactly as an identifier. Say "PIN code 560001" or the natural Hindi/Kannada equivalent. Never reinterpret 560001 as the quantity five hundred sixty thousand one.
- PHONE NUMBER: when a long digit string is clearly a phone/mobile/contact number, preserve every digit exactly and introduce it as a phone number. Do not interpret it as a large numerical quantity. Natural digit grouping is allowed for speech clarity, but the digit sequence must never change.
- BUS/ROUTE NUMBER: keep identifiers such as 500K together. Say "Bus number 500K", not "five hundred thousand".
- HOUSE/SHOP/BUILDING NUMBER: keep the number as an address identifier, such as "Shop number 24".
- PRICE/FARE: if paired with ₹, Rs, INR, price, or fare, speak it as a price or fare, not as a distance.
- SIGN DISTANCE: a number followed by M, metre, metres, km, or kilometres on the printed sign is sign content. It is NOT the measured distance from the user.
- DATE/TIME: preserve clearly labelled dates and times as dates/times.
- GENERAL NUMBERS: when the meaning is uncertain, preserve the original digits and nearby label rather than converting them into a large spoken quantity.
- NUMERIC INTEGRITY: never drop, reorder, merge, or invent digits from a clearly readable identifier. Keep the exact digit sequence for PIN codes, phone numbers, bus/route numbers, house/shop numbers, prices, dates, and times.
- Do not turn OCR fragments into a place name unless the fragments support that interpretation.
- Do not invent street names, businesses, distances, directions, or navigation instructions.
- If current_location contains the user's current street, area, city, or address with good GPS accuracy, use that current location explicitly when it helps orient the user.
- If verified_signboard_location contains a verified mapped place/address, clearly distinguish it from the user's current location and include the verified approximate distance.
- Never call a mapped POI the exact physical sign position unless the evidence actually establishes that. Prefer "map data places the business..." or "the sign appears to refer to..." when appropriate.

CRITICAL RULES:
1. NEVER output class IDs, confidence scores, bounding boxes, JSON, OCR terminology, model terminology, debugging text, or words such as "class 0".
2. NEVER simply repeat the detected label. Interpret the label together with all visible text and context.
3. Correct obvious OCR spelling and spacing errors before narration. For example, "pharnacy" -> "pharmacy", "MED1CAL" -> "MEDICAL", and "H0SPITAL" -> "HOSPITAL" when the sign/category supports it. Never make speculative corrections.
4. Combine fragments. "M E D I C A L" -> "Medical". "H" on a hospital sign may mean Hospital. "P" on a parking/no-parking sign may mean Parking when the sign context supports it.
5. Do NOT invent missing words. If evidence is uncertain, describe only what is reliably known.
6. Preserve useful numbers from the sign, but treat them as sign content. Never convert 50M or 20M in OCR into the user's distance from the sign.
7. If the detector class or OCR clearly says NO PARKING / NO-PARKING, say "No parking". If evidence only says "P", do NOT claim no parking; say parking or a parking symbol.
8. If several OCR fragments belong to one sign, combine them into one meaning instead of reading each fragment separately.
9. Position is important. Use the supplied position exactly: far left, slightly left, directly ahead, slightly right, or far right.
10. Mention movement or proximity only when supplied.
11. Safety information comes first.
12. Do not give crossing, turning, route, or navigation instructions unless explicit guidance is supplied.
13. Use supplied place context when it helps the user understand where they are or where the sign points.
14. Never translate detector labels word-for-word when that creates an unnatural sentence in Hindi or Kannada. Translate the real-world meaning naturally.
15. When a safety sign is detected, give the safety message first and a simple helpful caution when appropriate.
16. When multiple detections are present, combine related detections into ONE concise scene summary. Do not produce repetitive sentences for every detection.
17. Prefer meaning over literal OCR. Never spell ordinary words letter by letter. "P H A R M A C Y" and "PHARNACY" should become "pharmacy" when context is strong.
18. If OCR contains a likely business name with one obvious spelling error, silently correct that error and speak the corrected name. Do not announce that OCR was corrected.
19. If the OCR is mostly noise, do not repeat the noise. Fall back to the reliable sign category and position.
20. If several detections describe the same physical sign, merge them instead of repeating the same sign.
21. Put the most useful information first: safety/restriction, readable sign meaning, position, then relevant proximity or guidance, then useful location context.
22. Output ONLY the final spoken sentence. No quotes, headings, labels, explanations, or alternatives.
23. Keep it very concise: normally one sentence, maximum two short sentences.
24. Speak ONLY in $languageName. Do not answer in English when Hindi or Kannada is requested.
25. Never spell isolated OCR letters as if they were a normal word.
26. Never output internal detector or debugging terminology.
27. If a shop/business name is readable after correction, preserve that corrected name naturally.
28. Never claim that a business is nearby unless location verification explicitly supplies that fact.
29. Never say phrases like "I can see 3 signs" or "the sign refers to" when a direct natural description is possible.
30. Never discard a clearly useful PIN, phone number, route number, house number, price, date, or time merely because it is numeric.
31. Preserve exact digit sequences for numeric identifiers. Do not turn "560001" into "five hundred sixty thousand one"; say "PIN code 560001" or the natural equivalent in the requested language.
32. Do not read every digit as an unrelated number phrase when the digits form one identifier.
33. If a number is ambiguous, preserve the digits and their nearby label instead of guessing its meaning.
34. If current_location is supplied with good GPS accuracy, include the user's current street/area/city when location is relevant.
35. If verified_signboard_location is supplied and marked reliable, mention the mapped place/address and approximate distance. Do not claim it is the exact physical sign unless the evidence establishes that.
36. If both current_location and verified_signboard_location are supplied, make the relationship clear: first where the user is now, then where the verified sign-related place is relative to them.
37. When a VERIFIED SIGN-RELATED PLACE is supplied, do not omit it merely to make the sentence shorter. Use two short sentences if needed.
38. Never replace a verified street/address with only a city name when the more detailed address is supplied.
37. If a warning sign and a business sign are both present, mention the warning first.
REASONING PROCEDURE (do silently):
A. Identify the strongest sign category.
B. Collect every OCR fragment and number belonging to that detection.
C. Repair obvious spacing, character substitutions, and partial words.
D. Check whether fragments change the meaning of the sign, especially NOT/NO, arrows, distances, restrictions, and warnings.
E. Combine category + readable meaning + position + relevant distance/proximity.
F. If the detector label has an awkward literal translation, express its real-world meaning naturally in the requested language.
G. If current location or a verified signboard location is supplied, explain the relationship naturally and include the verified distance when available.
H. Produce the safest useful narration supported by the evidence.

EXAMPLES:
- sign=parking, visible_text=P, position=directly ahead -> "There is a parking sign directly ahead."
- sign=no parking, visible_text=P 50M -> "There is a no-parking sign directly ahead." Do not call 50M the distance from the user.
- sign=traffic, visible_text=P 50M -> "There is a parking symbol directly ahead." Do not claim no parking without evidence.
- sign=hospital, visible_text=H -> "There is a hospital sign ahead."
- sign=shop, visible_text=M E D I C A L -> "There is a medical shop sign ahead."
- sign=shop, visible_text=PHARNACY -> "There is a pharmacy sign ahead."
- sign=shop, visible_text=SHREE MEDICALS -> "There is a Shree Medicals shop sign ahead."
- sign=shop, visible_text=560001 -> "There is a shop sign ahead with PIN code 560001." Never say "five hundred sixty thousand one."
- sign=shop, visible_text=PIN 560001 -> "There is a shop sign ahead. The PIN code is 560001."
- sign=shop, visible_text=CONTACT 9876543210 -> "There is a shop sign ahead. The contact number is 9876543210."
- sign=bus, visible_text=500K -> "Bus number 500K is ahead."
- sign=shop, visible_text=SHOP 24 -> "Shop number 24 is ahead."
- sign=shop, visible_text=₹250 -> "The price is 250 rupees."
- sign=stop, visible_text=STOP -> "There is a stop sign ahead. Please be careful."
- Kannada: a stop sign should be described naturally as "ಮುಂದೆ ಸ್ಟಾಪ್ ಫಲಕ ಇದೆ. ದಯವಿಟ್ಟು ಎಚ್ಚರಿಕೆಯಿಂದಿರಿ." Never translate "stop" into an unrelated literal phrase.
- If current location is supplied as "Jayanagar, Bengaluru" and a verified shop is 65 metres away, naturally mention that the user is near Jayanagar and the shop sign is about 65 metres away.
- uncertain OCR such as XQ7 -> do not invent a word; describe the detected sign category and position.
''',
          },
          {
            'role': 'user',
            'content': jsonEncode({
              'language': languageName,
              'location_context': place ?? '',
              'current_location': place ?? '',
              'verified_signboard_location': detections
                  .map((d) => d.placeContext)
                  .where((value) => value.isNotEmpty)
                  .toList(),
              'detections': evidence,
            }),
          },
        ],
      };

      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(
        const Duration(seconds: 18),
      );

      final body = await utf8.decoder.bind(response).join();
      _debug('HTTP STATUS = ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        var detail = body.replaceAll(RegExp(r'[Groq]s+'), ' ').trim();
        if (detail.length > 500) {
          detail = detail.substring(0, 500);
        }
        if (detail.isNotEmpty) {
          _debug('ERROR BODY -> $detail');
        }
        _debug('REQUEST FAILED -> HTTP ${response.statusCode} -> local fallback');
        return null;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final usage = decoded['usage'];
      if (usage is Map<String, dynamic>) {
        _debug('TOKEN USAGE -> prompt=${usage['prompt_tokens']}, completion=${usage['completion_tokens']}, total=${usage['total_tokens']}');
      } else {
        _debug('TOKEN USAGE -> not returned by Groq API');
      }
      _debug('ROUTER RESPONSE -> model=${decoded['model'] ?? 'unknown'}, requestId=${decoded['id'] ?? 'unknown'}');

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

      _debug('RESPONSE CONTENT RECEIVED -> ${content.length} characters');
      _debug('GROQ RESULT -> $content');
      return content;
    } catch (e) {
      _debug('REQUEST EXCEPTION -> $e');
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
      final selected = _selectFallbackDetections(detections);
      final parts = selected.map(_hindiItem).join('। ');

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
      final selected = _selectFallbackDetections(detections);
      final parts = selected.map(_kannadaItem).join('. ');

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

    final selected = _selectFallbackDetections(detections);
    final parts = selected.map(_englishItem).join('. ');

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


  List<SpeechDetectionInput> _selectFallbackDetections(
    List<SpeechDetectionInput> detections,
  ) {
    final sorted = [...detections]
      ..sort((a, b) {
        if (a.safety != b.safety) return a.safety ? -1 : 1;
        return b.text.trim().length.compareTo(a.text.trim().length);
      });
    return sorted.take(2).toList();
  }

  String _friendlyLabel(String label, String languageCode) {
    final value = label.toLowerCase().replaceAll('_', ' ').trim();
    if (languageCode == 'kn') {
      if (value.contains('no parking')) return 'ನೋ ಪಾರ್ಕಿಂಗ್ ಫಲಕ';
      if (value.contains('parking')) return 'ಪಾರ್ಕಿಂಗ್ ಫಲಕ';
      if (value.contains('hospital')) return 'ಆಸ್ಪತ್ರೆಯ ಫಲಕ';
      if (value.contains('stop')) return 'ಸ್ಟಾಪ್ ಫಲಕ';
      if (value.contains('warning')) return 'ಎಚ್ಚರಿಕೆ ಫಲಕ';
      if (value.contains('shop')) return 'ಅಂಗಡಿಯ ಫಲಕ';
    }
    if (languageCode == 'hi') {
      if (value.contains('no parking')) return 'नो पार्किंग का संकेत';
      if (value.contains('parking')) return 'पार्किंग का संकेत';
      if (value.contains('hospital')) return 'अस्पताल का संकेत';
      if (value.contains('stop')) return 'स्टॉप का संकेत';
      if (value.contains('warning')) return 'चेतावनी का संकेत';
      if (value.contains('shop')) return 'दुकान का संकेत';
    }
    if (value.contains('no parking')) return 'no-parking sign';
    if (value.contains('parking')) return 'parking sign';
    if (value.contains('hospital')) return 'hospital sign';
    if (value.contains('stop')) return 'stop sign';
    if (value.contains('warning')) return 'warning sign';
    if (value.contains('shop')) return 'shop sign';
    return 'sign';
  }

  String _englishItem(
    SpeechDetectionInput e,
  ) {
    var result =
        '${_friendlyLabel(e.label, 'en')} ${e.position}';

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
        '${_friendlyLabel(e.label, 'hi')} ${_hindiPosition(e.position)}';

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
        '${_friendlyLabel(e.label, 'kn')} ${_kannadaPosition(e.position)}';

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

  bool _matchesRequestedLanguage(String text, String languageCode) {
    if (text.trim().isEmpty) return false;
    if (languageCode == 'kn') return RegExp(r'[\u0C80-\u0CFF]').hasMatch(text);
    if (languageCode == 'hi') return RegExp(r'[\u0900-\u097F]').hasMatch(text);
    return true;
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