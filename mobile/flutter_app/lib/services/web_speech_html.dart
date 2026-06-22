// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Plays raw MP3 bytes via a native <audio> element.
/// This is the most iOS Safari-compatible audio method.
Future<bool> webPlayAudioBytes(Uint8List bytes, {bool awaitCompletion = false}) async {
  try {
    final blob = html.Blob([bytes], 'audio/mpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final audio = html.AudioElement()..src = url;
    html.document.body?.append(audio);

    if (awaitCompletion) {
      final completer = Completer<void>();
      audio.onEnded.listen((_) {
        if (!completer.isCompleted) completer.complete();
        html.Url.revokeObjectUrl(url);
        audio.remove();
      });
      audio.onError.listen((_) {
        if (!completer.isCompleted) completer.complete();
        html.Url.revokeObjectUrl(url);
        audio.remove();
      });
      await audio.play().catchError((_) {});
      await completer.future.timeout(
        Duration(milliseconds: (bytes.length ~/ 16).clamp(4000, 60000)),
        onTimeout: () {
          html.Url.revokeObjectUrl(url);
          audio.remove();
        },
      );
    } else {
      await audio.play().catchError((_) {});
    }
    return true;
  } catch (e) {
    return false;
  }
}

/// Falls back to browser SpeechSynthesis when no audio bytes available.
Future<void> webSpeak(String text, {bool awaitCompletion = false}) async {
  html.window.speechSynthesis?.cancel();
  final utterance = html.SpeechSynthesisUtterance(text);
  utterance.lang = 'de-DE';
  utterance.rate = 0.9;
  utterance.volume = 1.0;

  if (awaitCompletion) {
    final completer = Completer<void>();
    utterance.onEnd.listen((_) { if (!completer.isCompleted) completer.complete(); });
    utterance.onError.listen((_) { if (!completer.isCompleted) completer.complete(); });
    html.window.speechSynthesis?.speak(utterance);
    await completer.future.timeout(
      Duration(milliseconds: (text.length * 90).clamp(4000, 60000)),
      onTimeout: () {},
    );
  } else {
    html.window.speechSynthesis?.speak(utterance);
  }
}

void webSpeechCancel() {
  html.window.speechSynthesis?.cancel();
}
