import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/date_strip.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/pill_selector.dart';
import '../../shared/widgets/section_card.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

enum _NotesMode { daily, analytics }

/// Date-oriented Notes tab. The horizontal date strip matches the Dashboard;
/// Daily Log shows journal entries and money transactions for the selected date;
/// Money Analytics rolls income and expenses up by month.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  _NotesMode _mode = _NotesMode.daily;
  late DateTime _selectedDate;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final DateTime today = dateOnly(ref.read(todayProvider));
    _selectedDate = today;
    _selectedMonth = DateTime(today.year, today.month);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    final DateTime today = ref.watch(todayProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your daily records',
            message: '$error',
          ),
          data: (AppData data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 8, AppDimens.gapSm, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _mode == _NotesMode.daily ? 'Daily Log' : 'Income & Expense Analytics',
                        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_mode == _NotesMode.daily) ...<Widget>[
                      IconButton(tooltip: 'Notes Library', icon: const Icon(Icons.library_books_outlined), onPressed: () => context.push(AppRoutes.noteLibrary)),
                      IconButton(
                        tooltip: 'Add daily note',
                        icon: const Icon(Icons.note_add_outlined),
                        onPressed: () => context.push(AppRoutes.noteNew(date: _selectedDate)),
                      ),
                      IconButton(
                        tooltip: 'Add income',
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF66BB6A)),
                        onPressed: () => context.push(AppRoutes.expenseNew(date: _selectedDate, type: TransactionType.income)),
                      ),
                      IconButton(
                        tooltip: 'Add expense',
                        icon: const Icon(Icons.add_shopping_cart_outlined),
                        onPressed: () => context.push(AppRoutes.expenseNew(date: _selectedDate)),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
                child: PillSelector<_NotesMode>(
                  selected: _mode,
                  onChanged: (_NotesMode next) => setState(() => _mode = next),
                  options: const <PillOption<_NotesMode>>[
                    PillOption<_NotesMode>(value: _NotesMode.daily, label: 'Daily Log'),
                    PillOption<_NotesMode>(value: _NotesMode.analytics, label: 'Money Analytics'),
                  ],
                ),
              ),
              if (_mode == _NotesMode.daily)
                DateStrip(
                  today: today,
                  selected: _selectedDate,
                  onSelected: (DateTime date) => setState(() => _selectedDate = dateOnly(date)),
                  dayCount: 730,
                ),
              Expanded(
                child: switch (_mode) {
                  _NotesMode.daily => _DailyOverviewContent(data: data, date: _selectedDate),
                  _NotesMode.analytics => _ExpenseAnalyticsContent(data: data, month: _selectedMonth, onMonthChanged: (DateTime month) => setState(() => _selectedMonth = DateTime(month.year, month.month))),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyOverviewContent extends StatelessWidget {
  const _DailyOverviewContent({required this.data, required this.date});
  final AppData data;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final List<Note> notes = data.notesForDate(date);
    final List<Note> habitNotes = data.habitNotesForDate(date);
    final List<Expense> transactions = data.expensesForDate(date);
    final List<Expense> income = transactions.where((Expense e) => e.isIncome).toList();
    final List<Expense> expenses = transactions.where((Expense e) => e.isExpense).toList();
    final int incomeTotal = income.fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);
    final int expenseTotal = expenses.fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);
    final int net = incomeTotal - expenseTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 28),
      children: <Widget>[
        _DateHeading(date: date, title: 'Your activity and money flow'),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Daily Notes (${notes.length})',
          child: Column(
            children: <Widget>[
              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No notes recorded for this date.', style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                for (int i = 0; i < notes.length; i++) ...<Widget>[
                  _NoteTile(note: notes[i]),
                  if (i != notes.length - 1) Divider(height: 18, color: AppColors.divider),
                ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.noteNew(date: date)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Note'),
                ),
              ),
            ],
          ),
        ),
        if (habitNotes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Habit Notes (${habitNotes.length})',
            child: Column(
              children: <Widget>[
                for (int i = 0; i < habitNotes.length; i++) ...<Widget>[
                  _NoteTile(note: habitNotes[i], habit: data.habitById(habitNotes[i].habitId ?? '')),
                  if (i != habitNotes.length - 1) Divider(height: 18, color: AppColors.divider),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        SectionCard(
          title: 'Money Transactions (${transactions.length})',
          child: Column(
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: _MetricCard(label: 'Income', value: _money(incomeTotal), icon: Icons.south_west_rounded, detail: '${income.length} entries')),
                const SizedBox(width: 8),
                Expanded(child: _MetricCard(label: 'Expenses', value: _money(expenseTotal), icon: Icons.north_east_rounded, detail: '${expenses.length} entries')),
              ]),
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(12)),
                child: Row(children: <Widget>[
                  Expanded(child: Text('Net for this day', style: TextStyle(color: AppColors.textSecondary))),
                  Text('${net >= 0 ? '+' : '−'}${_money(net.abs())}', style: TextStyle(fontWeight: FontWeight.w800, color: net >= 0 ? const Color(0xFF66BB6A) : AppColors.danger)),
                ]),
              ),
              const SizedBox(height: 10),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No income or expenses recorded for this date.', style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                for (int i = 0; i < transactions.length; i++) ...<Widget>[
                  _TransactionTile(
                    transaction: transactions[i],
                    category: data.expenseCategoryById(transactions[i].categoryId),
                  ),
                  if (i != transactions.length - 1) Divider(height: 18, color: AppColors.divider),
                ],
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.expenseNew(date: date)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Expense'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.expenseNew(date: date, type: TransactionType.income)),
                    icon: const Icon(Icons.add_rounded, color: Color(0xFF66BB6A)),
                    label: const Text('Add Income'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpenseAnalyticsContent extends StatelessWidget {
  const _ExpenseAnalyticsContent({required this.data, required this.month, required this.onMonthChanged});
  final AppData data;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final List<Expense> transactions = data.expensesForMonth(month);
    final List<Expense> expenses = transactions.where((Expense e) => e.isExpense).toList();
    final List<Expense> income = transactions.where((Expense e) => e.isIncome).toList();
    final DateTime now = DateTime.now();
    final DateTime currentMonth = DateTime(now.year, now.month);
    final DateTime selectedMonth = DateTime(month.year, month.month);
    final int days = selectedMonth.isAfter(currentMonth)
        ? 0
        : (selectedMonth == currentMonth ? now.day : daysInMonth(month.year, month.month));

    int totalForDay(List<Expense> items, int day) => items
        .where((Expense e) => e.expenseDate.day == day)
        .fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);

    final List<int> dailyExpenseTotals = List<int>.generate(
      days, (int index) => totalForDay(expenses, index + 1),
    );
    final List<int> dailyIncomeTotals = List<int>.generate(
      days, (int index) => totalForDay(income, index + 1),
    );
    final int expenseTotal = expenses.fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);
    final int incomeTotal = income.fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);
    final int net = incomeTotal - expenseTotal;
    final int zeroDays = dailyExpenseTotals.where((int value) => value == 0).length;
    final int highestExpense = dailyExpenseTotals.fold<int>(0, (int a, int b) => a > b ? a : b);
    final int highestIncome = dailyIncomeTotals.fold<int>(0, (int a, int b) => a > b ? a : b);
    final int highestExpenseDay = dailyExpenseTotals.indexOf(highestExpense) + 1;
    final int highestIncomeDay = dailyIncomeTotals.indexOf(highestIncome) + 1;
    final double dailyExpenseAverage = days == 0 ? 0 : expenseTotal / days;
    final double dailyIncomeAverage = days == 0 ? 0 : incomeTotal / days;
    final double dailyNetAverage = days == 0 ? 0 : net / days;
    final String averagePeriod = selectedMonth.isAfter(currentMonth)
        ? 'per day'
        : (selectedMonth == currentMonth ? 'per day so far' : 'per calendar day');

    Map<String, int> categoryTotals(List<Expense> records) {
      final Map<String, int> totals = <String, int>{};
      for (final Expense transaction in records) {
        final String key = transaction.categoryId ?? 'uncategorised';
        totals[key] = (totals[key] ?? 0) + transaction.amountPaise;
      }
      return totals;
    }

    List<MapEntry<String, int>> sortedCategories(List<Expense> records) {
      final List<MapEntry<String, int>> result = categoryTotals(records).entries.toList()
        ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
      return result;
    }

    final List<MapEntry<String, int>> expenseCategories = sortedCategories(expenses);
    final List<MapEntry<String, int>> incomeCategories = sortedCategories(income);
    final MapEntry<String, int>? topExpenseCategory = expenseCategories.isEmpty ? null : expenseCategories.first;
    final MapEntry<String, int>? topIncomeCategory = incomeCategories.isEmpty ? null : incomeCategories.first;
    String categoryName(String key) => key == 'uncategorised'
        ? 'Uncategorised'
        : (data.expenseCategoryById(key)?.name ?? 'Uncategorised');
    final int maxDaily = math.max(highestExpense, highestIncome).toInt();

    Widget categorySection({
      required String title,
      required List<MapEntry<String, int>> categories,
      required int total,
      required Color fallbackColor,
      required String emptyText,
    }) => SectionCard(
      title: title,
      child: categories.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(emptyText, style: TextStyle(color: AppColors.textSecondary)),
            )
          : Column(children: <Widget>[
              for (final MapEntry<String, int> entry in categories) ...<Widget>[
                _CategoryBreakdownRow(
                  label: categoryName(entry.key),
                  amount: entry.value,
                  fraction: total == 0 ? 0 : entry.value / total,
                  color: Color(data.expenseCategoryById(entry.key)?.colorValue ?? fallbackColor.toARGB32()),
                ),
                if (entry != categories.last) const SizedBox(height: 14),
              ],
            ]),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 8, AppDimens.pagePadding, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(tooltip: 'Previous month', onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(child: Center(child: Text(monthYear(month), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)))),
            IconButton(tooltip: 'Next month', onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.goldDim, borderRadius: BorderRadius.circular(AppDimens.radiusLg)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Net Cash Flow', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('${net >= 0 ? '+' : '−'}${_money(net.abs())}', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: net >= 0 ? const Color(0xFF66BB6A) : AppColors.danger)),
            const SizedBox(height: 4),
            Text('Income minus expenses · ${transactions.length} total transactions', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Row(children: <Widget>[
              Expanded(child: _FlowSummary(label: 'Money received', amount: incomeTotal, color: const Color(0xFF66BB6A))),
              const SizedBox(width: 12),
              Expanded(child: _FlowSummary(label: 'Money spent', amount: expenseTotal, color: AppColors.gold)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Total Expenses', value: _money(expenseTotal), icon: Icons.north_east_rounded)),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(label: 'Total Income', value: _money(incomeTotal), icon: Icons.south_west_rounded)),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Daily spend avg.', value: _money(dailyExpenseAverage.round()), icon: Icons.calendar_today_outlined)),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(label: 'Daily income avg.', value: _money(dailyIncomeAverage.round()), icon: Icons.event_available_outlined)),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Expense transactions', value: '${expenses.length}', icon: Icons.receipt_long_outlined)),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(label: 'Income transactions', value: '${income.length}', icon: Icons.account_balance_wallet_outlined)),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(
            label: 'Top spending category',
            value: topExpenseCategory == null ? '—' : _money(topExpenseCategory.value),
            icon: Icons.shopping_bag_outlined,
            detail: topExpenseCategory == null ? 'No expenses' : categoryName(topExpenseCategory.key),
          )),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(
            label: 'Top income source',
            value: topIncomeCategory == null ? '—' : _money(topIncomeCategory.value),
            icon: Icons.savings_outlined,
            detail: topIncomeCategory == null ? 'No income' : categoryName(topIncomeCategory.key),
          )),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Zero-expense days', value: '$zeroDays', icon: Icons.event_available_outlined, detail: 'of $days days')),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(label: 'Avg. net per day', value: '${dailyNetAverage >= 0 ? '+' : '−'}${_money(dailyNetAverage.abs().round())}', icon: Icons.account_balance_outlined)),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Highest spending day', value: highestExpense == 0 ? '₹0' : _money(highestExpense), icon: Icons.trending_up_rounded, detail: highestExpense == 0 ? 'No spending' : '$highestExpenseDay ${monthShort(month)}')),
          const SizedBox(width: 9),
          Expanded(child: _MetricCard(label: 'Highest income day', value: highestIncome == 0 ? '₹0' : _money(highestIncome), icon: Icons.trending_down_rounded, detail: highestIncome == 0 ? 'No income' : '$highestIncomeDay ${monthShort(month)}')),
        ]),
        const SizedBox(height: 16),
        categorySection(
          title: 'Expense by Category',
          categories: expenseCategories,
          total: expenseTotal,
          fallbackColor: AppColors.gold,
          emptyText: 'No expenses recorded for this month.',
        ),
        const SizedBox(height: 14),
        categorySection(
          title: 'Income by Source',
          categories: incomeCategories,
          total: incomeTotal,
          fallbackColor: const Color(0xFF66BB6A),
          emptyText: 'No income recorded for this month.',
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Daily Cash Flow',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Compare money received and money spent for each day in this reporting period.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              _LegendDot(color: const Color(0xFF66BB6A), label: 'Income'),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.gold, label: 'Expenses'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 148,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < days; i++)
                      _DailyCashFlowBar(
                        day: i + 1,
                        income: dailyIncomeTotals[i],
                        expense: dailyExpenseTotals[i],
                        maxAmount: maxDaily,
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Daily Spending',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Total outgoing money for each day. Days without expenses are shown as ₹0.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            SizedBox(
              height: 132,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < dailyExpenseTotals.length; i++)
                      _DailySingleBar(day: i + 1, amount: dailyExpenseTotals[i], maxAmount: highestExpense, color: AppColors.gold),
                  ],
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Transaction Summary',
          child: Column(children: <Widget>[
            _SummaryLine(label: 'Total transactions', value: '${transactions.length}'),
            _SummaryLine(label: 'Income entries', value: '${income.length}'),
            _SummaryLine(label: 'Expense entries', value: '${expenses.length}'),
            _SummaryLine(label: 'Net amount (income − expenses)', value: '${net >= 0 ? '+' : '−'}${_money(net.abs())}', valueColor: net >= 0 ? const Color(0xFF66BB6A) : AppColors.danger),
            _SummaryLine(label: 'Reporting days', value: '$days'),
            _SummaryLine(label: 'Period', value: averagePeriod),
          ]),
        ),
      ],
    );
  }
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.date, required this.title});
  final DateTime date;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
    Icon(Icons.event_note_rounded, color: AppColors.gold, size: 20),
    const SizedBox(width: 9),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('${weekdayShort(date)}, ${date.day} ${monthShort(date)} ${date.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      Text(title, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ])),
  ]);
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, this.habit});
  final Note note;
  final Habit? habit;

  @override
  Widget build(BuildContext context) {
    final String title = note.title.trim().isEmpty ? 'Untitled note' : note.title.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(AppRoutes.noteEdit(note.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(Icons.sticky_note_2_outlined, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (note.body.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(note.body.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            if (note.photoPaths.isNotEmpty || note.audioPaths.isNotEmpty || note.videoPaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 5),
              Row(children: <Widget>[
                if (note.photoPaths.isNotEmpty) ...<Widget>[
                  Icon(Icons.image_outlined, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Text('${note.photoPaths.length}', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 9),
                ],
                if (note.audioPaths.isNotEmpty) ...<Widget>[
                  Icon(Icons.mic_none_rounded, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Text('${note.audioPaths.length}', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 9),
                ],
                if (note.videoPaths.isNotEmpty) ...<Widget>[
                  Icon(Icons.videocam_outlined, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Text('${note.videoPaths.length}', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                ],
                Text('attachments', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
            ],
            if (habit != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Habit · ${habit!.title}', style: TextStyle(fontSize: 11, color: AppColors.textHint))),
          ])),
          Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ]),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction, required this.category});
  final Expense transaction;
  final ExpenseCategory? category;

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.isIncome;
    final Color typeColor = isIncome ? const Color(0xFF66BB6A) : AppColors.gold;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(AppRoutes.expenseEdit(transaction.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: <Widget>[
          Container(width: 38, height: 38, decoration: BoxDecoration(color: Color(category?.colorValue ?? typeColor.toARGB32()).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)), child: Icon(_categoryIcon(category?.iconKey ?? ''), color: Color(category?.colorValue ?? typeColor.toARGB32()), size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(transaction.description.trim().isEmpty ? (category?.name ?? (isIncome ? 'Income' : 'Expense')) : transaction.description.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${isIncome ? 'Income' : 'Expense'} · ${category?.name ?? 'Uncategorised'}${transaction.paymentMethod.isEmpty ? '' : ' · ${transaction.paymentMethod}'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ])),
          const SizedBox(width: 8),
          Text('${isIncome ? '+' : '−'}${_money(transaction.amountPaise)}', style: TextStyle(fontWeight: FontWeight.w700, color: typeColor)),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
        ]),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, this.detail});
  final String label;
  final String value;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
    child: Row(children: <Widget>[
      Icon(icon, color: AppColors.gold, size: 21),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 3),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        if (detail != null) Text(detail!, style: TextStyle(fontSize: 10, color: AppColors.textHint)),
      ])),
    ]),
  );
}

