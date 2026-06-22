enum WorkoutType {
  running,
  cycling,
  swimming,
  weightlifting,
  yoga,
  hiit,
  walking,
  other,
}

extension WorkoutTypeExtension on WorkoutType {
  String get emoji {
    switch (this) {
      case WorkoutType.running:
        return '🏃';
      case WorkoutType.cycling:
        return '🚴';
      case WorkoutType.swimming:
        return '🏊';
      case WorkoutType.weightlifting:
        return '🏋️';
      case WorkoutType.yoga:
        return '🧘';
      case WorkoutType.hiit:
        return '⚡';
      case WorkoutType.walking:
        return '🚶';
      case WorkoutType.other:
        return '💪';
    }
  }

  String get label {
    switch (this) {
      case WorkoutType.running:
        return 'Laufen';
      case WorkoutType.cycling:
        return 'Radfahren';
      case WorkoutType.swimming:
        return 'Schwimmen';
      case WorkoutType.weightlifting:
        return 'Krafttraining';
      case WorkoutType.yoga:
        return 'Yoga';
      case WorkoutType.hiit:
        return 'HIIT';
      case WorkoutType.walking:
        return 'Gehen';
      case WorkoutType.other:
        return 'Sonstiges';
    }
  }
}

class Workout {
  final String id;
  final WorkoutType type;
  final int durationMinutes;
  final int? calories;
  final DateTime date;
  final String? notes;

  const Workout({
    required this.id,
    required this.type,
    required this.durationMinutes,
    this.calories,
    required this.date,
    this.notes,
  });

  Workout copyWith({
    String? id,
    WorkoutType? type,
    int? durationMinutes,
    int? calories,
    DateTime? date,
    String? notes,
  }) {
    return Workout(
      id: id ?? this.id,
      type: type ?? this.type,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      calories: calories ?? this.calories,
      date: date ?? this.date,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'duration_min': durationMinutes,
        'calories': calories,
        'date': date.toIso8601String(),
      };

  factory Workout.fromJson(Map<String, dynamic> json) {
    WorkoutType type = WorkoutType.other;
    final typeStr = json['type']?.toString() ?? '';
    for (final t in WorkoutType.values) {
      if (t.name == typeStr) {
        type = t;
        break;
      }
    }

    // Backend sends duration_min; older shape sent durationMinutes.
    final duration = (json['duration_min'] as num?)?.toInt() ??
        (json['durationMinutes'] as num?)?.toInt() ??
        0;

    return Workout(
      id: json['id']?.toString() ?? '',
      type: type,
      durationMinutes: duration,
      calories: (json['calories'] as num?)?.toInt(),
      date: json['date'] != null
          ? (DateTime.tryParse(json['date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      notes: json['notes']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Workout && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
