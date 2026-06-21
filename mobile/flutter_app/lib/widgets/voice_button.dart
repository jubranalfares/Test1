import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';

class VoiceButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;

  const VoiceButton({
    super.key,
    this.onTap,
    this.size = 64,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceService = context.watch<VoiceService>();
    final isRecording = voiceService.isRecording;
    final isProcessing = voiceService.isProcessing;

    return GestureDetector(
      onTap: widget.onTap,
      child: _buildButton(isRecording, isProcessing),
    );
  }

  Widget _buildButton(bool isRecording, bool isProcessing) {
    final size = widget.size;

    if (isProcessing) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Spinning gradient ring
            SizedBox(
              width: size,
              height: size,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .rotate(duration: 1.seconds),
            ),
            Container(
              width: size - 12,
              height: size - 12,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_empty_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        ),
      );
    }

    if (isRecording) {
      return SizedBox(
        width: size + 20,
        height: size + 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ripple rings
            ...List.generate(3, (i) {
              return Container(
                width: size + (i * 14).toDouble(),
                height: size + (i * 14).toDouble(),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withValues(alpha:0.3 - i * 0.08),
                    width: 2,
                  ),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1.2, 1.2),
                    duration: Duration(milliseconds: 800 + i * 200),
                    curve: Curves.easeOut,
                  )
                  .fade(
                    begin: 0.8,
                    end: 0.0,
                    duration: Duration(milliseconds: 800 + i * 200),
                  );
            }),
            // Main button - red while recording
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.shade700,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha:0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ],
        ),
      );
    }

    // Idle state with slow pulse
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha:0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppColors.secondary.withValues(alpha:0.2),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.mic_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
