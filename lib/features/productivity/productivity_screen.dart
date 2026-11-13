import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/ids.dart';
import '../../data/services/productivity_usage_service.dart';
import '../../domain/logic/productivity_engine.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_settings.dart';
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
  Map<String, String> _installedAppLabels = <String, String>{};
  String? _autoRefreshRequestedForDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUsagePermission();
    _loadInstalledAppLabels();
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
      _loadInstalledAppLabels();
    }
  }

  Future<void> _loadInstalledAppLabels() async {
    try {
      final List<InstalledApp> apps = await ProductivityUsageService.instance.getInstalledApps();
      if (!mounted) return;
      setState(() {
        _installedAppLabels = <String, String>{
          for (final InstalledApp app in apps) app.packageName: app.label,
        };
      });
    } catch (_) {
      // Manual distraction logging remains available if app visibility is unavailable.
    }
  }

  Future<void> _loadUsagePermission() async {
    final bool permitted = await ProductivityUsageService.instance.hasPermission();
    if (mounted) setState(() => _usagePermission = permitted);
  }

  DateTime? _scoringModelStartDate(AppData data) {
    final String? stored = data.settings[AppSettingKeys.productivityScoringStartDate];
    final DateTime? parsed = stored == null ? null : DateTime.tryParse(stored);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _dateLabel(DateTime date) => '${date.day} ${_month(date.month)} ${date.year}';
  String _month(int month) => const <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];

  String _distractionCategorySubtitle(DistractionCategory category) {
    final String severity = '${category.severityPointsPerHour.toStringAsFixed(1)} penalty points/hour';
    if (!category.autoTrack) return '$severity · manual only';
    final List<String> limits = category.packageNames.map((String packageName) {
      final String appName = _installedAppLabels[packageName] ?? packageName;
      final int minutes = category.dailyAllowanceMinutesByPackage[packageName] ?? 0;
      return '$appName: $minutes min/day free';
    }).toList();
    return '$severity · ${limits.join(' · ')}';
  }
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

  Future<({List<InstalledApp> apps, Set<String> selected})?> _chooseInstalledApps(
    Set<String> currentSelection,
  ) async {
    List<InstalledApp> apps;
    try {
      apps = await ProductivityUsageService.instance.getInstalledApps();
    } catch (error) {
      if (mounted) _message('Could not load installed apps: $error');
      return null;
    }
    if (apps.isEmpty) {
      if (mounted) _message('No installed apps were found on this device.');
      return null;
    }

    final TextEditingController search = TextEditingController();
    final Set<String> selected = Set<String>.of(currentSelection);
    String query = '';
    final Set<String>? result = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final List<InstalledApp> visible = apps.where((InstalledApp app) {
            return app.label.toLowerCase().contains(query.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Choose distracting apps'),
            content: SizedBox(
              width: 420,
              height: MediaQuery.sizeOf(context).height * 0.58,
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search installed apps',
                    ),
                    onChanged: (String value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${selected.length} selected',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final InstalledApp app = visible[index];
                        final bool checked = selected.contains(app.packageName);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.apps_rounded),
                          title: Text(app.label),
                          value: checked,
                          onChanged: (bool? value) => setDialogState(() {
                            if (value == true) {
                              selected.add(app.packageName);
                            } else {
                              selected.remove(app.packageName);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => setDialogState(selected.clear),
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('Use selected apps'),
              ),
            ],
          );
        },
      ),
    );
    search.dispose();
    if (result == null) return null;
    return (apps: apps, selected: result);
  }

  Future<void> _createCategory({DistractionCategory? existing}) async {
    final TextEditingController name = TextEditingController(text: existing?.name ?? '');
    final TextEditingController severity = TextEditingController(text: (existing?.severityPointsPerHour ?? 1.0).toString());
    final TextEditingController details = TextEditingController(text: existing?.details ?? '');
    Set<String> selectedPackages = Set<String>.of(existing?.packageNames ?? const <String>[]);
    final Map<String, TextEditingController> allowanceControllers = <String, TextEditingController>{
      for (final String packageName in selectedPackages)
        packageName: TextEditingController(
          text: (existing?.dailyAllowanceMinutesByPackage[packageName] ?? 30).toString(),
        ),
    };
    List<InstalledApp> selectedAppCatalog = <InstalledApp>[];
    if (selectedPackages.isNotEmpty) {
      try {
        selectedAppCatalog = await ProductivityUsageService.instance.getInstalledApps();
      } catch (_) {
        // The existing category remains editable even if the app list is unavailable.
      }
    }
    bool autoTrack = existing?.autoTrack ?? false;
    final bool? saved = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
      title: Text(existing == null ? 'Distraction category' : 'Edit category'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Category name')),
        TextField(controller: severity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Distraction penalty (points per hour)')),
        TextField(controller: details, maxLines: 2, decoration: const InputDecoration(labelText: 'Details (optional)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Track app usage automatically'), value: autoTrack, onChanged: (bool value) => setDialogState(() => autoTrack = value)),
        if (autoTrack) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () async {
              final ({List<InstalledApp> apps, Set<String> selected})? result =
                  await _chooseInstalledApps(selectedPackages);
              if (result != null) {
                for (final String packageName in result.selected) {
                  allowanceControllers.putIfAbsent(
                    packageName,
                    () => TextEditingController(text: '30'),
                  );
                }
                setDialogState(() {
                  selectedAppCatalog = result.apps;
                  selectedPackages = result.selected;
                });
              }
            },
            icon: const Icon(Icons.apps_rounded),
            label: Text('Choose installed apps (${selectedPackages.length} selected)'),
          ),
          if (selectedPackages.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Daily free usage allowance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(height: 3),
            Text(
              'Set a separate daily limit for each app. Penalties apply only to usage beyond the limit. Enter 0 for no free allowance.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            ...selectedPackages.map((String packageName) {
              final InstalledApp? app = selectedAppCatalog
                  .where((InstalledApp item) => item.packageName == packageName)
                  .firstOrNull;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        app?.label ?? packageName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 94,
                      child: TextField(
                        controller: allowanceControllers[packageName],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          labelText: 'Limit',
                          suffixText: 'min',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove app',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setDialogState(() => selectedPackages.remove(packageName)),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
          Text('Choose the apps you want Tazkiyane to count as distractions. Only apps with an icon in your app drawer are listed.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ])),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        if (existing != null) TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
      ],
    )));
    if (saved == true && mounted) {
      final Map<String, int> allowances = <String, int>{};
      String? allowanceProblem;
      for (final String packageName in (autoTrack ? selectedPackages : <String>{})) {
        final int? minutes = int.tryParse(allowanceControllers[packageName]?.text.trim() ?? '30');
        if (minutes == null || minutes < 0 || minutes > 1440) {
          allowanceProblem = 'Enter a daily allowance from 0 to 1440 minutes for every selected app.';
          break;
        }
        allowances[packageName] = minutes;
      }
      if (allowanceProblem != null) {
        _message(allowanceProblem);
      } else {
        final DistractionCategory category = DistractionCategory(
          id: existing?.id ?? newId(), name: name.text.trim(),
          severityPointsPerHour: double.tryParse(severity.text.trim().replaceAll(',', '.')) ?? 1,
          details: details.text.trim(), autoTrack: autoTrack,
          packageNames: selectedPackages.toList()..sort(),
          dailyAllowanceMinutesByPackage: allowances,
          createdAt: existing?.createdAt ?? DateTime.now(),
        );
        await _guard(() => ref.read(appDataProvider.notifier).saveDistractionCategory(category));
      }
    }
    name.dispose(); severity.dispose(); details.dispose();
    for (final TextEditingController controller in allowanceControllers.values) {
      controller.dispose();
    }
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
      final UsageDayResult usage = await service.readUsageForDay(day: _selectedDate, categories: data.distractionCategories);
      await ref.read(appDataProvider.notifier).replaceAutomaticUsageForDate(
        _selectedDate,
        usage.sessions,
        dailyTotals: usage.dailyTotals,
      );
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
    final DateTime selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
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
      assignments: const <Assignment>[],
      distractionCategories: data.distractionCategories,
      distractionLogs: data.distractionLogs,
      appUsageRecords: data.appUsageRecords,
      currentStateScoringStartDate: _scoringModelStartDate(data),
    );
    final List<DistractionLog> dayLogs = data.distractionLogs.where((DistractionLog log) => log.startAt.isBefore(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).add(const Duration(days: 1))) && log.endAt.isAfter(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))).toList();
    final List<AppUsageRecord> dayUsage = data.appUsageRecords.where((AppUsageRecord record) => record.startAt.isBefore(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).add(const Duration(days: 1))) && record.endAt.isAfter(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))).toList();
    final String selectedDateKey = _dateKey(_selectedDate);
    final List<AppUsageDailyTotal> dayUsageTotals = data.appUsageDailyTotals.where((AppUsageDailyTotal total) => total.dateKey == selectedDateKey).toList()
      ..sort((AppUsageDailyTotal a, AppUsageDailyTotal b) => b.displayMillis.compareTo(a.displayMillis));
    final ProductivityDayScore todayScore = _isToday
        ? score
        : engine.calculateDay(
            date: today,
            target: data.targetForDate(today),
            habits: data.habits,
            completions: data.completions,
            tasks: data.tasks,
            activities: data.taskActivities,
            progressEvents: data.taskProgressEvents,
            assignments: const <Assignment>[],
            distractionCategories: data.distractionCategories,
            distractionLogs: data.distractionLogs,
            appUsageRecords: data.appUsageRecords,
            currentStateScoringStartDate: _scoringModelStartDate(data),
          );
    final List<RecommendedTask> suggestedTasks = engine.recommendTasks(
      tasks: data.tasks,
      date: today,
      remainingTarget: (todayScore.target - todayScore.netScore).clamp(0, double.infinity).toDouble(),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 32),
      children: <Widget>[
        _dateSelector(),
        const SizedBox(height: 12),
        _scoreCard(score, data),
        const SizedBox(height: 14),
        _suggestedNextCard(context, suggestedTasks),
        const SizedBox(height: 18),
        _historyStrip(data, engine),
        const SizedBox(height: 18),
        _contributionCard(score),
        const SizedBox(height: 18),
        _distractionCard(data, dayLogs, dayUsage, dayUsageTotals),
      ],
    );
  }

  Widget _suggestedNextCard(
    BuildContext context,
    List<RecommendedTask> recommendations,
  ) => _Panel(
        title: 'Suggested Next',
        child: recommendations.isEmpty
            ? const _Muted(
                'No upcoming or unscheduled tasks to suggest. New recommendations appear when you add tasks or change their dates.',
              )
            : Column(
                children: <Widget>[
                  for (int index = 0; index < recommendations.length; index++) ...<Widget>[
                    if (index > 0) const Divider(height: 12),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.accentDim,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          recommendations[index].task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          recommendations[index].reason,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(
                          AppRoutes.taskDetail(recommendations[index].task.id),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      );

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
      Row(children: <Widget>[const Expanded(child: Text('Daily productivity score', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))), Text('${score.netScore.toStringAsFixed(1)} / ${score.target.toStringAsFixed(1)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.gold))]),
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
      if (data.productivityTargetOverrides.containsKey(_dateKey(_selectedDate))) Text('This date has a custom target override.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
            final ProductivityDayScore value = engine.calculateDay(date: day, target: data.targetForDate(day), habits: data.habits, completions: data.completions, tasks: data.tasks, activities: data.taskActivities, progressEvents: data.taskProgressEvents, assignments: const <Assignment>[], distractionCategories: data.distractionCategories, distractionLogs: data.distractionLogs, appUsageRecords: data.appUsageRecords, currentStateScoringStartDate: _scoringModelStartDate(data));
            final bool selected = _dateKey(day) == _dateKey(_selectedDate);
            return Padding(padding: const EdgeInsets.only(right: 7), child: InkWell(onTap: () => setState(() => _selectedDate = day), borderRadius: BorderRadius.circular(12), child: Container(width: 62, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5), decoration: BoxDecoration(color: selected ? AppColors.surfaceRaised : AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? AppColors.gold : AppColors.border)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(_month(day.month), style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              Text(value.netScore.toStringAsFixed(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
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

  Widget _distractionCard(
    AppData data,
    List<DistractionLog> dayLogs,
    List<AppUsageRecord> dayUsage,
    List<AppUsageDailyTotal> dayUsageTotals,
  ) => _Panel(
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
      if (data.distractionCategories.isEmpty) const _Muted('Create a distraction category, then choose installed apps to monitor automatically. You can also record distraction time manually.'),
      for (final DistractionCategory category in data.distractionCategories)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            _distractionCategorySubtitle(category),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          trailing: IconButton(tooltip: 'Edit category', onPressed: () => _createCategory(existing: category), icon: const Icon(Icons.edit_outlined, size: 18)),
        ),
      const Divider(height: 18),
      Row(children: <Widget>[Expanded(child: Text('Manual logs · ${dayLogs.length}', style: const TextStyle(fontWeight: FontWeight.w700))), Text('${_minutes(dayLogs.fold<double>(0, (double sum, DistractionLog l) => sum + l.durationMinutes))} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
      for (final DistractionLog log in dayLogs)
        _LogRow(title: data.distractionCategories.where((DistractionCategory c) => c.id == log.categoryId).firstOrNull?.name ?? 'Category removed', subtitle: '${_timeLabel(log.startAt)} · ${log.durationMinutes.toStringAsFixed(0)} min', onDelete: () => _guard(() => ref.read(appDataProvider.notifier).deleteDistractionLog(log.id))),
      if (dayUsageTotals.isNotEmpty) ...<Widget>[
        Builder(builder: (BuildContext context) {
          final bool nativeAvailable = dayUsageTotals.every((AppUsageDailyTotal total) => total.nativeStatsAvailable);
          final int androidTotal = dayUsageTotals.fold<int>(0, (int sum, AppUsageDailyTotal total) => sum + total.androidForegroundMillis);
          final int reconstructedTotal = dayUsageTotals.fold<int>(0, (int sum, AppUsageDailyTotal total) => sum + total.reconstructedMillis);
          final int shownTotal = nativeAvailable ? androidTotal : reconstructedTotal;
          final int sessionCount = dayUsage.length;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Text(nativeAvailable ? 'Android daily usage · ${dayUsageTotals.length} app(s)' : 'Session estimate · ${dayUsageTotals.length} app(s)', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${(shownTotal / 60000).round()} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(
              nativeAvailable
                  ? 'Session reconstruction: ${(reconstructedTotal / 60000).round()} min across $sessionCount session(s) · Difference: ${((androidTotal - reconstructedTotal) / 60000).round()} min'
                  : 'Android daily aggregate is unavailable. Showing the reconstructed session estimate.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final AppUsageDailyTotal total in dayUsageTotals.where((AppUsageDailyTotal value) => value.displayMillis > 0 || value.reconstructedMillis > 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: <Widget>[
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(_installedAppLabels[total.packageName] ?? total.packageName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(
                      total.nativeStatsAvailable
                          ? 'Android: ${(total.androidForegroundMillis / 60000).round()} min · Sessions: ${(total.reconstructedMillis / 60000).round()} min · Δ ${((total.discrepancyMillis) / 60000).round()} min'
                          : 'Session events: ${(total.reconstructedMillis / 60000).round()} min',
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ])),
                  Text('${(total.displayMillis / 60000).round()} min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]);
        }),
      ] else ...<Widget>[
        Row(children: <Widget>[Expanded(child: Text('Automatic usage · ${dayUsage.length} session(s)', style: const TextStyle(fontWeight: FontWeight.w700))), Text('${_minutes(dayUsage.fold<double>(0, (double sum, AppUsageRecord r) => sum + r.endAt.difference(r.startAt).inSeconds / 60))} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
        const _Muted('Refresh app usage to compare the session timeline with Android daily totals.'),
      ],
      const SizedBox(height: 6),
      const _Muted('Android daily totals are the screen-time reference. Timestamped foreground sessions remain the input to overlap-aware productivity scoring; background time must not be counted as an app session.'),
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