class _FlowSummary extends StatelessWidget {
  const _FlowSummary({required this.label, required this.amount, required this.color});
  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      const SizedBox(height: 4),
      Text(_money(amount), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
  ]);
}

class _DailyCashFlowBar extends StatelessWidget {
  const _DailyCashFlowBar({required this.day, required this.income, required this.expense, required this.maxAmount});
  final int day;
  final int income;
  final int expense;
  final int maxAmount;

  @override
  Widget build(BuildContext context) {
    final double incomeHeight = maxAmount == 0 ? 3 : math.max(3, income / maxAmount * 86).toDouble();
    final double expenseHeight = maxAmount == 0 ? 3 : math.max(3, expense / maxAmount * 86).toDouble();
    return SizedBox(
      width: 29,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(height: incomeHeight, width: 7, decoration: BoxDecoration(color: income == 0 ? AppColors.border : const Color(0xFF66BB6A), borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
            const SizedBox(width: 3),
            Container(height: expenseHeight, width: 7, decoration: BoxDecoration(color: expense == 0 ? AppColors.border : AppColors.gold, borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
          ],
        ),
        const SizedBox(height: 6),
        Text('$day', style: TextStyle(fontSize: 9, color: AppColors.textHint)),
      ]),
    );
  }
}

class _DailySingleBar extends StatelessWidget {
  const _DailySingleBar({required this.day, required this.amount, required this.maxAmount, required this.color});
  final int day;
  final int amount;
  final int maxAmount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double barHeight = maxAmount == 0 ? 3 : math.max(3, amount / maxAmount * 78).toDouble();
    return SizedBox(
      width: 23,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
        const Spacer(),
        Container(height: barHeight, width: 11, decoration: BoxDecoration(color: amount == 0 ? AppColors.border : color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
        const SizedBox(height: 6),
        Text('$day', style: TextStyle(fontSize: 9, color: AppColors.textHint)),
      ]),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: <Widget>[
      Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? AppColors.textPrimary)),
    ]),
  );
}

