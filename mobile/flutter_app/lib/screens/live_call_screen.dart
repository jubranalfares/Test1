import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/live_conversation_service.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';

/// A full-screen, phone-call-like UI for a hands-free live voice
/// conversation with Jarvis. Opens, greets the user immediately, then loops
/// listening/responding until the user presses "Beenden".
class LiveCallScreen extends StatefulWidget {
  const LiveCallScreen({super.key});

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen> {
  @override
  void initState() {
    super.initState();
    // Start the conversation as soon as the screen is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveConversationService>().start();
    });
  }

  @override
  void dispose() {
    // Ensure the conversation is fully stopped when leaving the screen.
    // read() is safe here because the provider lives above this screen.
    try {
      context.read<LiveConversationService>().stop();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _endCall() async {
    context.read<LiveConversationService>().stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _statusLabel(LiveConversationState state) {
    switch (state) {
      case LiveConversationState.greeting:
      case LiveConversationState.speaking:
        return 'Jarvis spricht…';
      case LiveConversationState.waitingForTap:
        return 'Tippe auf das Mikrofon zum Sprechen';
      case LiveConversationState.listening:
        return 'Ich höre zu…';
      case LiveConversationState.thinking:
        return 'Denke nach…';
      case LiveConversationState.ended:
        return 'Gespräch beendet';
      case LiveConversationState.idle:
        return 'Verbinde…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LiveConversationService>();
    final voice = context.watch<VoiceService>();
    final state = service.state;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) {
          context.read<LiveConversationService>().stop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0A0F), Color(0xFF12121A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                _Header(),
                const Spacer(),

                // Animated orb representing Jarvis.
                _JarvisOrb(state: state),
                const SizedBox(height: 32),

                // Status label.
                Text(
                  _statusLabel(state),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ).animate(key: ValueKey(state)).fade(duration: 300.ms),

                const SizedBox(height: 16),

                // Mode switch: tap-to-talk vs hands-free.
                _ModeToggle(service: service),

                const SizedBox(height: 12),

                // Big tap-to-talk button (only in push-to-talk while waiting).
                if (service.mode == LiveMode.pushToTalk &&
                    state == LiveConversationState.waitingForTap)
                  _TapToTalkButton(
                    onTap: () =>
                        context.read<LiveConversationService>().startListeningOnce(),
                  ),

                const SizedBox(height: 12),

                // Live transcript / partial recognition.
                Expanded(
                  flex: 2,
                  child: _TranscriptView(service: service),
                ),

                if (service.lastError != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Text(
                      service.lastError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Bottom controls: mute toggle + big red end button.
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleControl(
                        icon: voice.ttsEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        color: AppColors.card,
                        iconColor: voice.ttsEnabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        size: 56,
                        onTap: () => context.read<VoiceService>().toggleTts(),
                      ),
                      const SizedBox(width: 40),
                      _EndCallButton(onTap: _endCall),
                      const SizedBox(width: 40),
                      _CircleControl(
                        icon: Icons.refresh_rounded,
                        color: AppColors.card,
                        iconColor: AppColors.textPrimary,
                        size: 56,
                        onTap: () {
                          final s =
                              context.read<LiveConversationService>();
                          s.stop();
                          s.start();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary, size: 28),
          onPressed: () {
            context.read<LiveConversationService>().stop();
            Navigator.of(context).maybePop();
          },
        ),
        const Spacer(),
        const Text(
          'Live mit Jarvis',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

/// The central glowing orb. Its colour, glow and animation depend on the
/// current conversation state.
class _JarvisOrb extends StatelessWidget {
  final LiveConversationState state;

  const _JarvisOrb({required this.state});

  bool get _isSpeaking =>
      state == LiveConversationState.speaking ||
      state == LiveConversationState.greeting;
  bool get _isListening => state == LiveConversationState.listening;
  bool get _isThinking => state == LiveConversationState.thinking;

  @override
  Widget build(BuildContext context) {
    final Color glow = _isListening
        ? AppColors.success
        : _isThinking
            ? AppColors.secondary
            : AppColors.primary;

    final Gradient orbGradient = _isListening
        ? const LinearGradient(
            colors: [AppColors.success, Color(0xFF00BFA5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    Widget orb = Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: orbGradient,
        boxShadow: [
          BoxShadow(
            color: glow.withOpacity(0.55),
            blurRadius: 50,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: glow.withOpacity(0.3),
            blurRadius: 90,
            spreadRadius: 20,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'J',
          style: TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );

    // Per-state animation.
    if (_isSpeaking) {
      orb = orb
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1.08, 1.08),
            duration: 700.ms,
            curve: Curves.easeInOut,
          );
    } else if (_isThinking) {
      // Spinning gradient ring around a steady orb.
      orb = orb.animate(onPlay: (c) => c.repeat()).rotate(
            duration: 2.seconds,
          );
    } else if (_isListening) {
      orb = orb
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.04, 1.04),
            duration: 1.2.seconds,
            curve: Curves.easeInOut,
          );
    }

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Listening ripple rings.
          if (_isListening)
            ...List.generate(3, (i) {
              return Container(
                width: 170 + i * 22.0,
                height: 170 + i * 22.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.35 - i * 0.1),
                    width: 2,
                  ),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    end: const Offset(1.25, 1.25),
                    duration: Duration(milliseconds: 1400 + i * 300),
                    curve: Curves.easeOut,
                  )
                  .fade(
                    begin: 0.7,
                    end: 0.0,
                    duration: Duration(milliseconds: 1400 + i * 300),
                  );
            }),

          // Thinking ring.
          if (_isThinking)
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.secondary),
                backgroundColor: AppColors.cardBorder.withOpacity(0.3),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .rotate(duration: 1.2.seconds),
            ),

          orb,
        ],
      ),
    );
  }
}

/// Shows the latest exchange and the live partial recognition text.
class _TranscriptView extends StatelessWidget {
  final LiveConversationService service;

  const _TranscriptView({required this.service});

  @override
  Widget build(BuildContext context) {
    final turns = service.transcript;
    final partial = service.partialText;

    // Show the last few turns for context.
    final recent = turns.length > 4 ? turns.sublist(turns.length - 4) : turns;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      reverse: false,
      children: [
        for (final turn in recent)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment:
                  turn.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: turn.isUser
                      ? AppColors.primary.withOpacity(0.18)
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: turn.isUser
                        ? AppColors.primary.withOpacity(0.4)
                        : AppColors.cardBorder,
                  ),
                ),
                child: Text(
                  turn.text,
                  style: TextStyle(
                    color: turn.isUser
                        ? AppColors.textPrimary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ).animate().fade(duration: 250.ms).slideY(begin: 0.15, end: 0),

        // Live partial text while the user is speaking.
        if (partial.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.25),
                  ),
                ),
                child: Text(
                  partial,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircleControl extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onTap;

  const _CircleControl({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: iconColor, size: size * 0.42),
      ),
    );
  }
}

/// Segmented toggle between push-to-talk and hands-free modes.
class _ModeToggle extends StatelessWidget {
  final LiveConversationService service;

  const _ModeToggle({required this.service});

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, IconData icon, LiveMode mode) {
      final selected = service.mode == mode;
      return GestureDetector(
        onTap: () => context.read<LiveConversationService>().setMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? Colors.white
                      : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('Tippen', Icons.touch_app_rounded, LiveMode.pushToTalk),
          segment('Freihändig', Icons.graphic_eq_rounded, LiveMode.handsFree),
        ],
      ),
    );
  }
}

/// Large mic button for push-to-talk: tap to start speaking one phrase.
class _TapToTalkButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TapToTalkButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.gradientPurpleCyan,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.5),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 38),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(1.06, 1.06),
          duration: 900.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFF3333), AppColors.error],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}
