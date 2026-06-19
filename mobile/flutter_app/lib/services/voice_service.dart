import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class VoiceService extends ChangeNotifier {
  final ApiService _apiService;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  static const _ttsEnabledKey = 'tts_enabled';

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isProcessing = false;
  bool _ttsEnabled = true;
  bool _ttsConfigured = false;
  String? _currentRecordingPath;

  VoiceService(this._apiService) {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _initTts();
    _loadTtsPreference();
  }

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isProcessing => _isProcessing;
  bool get ttsEnabled => _ttsEnabled;

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('de-DE');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);
      _flutterTts.setStartHandler(() {
        _isPlaying = true;
        notifyListeners();
      });
      _flutterTts.setCompletionHandler(() {
        _isPlaying = false;
        notifyListeners();
      });
      _flutterTts.setCancelHandler(() {
        _isPlaying = false;
        notifyListeners();
      });
      _ttsConfigured = true;
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  Future<void> _loadTtsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ttsEnabled = prefs.getBool(_ttsEnabledKey) ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('Load TTS preference error: $e');
    }
  }

  Future<void> setTtsEnabled(bool enabled) async {
    _ttsEnabled = enabled;
    notifyListeners();
    if (!enabled) {
      await stopSpeaking();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ttsEnabledKey, enabled);
    } catch (e) {
      debugPrint('Save TTS preference error: $e');
    }
  }

  Future<void> toggleTts() => setTtsEnabled(!_ttsEnabled);

  Future<bool> requestPermissions() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.microphone.request();
      return status == PermissionStatus.granted;
    }
    return true;
  }

  Future<bool> startRecording() async {
    try {
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        debugPrint('Microphone permission denied');
        return false;
      }

      final dir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${dir.path}/jarvis_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Start recording error: $e');
      _isRecording = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> stopRecordingAndTranscribe() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      _isProcessing = true;
      notifyListeners();

      if (path == null || path.isEmpty) {
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      final transcript = await _apiService.transcribeAudio(path);

      // Clean up temp file
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      _isProcessing = false;
      notifyListeners();
      return transcript;
    } catch (e) {
      debugPrint('Stop recording error: $e');
      _isRecording = false;
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.cancel();
    } catch (_) {}
    _isRecording = false;
    _isProcessing = false;
    notifyListeners();
  }

  /// Speaks [text] aloud using the on-device German TTS engine.
  /// Stops any current speech first. Does nothing if TTS is muted.
  Future<void> speakText(String text) async {
    if (!_ttsEnabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    try {
      if (!_ttsConfigured) {
        await _initTts();
      }
      // Stop anything currently playing/speaking
      await stopSpeaking();
      await _flutterTts.setLanguage('de-DE');
      await _flutterTts.speak(clean);
    } catch (e) {
      debugPrint('speakText error: $e');
    }
  }

  /// Primary speak path for Jarvis text — uses on-device TTS (reliable
  /// across web, iOS and Android) instead of the unreliable backend TTS.
  Future<void> speak(String text) => speakText(text);

  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('Stop TTS error: $e');
    }
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Stop player error: $e');
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
      await _player.dispose();
      await _flutterTts.stop();
    } catch (_) {}
  }
}