class _CategoryBreakdownRow extends StatelessWidget {
  const _CategoryBreakdownRow({required this.label, required this.amount, required this.fraction, required this.color});
  final String label;
  final int amount;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Row(children: <Widget>[Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))), Text(_money(amount), style: TextStyle(color: AppColors.textSecondary, fontSize: 13))]),
    const SizedBox(height: 7),
    ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0).toDouble(), minHeight: 7, color: color, backgroundColor: AppColors.border)),
    const SizedBox(height: 3),
    Text('${(fraction * 100).round()}%', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
  ]);
}

IconData _categoryIcon(String key) => switch (key) {
  'restaurant' => Icons.restaurant_rounded,
  'directions_car' => Icons.directions_car_rounded,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'school' => Icons.school_outlined,
  'movie' => Icons.movie_outlined,
  'medical_services' => Icons.medical_services_outlined,
  'receipt_long' => Icons.receipt_long_outlined,
  'person' => Icons.person_outline_rounded,
  'payments' => Icons.payments_outlined,
  'work' => Icons.work_outline_rounded,
  'business' => Icons.business_outlined,
  'trending_up' => Icons.trending_up_rounded,
  'savings' => Icons.savings_outlined,
  'card_giftcard' => Icons.card_giftcard_rounded,
  'more_horiz' => Icons.more_horiz_rounded,
  _ => Icons.category_outlined,
};

String _money(int paise) {
  final int rupees = paise ~/ 100;
  final int remainder = paise % 100;
  final String digits = rupees.toString();
  String grouped = digits;
  if (digits.length > 3) {
    final String lastThree = digits.substring(digits.length - 3);
    String leading = digits.substring(0, digits.length - 3);
    final List<String> groups = <String>[];
    while (leading.length > 2) {
      groups.insert(0, leading.substring(leading.length - 2));
      leading = leading.substring(0, leading.length - 2);
    }
    if (leading.isNotEmpty) groups.insert(0, leading);
    grouped = '${groups.join(',')},$lastThree';
  }
  return remainder == 0 ? '₹$grouped' : '₹$grouped.${remainder.toString().padLeft(2, '0')}';
}
