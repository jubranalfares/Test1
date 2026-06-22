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
      // A touch faster than the default for a livelier, less sleepy delivery.
      await _flutterTts.setSpeechRate(0.58);
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

  // Bumped whenever speech (re)starts or is stopped, so an in-flight sentence
  // pipeline can detect it has been superseded/cancelled and bail out.
  int _speakGen = 0;

  /// Splits [text] into sentence-sized chunks so Jarvis can start talking
  /// after the FIRST sentence's audio is ready, instead of waiting for the
  /// whole reply. Long sentences are further chunked so no single request is
  /// huge. This is what makes speech start almost immediately.
  List<String> _splitSentences(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return const [];
    final out = <String>[];
    for (final m in RegExp(r'[^.!?…]+[.!?…]*').allMatches(cleaned)) {
      final s = m.group(0)?.trim() ?? '';
      if (s.isEmpty) continue;
      if (s.length <= 180) {
        out.add(s);
      } else {
        out.addAll(_chunkLong(s, 180));
      }
    }
    return out.isEmpty ? [cleaned] : out;
  }

  Iterable<String> _chunkLong(String s, int max) sync* {
    final words = s.split(' ');
    final buf = StringBuffer();
    for (final w in words) {
      if (buf.length + w.length + 1 > max && buf.isNotEmpty) {
        yield buf.toString().trim();
        buf.clear();
      }
      buf.write('$w ');
    }
    if (buf.isNotEmpty) yield buf.toString().trim();
  }

  /// Web (Safari) path: fetch each sentence's neural audio from the backend
  /// and play them in order, PREFETCHING the next sentence while the current
  /// one plays so there's no gap. Bails out if [gen] is superseded.
  Future<void> _speakSentencesWeb(String text, int gen, double speed) async {
    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return;

    // Kick off the first sentence's audio immediately.
    Future<Uint8List?> pending =
        _apiService.fetchTts(sentences.first, speed: speed);

    for (int i = 0; i < sentences.length; i++) {
      if (gen != _speakGen) return;
      Uint8List? bytes;
      try {
        bytes = await pending;
      } catch (_) {
        bytes = null;
      }

      // Start fetching the next sentence while this one plays (no gap).
      if (i + 1 < sentences.length) {
        pending = _apiService.fetchTts(sentences[i + 1], speed: speed);
      }

      if (gen != _speakGen) return;

      if (bytes != null && bytes.isNotEmpty) {
        await _playBytesAwait(bytes, sentences[i], gen);
      } else {
        // Backend gave no audio for this sentence — fall back to flutter_tts.
        if (!_ttsConfigured) await _initTts();
        await _flutterTts.setLanguage('de-DE');
        await _flutterTts.speak(sentences[i]).timeout(
              _speakSafetyTimeout(sentences[i]),
              onTimeout: () {},
            );
      }
    }
  }

  /// Plays raw audio [bytes] and resolves when playback finishes (or a safety
  /// timeout fires), unless superseded.
  Future<void> _playBytesAwait(Uint8List bytes, String forTiming, int gen) async {
    final completer = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _player.play(BytesSource(bytes));
      await completer.future.timeout(
        _speakSafetyTimeout(forTiming),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('play bytes error: $e');
    } finally {
      await sub.cancel();
    }
  }

  /// Native (iOS/Android) path: speak sentence by sentence with the on-device
  /// voice. flutter_tts already starts quickly, so this mainly keeps behaviour
  /// consistent and cancellable.
  Future<void> _speakSentencesNative(String text, int gen) async {
    final sentences = _splitSentences(text);
    if (!_ttsConfigured) await _initTts();
    await _flutterTts.setLanguage('de-DE');
    for (final s in sentences) {
      if (gen != _speakGen) return;
      await _flutterTts.speak(s).timeout(
            _speakSafetyTimeout(s),
            onTimeout: () {},
          );
    }
  }

  /// Speaks [text] aloud, starting as soon as the first sentence is ready.
  /// Fire-and-forget: the chat screen doesn't need to await the whole reply.
  /// Silent when TTS is muted.
  Future<void> speakText(String text) async {
    if (!_ttsEnabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    await stopSpeaking();
    final gen = _speakGen;
    // Intentionally not awaited: let it stream in the background.
    if (kIsWeb) {
      _speakSentencesWeb(clean, gen, 1.0);
    } else {
      _speakSentencesNative(clean, gen);
    }
  }

  /// Primary speak path for Jarvis replies.
  Future<void> speak(String text) => speakText(text);

  /// Speaks [text] and only completes once the whole reply has finished
  /// playing (or been superseded). The live conversation loop uses this so it
  /// can start listening again right after Jarvis stops talking. Still starts
  /// talking after the first sentence. Silent when TTS is muted.
  Future<void> speakAndWait(String text) async {
    if (!_ttsEnabled) return;
    final clean = text.trim();
    if (clean.isEmpty) return;

    await stopSpeaking();
    final gen = _speakGen;
    try {
      if (kIsWeb) {
        await _speakSentencesWeb(clean, gen, 1.0);
      } else {
        await _speakSentencesNative(clean, gen);
      }
    } catch (e) {
      debugPrint('speakAndWait error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    // Supersede any in-flight sentence pipeline so it stops queuing audio.
    _speakGen++;
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
