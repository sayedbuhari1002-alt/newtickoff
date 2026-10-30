import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/services/task_reminder_service.dart';
import '../../state/app_state.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  ReminderPermissionStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ReminderPermissionStatus status =
        await TaskReminderService.instance.checkPermissions();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _request() async {
    setState(() => _loading = true);
    final ReminderPermissionStatus status =
        await TaskReminderService.instance.requestPermissions();
    ref.invalidate(reminderPermissionProvider);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(status.ready
            ? 'Task and habit reminders are ready.'
            : 'Some permissions are still disabled. Follow the Android Settings instructions below.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReminderPermissionStatus? status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications & reminders')),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pagePadding),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Reminder permissions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (status != null) ...<Widget>[
                  _PermissionRow(
                    label: 'Notifications',
                    granted: status.notificationsGranted,
                  ),
                  const SizedBox(height: 10),
                  _PermissionRow(
                    label: 'Exact alarms',
                    granted: status.exactAlarmsGranted,
                  ),
                  const SizedBox(height: 10),
                  _PermissionRow(
                    label: 'Device time zone',
                    granted: status.timeZoneAvailable,
                  ),
                  if (status.schedulingIssue != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      status.schedulingIssue!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _request,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Enable reminder permissions'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'If Android does not show a permission prompt',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 10),
                Text(
                  '1. Open Android Settings → Apps → TickOff → Notifications and allow notifications.\n\n'
                  '2. Open Settings → Apps → Special app access → Alarms & reminders → TickOff and allow alarms and reminders.\n\n'
                  '3. Return to TickOff and tap “Enable reminder permissions” again.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'TickOff uses exact local reminders. Android battery management and some device manufacturers may still affect delivery, even when permissions are enabled.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: granted ? AppColors.cyan : AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(label)),
          Text(
            granted ? 'Allowed' : 'Not allowed',
            style: TextStyle(
              color: granted ? AppColors.cyan : AppColors.danger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
