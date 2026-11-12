import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

void main() {
  group('Schedule', () {
    test('everyday is always scheduled', () {
      const Schedule s = Schedule();
      expect(s.isScheduledOn(DateTime(2026, 10, 27)), isTrue);
      expect(s.validate(), isNull);
    });

    test('days of week uses Monday=1..Sunday=7', () {
      const Schedule s =
          Schedule(type: FrequencyType.daysOfWeek, weekdays: <int>{1, 3});
      expect(s.isScheduledOn(DateTime(2026, 10, 26)), isTrue); // Monday
      expect(s.isScheduledOn(DateTime(2026, 10, 27)), isFalse); // Tuesday
      expect(s.isScheduledOn(DateTime(2026, 10, 28)), isTrue); // Wednesday
    });

    test('days of week needs at least one day', () {
      const Schedule s = Schedule(type: FrequencyType.daysOfWeek);
      expect(s.validate(), isNotNull);
    });

    test('day 31 falls on the last day of a short month', () {
      const Schedule s =
          Schedule(type: FrequencyType.daysOfMonth, monthDays: <int>{31});
      expect(s.isScheduledOn(DateTime(2026, 2, 28)), isTrue);
      expect(s.isScheduledOn(DateTime(2026, 2, 27)), isFalse);
      expect(s.isScheduledOn(DateTime(2026, 10, 31)), isTrue);
      expect(s.isScheduledOn(DateTime(2026, 4, 30)), isTrue);
    });

    test('some days per period validates its range', () {
      const Schedule ok =
          Schedule(type: FrequencyType.somePerPeriod, timesPerPeriod: 3);
      const Schedule bad =
          Schedule(type: FrequencyType.somePerPeriod, timesPerPeriod: 8);
      expect(ok.validate(), isNull);
      expect(ok.isFlexible, isTrue);
      expect(bad.validate(), isNotNull);
    });

    test('json round trip', () {
      const Schedule s = Schedule(
        type: FrequencyType.daysOfMonth,
        monthDays: <int>{1, 15},
      );
      expect(Schedule.fromJson(s.toJson()), s);
    });
  });

  group('Reminder', () {
    test('time label', () {
      expect(const Reminder().timeLabel, '09:00');
      expect(const Reminder(minutesOfDay: 21 * 60 + 5).timeLabel, '21:05');
    });

    test('json round trip and bad minutes fall back', () {
      const Reminder r = Reminder(
        enabled: true,
        minutesOfDay: 1260,
        weekdays: <int>{1, 2},
      );
      expect(Reminder.fromJson(r.toJson()), r);
      expect(Reminder.fromJson(<String, dynamic>{'minutesOfDay': 5000}).minutesOfDay,
          540);
    });
  });

  group('Habit', () {
    test('create trims title and assigns an id', () {
      final Habit h = Habit.create(title: '  Reading Books  ');
      expect(h.title, 'Reading Books');
      expect(h.id, isNotEmpty);
      expect(h.isArchived, isFalse);
    });

    test('validate: title, count and checklist rules', () {
      expect(Habit.create(title: '   ').validate(), isNotNull);
      expect(Habit.create(title: 'Run').validate(), isNull);
      expect(
        Habit.create(
          title: 'Water',
          tracking: TrackingMethod.count,
          dailyGoal: 0,
        ).validate(),
        isNotNull,
      );
      expect(
        Habit.create(
          title: 'Water',
          tracking: TrackingMethod.count,
          dailyGoal: 8,
          unit: 'glasses',
        ).validate(),
        isNull,
      );
      expect(
        Habit.create(title: 'Routine', tracking: TrackingMethod.checklist)
            .validate(),
        isNotNull,
      );
      expect(
        Habit.create(
          title: 'Routine',
          tracking: TrackingMethod.checklist,
          checklist: const <ChecklistItem>[
            ChecklistItem(id: 'a', title: 'Stretch'),
          ],
        ).validate(),
        isNull,
      );
    });

    test('archive and restore via copyWith', () {
      final Habit h = Habit.create(title: 'Run');
      final Habit archived = h.copyWith(archivedAt: DateTime(2026, 10, 27));
      expect(archived.isArchived, isTrue);
      expect(archived.copyWith(clearArchived: true).isArchived, isFalse);
      expect(archived.id, h.id);
      expect(archived.createdAt, h.createdAt);
    });

    test('survives a real JSON encode/decode round trip', () {
      final Habit h = Habit.create(
        title: 'Reading Books',
        description: 'Read 20 pages',
        type: HabitType.quit,
        tracking: TrackingMethod.checklist,
        schedule: const Schedule(
          type: FrequencyType.daysOfWeek,
          weekdays: <int>{1, 2, 5},
        ),
        reminder: const Reminder(enabled: true, minutesOfDay: 1260),
        categoryId: 'cat-1',
        checklist: const <ChecklistItem>[
          ChecklistItem(id: 'i1', title: 'Chapter 1'),
          ChecklistItem(
            id: 'i2',
            title: 'Chapter 2',
            reminder: Reminder(enabled: true),
          ),
        ],
        dailyGoal: 3.5,
        unit: 'pages',
        step: 0.5,
      ).copyWith(archivedAt: DateTime(2026, 10, 27, 8, 30));

      final String encoded = jsonEncode(h.toJson());
      final Habit decoded =
          Habit.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, h);
    });

    test('unknown stored enum values fall back instead of crashing', () {
      final Habit h = Habit.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 'T',
        'type': 'something-new',
        'tracking': 42,
        'createdAt': 'not a date',
      });
      expect(h.type, HabitType.build);
      expect(h.tracking, TrackingMethod.tick);
    });
  });

  group('Productivity point ranges', () {
    test('task, subtask and habit points accept the expanded 1–10 scale', () {
      final DateTime now = DateTime(2026, 11, 10);
      final Task task = Task(
        id: 'ten-point-task', title: 'Deep work', createdAt: now,
        updatedAt: now, difficultyScore: 10,
      );
      final Task checklistTask = Task(
        id: 'ten-point-subtask', title: 'Plan', createdAt: now,
        updatedAt: now,
        subtasks: <Subtask>[Subtask(
          id: 'sub-10', title: 'Research', createdAt: now, difficultyScore: 10,
        )],
      );
      final Habit habit = Habit.create(title: 'Study', productivityPoints: 10, now: now);
      expect(task.validate(), isNull);
      expect(checklistTask.validate(), isNull);
      expect(habit.validate(), isNull);
      expect(task.copyWith(difficultyScore: 10.1).validate(), isNotNull);
      expect(Habit.create(title: 'Study', productivityPoints: 10.1, now: now).validate(), isNotNull);
      final Assignment assignment = Assignment(
        id: 'assignment-10', title: 'Submit project', createdAt: now,
        updatedAt: now, difficultyScore: 10,
      );
      expect(assignment.validate(), isNull);
      expect(assignment.copyWith(difficultyScore: 10.1).validate(), isNotNull);
    });
  });

  group('CompletionRecord', () {
    test('key is unique per habit and day', () {
      final DateTime t = DateTime(2026, 10, 27);
      final CompletionRecord a =
          CompletionRecord(habitId: 'h', dateKey: '2026-10-27', updatedAt: t);
      final CompletionRecord b = a.copyWith(done: true);
      expect(a.key, b.key);
      expect(a.key, 'h|2026-10-27');
    });

    test('json round trip', () {
      final CompletionRecord r = CompletionRecord(
        habitId: 'h',
        dateKey: '2026-10-27',
        updatedAt: DateTime(2026, 10, 27, 19, 3),
        done: true,
        count: 4.5,
        checkedItemIds: const <String>{'a', 'b'},
        slipped: true,
      );
      final CompletionRecord back = CompletionRecord.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
      );
      expect(back, r);
    });
  });

  group('Expense records', () {
    test('amounts use integer paise and survive JSON round trip', () {
      final DateTime date = DateTime(2026, 11, 4);
      final Expense expense = Expense(
        id: 'expense-1',
        amountPaise: 12345,
        expenseDate: date,
        categoryId: 'food',
        description: 'Lunch',
        paymentMethod: 'UPI',
        createdAt: date,
        updatedAt: date,
      );
      expect(expense.amountRupees, 123.45);
      expect(expense.validate(), isNull);
      expect(Expense.fromJson(expense.toJson()), expense);
      expect(expense.copyWith(clearCategory: true).categoryId, isNull);
      final Expense income = expense.copyWith(transactionType: TransactionType.income);
      expect(income.isIncome, isTrue);
      expect(Expense.fromJson(income.toJson()), income);
      final Map<String, dynamic> legacyJson = Map<String, dynamic>.of(expense.toJson())
        ..remove('transactionType');
      expect(Expense.fromJson(legacyJson).transactionType, TransactionType.expense);
    });

    test('expense amount and description are validated', () {
      final DateTime date = DateTime(2026, 11, 4);
      Expense makeExpense({required int amount, String description = ''}) => Expense(
        id: 'e', amountPaise: amount, expenseDate: date,
        createdAt: date, updatedAt: date, description: description,
      );
      expect(makeExpense(amount: 0).validate(), isNotNull);
      expect(makeExpense(amount: 100, description: List<String>.filled(301, 'x').join()).validate(), isNotNull);
      expect(makeExpense(amount: 100).validate(), isNull);
    });
  });

  test('subtask reminder timestamp survives JSON and can be cleared', () {
    final DateTime reminder = DateTime(2026, 11, 8, 18, 30);
    final Subtask item = Subtask(
      id: 'step-reminder',
      title: 'Prepare slides',
      createdAt: DateTime(2026, 11, 7),
      reminderAt: reminder,
    );
    final Subtask decoded = Subtask.fromJson(
      jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.reminderAt, reminder);
    expect(decoded.copyWith(clearReminderAt: true).reminderAt, isNull);
  });

  group('Note and HabitCategory', () {
    test('note emptiness and round trip', () {
      final DateTime t = DateTime(2026, 10, 27);
      final Note empty = Note(id: 'n', createdAt: t, updatedAt: t);
      expect(empty.isEmpty, isTrue);
      final Note full = empty.copyWith(title: 'Title', habitId: 'h');
      expect(full.isEmpty, isFalse);
      expect(Note.fromJson(full.toJson()), full);
    });

    test('category round trip', () {
      const HabitCategory c =
          HabitCategory(id: 'c', name: 'Taskiya', sortOrder: 2);
      expect(HabitCategory.fromJson(c.toJson()), c);
    });
  });

  test('note types and selected periods round-trip through JSON', () {
    final DateTime now = DateTime(2026, 11, 7, 10);
    final Note monthly = Note(id: 'monthly-note', title: 'Review', noteType: NoteType.monthly, periodDate: DateTime(2026, 11), createdAt: now, updatedAt: now);
    expect(Note.fromJson(monthly.toJson()), monthly);
    final Note legacy = Note.fromJson(<String, dynamic>{'id': 'legacy', 'createdAt': now.toIso8601String(), 'updatedAt': now.toIso8601String()});
    expect(legacy.noteType, NoteType.general);
  });

}
