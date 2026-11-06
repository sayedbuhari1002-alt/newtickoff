import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/core/utils/date_utils.dart';
import 'package:tickoff_replacement/domain/models/models.dart';
import 'package:tickoff_replacement/features/tasks/habit_task_card.dart';

import '../support/in_memory_repository.dart';
import '../support/test_helpers.dart';

void main() {
  testWidgets('Tasks list includes Build habits but excludes Quit habits',
      (WidgetTester tester) async {
    final InMemoryAppRepository repo = InMemoryAppRepository()
      ..tasks['t1'] = Task(
        id: 't1',
        title: 'Prepare notes',
        dueAt: DateTime(2026, 10, 27),
        priority: TaskPriority.high,
        createdAt: DateTime(2026, 10, 26),
        updatedAt: DateTime(2026, 10, 26),
      )
      ..habits['build'] = sampleHabit(id: 'build', title: 'Morning Walk')
      ..habits['quit'] = sampleHabit(
        id: 'quit',
        title: 'Avoid Smoking',
        type: HabitType.quit,
      );

    await pumpApp(tester, repo: repo);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();

    expect(find.text('Prepare notes'), findsOneWidget);
    expect(find.text('Morning Walk'), findsOneWidget);
    expect(find.text('Avoid Smoking'), findsNothing);
    expect(find.text('All priorities'), findsNothing);
    expect(find.text('HABIT'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(HabitTaskCard), matching: find.byType(Checkbox)).first);
    await tester.pumpAndSettle();
    expect(repo.records['build|${dateKey(kToday)}']!.done, isTrue);
  });

  testWidgets('tapping a count Build habit in Tasks opens its tracking page',
      (WidgetTester tester) async {
    final InMemoryAppRepository repo = InMemoryAppRepository()
      ..habits['water'] = sampleHabit(
        id: 'water',
        title: 'Drink Water',
        tracking: TrackingMethod.count,
        goal: 100,
      );

    await pumpApp(tester, repo: repo);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drink Water'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add 1'), findsOneWidget);
    expect(find.byTooltip('Decrease by 1'), findsOneWidget);
    expect(find.byTooltip("Reset this day's count"), findsOneWidget);
  });
}
