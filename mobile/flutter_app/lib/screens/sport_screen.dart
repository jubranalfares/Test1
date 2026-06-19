import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/workout.dart';
import '../theme/app_theme.dart';

class SportScreen extends StatefulWidget {
  const SportScreen({super.key});

  @override
  State<SportScreen> createState() => _SportScreenState();
}

class _SportScreenState extends State<SportScreen> {
  List<Workout> _workouts = [];
  final int _weeklyGoal = 5;

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
    _loadSampleWorkouts();
  }

  void _loadSampleWorkouts() {
    final now = DateTime.now();
    _workouts = [
      Workout(
        id: '1',
        type: WorkoutType.running,
        durationMinutes: 35,
        calories: 320,
        date: now.subtract(const Duration(days: 1)),
      ),
      Workout(
        id: '2',
        type: WorkoutType.weightlifting,
        durationMinutes: 55,
        calories: 280,
        date: now.subtract(const Duration(days: 2)),
      ),
      Workout(
        id: '3',
        type: WorkoutType.yoga,
        durationMinutes: 40,
        calories: 150,
        date: now.subtract(const Duration(days: 3)),
      ),
      Workout(
        id: '4',
        type: WorkoutType.cycling,
        durationMinutes: 45,
        calories: 380,
        date: now.subtract(const Duration(days: 5)),
      ),
      Workout(
        id: '5',
        type: WorkoutType.hiit,
        durationMinutes: 25,
        calories: 290,
        date: now.subtract(const Duration(days: 8)),
      ),
      Workout(
        id: '6',
        type: WorkoutType.running,
        durationMinutes: 30,
        calories: 280,
        date: now.subtract(const Duration(days: 9)),
      ),
    ];
  }

  List<Workout> get _thisWeekWorkouts {
    final weekStart = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    return _workouts
        .where((w) => w.date.isAfter(weekStart.subtract(const Duration(days: 1))))
        .toList();
  }

  int get _thisMonthTotal {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    return _workouts
        .where((w) => w.date.isAfter(monthStart))
        .length;
  }

  int get _totalMinutesThisMonth {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    return _workouts
        .where((w) => w.date.isAfter(monthStart))
        .fold(0, (sum, w) => sum + w.durationMinutes);
  }

  int get _currentStreak {
    int streak = 0;
    var checkDate = DateTime.now();
    while (true) {
      final hasWorkout = _workouts.any((w) =>
          w.date.year == checkDate.year &&
          w.date.month == checkDate.month &&
          w.date.day == checkDate.day);
      if (hasWorkout) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  void _logWorkout() {
    WorkoutType selectedType = WorkoutType.running;
    final durationCtrl = TextEditingController(text: '30');
    final caloriesCtrl = TextEditingController();

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
                            ? AppColors.primary.withOpacity(0.2)
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

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final duration =
                        int.tryParse(durationCtrl.text) ?? 30;
                    final calories =
                        int.tryParse(caloriesCtrl.text);
                    setState(() {
                      _workouts.insert(
                        0,
                        Workout(
                          id: DateTime.now()
                              .millisecondsSinceEpoch
                              .toString(),
                          type: selectedType,
                          durationMinutes: duration,
                          calories: calories,
                          date: DateTime.now(),
                        ),
                      );
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Training eintragen'),
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
    final weeklyWorkouts = _thisWeekWorkouts.length;
    final progressRatio = (weeklyWorkouts / _weeklyGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Sport')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _logWorkout,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Training eintragen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
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
                    AppColors.primary.withOpacity(0.12),
                    AppColors.secondary.withOpacity(0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.25)),
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
              child: _WeekCalendar(workouts: _workouts),
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
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Noch keine Einheiten eingetragen',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ..._workouts.take(10).toList().asMap().entries.map(
                    (e) => _WorkoutItem(workout: e.value)
                        .animate(
                            delay: Duration(
                                milliseconds: 450 + e.key * 60))
                        .fade(duration: 300.ms)
                        .slideX(begin: -0.05, end: 0),
                  ),
          ],
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
  final List<Workout> workouts;

  const _WeekCalendar({required this.workouts});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

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
              final hasWorkout = workouts.any(
                (w) =>
                    w.date.year == day.year &&
                    w.date.month == day.month &&
                    w.date.day == day.day,
              );
              final isToday = day.day == now.day &&
                  day.month == now.month &&
                  day.year == now.year;
              final isPast = day.isBefore(now);

              return Column(
                children: [
                  Text(
                    days[i],
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
                          ? AppColors.primary.withOpacity(0.2)
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

  const _WorkoutItem({required this.workout});

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
    return Container(
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
              color: AppColors.primary.withOpacity(0.15),
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
        ],
      ),
    );
  }
}
