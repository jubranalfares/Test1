import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'api_service.dart';
import 'voice_service.dart';

/// The phases of a live, hands-free voice conversation with Jarvis.
enum LiveConversationState {
  idle,
  greeting,
  listening,
  thinking,
  speaking,
  ended,
}

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
  final List<ConversationTurn> _transcript = [];
  String _partialText = '';
  bool _speechAvailable = false;
  bool _stopped = false;
  String? _lastError;

  // Guards so a stop() mid-flight doesn't get overwritten by a late callback.
  bool _resultHandled = false;

  LiveConversationService(this._apiService, this._voiceService);

  LiveConversationState get state => _state;
  List<ConversationTurn> get transcript => List.unmodifiable(_transcript);
  String get partialText => _partialText;
  String? get lastError => _lastError;

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
      // Silence / timeout — just listen again.
      if (!_stopped) await _listenLoop();
      return;
    }

    await _handleUserPhrase(phrase);
  }

  Future<void> _handleUserPhrase(String phrase) async {
    _partialText = '';
    _addTurn(phrase, isUser: true);
    _setState(LiveConversationState.thinking);

    String replyText;
    try {
      final response = await _apiService.chat(phrase);
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
    await _voiceService.speakAndWait(replyText);

    if (_stopped) return;

    // Continue the conversation: listen again.
    await _listenLoop();
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
