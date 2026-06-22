import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/workout.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SportScreen extends StatefulWidget {
  const SportScreen({super.key});

  @override
  State<SportScreen> createState() => _SportScreenState();
}

class _SportScreenState extends State<SportScreen> {
  List<Workout> _workouts = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  int get _weeklyGoal {
    final g = (_stats['weekly_goal'] as num?)?.toInt() ?? 5;
    return g > 0 ? g : 5;
  }

  static const List<String> _motivationQuotes = [
    '„Streng dich an, denn niemand sonst wird es für dich tun."',
    '„Das einzige schlechte Training ist das, das nicht stattgefunden hat."',
    '„Dein Körper hält fast alles aus. Du musst nur deinen Kopf überzeugen."',
    '„Erfolg beginnt mit Selbstdisziplin."',
    '„Hör nicht auf, wenn du müde bist. Hör auf, wenn du fertig bist."',
  ];

  String get _todayQuote {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return _motivationQuotes[dayOfYear % _motivationQuotes.length];
  }

  @override
  void initState() {
    super.initState();
    _loadSport();
  }

  Future<void> _loadSport() async {
    if (mounted && !_loading) setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.getWorkouts(),
        api.getSportStats(),
      ]);
      final rawWorkouts = results[0] as List<Map<String, dynamic>>;
      final stats = results[1] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _workouts = rawWorkouts.map((d) => Workout.fromJson(d)).toList();
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sportdaten konnten nicht geladen werden: $e')),
        );
      }
    }
  }

  int get _thisWeekCount => (_stats['this_week_count'] as num?)?.toInt() ?? 0;

  int get _thisMonthTotal =>
      (_stats['total_workouts_month'] as num?)?.toInt() ?? 0;

  int get _totalMinutesThisMonth =>
      (_stats['total_minutes_month'] as num?)?.toInt() ?? 0;

  int get _currentStreak => (_stats['current_streak'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _weekDays {
    final raw = _stats['week_days'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const [];
  }

  void _logWorkout() {
    WorkoutType selectedType = WorkoutType.running;
    final durationCtrl = TextEditingController(text: '30');
    final caloriesCtrl = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
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
                'Training eintragen',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Type grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WorkoutType.values.map((type) {
                  final isSelected = selectedType == type;
                  return GestureDetector(
                    onTap: () => setInner(() => selectedType = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha:0.2)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: Text(
                        '${type.emoji} ${type.label}',
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Dauer (Min.)',
                        hintText: '30',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: caloriesCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Kalorien (opt.)',
                        hintText: '250',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Optional date picker
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate ?? now,
                    firstDate: DateTime(now.year - 2),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setInner(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: AppColors.primary, size: 16),
                      const SizedBox(width: 10),
                      Text(
                        selectedDate == null
                            ? 'Datum (optional)'
                            : DateFormat('dd.MM.yyyy').format(selectedDate!),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (selectedDate != null)
                        GestureDetector(
                          onTap: () => setInner(() => selectedDate = null),
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textSecondary, size: 16),
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
                          final duration =
                              int.tryParse(durationCtrl.text) ?? 30;
                          final calories =
                              int.tryParse(caloriesCtrl.text) ?? 0;
                          setInner(() => saving = true);
                          try {
                            await context.read<ApiService>().createWorkout({
                              'type': selectedType.name,
                              'duration_min': duration,
                              'calories': calories,
                              'date': selectedDate
                                      ?.toIso8601String()
                                      .split('T')
                                      .first ??
                                  '',
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadSport();
                          } catch (e) {
                            setInner(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Training konnte nicht gespeichert werden: $e')),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Training eintragen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWorkout(Workout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training löschen'),
        content: Text('„${workout.type.label}" löschen?'),
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
        await context.read<ApiService>().deleteWorkout(workout.id);
        await _loadSport();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final weeklyWorkouts = _thisWeekCount;
    final progressRatio = (weeklyWorkouts / _weeklyGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Sport')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_sport',
        onPressed: _logWorkout,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Training eintragen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSport,
              color: AppColors.primary,
              child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Motivation quote
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha:0.12),
                    AppColors.secondary.withValues(alpha:0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha:0.25)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _todayQuote,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fade(duration: 400.ms),

            const SizedBox(height: 20),

            // Weekly progress ring + stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Progress ring
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: progressRatio,
                            backgroundColor: AppColors.cardBorder,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$weeklyWorkouts',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'von $_weeklyGoal',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fade(delay: 200.ms, duration: 400.ms),

                  const SizedBox(width: 20),

                  // Right stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Diese Woche',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SmallStat(
                          icon: Icons.fitness_center_rounded,
                          label: 'Gesamt diesen Monat',
                          value: '$_thisMonthTotal Einheiten',
                        ),
                        const SizedBox(height: 8),
                        _SmallStat(
                          icon: Icons.timer_rounded,
                          label: 'Minuten gesamt',
                          value: '$_totalMinutesThisMonth Min.',
                        ),
                        const SizedBox(height: 8),
                        _SmallStat(
                          icon: Icons.local_fire_department_rounded,
                          label: 'Aktuelle Streak',
                          value: '$_currentStreak Tage',
                          valueColor: AppColors.warning,
                        ),
                      ],
                    ),
                  ).animate().fade(delay: 300.ms, duration: 400.ms),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Weekly calendar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WeekCalendar(weekDays: _weekDays),
            ).animate().fade(delay: 400.ms, duration: 400.ms),

            const SizedBox(height: 24),

            // Recent workouts
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'LETZTE EINHEITEN',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (_workouts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.fitness_center_rounded,
                          color: AppColors.textSecondary, size: 40),
                      SizedBox(height: 12),
                      Text(
                        'Noch keine Einheiten eingetragen',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tippe auf „Training eintragen", um zu starten.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._workouts.take(10).toList().asMap().entries.map(
                    (e) => _WorkoutItem(
                      workout: e.value,
                      onDelete: () => _deleteWorkout(e.value),
                    )
                        .animate(
                            delay: Duration(
                                milliseconds: 450 + e.key * 60))
                        .fade(duration: 300.ms)
                        .slideX(begin: -0.05, end: 0),
                  ),
          ],
        ),
      ),
            ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _SmallStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeekCalendar extends StatelessWidget {
  final List<Map<String, dynamic>> weekDays;

  const _WeekCalendar({required this.weekDays});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    // Fallback labels if backend returns nothing.
    const fallback = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

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
          const Text(
            'Diese Woche',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (i) {
              final day = weekStart.add(Duration(days: i));
              final dayData = i < weekDays.length ? weekDays[i] : null;
              final label = (dayData?['day']?.toString().isNotEmpty ?? false)
                  ? dayData!['day'].toString()
                  : fallback[i];
              final hasWorkout = dayData?['done'] == true;
              final isToday = day.day == now.day &&
                  day.month == now.month &&
                  day.year == now.year;
              final isPast = day.isBefore(now);

              return Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isToday
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isToday
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasWorkout
                          ? AppColors.primary.withValues(alpha:0.2)
                          : isToday
                              ? AppColors.cardBorder
                              : Colors.transparent,
                      border: isToday
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: hasWorkout
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.primary,
                              size: 16,
                            )
                          : isPast
                              ? const Icon(
                                  Icons.remove_rounded,
                                  color: AppColors.textSecondary,
                                  size: 14,
                                )
                              : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isToday
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _WorkoutItem extends StatelessWidget {
  final Workout workout;
  final VoidCallback? onDelete;

  const _WorkoutItem({required this.workout, this.onDelete});

  static const List<String> _weekdayShort = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'
  ];

  String _formatDate(DateTime date) {
    // weekday: 1 = Monday ... 7 = Sunday
    final wd = _weekdayShort[(date.weekday - 1).clamp(0, 6)];
    return '$wd, ${DateFormat('dd.MM.').format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onLongPress: onDelete,
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                workout.type.emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.type.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(workout.date),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: AppColors.textSecondary, size: 13),
                  const SizedBox(width: 3),
                  Text(
                    '${workout.durationMinutes} Min.',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (workout.calories != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.warning, size: 13),
                    const SizedBox(width: 3),
                    Text(
                      '${workout.calories} kcal',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.delete_outline_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
            ),
          ],
        ],
      ),
      ),
    );

    if (onDelete == null) return card;

    return Dismissible(
      key: ValueKey(workout.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete!();
        // Deletion + reload handled by callback; don't auto-remove here.
        return false;
      },
      background: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.error),
      ),
      child: card,
    );
  }
}
