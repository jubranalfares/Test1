import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Color(0xFF0F0F1E),
              AppColors.background,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background dots / grid
            Positioned.fill(child: _GridBackground()),
            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Glow ring + J logo
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      final glow = 0.3 + 0.4 * _glowController.value;
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha:glow),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                            BoxShadow(
                              color: AppColors.secondary.withValues(alpha:glow * 0.5),
                              blurRadius: 70,
                              spreadRadius: 15,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: const Center(
                      child: Text(
                        'J',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.5, 0.5),
                        end: const Offset(1.0, 1.0),
                        duration: 700.ms,
                        curve: Curves.elasticOut,
                      )
                      .fade(duration: 500.ms),

                  const SizedBox(height: 40),

                  // JARVIS title — letter by letter
                  const _AnimatedTitle(),

                  const SizedBox(height: 16),

                  // Subtitle
                  const Text(
                    'DEIN PERSÖNLICHER KI-ASSISTENT',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 4,
                    ),
                  )
                      .animate(delay: 1200.ms)
                      .fade(duration: 600.ms)
                      .slideY(begin: 0.3, end: 0),

                  const SizedBox(height: 80),

                  // Loading indicator
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      backgroundColor: AppColors.cardBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                      .animate(delay: 1800.ms)
                      .fade(duration: 400.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedTitle extends StatelessWidget {
  final String text = 'JARVIS';

  const _AnimatedTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: text
          .split('')
          .asMap()
          .entries
          .map(
            (e) => Text(
              e.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            )
                .animate(delay: Duration(milliseconds: 600 + e.key * 80))
                .fade(duration: 300.ms)
                .slideY(begin: -0.5, end: 0, curve: Curves.easeOut),
          )
          .toList(),
    );
  }
}

class _GridBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha:0.04)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Dots at intersections
    final dotPaint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha:0.12)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
