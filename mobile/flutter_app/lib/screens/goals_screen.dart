import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Goal> _goals = [];
  Map<String, dynamic> _stats = {};
  bool _showCompleted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.getGoals(),
        api.getGoalsStats(),
      ]);
      final goalsData = results[0] as List<Map<String, dynamic>>;
      final statsData = results[1] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _goals = goalsData.map((d) => Goal.fromJson(d)).toList();
          _stats = statsData;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ziele konnten nicht geladen werden: $e')),
        );
      }
    }
  }

  List<Goal> get _activeGoals =>
      _goals.where((g) => !g.isCompleted).toList();
  List<Goal> get _completedGoals =>
      _goals.where((g) => g.isCompleted).toList();

  // Prefer backend-provided stats, fall back to deriving from the loaded list.
  int get _activeCount =>
      (_stats['active_count'] as num?)?.toInt() ?? _activeGoals.length;
  int get _completedCount =>
      (_stats['completed_count'] as num?)?.toInt() ?? _completedGoals.length;
  int get _maxStreak =>
      (_stats['best_streak'] as num?)?.toInt() ??
      _goals.fold(0, (max, g) => g.streak > max ? g.streak : max);

  Future<void> _updateProgress(Goal goal, double progress) async {
    // The slider is 0..1; the backend stores a value against the goal's
    // target. When a target exists, convert the fraction back to an absolute
    // value; otherwise send the percentage (0..100).
    final double value = goal.targetValue > 0
        ? progress * goal.targetValue
        : progress * 100.0;
    try {
      await context.read<ApiService>().updateGoalProgress(goal.id, value);
      await _loadGoals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fortschritt konnte nicht aktualisiert werden: $e')),
        );
      }
    }
  }

  Future<void> _deleteGoal(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Ziel löschen',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('„${goal.title}" wirklich löschen?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<ApiService>().deleteGoal(goal.id);
        await _loadGoals();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
          );
        }
      }
    }
  }

  void _addGoal() {
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    DateTime? deadline;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: targetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'z. B. 5',
                        labelText: 'Zielwert',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: unitCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'z. B. km',
                        labelText: 'Einheit',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: deadline ?? now,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) setSheet(() => deadline = picked);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        deadline == null
                            ? 'Frist wählen (optional)'
                            : 'Frist: ${DateFormat('dd.MM.yyyy').format(deadline!)}',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      if (deadline != null)
                        GestureDetector(
                          onTap: () => setSheet(() => deadline = null),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textSecondary, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (titleCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Bitte einen Titel eingeben.')),
                            );
                            return;
                          }
                          setSheet(() => saving = true);
                          try {
                            await context.read<ApiService>().createGoal({
                              'title': titleCtrl.text.trim(),
                              'target_value':
                                  num.tryParse(targetCtrl.text.trim()) ?? 0,
                              'unit': unitCtrl.text.trim(),
                              'deadline': deadline?.toIso8601String() ?? '',
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadGoals();
                          } catch (e) {
                            setSheet(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Ziel konnte nicht erstellt werden: $e')),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Ziel hinzufügen'),
                ),
              ),
            ],
          ),
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
        heroTag: 'fab_goals',
        onPressed: _addGoal,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadGoals,
              color: AppColors.primary,
              backgroundColor: AppColors.card,
              child: _goals.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(),
            ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 80),
      children: [
        const Icon(Icons.flag_rounded,
            color: AppColors.textSecondary, size: 56),
        const SizedBox(height: 16),
        const Text(
          'Noch keine Ziele',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tippe auf das Plus-Symbol, um dein erstes Ziel zu erstellen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats row
            _StatsRow(
              activeCount: _activeCount,
              completedCount: _completedCount,
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
                        onProgressCommit: (p) => _updateProgress(e.value, p),
                        onDelete: () => _deleteGoal(e.value),
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
                      color: AppColors.success.withValues(alpha:0.15),
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
                                child: _CompletedGoalCard(
                                  goal: g,
                                  onDelete: () => _deleteGoal(g),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
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
  final ValueChanged<double> onProgressCommit;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.onProgressUpdate,
    required this.onProgressCommit,
    required this.onDelete,
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
    return GestureDetector(
      onLongPress: onDelete,
      child: Container(
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
                  color: _statusColor.withValues(alpha:0.15),
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
                        overlayColor: _statusColor.withValues(alpha:0.2),
                      ),
                      child: Slider(
                        value: goal.progress.clamp(0.0, 1.0),
                        onChanged: onProgressUpdate,
                        onChangeEnd: onProgressCommit,
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
      ),
    );
  }
}

class _CompletedGoalCard extends StatelessWidget {
  final Goal goal;
  final VoidCallback onDelete;

  const _CompletedGoalCard({required this.goal, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onDelete,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha:0.15),
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
      ),
    );
  }
}
