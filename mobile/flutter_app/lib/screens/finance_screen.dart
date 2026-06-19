import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Transaction> _transactions = [];
  String _filterType = 'all'; // all, income, expense

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        switch (_tabController.index) {
          case 0:
            _filterType = 'all';
            break;
          case 1:
            _filterType = 'income';
            break;
          case 2:
            _filterType = 'expense';
            break;
        }
      });
    });
    _loadSampleData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSampleData() {
    _transactions = [
      Transaction(
        id: '1',
        description: 'Monatsgehalt',
        amount: 4500,
        type: TransactionType.income,
        category: TransactionCategory.salary,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Transaction(
        id: '2',
        description: 'Lebensmitteleinkauf',
        amount: 87.50,
        type: TransactionType.expense,
        category: TransactionCategory.food,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Transaction(
        id: '3',
        description: 'Uber-Fahrt',
        amount: 24.00,
        type: TransactionType.expense,
        category: TransactionCategory.transport,
        date: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Transaction(
        id: '4',
        description: 'Freelance-Projekt',
        amount: 850,
        type: TransactionType.income,
        category: TransactionCategory.freelance,
        date: DateTime.now().subtract(const Duration(days: 4)),
      ),
      Transaction(
        id: '5',
        description: 'Netflix-Abo',
        amount: 15.99,
        type: TransactionType.expense,
        category: TransactionCategory.entertainment,
        date: DateTime.now().subtract(const Duration(days: 5)),
      ),
      Transaction(
        id: '6',
        description: 'Amazon-Einkauf',
        amount: 142.30,
        type: TransactionType.expense,
        category: TransactionCategory.shopping,
        date: DateTime.now().subtract(const Duration(days: 6)),
      ),
      Transaction(
        id: '7',
        description: 'Apotheke',
        amount: 33.00,
        type: TransactionType.expense,
        category: TransactionCategory.health,
        date: DateTime.now().subtract(const Duration(days: 7)),
      ),
      Transaction(
        id: '8',
        description: 'Café',
        amount: 18.50,
        type: TransactionType.expense,
        category: TransactionCategory.food,
        date: DateTime.now().subtract(const Duration(days: 8)),
      ),
    ];
  }

  List<Transaction> get _filteredTransactions {
    switch (_filterType) {
      case 'income':
        return _transactions
            .where((t) => t.type == TransactionType.income)
            .toList();
      case 'expense':
        return _transactions
            .where((t) => t.type == TransactionType.expense)
            .toList();
      default:
        return _transactions;
    }
  }

  double get _totalIncome => _transactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpenses => _transactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get _balance => _totalIncome - _totalExpenses;

  void _addTransaction() {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    TransactionType selectedType = TransactionType.expense;
    TransactionCategory selectedCategory = TransactionCategory.other;

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
                'Transaktion hinzufügen',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Type toggle
              Row(
                children: [
                  Expanded(
                    child: _TypeToggle(
                      label: 'Ausgabe',
                      isSelected:
                          selectedType == TransactionType.expense,
                      color: AppColors.error,
                      onTap: () => setInner(() =>
                          selectedType = TransactionType.expense),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TypeToggle(
                      label: 'Einnahme',
                      isSelected:
                          selectedType == TransactionType.income,
                      color: AppColors.success,
                      onTap: () => setInner(
                          () => selectedType = TransactionType.income),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              TextField(
                controller: descCtrl,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Beschreibung',
                  labelText: 'Beschreibung',
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: amountCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0,00',
                  labelText: 'Betrag',
                  prefixText: '€ ',
                ),
              ),

              const SizedBox(height: 12),

              // Category dropdown
              DropdownButtonFormField<TransactionCategory>(
                value: selectedCategory,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: TransactionCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(
                      '${cat.emoji} ${cat.label}',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (v) =>
                    setInner(() => selectedCategory = v!),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final amount =
                        double.tryParse(amountCtrl.text) ?? 0;
                    if (descCtrl.text.isNotEmpty && amount > 0) {
                      setState(() {
                        _transactions.insert(
                          0,
                          Transaction(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            description: descCtrl.text,
                            amount: amount,
                            type: selectedType,
                            category: selectedCategory,
                            date: DateTime.now(),
                          ),
                        );
                      });
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Hinzufügen'),
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
      appBar: AppBar(title: const Text('Finanzen')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTransaction,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance card
            _BalanceCard(
              balance: _balance,
              income: _totalIncome,
              expenses: _totalExpenses,
            ).animate().fade(duration: 400.ms).slideY(begin: -0.05, end: 0),

            const SizedBox(height: 20),

            // Chart
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BarChartWidget(
                income: _totalIncome,
                expenses: _totalExpenses,
              ).animate().fade(delay: 200.ms, duration: 400.ms),
            ),

            const SizedBox(height: 20),

            // Filter tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicator: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Alle'),
                    Tab(text: 'Einnahmen'),
                    Tab(text: 'Ausgaben'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Transaction list
            ..._filteredTransactions.asMap().entries.map(
                  (e) => _TransactionItem(transaction: e.value)
                      .animate(
                          delay: Duration(milliseconds: e.key * 50))
                      .fade(duration: 300.ms)
                      .slideX(begin: -0.05, end: 0),
                ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final double income;
  final double expenses;

  const _BalanceCard({
    required this.balance,
    required this.income,
    required this.expenses,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = balance >= 0;
    final formatter = NumberFormat.currency(locale: 'de_DE', symbol: '€');

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF0D2E1A), const Color(0xFF12281A)]
              : [const Color(0xFF2E0D0D), const Color(0xFF281212)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPositive
              ? AppColors.success.withOpacity(0.3)
              : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIESEN MONAT',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatter.format(balance.abs()),
                style: TextStyle(
                  color: isPositive ? AppColors.success : AppColors.error,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(
                  isPositive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: isPositive ? AppColors.success : AppColors.error,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isPositive
                ? 'Diesen Monat im Plus'
                : 'Mehr ausgegeben als eingenommen',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Einnahmen',
                  value: formatter.format(income),
                  color: AppColors.success,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MiniStat(
                  label: 'Ausgaben',
                  value: formatter.format(expenses),
                  color: AppColors.error,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
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
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarChartWidget extends StatelessWidget {
  final double income;
  final double expenses;

  const _BarChartWidget({required this.income, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final max = (income > expenses ? income : expenses) * 1.2;

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
            'Einnahmen vs. Ausgaben',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                maxY: max > 0 ? max : 100,
                minY: 0,
                backgroundColor: Colors.transparent,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: max > 0 ? max / 4 : 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.cardBorder,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, meta) => Text(
                        '€${(v / 1000).toStringAsFixed(1)}k',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final labels = ['Einnahmen', 'Ausgaben'];
                        final idx = v.toInt();
                        if (idx >= 0 && idx < labels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              labels[idx],
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: income,
                        gradient: const LinearGradient(
                          colors: [AppColors.success, Color(0xFF00BF60)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 40,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(
                        toY: expenses,
                        gradient: const LinearGradient(
                          colors: [AppColors.error, Color(0xFFFF7575)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 40,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ],
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: AppColors.surface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '€${rod.toY.toStringAsFixed(0)}',
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction transaction;

  const _TransactionItem({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionType.income;
    final color = isIncome ? AppColors.success : AppColors.error;
    final sign = isIncome ? '+' : '-';
    final formatter = NumberFormat.currency(locale: 'de_DE', symbol: '€');

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
          // Category icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Center(
              child: Text(
                transaction.category.emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Description + category
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${transaction.category.label} • ${DateFormat('dd.MM.').format(transaction.date)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '$sign${formatter.format(transaction.amount)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _TypeToggle({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppColors.cardBorder,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? color : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
