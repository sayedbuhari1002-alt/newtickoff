import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/data/services/task_reminder_service.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

void main() {
  final TaskReminderService reminders = TaskReminderService.instance;

  Task task(DateTime? deadline) => Task(
        id: 'task-1',
        title: 'Prepare report',
        dueAt: deadline,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );

  group('automatic task deadline reminder time', () {
    test('is scheduled 30 minutes before a timed deadline', () {
      expect(
        reminders.taskDeadlineAlertTime(task(DateTime(2026, 11, 4, 17))),
        DateTime(2026, 11, 4, 16, 30),
      );
    });

    test('date-only deadline is treated as 23:59 on that date', () {
      expect(
        reminders.taskDeadlineAlertTime(task(DateTime(2026, 11, 4))),
        DateTime(2026, 11, 4, 23, 29),
      );
    });

    test('tasks without a deadline have no automatic deadline reminder', () {
      expect(reminders.taskDeadlineAlertTime(task(null)), isNull);
    });
  });

  test('subtask reminder IDs are stable and task payload resolves parent ID', () {
    expect(TaskReminderService.taskIdFromPayload('task-subtask|task-7|step-2'), 'task-7');
    expect(TaskReminderService.taskIdFromPayload('task-deadline|task-9'), 'task-9');
  });

}
