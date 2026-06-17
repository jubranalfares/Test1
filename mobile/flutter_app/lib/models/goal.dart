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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'progress': progress,
        'deadline': deadline?.toIso8601String(),
        'streak': streak,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'isCompleted': isCompleted,
      };

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
        status = GoalStatus.completed;
        break;
      default:
        status = GoalStatus.onTrack;
    }

    return Goal(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'].toString())
          : null,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      status: status,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Goal && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
