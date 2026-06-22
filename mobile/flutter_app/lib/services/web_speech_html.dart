// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

// The currently-playing audio element + its object URL, so a new utterance
// (or a stop/barge-in) can tear down the previous one. This prevents two
// clips overlapping (which sounds like garbled/echoed speech).
html.AudioElement? _currentAudio;
String? _currentUrl;

void _disposeCurrent() {
  try {
    _currentAudio?.pause();
  } catch (_) {}
  try {
    if (_currentUrl != null) html.Url.revokeObjectUrl(_currentUrl!);
  } catch (_) {}
  try {
    _currentAudio?.remove();
  } catch (_) {}
  _currentAudio = null;
  _currentUrl = null;
}

/// Plays raw MP3 bytes via a native <audio> element.
/// This is the most iOS Safari-compatible audio method. Any previously
/// playing clip is stopped first so clips never overlap.
Future<bool> webPlayAudioBytes(Uint8List bytes,
    {bool awaitCompletion = false}) async {
  try {
    _disposeCurrent();

    final blob = html.Blob([bytes], 'audio/mpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final audio = html.AudioElement()..src = url;
    html.document.body?.append(audio);
    _currentAudio = audio;
    _currentUrl = url;

    if (awaitCompletion) {
      final completer = Completer<void>();
      audio.onEnded.listen((_) {
        if (!completer.isCompleted) completer.complete();
        if (identical(_currentAudio, audio)) _disposeCurrent();
      });
      audio.onError.listen((_) {
        if (!completer.isCompleted) completer.complete();
        if (identical(_currentAudio, audio)) _disposeCurrent();
      });
      await audio.play().catchError((_) {});
      await completer.future.timeout(
        Duration(milliseconds: (bytes.length ~/ 16).clamp(4000, 60000)),
        onTimeout: () {
          if (identical(_currentAudio, audio)) _disposeCurrent();
        },
      );
    } else {
      audio.onEnded.listen((_) {
        if (identical(_currentAudio, audio)) _disposeCurrent();
      });
      await audio.play().catchError((_) {});
    }
    return true;
  } catch (e) {
    return false;
  }
}

/// Browser SpeechSynthesis. Intentionally NOT used by VoiceService anymore:
/// it's a different voice than the backend neural voice, and overlapping the
/// two caused a "two voices" bug. Kept for completeness / optional use.
Future<void> webSpeak(String text, {bool awaitCompletion = false}) async {
  html.window.speechSynthesis?.cancel();
  final utterance = html.SpeechSynthesisUtterance(text);
  utterance.lang = 'de-DE';
  utterance.rate = 0.9;
  utterance.volume = 1.0;

  if (awaitCompletion) {
    final completer = Completer<void>();
    utterance.onEnd.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    utterance.onError.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    html.window.speechSynthesis?.speak(utterance);
    await completer.future.timeout(
      Duration(milliseconds: (text.length * 90).clamp(4000, 60000)),
      onTimeout: () {},
    );
  } else {
    html.window.speechSynthesis?.speak(utterance);
  }
}

/// Stops any web speech: cancels synthesis AND stops the current audio clip.
void webSpeechCancel() {
  try {
    html.window.speechSynthesis?.cancel();
  } catch (_) {}
  _disposeCurrent();
}
