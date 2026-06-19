enum TransactionType { income, expense }

enum TransactionCategory {
  food,
  transport,
  shopping,
  health,
  entertainment,
  other,
  salary,
  freelance,
}

extension TransactionCategoryExtension on TransactionCategory {
  String get emoji {
    switch (this) {
      case TransactionCategory.food:
        return '🍕';
      case TransactionCategory.transport:
        return '🚗';
      case TransactionCategory.shopping:
        return '🛍️';
      case TransactionCategory.health:
        return '💊';
      case TransactionCategory.entertainment:
        return '🎮';
      case TransactionCategory.salary:
        return '💼';
      case TransactionCategory.freelance:
        return '💻';
      case TransactionCategory.other:
        return '💰';
    }
  }

  String get label {
    switch (this) {
      case TransactionCategory.food:
        return 'Essen';
      case TransactionCategory.transport:
        return 'Transport';
      case TransactionCategory.shopping:
        return 'Einkaufen';
      case TransactionCategory.health:
        return 'Gesundheit';
      case TransactionCategory.entertainment:
        return 'Unterhaltung';
      case TransactionCategory.salary:
        return 'Gehalt';
      case TransactionCategory.freelance:
        return 'Freelance';
      case TransactionCategory.other:
        return 'Sonstiges';
    }
  }
}

class Transaction {
  final String id;
  final String description;
  final double amount;
  final TransactionType type;
  final TransactionCategory category;
  final DateTime date;
  final String? note;

  const Transaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.note,
  });

  Transaction copyWith({
    String? id,
    String? description,
    double? amount,
    TransactionType? type,
    TransactionCategory? category,
    DateTime? date,
    String? note,
  }) {
    return Transaction(
      id: id ?? this.id,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount': amount,
        'type': type.name,
        'category': category.name,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) {
    TransactionType type = TransactionType.expense;
    if (json['type']?.toString() == 'income') {
      type = TransactionType.income;
    }

    TransactionCategory category = TransactionCategory.other;
    final catStr = json['category']?.toString() ?? '';
    for (final c in TransactionCategory.values) {
      if (c.name == catStr) {
        category = c;
        break;
      }
    }

    return Transaction(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: type,
      category: category,
      date: json['date'] != null
          ? DateTime.parse(json['date'].toString())
          : DateTime.now(),
      note: json['note']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transaction &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
