import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'api_service.dart';
import 'voice_service.dart';

/// The phases of a live voice conversation with Jarvis.
enum LiveConversationState {
  idle,
  greeting,
  waitingForTap,
  listening,
  thinking,
  speaking,
  ended,
}

/// How the user talks to Jarvis.
/// - [pushToTalk]: the mic only opens when the user taps. No echo. Reliable on
///   laptops with open speakers. Default.
/// - [handsFree]: continuous loop; Jarvis listens again automatically after
///   speaking. Best with headphones / on phone (built-in echo cancellation).
enum LiveMode { pushToTalk, handsFree }

/// A single turn in the live conversation transcript.
class ConversationTurn {
  final String text;
  final bool isUser;

  const ConversationTurn({required this.text, required this.isUser});
}

/// Orchestrates a continuous, phone-call-like voice conversation:
/// Jarvis greets the user, then they talk back and forth hands-free until
/// [stop] is called.
///
/// Speech recognition is done on-device via `speech_to_text` (German, de_DE),
/// which is fast enough for live back-and-forth. The backend [ApiService]
/// is only used for the chat replies and the opening greeting. Speaking is
/// delegated to the shared [VoiceService] (flutter_tts, de-DE).
class LiveConversationService extends ChangeNotifier {
  final ApiService _apiService;
  final VoiceService _voiceService;

  final stt.SpeechToText _speech = stt.SpeechToText();

  static const String _localeId = 'de_DE';
  static const String _fallbackGreeting =
      'Hallo! Schön dich zu sehen. Was kann ich für dich tun?';

  LiveConversationState _state = LiveConversationState.idle;
  LiveMode _mode = LiveMode.pushToTalk;
  final List<ConversationTurn> _transcript = [];
  String _partialText = '';
  bool _speechAvailable = false;
  bool _stopped = false;
  String? _lastError;

  // Guards so a stop() mid-flight doesn't get overwritten by a late callback.
  bool _resultHandled = false;

  LiveConversationService(this._apiService, this._voiceService);

  LiveConversationState get state => _state;
  LiveMode get mode => _mode;
  List<ConversationTurn> get transcript => List.unmodifiable(_transcript);
  String get partialText => _partialText;
  String? get lastError => _lastError;

  /// Switch between push-to-talk and hands-free. Safe to call any time.
  void setMode(LiveMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
    // If we switch to hands-free while waiting for a tap, start listening.
    if (m == LiveMode.handsFree &&
        _state == LiveConversationState.waitingForTap &&
        !_stopped) {
      _listenLoop();
    }
  }

  bool get isActive =>
      _state != LiveConversationState.idle &&
      _state != LiveConversationState.ended;

  void _setState(LiveConversationState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  void _addTurn(String text, {required bool isUser}) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _transcript.add(ConversationTurn(text: clean, isUser: isUser));
    notifyListeners();
  }

  /// Starts the conversation: greets the user by voice, then begins the
  /// continuous listen/respond loop.
  Future<void> start() async {
    if (isActive) return;
    _stopped = false;
    _lastError = null;
    _partialText = '';
    _transcript.clear();

    // Request microphone permission + initialize STT.
    try {
      _speechAvailable = await _speech.initialize(
        onError: (err) {
          debugPrint('STT error: ${err.errorMsg}');
        },
        onStatus: (status) {
          debugPrint('STT status: $status');
        },
      );
    } catch (e) {
      debugPrint('STT initialize error: $e');
      _speechAvailable = false;
    }

    if (_stopped) return;

    // Greeting phase.
    _setState(LiveConversationState.greeting);
    String greeting = _fallbackGreeting;
    try {
      final opening = await _apiService.getOpening();
      if (opening != null && opening.trim().isNotEmpty) {
        greeting = opening.trim();
      }
    } catch (e) {
      debugPrint('getOpening error: $e');
    }

    if (_stopped) return;

    _addTurn(greeting, isUser: false);
    await _voiceService.speakAndWait(greeting);

    if (_stopped) return;

    if (!_speechAvailable) {
      // Without recognition we can't continue the loop.
      _lastError =
          'Spracherkennung nicht verfügbar. Bitte Mikrofon erlauben.';
      _setState(LiveConversationState.ended);
      return;
    }

    _afterTurn();
  }

