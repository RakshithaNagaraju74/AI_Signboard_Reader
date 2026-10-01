import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SpeechDetectionInput {
  final String label;
  final String position;
  final String text;
  final String movement;
  final String proximity;
  final bool safety;

  const SpeechDetectionInput({
    required this.label,
    required this.position,
    this.text = '',
    this.movement = '',
    this.proximity = '',
    this.safety = false,
  });

  Map<String, dynamic> toJson() => {
    'sign': label,
    'position': position,
    if (text.isNotEmpty) 'visible_text': text,
    if (movement.isNotEmpty) 'movement': movement,
    if (proximity.isNotEmpty) 'proximity': proximity,
    'safety': safety,
  };
}

class AISpeechService {
  static const String _endpoint = String.fromEnvironment(
    'GROQ_BASE_URL',
    defaultValue: 'https://api.groq.com/openai/v1',
  );
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _model = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'openai/gpt-oss-20b',
  );

  bool get groqEnabled => _apiKey.trim().isNotEmpty;

  Future<String> compose({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
    bool useGroq = true,
  }) async {
    if (detections.isEmpty) return _fallback(detections, languageCode, place);
    if (useGroq && groqEnabled) {
      final generated = await _composeWithGroq(
        detections: detections,
        languageCode: languageCode,
        place: place,
      );
      if (generated != null && generated.trim().isNotEmpty) return _clean(generated);
    }
    return _fallback(detections, languageCode, place);
  }

  Future<String?> _composeWithGroq({
    required List<SpeechDetectionInput> detections,
    required String languageCode,
    String? place,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final base = _endpoint.endsWith('/') ? _endpoint.substring(0, _endpoint.length - 1) : _endpoint;
      final request = await client.postUrl(Uri.parse(base + '/chat/completions')).timeout(const Duration(seconds: 3));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + _apiKey);
      final languageName = languageCode == 'hi' ? 'Hindi' : (languageCode == 'kn' ? 'Kannada' : 'English');
      final payload = {
        'model': _model,
        'temperature': 0.2,
        'max_completion_tokens': 140,
        'messages': [
          {
            'role': 'system',
            'content': 'You are the voice narration layer of an accessibility app for a blind user. Turn structured sign detections into one short, natural spoken update in ' + languageName + '. Never mention class IDs, confidence scores, model names, bounding boxes, JSON, or developer terms. Never invent a sign, text, distance, direction, or location. Preserve OCR text exactly when you quote it. Mention every supplied sign once. Use only the relative visual positions supplied. If a safety sign is present, make it clear and prominent. Use simple sentences suitable for speech. Return only the narration, with no quotation marks.',
          },
          {
            'role': 'user',
            'content': jsonEncode({
              'language': languageName,
              'location_context': place ?? '',
              'detections': detections.map((e) => e.toJson()).toList(),
            }),
          },
        ],
      };
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final message = choices.first['message'] as Map<String, dynamic>?;
      return message?['content']?.toString();
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  String _fallback(List<SpeechDetectionInput> detections, String languageCode, String? place) {
    if (detections.isEmpty) {
      if (languageCode == 'hi') return 'मुझे कोई स्पष्ट संकेत नहीं मिला।';
      if (languageCode == 'kn') return 'ಯಾವುದೇ ಸ್ಪಷ್ಟ ಫಲಕ ಕಂಡುಬಂದಿಲ್ಲ.';
      return 'I cannot see a clear signboard.';
    }
    final safety = detections.any((e) => e.safety);
    final count = detections.length;
    if (languageCode == 'hi') {
      final parts = detections.map(_hindiItem).join('। ');
      final prefix = safety ? 'सावधान। ' : '';
      final placePart = place == null || place.isEmpty ? '' : ' आप अभी ' + place + ' के पास हैं।';
      return prefix + 'मुझे ' + count.toString() + ' संकेत दिखाई दे रहे हैं। ' + parts + '।' + placePart;
    }
    if (languageCode == 'kn') {
      final parts = detections.map(_kannadaItem).join('. ');
      final prefix = safety ? 'ಎಚ್ಚರಿಕೆ. ' : '';
      final placePart = place == null || place.isEmpty ? '' : ' ನೀವು ಈಗ ' + place + ' ಬಳಿ ಇದ್ದೀರಿ.';
      return prefix + 'ನನಗೆ ' + count.toString() + ' ಫಲಕಗಳು ಕಾಣುತ್ತಿವೆ. ' + parts + '.' + placePart;
    }
    final parts = detections.map(_englishItem).join('. ');
    final prefix = safety ? 'Warning. ' : '';
    final placePart = place == null || place.isEmpty ? '' : ' You are near ' + place + '.';
    return prefix + 'I can see ' + count.toString() + ' sign' + (count == 1 ? '' : 's') + '. ' + parts + '.' + placePart;
  }

  String _englishItem(SpeechDetectionInput e) {
    var result = e.label + ' ' + e.position;
    if (e.text.isNotEmpty) result += ', with the text "' + e.text + '"';
    if (e.movement.isNotEmpty) result += '. ' + _englishMovement(e.movement);
    else if (e.proximity.isNotEmpty) result += '. ' + _englishProximity(e.proximity);
    return result;
  }
  String _hindiItem(SpeechDetectionInput e) {
    var result = e.label + ' ' + _hindiPosition(e.position);
    if (e.text.isNotEmpty) result += ', जिस पर "' + e.text + '" लिखा है';
    if (e.movement.isNotEmpty) result += '। ' + _hindiMovement(e.movement);
    else if (e.proximity.isNotEmpty) result += '। ' + _hindiProximity(e.proximity);
    return result;
  }
  String _kannadaItem(SpeechDetectionInput e) {
    var result = e.label + ' ' + _kannadaPosition(e.position);
    if (e.text.isNotEmpty) result += ', ಅದರಲ್ಲಿ "' + e.text + '" ಎಂದು ಬರೆಯಲಾಗಿದೆ';
    if (e.movement.isNotEmpty) result += '. ' + _kannadaMovement(e.movement);
    else if (e.proximity.isNotEmpty) result += '. ' + _kannadaProximity(e.proximity);
    return result;
  }
  String _englishMovement(String v) => v == 'getting closer' ? 'It appears to be getting closer' : v == 'moving farther away' ? 'It appears to be getting farther away' : v == 'moving to your left' ? 'It is moving toward your left' : v == 'moving to your right' ? 'It is moving toward your right' : v;
  String _englishProximity(String v) => v == 'far' ? 'It appears far away' : v == 'approaching' ? 'It appears to be getting closer' : v == 'nearby' ? 'It is nearby' : '';
  String _hindiPosition(String v) => v == 'far left' ? 'बहुत बाईं ओर है' : v == 'slightly left' ? 'थोड़ा बाईं ओर है' : v == 'directly ahead' ? 'सीधे सामने है' : v == 'slightly right' ? 'थोड़ा दाईं ओर है' : 'बहुत दाईं ओर है';
  String _kannadaPosition(String v) => v == 'far left' ? 'ತುಂಬಾ ಎಡಭಾಗದಲ್ಲಿದೆ' : v == 'slightly left' ? 'ಸ್ವಲ್ಪ ಎಡಭಾಗದಲ್ಲಿದೆ' : v == 'directly ahead' ? 'ನೇರವಾಗಿ ಮುಂದೆ ಇದೆ' : v == 'slightly right' ? 'ಸ್ವಲ್ಪ ಬಲಭಾಗದಲ್ಲಿದೆ' : 'ತುಂಬಾ ಬಲಭಾಗದಲ್ಲಿದೆ';
  String _hindiMovement(String v) => v == 'getting closer' ? 'संकेत पास आता हुआ लग रहा है' : v == 'moving farther away' ? 'संकेत दूर जाता हुआ लग रहा है' : v == 'moving to your left' ? 'संकेत बाईं ओर जा रहा है' : v == 'moving to your right' ? 'संकेत दाईं ओर जा रहा है' : v;
  String _kannadaMovement(String v) => v == 'getting closer' ? 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ' : v == 'moving farther away' ? 'ಸಂಕೇತ ದೂರವಾಗುತ್ತಿದೆ' : v == 'moving to your left' ? 'ಸಂಕೇತ ಎಡಕ್ಕೆ ಸರಿಯುತ್ತಿದೆ' : v == 'moving to your right' ? 'ಸಂಕೇತ ಬಲಕ್ಕೆ ಸರಿಯುತ್ತಿದೆ' : v;
  String _hindiProximity(String v) => v == 'far' ? 'संकेत दूर है' : v == 'approaching' ? 'संकेत पास आ रहा है' : v == 'nearby' ? 'संकेत पास है' : '';
  String _kannadaProximity(String v) => v == 'far' ? 'ಸಂಕೇತ ದೂರದಲ್ಲಿದೆ' : v == 'approaching' ? 'ಸಂಕೇತ ಹತ್ತಿರವಾಗುತ್ತಿದೆ' : v == 'nearby' ? 'ಸಂಕೇತ ಹತ್ತಿರದಲ್ಲಿದೆ' : '';
  String _clean(String value) => value.replaceAll(RegExp(r'^(assistant|response):\\s*', caseSensitive: false), '').replaceAll(RegExp(r'^["\']|["\']$'), '').trim();
}