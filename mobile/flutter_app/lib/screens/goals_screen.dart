import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/goal.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Goal> _goals = [];
  bool _showCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadSampleGoals();
  }

  void _loadSampleGoals() {
    _goals = [
      Goal(
        id: '1',
        title: 'Täglich 5 km laufen',
        description: 'Ausdauer aufbauen',
        progress: 0.72,
        deadline: DateTime.now().add(const Duration(days: 14)),
        streak: 7,
        status: GoalStatus.onTrack,
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      Goal(
        id: '2',
        title: '2 Bücher pro Monat lesen',
        description: 'Wissen und Wortschatz erweitern',
        progress: 0.45,
        deadline: DateTime.now().add(const Duration(days: 8)),
        streak: 3,
        status: GoalStatus.atRisk,
        createdAt: DateTime.now().subtract(const Duration(days: 22)),
      ),
      Goal(
        id: '3',
        title: 'Diesen Monat 500 € sparen',
        description: 'Beitrag zum Notgroschen',
        progress: 0.25,
        deadline: DateTime.now().add(const Duration(days: 5)),
        streak: 1,
        status: GoalStatus.behind,
        createdAt: DateTime.now().subtract(const Duration(days: 25)),
      ),
      Goal(
        id: '4',
        title: 'Flutter lernen',
        description: 'Mobile-Dev-Kurs abschließen',
        progress: 1.0,
        streak: 30,
        status: GoalStatus.completed,
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
        isCompleted: true,
      ),
      Goal(
        id: '5',
        title: 'Täglich meditieren',
        description: '10 Minuten jeden Morgen',
        progress: 1.0,
        streak: 14,
        status: GoalStatus.completed,
        createdAt: DateTime.now().subtract(const Duration(days: 45)),
        isCompleted: true,
      ),
    ];
  }

  List<Goal> get _activeGoals =>
      _goals.where((g) => !g.isCompleted).toList();
  List<Goal> get _completedGoals =>
      _goals.where((g) => g.isCompleted).toList();

  int get _maxStreak =>
      _goals.fold(0, (max, g) => g.streak > max ? g.streak : max);

  void _addGoal() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Neues Ziel',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Titel des Ziels',
                labelText: 'Was möchtest du erreichen?',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Beschreibung (optional)',
                labelText: 'Beschreibung',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (titleCtrl.text.isNotEmpty) {
                    setState(() {
                      _goals.insert(
                        0,
                        Goal(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: titleCtrl.text,
                          description: descCtrl.text,
                          progress: 0,
                          status: GoalStatus.onTrack,
                          createdAt: DateTime.now(),
                        ),
                      );
                    });
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Ziel hinzufügen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ziele')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addGoal,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats row
            _StatsRow(
              activeCount: _activeGoals.length,
              completedCount: _completedGoals.length,
              maxStreak: _maxStreak,
            ).animate().fade(duration: 400.ms),

            const SizedBox(height: 20),

            // Active goals
            const Text(
              'AKTIVE ZIELE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            if (_activeGoals.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Center(
                  child: Text(
                    'Keine aktiven Ziele. Füge eins hinzu!',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ..._activeGoals.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GoalCard(
                        goal: e.value,
                        onProgressUpdate: (p) {
                          setState(() {
                            final idx = _goals.indexWhere(
                                (g) => g.id == e.value.id);
                            if (idx >= 0) {
                              _goals[idx] = _goals[idx].copyWith(
                                progress: p,
                                isCompleted: p >= 1.0,
                                status: p >= 1.0
                                    ? GoalStatus.completed
                                    : _goals[idx].status,
                              );
                            }
                          });
                        },
                      )
                          .animate(
                              delay:
                                  Duration(milliseconds: e.key * 100))
                          .fade(duration: 400.ms)
                          .slideX(begin: -0.05, end: 0),
                    ),
                  ),

            const SizedBox(height: 20),

            // Completed goals
            GestureDetector(
              onTap: () =>
                  setState(() => _showCompleted = !_showCompleted),
              child: Row(
                children: [
                  const Text(
                    'ABGESCHLOSSENE ZIELE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_completedGoals.length}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showCompleted
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _showCompleted
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: _completedGoals
                            .map(
                              (g) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: _CompletedGoalCard(goal: g),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int activeCount;
  final int completedCount;
  final int maxStreak;

  const _StatsRow({
    required this.activeCount,
    required this.completedCount,
    required this.maxStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatItem(
            icon: Icons.flag_rounded,
            label: 'Aktiv',
            value: '$activeCount',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatItem(
            icon: Icons.check_circle_rounded,
            label: 'Abgeschlossen',
            value: '$completedCount',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatItem(
            icon: Icons.local_fire_department_rounded,
            label: 'Beste Streak',
            value: '$maxStreak Tage',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final ValueChanged<double> onProgressUpdate;

  const _GoalCard({
    required this.goal,
    required this.onProgressUpdate,
  });

  Color get _statusColor {
    switch (goal.status) {
      case GoalStatus.onTrack:
        return AppColors.success;
      case GoalStatus.atRisk:
        return AppColors.warning;
      case GoalStatus.behind:
        return AppColors.error;
      case GoalStatus.completed:
        return AppColors.success;
    }
  }

  String get _statusLabel {
    switch (goal.status) {
      case GoalStatus.onTrack:
        return 'Im Plan';
      case GoalStatus.atRisk:
        return 'Gefährdet';
      case GoalStatus.behind:
        return 'Im Rückstand';
      case GoalStatus.completed:
        return 'Abgeschlossen';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (goal.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        goal.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Progress bar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Fortschritt',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${(goal.progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                        activeTrackColor: _statusColor,
                        inactiveTrackColor: AppColors.cardBorder,
                        thumbColor: _statusColor,
                        overlayColor: _statusColor.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: goal.progress.clamp(0.0, 1.0),
                        onChanged: onProgressUpdate,
                        min: 0,
                        max: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Footer row: deadline + streak
          Row(
            children: [
              if (goal.deadline != null) ...[
                const Icon(Icons.calendar_today_rounded,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd.MM.').format(goal.deadline!),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
              ],
              const Icon(Icons.local_fire_department_rounded,
                  color: AppColors.warning, size: 14),
              const SizedBox(width: 4),
              Text(
                '${goal.streak} Tage Streak',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletedGoalCard extends StatelessWidget {
  final Goal goal;

  const _CompletedGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.warning, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${goal.streak} Tage Streak',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Text(
            '100%',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
