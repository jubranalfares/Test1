import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService;
  final VoiceService _voiceService;

  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _morningBriefing;
  bool _briefingLoaded = false;
  bool _openingLoaded = false;

  ChatProvider(this._apiService, this._voiceService);

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get morningBriefing => _morningBriefing;
  bool get briefingLoaded => _briefingLoaded;

  /// Proactively greets the user with voice when the chat opens.
  /// Only runs once per session and only if there are no messages yet.
  Future<void> loadOpening() async {
    if (_openingLoaded) return;
    _openingLoaded = true;

    if (_messages.isNotEmpty) return;

    final message = await _apiService.getOpening();
    if (message == null || message.trim().isEmpty) return;

    // Still guard against a race where a message arrived meanwhile.
    if (_messages.isNotEmpty) return;

    final jarvisMessage = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}_opening',
      content: message.trim(),
      isUser: false,
      timestamp: DateTime.now(),
    );

    _messages.add(jarvisMessage);
    notifyListeners();

    // Speak the proactive greeting aloud (respects the mute toggle).
    if (_voiceService.ttsEnabled) {
      await _voiceService.speakText(jarvisMessage.content);
    }
  }

  Future<void> loadMorningBriefing() async {
    if (_briefingLoaded) return;
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour <= 11) {
      try {
        _morningBriefing = await _apiService.getMorningBriefing();
        _briefingLoaded = true;
        notifyListeners();
      } catch (_) {
        _briefingLoaded = true;
      }
    } else {
      _briefingLoaded = true;
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Build conversation history from prior messages (before adding the new
    // user message) so Jarvis remembers the context. Keep the last 12 turns.
    final history = _messages
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();
    final trimmedHistory =
        history.length > 12 ? history.sublist(history.length - 12) : history;

    final userMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    _messages.add(userMessage);
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response =
          await _apiService.chat(text.trim(), history: trimmedHistory);
      final replyText = response['response']?.toString() ??
          response['message']?.toString() ??
          response['text']?.toString() ??
          'Ich habe deine Nachricht erhalten.';

      final jarvisMessage = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}_j',
        content: replyText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      _messages.add(jarvisMessage);
      _isLoading = false;
      notifyListeners();

      // Speak Jarvis's response aloud (respects the mute toggle).
      if (_voiceService.ttsEnabled) {
        await _voiceService.speakText(jarvisMessage.content);
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendVoiceMessage() async {
    final isCurrentlyRecording = _voiceService.isRecording;

    if (isCurrentlyRecording) {
      _isLoading = true;
      notifyListeners();

      final transcript = await _voiceService.stopRecordingAndTranscribe();
      if (transcript != null && transcript.isNotEmpty) {
        // sendMessage already speaks the Jarvis reply (if TTS enabled).
        await sendMessage(transcript);
      } else {
        _isLoading = false;
        notifyListeners();
      }
    } else {
      await _voiceService.startRecording();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void addLocalMessage(String content, {bool isUser = false}) {
    _messages.add(Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }
}
