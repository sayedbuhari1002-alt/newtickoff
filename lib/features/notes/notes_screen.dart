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
/// Daily Log shows journal entries and expenses for the selected date;
/// Expense Analytics rolls the saved expenses up by month.
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
                        _mode == _NotesMode.daily ? 'Daily Log' : 'Expense Analytics',
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
                    PillOption<_NotesMode>(value: _NotesMode.analytics, label: 'Expense Analytics'),
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
    final List<Expense> expenses = data.expensesForDate(date);
    final int total = expenses.fold<int>(
      0,
      (int sum, Expense expense) => sum + expense.amountPaise,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 28),
      children: <Widget>[
        _DateHeading(date: date, title: 'Your activity and spending'),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Daily Notes (${notes.length})',
          child: Column(
            children: <Widget>[
              if (notes.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
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
          title: 'Expenses (${expenses.length})',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('Total Expenses', style: TextStyle(color: AppColors.textSecondary))),
                  Text(_money(total), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.gold)),
                ],
              ),
              const SizedBox(height: 8),
              if (expenses.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No expenses recorded. This date\'s total is ₹0.', style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                for (int i = 0; i < expenses.length; i++) ...<Widget>[
                  _ExpenseTile(expense: expenses[i], category: data.expenseCategoryById(expenses[i].categoryId)),
                  if (i != expenses.length - 1) Divider(height: 18, color: AppColors.divider),
                ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.expenseNew(date: date)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Expense'),
                ),
              ),
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
    final List<Expense> expenses = data.expensesForMonth(month);
    final DateTime now = DateTime.now();
    final DateTime currentMonth = DateTime(now.year, now.month);
    final DateTime selectedMonth = DateTime(month.year, month.month);
    final int days = selectedMonth.isAfter(currentMonth)
        ? 0
        : (selectedMonth == currentMonth ? now.day : daysInMonth(month.year, month.month));
    final List<int> dailyTotals = List<int>.generate(days, (int index) {
      final int day = index + 1;
      return expenses.where((Expense e) => e.expenseDate.day == day).fold<int>(0, (int sum, Expense e) => sum + e.amountPaise);
    });
    final int total = dailyTotals.fold<int>(0, (int sum, int value) => sum + value);
    final int zeroDays = dailyTotals.where((int value) => value == 0).length;
    final int highest = dailyTotals.fold<int>(0, (int current, int value) => current > value ? current : value);
    final int highestIndex = dailyTotals.indexOf(highest);
    final Map<String, int> categoryTotals = <String, int>{};
    for (final Expense expense in expenses) {
      final String key = expense.categoryId ?? 'uncategorised';
      categoryTotals[key] = (categoryTotals[key] ?? 0) + expense.amountPaise;
    }
    final List<MapEntry<String, int>> byCategory = categoryTotals.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    final double average = days == 0 ? 0 : total / days;
    final String averageLabel = selectedMonth.isAfter(currentMonth)
        ? 'average per day'
        : (selectedMonth == currentMonth
            ? 'average per day so far'
            : 'average per calendar day');
    final int transactions = expenses.length;

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
            Text('Total Expenses', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(_money(total), style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: AppColors.gold)),
            const SizedBox(height: 4),
            Text('$transactions transactions · ${_money(average.round())} $averageLabel', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Daily average', value: _money(average.round()), icon: Icons.calendar_today_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _MetricCard(label: 'Highest day', value: highest == 0 ? '₹0' : _money(highest), icon: Icons.trending_up_rounded, detail: highest == 0 ? 'No spending' : '${highestIndex + 1} ${monthShort(month)}')),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: _MetricCard(label: 'Transactions', value: '$transactions', icon: Icons.receipt_long_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _MetricCard(label: 'Zero-expense days', value: '$zeroDays', icon: Icons.event_available_outlined)),
        ]),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Expense by Category',
          child: byCategory.isEmpty
              ? Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('No expenses recorded for this month.', style: TextStyle(color: AppColors.textSecondary)))
              : Column(children: <Widget>[
                  for (final MapEntry<String, int> entry in byCategory) ...<Widget>[
                    _CategoryBreakdownRow(
                      label: entry.key == 'uncategorised' ? 'Uncategorised' : (data.expenseCategoryById(entry.key)?.name ?? 'Uncategorised'),
                      amount: entry.value,
                      fraction: total == 0 ? 0 : entry.value / total,
                      color: Color(data.expenseCategoryById(entry.key)?.colorValue ?? AppColors.textSecondary.toARGB32()),
                    ),
                    if (entry != byCategory.last) const SizedBox(height: 14),
                  ],
                ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Daily Spending',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Every day in this reporting period is included. Days without expenses have a value of ₹0.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            SizedBox(
              height: 142,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < dailyTotals.length; i++)
                      _DailyBar(day: i + 1, amount: dailyTotals[i], maxAmount: highest),
                  ],
                ),
              ),
            ),
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

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.category});
  final Expense expense;
  final ExpenseCategory? category;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () => context.push(AppRoutes.expenseEdit(expense.id)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: <Widget>[
        Container(width: 38, height: 38, decoration: BoxDecoration(color: Color(category?.colorValue ?? AppColors.gold.toARGB32()).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)), child: Icon(_categoryIcon(category?.iconKey ?? ''), color: Color(category?.colorValue ?? AppColors.gold.toARGB32()), size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(expense.description.trim().isEmpty ? (category?.name ?? 'Expense') : expense.description.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${category?.name ?? 'Uncategorised'}${expense.paymentMethod.isEmpty ? '' : ' · ${expense.paymentMethod}'}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        const SizedBox(width: 8),
        Text(_money(expense.amountPaise), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold)),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
      ]),
    ),
  );
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

class _DailyBar extends StatelessWidget {
  const _DailyBar({required this.day, required this.amount, required this.maxAmount});
  final int day;
  final int amount;
  final int maxAmount;

  @override
  Widget build(BuildContext context) {
    final double barHeight = maxAmount == 0 ? 3 : math.max(3, amount / maxAmount * 88).toDouble();
    return SizedBox(
      width: 23,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
        const Spacer(),
        Container(height: barHeight, width: 11, decoration: BoxDecoration(color: amount == 0 ? AppColors.border : AppColors.gold, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
        const SizedBox(height: 6),
        Text('$day', style: TextStyle(fontSize: 9, color: AppColors.textHint)),
      ]),
    );
  }
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