  /// Decide what happens after Jarvis finishes speaking (or after silence):
  /// push-to-talk waits for the user to tap; hands-free listens again.
  void _afterTurn() {
    if (_stopped) return;
    if (_mode == LiveMode.handsFree) {
      _listenLoop();
    } else {
      _partialText = '';
      _setState(LiveConversationState.waitingForTap);
    }
  }

  /// Called from the UI when the user taps the mic in push-to-talk mode.
  /// Opens the mic for a single phrase.
  Future<void> startListeningOnce() async {
    if (_stopped) return;
    if (!_speechAvailable) return;
    if (_state == LiveConversationState.listening ||
        _state == LiveConversationState.thinking ||
        _state == LiveConversationState.speaking ||
        _state == LiveConversationState.greeting) {
      return;
    }
    await _listenLoop();
  }

  /// Begins (or resumes) listening for the user's next phrase.
  Future<void> _listenLoop() async {
    if (_stopped) return;

    _partialText = '';
    _resultHandled = false;
    _setState(LiveConversationState.listening);

    try {
      await _speech.listen(
        localeId: _localeId,
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('STT listen error: $e');
      // Retry listening after a short delay if not stopped.
      if (!_stopped) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!_stopped) await _listenLoop();
      }
    }
  }

  Future<void> _onSpeechResult(SpeechRecognitionResult result) async {
    if (_stopped) return;
    if (_state != LiveConversationState.listening) return;

    _partialText = result.recognizedWords;
    notifyListeners();

    if (!result.finalResult) return;
    if (_resultHandled) return;
    _resultHandled = true;

    final phrase = result.recognizedWords.trim();

    // Stop listening regardless; we either process or resume.
    try {
      await _speech.stop();
    } catch (_) {}

    if (_stopped) return;

    if (phrase.isEmpty) {
      // Silence / timeout — in hands-free, listen again; in push-to-talk,
      // wait for the user to tap again (mic stays closed → no echo).
      _afterTurn();
      return;
    }

    await _handleUserPhrase(phrase);
  }

  Future<void> _handleUserPhrase(String phrase) async {
    _partialText = '';

    // Build conversation history from prior turns (BEFORE adding the current
    // user phrase) so the backend remembers the context. Keep the last 12.
    final priorHistory = _transcript
        .map((t) => {
              'role': t.isUser ? 'user' : 'assistant',
              'content': t.text,
            })
        .toList();
    final trimmedHistory = priorHistory.length > 12
        ? priorHistory.sublist(priorHistory.length - 12)
        : priorHistory;

    _addTurn(phrase, isUser: true);
    _setState(LiveConversationState.thinking);

    String replyText;
    try {
      final response =
          await _apiService.chat(phrase, history: trimmedHistory);
      replyText = response['response']?.toString() ??
          response['message']?.toString() ??
          response['text']?.toString() ??
          'Ich habe dich verstanden.';
    } catch (e) {
      debugPrint('Live chat error: $e');
      replyText =
          'Entschuldige, da ist etwas schiefgelaufen. Versuch es nochmal.';
    }

    if (_stopped) return;

    _addTurn(replyText, isUser: false);
    _setState(LiveConversationState.speaking);

    // Speak the reply. Even if speaking throws, the loop must continue to
    // listening (speakAndWait already has a safety timeout so it can't hang).
    try {
      await _voiceService.speakAndWait(replyText);
    } catch (e) {
      debugPrint('Live speak error: $e');
    }

    if (_stopped) return;

    // Small delay to let the speaker audio fully settle before the mic could
    // reopen (extra protection against the mic hearing Jarvis = echo).
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (_stopped) return;

    // Continue: hands-free listens again automatically; push-to-talk waits.
    _afterTurn();
  }

  /// Ends the conversation: stops listening and any ongoing speech.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _setState(LiveConversationState.ended);

    try {
      _speech.stop();
    } catch (_) {}
    try {
      _speech.cancel();
    } catch (_) {}
    try {
      _voiceService.stopSpeaking();
    } catch (_) {}
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
