import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'web_speech_stub.dart' if (dart.library.html) 'web_speech_html.dart';

class VoiceService extends ChangeNotifier {
  final ApiService _apiService;
  final AudioRecorder _recorder = AudioRecorder();
  // Keep player around in case we want to play non-TTS audio in future.
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

      // On native iOS/Android, try to pick a high-quality German voice.
      // iOS ships "Helena" (enhanced) and "Anna" as German neural voices.
      if (!kIsWeb) {
        try {
          final voices = await _flutterTts.getVoices;
          if (voices is List) {
            const preferred = ['Helena', 'Anna', 'Petra', 'Yannick'];
            for (final name in preferred) {
              final match = voices.firstWhere(
                (v) =>
                    v is Map &&
                    (v['name'] as String?)
                            ?.toLowerCase()
                            .contains(name.toLowerCase()) ==
                        true,
                orElse: () => null,
              );
              if (match != null) {
                await _flutterTts.setVoice({
                  'name': match['name'] as String,
                  'locale': 'de-DE',
                });
                debugPrint('TTS voice: ${match['name']}');
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('TTS voice selection skipped: $e');
        }
      }

      // speak() futures resolve when the utterance ends — needed by the
      // live conversation loop so it can start listening again right after.
      try {
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}

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

  /// Computes a safety timeout so a speak call can never hang forever:
  /// at least 4s, growing with the length of the text.
  Duration _speakSafetyTimeout(String text) {
    final ms = (text.length * 90).clamp(4000, 600000);
    final floor = const Duration(seconds: 4).inMilliseconds;
    return Duration(milliseconds: ms < floor ? floor : ms);
  }

  /// Tries to play the backend's natural neural voice for [clean].
  /// Returns true if playback was started (and, when [awaitCompletion],
  /// finished/timed out); false if the backend returned no audio so the
  /// caller should fall back to flutter_tts.
  Future<bool> _playBackendTts(String clean, {required bool awaitCompletion}) async {
    Uint8List? bytes;
    try {
      bytes = await _apiService.fetchTts(clean);
    } catch (e) {
      debugPrint('fetchTts error: $e');
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) return false;

    try {
      if (awaitCompletion) {
        final completer = Completer<void>();
        late final StreamSubscription<void> sub;
        sub = _player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        try {
          await _player.play(BytesSource(bytes));
          // Wait for actual completion or a safety timeout so the live
          // conversation loop can never stall.
          await completer.future.timeout(
            _speakSafetyTimeout(clean),
            onTimeout: () {},
          );
        } finally {
          await sub.cancel();
        }
      } else {
        await _player.play(BytesSource(bytes));
      }
      return true;
    } catch (e) {
      debugPrint('Backend TTS playback error: $e');
      // Playback failed even though we had bytes — fall back to flutter_tts.
      return false;
    }
  }

  /// Speaks [text] aloud.
  /// On web: tries backend MP3 audio via <audio> element first (most iOS-compatible),
  /// then falls back to browser speechSynthesis.
  /// On native: uses flutter_tts.
  Future<void> speakText(String text) async {
    if (!_ttsEnabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    try {
      await stopSpeaking();
      if (kIsWeb) {
        final bytes = await _apiService.fetchTts(clean);
        if (bytes != null && bytes.isNotEmpty) {
          await webPlayAudioBytes(bytes, awaitCompletion: false);
        } else {
          await webSpeak(clean, awaitCompletion: false);
        }
        return;
      }
      if (!_ttsConfigured) await _initTts();
      await _flutterTts.setLanguage('de-DE');
      await _flutterTts.speak(clean);
    } catch (e) {
      debugPrint('speakText error: $e');
    }
  }

  /// Primary speak path for Jarvis replies.
  Future<void> speak(String text) => speakText(text);

  /// Speaks [text] and waits until playback finishes (or a safety timeout
  /// fires). The live conversation loop calls this so it can start listening
  /// again the moment Jarvis stops talking. Silent when TTS is muted.
  Future<void> speakAndWait(String text) async {
    if (!_ttsEnabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    try {
      await stopSpeaking();

      if (kIsWeb) {
        final bytes = await _apiService.fetchTts(clean);
        if (bytes != null && bytes.isNotEmpty) {
          await webPlayAudioBytes(bytes, awaitCompletion: true);
        } else {
          await webSpeak(clean, awaitCompletion: true);
        }
        return;
      }
      if (!_ttsConfigured) await _initTts();
      await _flutterTts.setLanguage('de-DE');
      // awaitSpeakCompletion(true) makes speak() resolve when done.
      // The safety timeout prevents a stall if the completion never fires.
      await _flutterTts.speak(clean).timeout(
            _speakSafetyTimeout(clean),
            onTimeout: () {},
          );
    } catch (e) {
      debugPrint('speakAndWait error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    if (kIsWeb) {
      webSpeechCancel();
    } else {
      try {
        await _flutterTts.stop();
      } catch (e) {
        debugPrint('Stop TTS error: $e');
      }
    }
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Stop player error: $e');
    }
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
      await _player.dispose();
      await _flutterTts.stop();
    } catch (_) {}
    super.dispose();
  }
}
