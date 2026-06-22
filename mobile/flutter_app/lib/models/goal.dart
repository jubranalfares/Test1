enum GoalStatus { onTrack, atRisk, behind, completed }

class Goal {
  final String id;
  final String title;
  final String description;
  final double progress;
  final DateTime? deadline;
  final int streak;
  final GoalStatus status;
  final DateTime createdAt;
  final bool isCompleted;
  final double targetValue;
  final double currentValue;
  final String unit;

  const Goal({
    required this.id,
    required this.title,
    this.description = '',
    this.progress = 0.0,
    this.deadline,
    this.streak = 0,
    this.status = GoalStatus.onTrack,
    required this.createdAt,
    this.isCompleted = false,
    this.targetValue = 0,
    this.currentValue = 0,
    this.unit = '',
  });

  Goal copyWith({
    String? id,
    String? title,
    String? description,
    double? progress,
    DateTime? deadline,
    int? streak,
    GoalStatus? status,
    DateTime? createdAt,
    bool? isCompleted,
    double? targetValue,
    double? currentValue,
    String? unit,
  }) {
    return Goal(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      progress: progress ?? this.progress,
      deadline: deadline ?? this.deadline,
      streak: streak ?? this.streak,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
      targetValue: targetValue ?? this.targetValue,
      currentValue: currentValue ?? this.currentValue,
      unit: unit ?? this.unit,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target_value': targetValue,
        'current_value': currentValue,
        'unit': unit,
        'deadline': deadline?.toIso8601String(),
        'streak': streak,
        'completed': isCompleted,
        'created_at': createdAt.toIso8601String(),
      };

  /// Parses a goal from the backend (snake_case, progress_percent 0-100,
  /// status strings on_track/at_risk/behind/done). Also tolerates the older
  /// camelCase shape so nothing breaks if both are ever in play.
  factory Goal.fromJson(Map<String, dynamic> json) {
    GoalStatus status = GoalStatus.onTrack;
    final statusStr = json['status']?.toString() ?? '';
    switch (statusStr) {
      case 'atRisk':
      case 'at_risk':
        status = GoalStatus.atRisk;
        break;
      case 'behind':
        status = GoalStatus.behind;
        break;
      case 'completed':
      case 'done':
        status = GoalStatus.completed;
        break;
      default:
        status = GoalStatus.onTrack;
    }

    // Progress: backend sends progress_percent (0-100); older shape sent
    // progress (0-1).
    double progress;
    if (json['progress_percent'] != null) {
      progress = ((json['progress_percent'] as num).toDouble()) / 100.0;
    } else {
      progress = (json['progress'] as num?)?.toDouble() ?? 0.0;
    }
    progress = progress.clamp(0.0, 1.0);

    final targetValue =
        (json['target_value'] as num?)?.toDouble() ?? 0.0;
    final currentValue =
        (json['current_value'] as num?)?.toDouble() ?? 0.0;
    final unit = json['unit']?.toString() ?? '';

    final completed =
        json['completed'] as bool? ?? json['isCompleted'] as bool? ?? false;

    final createdRaw = json['created_at'] ?? json['createdAt'];

    // Build a human description from the numbers when none is provided.
    String description = json['description']?.toString() ?? '';
    if (description.isEmpty && targetValue > 0) {
      final cur = currentValue == currentValue.roundToDouble()
          ? currentValue.toInt().toString()
          : currentValue.toString();
      final tgt = targetValue == targetValue.roundToDouble()
          ? targetValue.toInt().toString()
          : targetValue.toString();
      description = unit.isNotEmpty ? '$cur / $tgt $unit' : '$cur / $tgt';
    }

    return Goal(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: description,
      progress: progress,
      deadline: (json['deadline'] != null &&
              json['deadline'].toString().isNotEmpty)
          ? DateTime.tryParse(json['deadline'].toString())
          : null,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      status: status,
      createdAt: createdRaw != null
          ? (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now())
          : DateTime.now(),
      isCompleted: completed,
      targetValue: targetValue,
      currentValue: currentValue,
      unit: unit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Goal && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
