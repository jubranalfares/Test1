import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'notes_screen.dart';
import 'goals_screen.dart';
import 'finance_screen.dart';
import 'sport_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Chat',
    ),
    _NavItem(
      icon: Icons.note_outlined,
      activeIcon: Icons.note_rounded,
      label: 'Notes',
    ),
    _NavItem(
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag_rounded,
      label: 'Goals',
    ),
    _NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Finance',
    ),
    _NavItem(
      icon: Icons.fitness_center_outlined,
      activeIcon: Icons.fitness_center_rounded,
      label: 'Sport',
    ),
  ];

  static const List<Widget> _screens = [
    ChatScreen(),
    NotesScreen(),
    GoalsScreen(),
    FinanceScreen(),
    SportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final voiceService = context.watch<VoiceService>();
    final chatProvider = context.read<ChatProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.cardBorder),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final item = _navItems[i];
                final isActive = _currentIndex == i;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _currentIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isActive ? item.activeIcon : item.icon,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      floatingActionButton: _VoiceFAB(
        voiceService: voiceService,
        chatProvider: chatProvider,
        currentIndex: _currentIndex,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _VoiceFAB extends StatefulWidget {
  final VoiceService voiceService;
  final ChatProvider chatProvider;
  final int currentIndex;

  const _VoiceFAB({
    required this.voiceService,
    required this.chatProvider,
    required this.currentIndex,
  });

  @override
  State<_VoiceFAB> createState() => _VoiceFABState();
}

class _VoiceFABState extends State<_VoiceFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.voiceService.isRecording;
    final isProcessing = widget.voiceService.isProcessing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 70),
      child: GestureDetector(
        onTap: _handleVoiceTap,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: isRecording ? 1.0 : _pulseAnim.value,
              child: child,
            );
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isRecording
                  ? const LinearGradient(
                      colors: [Color(0xFFFF3333), Color(0xFFFF6666)],
                    )
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: [
                BoxShadow(
                  color: isRecording
                      ? Colors.red.withOpacity(0.5)
                      : AppColors.primary.withOpacity(0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleVoiceTap() async {
    if (widget.voiceService.isProcessing) return;

    if (widget.voiceService.isRecording) {
      // Stop and process
      final transcript =
          await widget.voiceService.stopRecordingAndTranscribe();
      if (transcript != null && transcript.isNotEmpty && mounted) {
        await widget.chatProvider.sendMessage(transcript);
        // If not on chat screen, show a snackbar
        if (widget.currentIndex != 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Jarvis: ${widget.chatProvider.messages.isNotEmpty && !widget.chatProvider.messages.last.isUser ? widget.chatProvider.messages.last.content.substring(0, widget.chatProvider.messages.last.content.length.clamp(0, 80)) : "Processing..."}'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'View',
                onPressed: () {
                  // Navigate to chat - parent will handle
                },
              ),
            ),
          );
        }
        // Speak the response
        if (widget.chatProvider.messages.isNotEmpty &&
            !widget.chatProvider.messages.last.isUser) {
          await widget.voiceService
              .speak(widget.chatProvider.messages.last.content);
        }
      }
    } else {
      await widget.voiceService.startRecording();
    }
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
