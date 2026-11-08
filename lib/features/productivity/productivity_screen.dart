import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/ids.dart';
import '../../data/services/productivity_usage_service.dart';
import '../../domain/logic/productivity_engine.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class ProductivityScreen extends ConsumerStatefulWidget {
  const ProductivityScreen({super.key});
  @override
  ConsumerState<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends ConsumerState<ProductivityScreen> with WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  bool _syncingUsage = false;
  bool? _usagePermission;
  String? _autoRefreshRequestedForDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUsagePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoRefreshRequestedForDate = null;
      _loadUsagePermission();
    }
  }

  Future<void> _loadUsagePermission() async {
    final bool permitted = await ProductivityUsageService.instance.hasPermission();
    if (mounted) setState(() => _usagePermission = permitted);
  }

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _dateLabel(DateTime date) => '${date.day} ${_month(date.month)} ${date.year}';
  String _month(int month) => const <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
  bool get _isToday => _dateKey(_selectedDate) == _dateKey(DateTime.now());

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select productivity date',
    );
    if (picked != null && mounted) setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _editTarget(AppData data) async {
    final TextEditingController controller = TextEditingController(text: data.targetForDate(_selectedDate).toStringAsFixed(1));
    final bool hasOverride = data.productivityTargetOverrides.containsKey(_dateKey(_selectedDate));
    final String? choice = await showDialog<String>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Daily productivity target'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Target for ${_dateLabel(_selectedDate)}'),
        const SizedBox(height: 10),
        TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target points')),
        const SizedBox(height: 8),
        const Text('“This date” changes only the selected day. “Default tomorrow” applies to future dates and leaves historical targets unchanged.', style: TextStyle(fontSize: 12)),
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        if (hasOverride) TextButton(onPressed: () => Navigator.pop(dialogContext, 'clear'), child: const Text('Remove override')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, 'date'), child: const Text('This date')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, 'default'), child: const Text('Default tomorrow')),
      ],
    ));
    if (choice == null || !mounted) { controller.dispose(); return; }
    if (choice == 'clear') {
      await ref.read(appDataProvider.notifier).clearProductivityTargetOverride(_selectedDate);
    } else {
      final double? target = double.tryParse(controller.text.trim().replaceAll(',', '.'));
      if (target == null || target <= 0 || target > 1000) {
        controller.dispose();
        _message('Enter a target greater than 0 and no more than 1000.');
        return;
      }
      if (choice == 'date') {
        await ref.read(appDataProvider.notifier).setProductivityTargetForDate(_selectedDate, target);
      } else {
        await ref.read(appDataProvider.notifier).saveDefaultProductivityTarget(target);
      }
    }
    controller.dispose();
  }

  Future<void> _createAssignment({Assignment? existing}) async {
    final TextEditingController title = TextEditingController(text: existing?.title ?? '');
    final TextEditingController description = TextEditingController(text: existing?.description ?? '');
    final TextEditingController points = TextEditingController(text: (existing?.difficultyScore ?? 1.0).toString());
    DateTime? dueAt = existing?.dueAt;
    String priority = existing?.priority ?? 'medium';
    final bool? saved = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
      title: Text(existing == null ? 'New assignment' : 'Edit assignment'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Assignment title')),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
        TextField(controller: points, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Productivity points (1.0–5.0)')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: priority, decoration: const InputDecoration(labelText: 'Priority'), items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: 'low', child: Text('Low')), DropdownMenuItem(value: 'medium', child: Text('Medium')), DropdownMenuItem(value: 'high', child: Text('High')),
        ], onChanged: (String? value) { if (value != null) setDialogState(() => priority = value); }),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_outlined), title: const Text('Deadline'), subtitle: Text(dueAt == null ? 'No deadline' : _dateLabel(dueAt!)), onTap: () async {
          final DateTime? picked = await showDatePicker(context: context, initialDate: dueAt ?? _selectedDate, firstDate: DateTime.now().subtract(const Duration(days: 3650)), lastDate: DateTime.now().add(const Duration(days: 3650)));
          if (picked != null) setDialogState(() => dueAt = DateTime(picked.year, picked.month, picked.day));
        }),
        if (dueAt != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setDialogState(() => dueAt = null), child: const Text('Clear deadline'))),
      ])),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
    )));
    if (saved == true && mounted) {
      final DateTime now = DateTime.now();
      final Assignment assignment = Assignment(id: existing?.id ?? newId(), title: title.text.trim(), description: description.text.trim(), dueAt: dueAt, priority: priority, difficultyScore: double.tryParse(points.text.trim().replaceAll(',', '.')) ?? 1, isCompleted: existing?.isCompleted ?? false, completedAt: existing?.completedAt, createdAt: existing?.createdAt ?? now, updatedAt: now);
      await _guard(() => ref.read(appDataProvider.notifier).saveAssignment(assignment));
    }
    title.dispose(); description.dispose(); points.dispose();
  }

  Future<void> _createCategory({DistractionCategory? existing}) async {
    final TextEditingController name = TextEditingController(text: existing?.name ?? '');
    final TextEditingController severity = TextEditingController(text: (existing?.severityPointsPerHour ?? 1.0).toString());
    final TextEditingController details = TextEditingController(text: existing?.details ?? '');
    final TextEditingController packages = TextEditingController(text: (existing?.packageNames ?? const <String>[]).join('\n'));
    bool autoTrack = existing?.autoTrack ?? false;
    final bool? saved = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
      title: Text(existing == null ? 'Distraction category' : 'Edit category'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Category name')),
        TextField(controller: severity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Penalty points per hour')),
        TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Details (optional)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Track app usage automatically'), value: autoTrack, onChanged: (bool value) => setDialogState(() => autoTrack = value)),
        if (autoTrack) ...<Widget>[
          TextField(controller: packages, maxLines: 3, decoration: const InputDecoration(labelText: 'Android package names', hintText: 'com.instagram.android\ncom.google.android.youtube'),),
          const Text('Enter one package name per line. Add app package IDs for social media or games you want tracked.', style: TextStyle(fontSize: 11)),
        ],
      ])),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        if (existing != null) TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
      ],
    )));
    if (saved == true && mounted) {
      final DistractionCategory category = DistractionCategory(
        id: existing?.id ?? newId(), name: name.text.trim(),
        severityPointsPerHour: double.tryParse(severity.text.trim().replaceAll(',', '.')) ?? 1,
        details: details.text.trim(), autoTrack: autoTrack,
        packageNames: packages.text.split('\n').map((String value) => value.trim()).where((String value) => value.isNotEmpty).toSet().toList(),
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      await _guard(() => ref.read(appDataProvider.notifier).saveDistractionCategory(category));
    }
    name.dispose(); severity.dispose(); details.dispose(); packages.dispose();
  }

  Future<void> _createDistractionLog(AppData data) async {
    if (data.distractionCategories.isEmpty) {
      _message('Create a distraction category first.');
      return;
    }
    String categoryId = data.distractionCategories.first.id;
    final TextEditingController duration = TextEditingController(text: '30');
    final TextEditingController note = TextEditingController();
    TimeOfDay time = _isToday ? TimeOfDay.now() : const TimeOfDay(hour: 12, minute: 0);
    final bool? saved = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
      title: const Text('Log distraction time'),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        DropdownButtonFormField<String>(value: categoryId, decoration: const InputDecoration(labelText: 'Category'), items: data.distractionCategories.map((DistractionCategory category) => DropdownMenuItem(value: category.id, child: Text(category.name))).toList(), onChanged: (String? value) { if (value != null) setDialogState(() => categoryId = value); }),
        TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration in minutes')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.schedule), title: const Text('Start time'), subtitle: Text(time.format(context)), onTap: () async { final TimeOfDay? value = await showTimePicker(context: context, initialTime: time); if (value != null) setDialogState(() => time = value); }),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        Align(alignment: Alignment.centerLeft, child: Text('Date: ${_dateLabel(_selectedDate)}', style: const TextStyle(fontSize: 12))),
      ]),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save log'))],
    )));
    if (saved == true && mounted) {
      final int? minutes = int.tryParse(duration.text.trim());
      if (minutes == null || minutes <= 0 || minutes > 1440) {
        _message('Enter a duration from 1 to 1440 minutes.');
      } else {
        final DateTime start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, time.hour, time.minute);
        await _guard(() => ref.read(appDataProvider.notifier).saveDistractionLog(DistractionLog(id: newId(), categoryId: categoryId, startAt: start, endAt: start.add(Duration(minutes: minutes)), details: note.text.trim())));
      }
    }
    duration.dispose(); note.dispose();
  }

  Future<void> _refreshUsage(AppData data, {bool showMessage = true}) async {
    if (!mounted) return;
    setState(() => _syncingUsage = true);
    try {
      final ProductivityUsageService service = ProductivityUsageService.instance;
      final bool permitted = await service.hasPermission();
      _usagePermission = permitted;
      if (!permitted) {
        await service.openSettings();
        if (mounted && showMessage) _message('Enable Usage Access for Tazkiyane, then return and tap Refresh app usage.');
        return;
      }
      final List<AppUsageRecord> records = await service.readUsageForDay(day: _selectedDate, categories: data.distractionCategories);
      await ref.read(appDataProvider.notifier).replaceAutomaticUsageForDate(_selectedDate, records);
      if (mounted && showMessage) _message('App usage refreshed for ${_dateLabel(_selectedDate)}.');
    } catch (error) {
      if (mounted && showMessage) _message('Usage tracking could not be refreshed: $error');
    } finally {
      if (mounted) setState(() => _syncingUsage = false);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try { await action(); } catch (error) { if (mounted) _message('$error'); }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppData> asyncData = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productivity'),
        actions: <Widget>[
          IconButton(tooltip: 'Choose date', onPressed: _chooseDate, icon: const Icon(Icons.calendar_month_outlined)),
          IconButton(tooltip: 'Settings', onPressed: () => _editTarget(asyncData.valueOrNull ?? const AppData()), icon: const Icon(Icons.tune_rounded)),
        ],
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(child: Text('$error')),
        data: (AppData data) => _buildContent(data),
      ),
    );
  }

  Widget _buildContent(AppData data) {
    final String selectedKey = _dateKey(_selectedDate);
    final DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final DateTime selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final bool hasAutoTrackedCategories = data.distractionCategories.any((DistractionCategory value) => value.autoTrack && value.packageNames.isNotEmpty);
    if (_usagePermission == true && hasAutoTrackedCategories && !selectedDay.isAfter(today) && _autoRefreshRequestedForDate != selectedKey) {
      _autoRefreshRequestedForDate = selectedKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dateKey(_selectedDate) == selectedKey) _refreshUsage(data, showMessage: false);
      });
    }
    final ProductivityEngine engine = const ProductivityEngine();
    final ProductivityDayScore score = engine.calculateDay(
      date: _selectedDate,
      target: data.targetForDate(_selectedDate),
      habits: data.habits,
      completions: data.completions,
      tasks: data.tasks,
      activities: data.taskActivities,
      progressEvents: data.taskProgressEvents,
      assignments: data.assignments,
      distractionCategories: data.distractionCategories,
      distractionLogs: data.distractionLogs,
      appUsageRecords: data.appUsageRecords,
    );
    final bool isHistoricalDate = selectedDay.isBefore(today);
    final List<RecommendedTask> recommendations = isHistoricalDate
        ? <RecommendedTask>[]
        : engine.recommendTasks(tasks: data.tasks, date: _selectedDate, remainingTarget: score.target - score.netScore);
    final List<DistractionLog> dayLogs = data.distractionLogs.where((DistractionLog log) => log.startAt.isBefore(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).add(const Duration(days: 1))) && log.endAt.isAfter(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))).toList();
    final List<AppUsageRecord> dayUsage = data.appUsageRecords.where((AppUsageRecord record) => record.startAt.isBefore(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).add(const Duration(days: 1))) && record.endAt.isAfter(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 32),
      children: <Widget>[
        _dateSelector(),
        const SizedBox(height: 12),
        _scoreCard(score, data),
        const SizedBox(height: 18),
        _historyStrip(data, engine),
        const SizedBox(height: 18),
        _contributionCard(score),
        const SizedBox(height: 18),
        _recommendationCard(recommendations, isHistoricalDate: isHistoricalDate),
        const SizedBox(height: 18),
        _assignmentCard(data),
        const SizedBox(height: 18),
        _distractionCard(data, dayLogs, dayUsage),
      ],
    );
  }

  Widget _dateSelector() => Row(children: <Widget>[
    IconButton(onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left_rounded)),
    Expanded(child: InkWell(onTap: _chooseDate, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: <Widget>[
      Text(_dateLabel(_selectedDate), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      Text(_isToday ? 'Today' : 'Selected date', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ])))),
    IconButton(onPressed: _dateKey(_selectedDate) == _dateKey(DateTime.now()) ? null : () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right_rounded)),
  ]);

  Widget _scoreCard(ProductivityDayScore score, AppData data) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[const Expanded(child: Text('Daily productivity score', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))), Text('${score.netScore.toStringAsFixed(1)} / ${score.target.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.gold))]),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: score.targetProgress, minHeight: 10, backgroundColor: AppColors.border, color: AppColors.gold)),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: _ScoreMetric(label: 'Earned', value: score.achievementPoints, icon: Icons.add_circle_outline, color: const Color(0xFF81C784))),
        Expanded(child: _ScoreMetric(label: 'Penalties', value: score.penaltyPoints, icon: Icons.remove_circle_outline, color: AppColors.danger)),
        Expanded(child: _ScoreMetric(label: 'Remaining', value: (score.target - score.netScore).clamp(0, double.infinity).toDouble(), icon: Icons.flag_outlined, color: AppColors.gold)),
      ]),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _editTarget(data), icon: const Icon(Icons.tune_rounded, size: 17), label: Text(data.productivityTargetOverrides.containsKey(_dateKey(_selectedDate)) ? 'Edit date target' : 'Change target'))),
      if (data.productivityTargetOverrides.containsKey(_dateKey(_selectedDate))) const Text('This date has a custom target override.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]),
  );

  Widget _historyStrip(AppData data, ProductivityEngine engine) {
    final DateTime today = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      const Text('Recent history', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 9),
      SizedBox(height: 74, child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[
        for (int i = 6; i >= 0; i--)
          Builder(builder: (BuildContext context) {
            final DateTime day = today.subtract(Duration(days: i));
            final ProductivityDayScore value = engine.calculateDay(date: day, target: data.targetForDate(day), habits: data.habits, completions: data.completions, tasks: data.tasks, activities: data.taskActivities, progressEvents: data.taskProgressEvents, assignments: data.assignments, distractionCategories: data.distractionCategories, distractionLogs: data.distractionLogs, appUsageRecords: data.appUsageRecords);
            final bool selected = _dateKey(day) == _dateKey(_selectedDate);
            return Padding(padding: const EdgeInsets.only(right: 7), child: InkWell(onTap: () => setState(() => _selectedDate = day), borderRadius: BorderRadius.circular(12), child: Container(width: 62, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5), decoration: BoxDecoration(color: selected ? AppColors.surfaceRaised : AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? AppColors.gold : AppColors.border)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(_month(day.month), style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              Text(value.netScore.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
            ]))));
          }),
      ])),
    ]);
  }

  Widget _contributionCard(ProductivityDayScore score) => _Panel(
    title: 'Score breakdown',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      const _Subheading('Achievements'),
      if (score.contributions.isEmpty) const _Muted('No achievement points recorded on this date.'),
      for (final ProductivityContribution value in score.contributions) _ContributionRow(value: value, positive: true),
      const Divider(height: 22),
      const _Subheading('Penalties'),
      if (score.penalties.isEmpty) const _Muted('No penalties recorded on this date.'),
      for (final ProductivityContribution value in score.penalties) _ContributionRow(value: value, positive: false),
      const SizedBox(height: 6),
      Text('Net score is clamped at zero; the full earned and penalty breakdown remains visible.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]),
  );

  Widget _recommendationCard(List<RecommendedTask> recommendations, {required bool isHistoricalDate}) => _Panel(
    title: 'Recommended tasks',
    trailing: IconButton(tooltip: 'Open tasks', onPressed: () => context.go(AppRoutes.tasks), icon: const Icon(Icons.open_in_new_rounded, size: 18)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (isHistoricalDate)
        const _Muted('Task recommendations are available for today and future dates. Historical dates show the recorded score only.'),
      if (!isHistoricalDate) ...<Widget>[
        const _Muted('Suggestions rank priority, deadline urgency, and how much each task can contribute toward your remaining target. Adding one to the schedule does not award points.'),
        const SizedBox(height: 10),
        if (recommendations.isEmpty) const _Muted('No eligible unscheduled or overdue tasks.'),
      ],
      for (final RecommendedTask item in recommendations.take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(item.reason, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          trailing: IconButton(tooltip: 'Schedule for ${_dateLabel(_selectedDate)}', onPressed: () async { await _guard(() => ref.read(appDataProvider.notifier).scheduleTaskForDate(item.task.id, _selectedDate)); _message('Added to ${_dateLabel(_selectedDate)} schedule.'); }, icon: const Icon(Icons.add_task_rounded, color: AppColors.gold)),
        ),
    ]),
  );

  Widget _assignmentCard(AppData data) {
    final List<Assignment> ordered = List<Assignment>.of(data.assignments)..sort((Assignment a, Assignment b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
    });
    return _Panel(
      title: 'Assignments',
      trailing: IconButton(tooltip: 'Add assignment', onPressed: _createAssignment, icon: const Icon(Icons.add_circle_outline_rounded)),
      child: Column(children: <Widget>[
        if (ordered.isEmpty) const _Muted('Create assignments and give each one its own point value.'),
        for (final Assignment assignment in ordered)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(value: assignment.isCompleted, onChanged: (bool? value) => _guard(() => ref.read(appDataProvider.notifier).saveAssignment(assignment.copyWith(isCompleted: value == true, completedAt: value == true ? (assignment.completedAt ?? DateTime.now()) : assignment.completedAt)))),
            title: Text(assignment.title, style: TextStyle(fontWeight: FontWeight.w600, decoration: assignment.isCompleted ? TextDecoration.lineThrough : null)),
            subtitle: Text('${assignment.difficultyScore.toStringAsFixed(1)} points${assignment.dueAt == null ? '' : ' · Due ${_dateLabel(assignment.dueAt!)}'}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onTap: () => _createAssignment(existing: assignment),
      trailing: PopupMenuButton<String>(onSelected: (String value) { if (value == 'edit') _createAssignment(existing: assignment); if (value == 'delete') _guard(() => ref.read(appDataProvider.notifier).deleteAssignment(assignment.id)); }, itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
          ),
      ]),
    );
  }

  Widget _distractionCard(AppData data, List<DistractionLog> dayLogs, List<AppUsageRecord> dayUsage) => _Panel(
    title: 'Distractions',
    trailing: PopupMenuButton<String>(onSelected: (String value) { if (value == 'category') _createCategory(); if (value == 'log') _createDistractionLog(data); }, itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'log', child: Text('Log distraction')), PopupMenuItem(value: 'category', child: Text('Manage categories')),
    ], child: const Icon(Icons.add_circle_outline_rounded)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('Automatic app usage', style: TextStyle(fontWeight: FontWeight.w600)),
          Text(_usagePermission == true ? 'Usage Access enabled' : 'Enable Android Usage Access to track selected apps', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ])),
        TextButton.icon(onPressed: _syncingUsage ? null : () => _refreshUsage(data), icon: _syncingUsage ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded, size: 17), label: const Text('Refresh')),
      ]),
      const SizedBox(height: 8),
      if (data.distractionCategories.isEmpty) const _Muted('Create a category with a severity value (points per hour). You can add Instagram, Facebook, YouTube or game package IDs for automatic monitoring.'),
      for (final DistractionCategory category in data.distractionCategories)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${category.severityPointsPerHour.toStringAsFixed(1)} penalty points/hour${category.autoTrack ? ' · ${category.packageNames.length} app package(s)' : ' · manual only'}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          trailing: IconButton(tooltip: 'Edit category', onPressed: () => _createCategory(existing: category), icon: const Icon(Icons.edit_outlined, size: 18)),
        ),
      const Divider(height: 18),
      Row(children: <Widget>[Expanded(child: Text('Manual logs · ${dayLogs.length}', style: const TextStyle(fontWeight: FontWeight.w700))), Text('${_minutes(dayLogs.fold<double>(0, (double sum, DistractionLog l) => sum + l.durationMinutes))} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
      for (final DistractionLog log in dayLogs)
        _LogRow(title: data.distractionCategories.where((DistractionCategory c) => c.id == log.categoryId).firstOrNull?.name ?? 'Category removed', subtitle: '${_timeLabel(log.startAt)} · ${log.durationMinutes.toStringAsFixed(0)} min', onDelete: () => _guard(() => ref.read(appDataProvider.notifier).deleteDistractionLog(log.id))),
      Row(children: <Widget>[Expanded(child: Text('Automatic usage · ${dayUsage.length} session(s)', style: const TextStyle(fontWeight: FontWeight.w700))), Text('${_minutes(dayUsage.fold<double>(0, (double sum, AppUsageRecord r) => sum + r.endAt.difference(r.startAt).inSeconds / 60))} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
      for (final AppUsageRecord record in dayUsage.take(8))
        Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: <Widget>[Expanded(child: Text(record.packageName, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))), Text('${(record.endAt.difference(record.startAt).inMinutes)} min', style: const TextStyle(fontSize: 12))])),
      const SizedBox(height: 6),
      const _Muted('Manual and automatic time intervals are merged across categories; overlapping time is charged once at the highest active severity.'),
    ]),
  );

  int _minutes(double value) => value.round();
  String _timeLabel(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Row(children: <Widget>[Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), if (trailing != null) trailing!]),
    const SizedBox(height: 8), child,
  ]));
}

class _ScoreMetric extends StatelessWidget {
  const _ScoreMetric({required this.label, required this.value, required this.icon, required this.color});
  final String label; final double value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[Icon(icon, size: 16, color: color), const SizedBox(width: 5), Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)), Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 10))]))]);
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.value, required this.positive});
  final ProductivityContribution value; final bool positive;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: <Widget>[
    Icon(positive ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 16, color: positive ? const Color(0xFF81C784) : AppColors.danger),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(value.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text('${value.kind} · ${value.detail}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary))])),
    Text('${positive ? '+' : '-'}${value.points.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: positive ? const Color(0xFF81C784) : AppColors.danger)),
  ]));
}

class _Subheading extends StatelessWidget { const _Subheading(this.text); final String text; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))); }
class _Muted extends StatelessWidget { const _Muted(this.text); final String text; @override Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.35)); }
class _LogRow extends StatelessWidget { const _LogRow({required this.title, required this.subtitle, required this.onDelete}); final String title; final String subtitle; final VoidCallback onDelete; @override Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(title, style: const TextStyle(fontSize: 12)), subtitle: Text(subtitle, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)), trailing: IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded, size: 17))); }

extension _FirstOrNullProductivity<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
