import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService extends ChangeNotifier {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _baseUrlKey = 'server_base_url';
  static const _tokenKey = 'auth_token';

  String _baseUrl = '';
  String _token = '';

  String get baseUrl => _baseUrl;
  bool get hasToken => _token.isNotEmpty;
  bool get isConfigured => _baseUrl.isNotEmpty;

  // Default gateway URL (user-editable). Port 8080 because 8000 is taken.
  static const _defaultBaseUrl = 'http://localhost:8080';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    try {
      _token = await _storage.read(key: _tokenKey) ?? '';
    } catch (e) {
      debugPrint('SecureStorage read error (non-fatal): $e');
      _token = prefs.getString(_tokenKey) ?? '';
    }
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl);
    notifyListeners();
  }

  Future<void> _storeToken(String token) async {
    _token = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('SecureStorage write error (non-fatal): $e');
      // Fallback: store in SharedPreferences (less secure but functional on web)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> clearToken() async {
    _token = '';
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('SecureStorage delete error (non-fatal): $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (_) {}
    notifyListeners();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  // --- Auth ---
  Future<bool> login(String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token']?.toString() ?? data['access_token']?.toString() ?? '';
        if (token.isNotEmpty) {
          await _storeToken(token);
          return true;
        }
        // Accept success response even without token
        if (data['success'] == true || data['status'] == 'ok') {
          await _storeToken('authenticated');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  // --- Chat ---
  Future<Map<String, dynamic>> chat(
    String message, {
    List<Map<String, String>>? history,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chat'),
            headers: _headers,
            body: jsonEncode({
              'message': message,
              'history': history ?? [],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiException('Chat failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Chat error: $e');
      rethrow;
    }
  }

  // --- Voice ---
  Future<String?> transcribeAudio(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/voice/stt'),
      );
      if (_token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      request.files.add(await http.MultipartFile.fromPath('audio', filePath));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['text']?.toString() ?? data['transcript']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Transcribe error: $e');
      return null;
    }
  }

  /// Fetches the backend's natural neural voice for [text].
  /// POSTs to `/voice/tts` with the auth header. Returns the MP3 bytes when
  /// the backend responds 200 with an `audio/*` content type; otherwise
  /// (JSON fallback body, error, offline) returns null so the caller can
  /// fall back to on-device TTS.
  Future<Uint8List?> fetchTts(String text, {double speed = 1.0}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/voice/tts'),
            headers: _headers,
            body: jsonEncode({'text': text, 'speed': speed}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('audio')) {
          return response.bodyBytes;
        }
      }
      return null;
    } catch (e) {
      debugPrint('fetchTts error: $e');
      return null;
    }
  }

  Future<Uint8List?> textToSpeech(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/voice/tts'),
            headers: _headers,
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('audio')) {
          return response.bodyBytes;
        }
        // Try JSON response with base64 encoded audio
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final audioBase64 = data['audio']?.toString() ?? data['data']?.toString();
          if (audioBase64 != null) {
            return base64Decode(audioBase64);
          }
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('TTS error: $e');
      return null;
    }
  }

  // --- Notes ---
  Future<List<Map<String, dynamic>>> getNotes({String? query, String? tag}) async {
    try {
      final params = <String, String>{};
      if (query != null && query.isNotEmpty) params['query'] = query;
      if (tag != null && tag.isNotEmpty) params['tag'] = tag;

      final uri = Uri.parse('$_baseUrl/notes').replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data.cast<Map<String, dynamic>>();
        if (data is Map && data['notes'] != null) {
          return (data['notes'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get notes error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createNote(Map<String, dynamic> note) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/notes'),
            headers: _headers,
            body: jsonEncode(note),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiException('Create note failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Create note error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateNote(String id, Map<String, dynamic> note) async {
    try {
      final response = await http
          .put(
            Uri.parse('$_baseUrl/notes/$id'),
            headers: _headers,
            body: jsonEncode(note),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiException('Update note failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Update note error: $e');
      rethrow;
    }
  }

  Future<void> deleteNote(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$_baseUrl/notes/$id'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw ApiException('Delete note failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Delete note error: $e');
      rethrow;
    }
  }

  // --- Memory ---
  Future<Map<String, dynamic>> getMemoryFacts() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/memory/facts'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      debugPrint('Memory facts error: $e');
      return {};
    }
  }

  // --- Opening (proactive greeting) ---
  Future<String?> getOpening() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/memory/opening'), headers: _headers)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['message']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('Opening error: $e');
      return null;
    }
  }

  // --- Briefing ---
  Future<Map<String, dynamic>> getMorningBriefing() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/briefing/morning'), headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      debugPrint('Morning briefing error: $e');
      return {};
    }
  }

  // --- Health ---
  Future<Map<String, dynamic>> getHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error'};
    } catch (e) {
      return {'status': 'offline', 'error': e.toString()};
    }
  }

  // --- Behavior ---
  Future<void> addBehaviorRule(String trigger, String action, String description) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/behavior/rules'),
            headers: _headers,
            body: jsonEncode({
              'trigger': trigger,
              'action': action,
              'description': description,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Add behavior rule error: $e');
    }
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
