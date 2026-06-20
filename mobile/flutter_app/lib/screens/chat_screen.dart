import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/voice_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_button.dart';
import 'live_call_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _showBriefing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      chat.loadMorningBriefing();
      // Jarvis greets the user by himself (with voice) the moment the
      // chat screen opens. Guarded internally to run once per session and
      // only when there are no messages yet.
      chat.loadOpening();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _focusNode.unfocus();
    await context.read<ChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chat.messages.isNotEmpty) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'J',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jarvis',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Immer bereit',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded,
                color: AppColors.success),
            tooltip: 'Live mit Jarvis sprechen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LiveCallScreen()),
            ),
          ),
          Builder(
            builder: (context) {
              final voice = context.watch<VoiceService>();
              return IconButton(
                icon: Icon(
                  voice.ttsEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: voice.ttsEnabled
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                onPressed: () =>
                    context.read<VoiceService>().toggleTts(),
                tooltip: voice.ttsEnabled
                    ? 'Stimme ausschalten'
                    : 'Stimme einschalten',
              );
            },
          ),
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => _confirmClear(context, chat),
              tooltip: 'Chat löschen',
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.cardBorder,
          ),
        ),
      ),
      body: Column(
        children: [
          // Morning briefing card
          if (chat.morningBriefing != null && _showBriefing)
            _MorningBriefingCard(
              briefing: chat.morningBriefing!,
              onDismiss: () => setState(() => _showBriefing = false),
            ),

          // Messages
          Expanded(
            child: chat.messages.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    itemCount:
                        chat.messages.length + (chat.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chat.messages.length) {
                        return const TypingIndicator()
                            .animate()
                            .fade(duration: 300.ms);
                      }
                      return MessageBubble(message: chat.messages[index])
                          .animate()
                          .fade(duration: 300.ms)
                          .slideY(begin: 0.1, end: 0);
                    },
                  ),
          ),

          // Error message
          if (chat.errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chat.errorMessage!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.error, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: chat.clearError,
                  ),
                ],
              ),
            ),

          // Input area
          _InputArea(
            controller: _textController,
            focusNode: _focusNode,
            onSend: _sendMessage,
            isLoading: chat.isLoading,
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat löschen'),
        content: const Text(
            'Dadurch werden alle Nachrichten gelöscht. Fortfahren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              chat.clearMessages();
            },
            child: const Text(
              'Löschen',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'J',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.05, 1.05),
                duration: 2.seconds,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 24),
          const Text(
            'Hey, ich bin Jarvis',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ).animate().fade(delay: 300.ms, duration: 500.ms),
          const SizedBox(height: 8),
          const Text(
            'Sag etwas oder schreib eine Nachricht',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ).animate().fade(delay: 500.ms, duration: 500.ms),
          const SizedBox(height: 40),
          _QuickSuggestions(),
        ],
      ),
    );
  }
}

class _QuickSuggestions extends StatelessWidget {
  final List<String> suggestions = const [
    'Was steht an?',
    'Neue Notiz',
    'Motivier mich',
    'Wie ist das Wetter?',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions
          .asMap()
          .entries
          .map(
            (e) => GestureDetector(
              onTap: () =>
                  context.read<ChatProvider>().sendMessage(e.value),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  e.value,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            )
                .animate(delay: Duration(milliseconds: 600 + e.key * 100))
                .fade(duration: 400.ms)
                .slideY(begin: 0.3, end: 0),
          )
          .toList(),
    );
  }
}

class _MorningBriefingCard extends StatefulWidget {
  final Map<String, dynamic> briefing;
  final VoidCallback onDismiss;

  const _MorningBriefingCard({
    required this.briefing,
    required this.onDismiss,
  });

  @override
  State<_MorningBriefingCard> createState() => _MorningBriefingCardState();
}

class _MorningBriefingCardState extends State<_MorningBriefingCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final greeting = widget.briefing['greeting']?.toString() ??
        widget.briefing['summary']?.toString() ??
        widget.briefing['briefing']?.toString() ??
        'Guten Morgen! Hier ist dein Briefing.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.15),
            AppColors.secondary.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.wb_sunny_rounded,
              color: AppColors.warning,
              size: 20,
            ),
            title: const Text(
              'Morgen-Briefing',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      setState(() => _expanded = !_expanded),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                greeting,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: -0.2, end: 0);
  }
}

class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool isLoading;

  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final voiceService = context.watch<VoiceService>();
    final chat = context.read<ChatProvider>();

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 12
            : 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      child: Row(
        children: [
          // Voice button
          VoiceButton(
            size: 44,
            onTap: isLoading
                ? null
                : () async {
                    await chat.sendVoiceMessage();
                  },
          ),
          const SizedBox(width: 12),

          // Text field
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: voiceService.isRecording
                    ? 'Höre zu...'
                    : 'Nachricht an Jarvis…',
                hintStyle: TextStyle(
                  color: voiceService.isRecording
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              enabled: !voiceService.isRecording,
            ),
          ),

          const SizedBox(width: 10),

          // Send button
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final hasText = controller.text.isNotEmpty;
              return AnimatedScale(
                scale: hasText ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: hasText && !isLoading ? onSend : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasText
                          ? const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                            )
                          : null,
                      color: hasText ? null : AppColors.card,
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      color: hasText
                          ? Colors.white
                          : AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
