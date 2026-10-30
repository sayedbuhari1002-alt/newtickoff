import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';

class RearrangeScreen extends ConsumerStatefulWidget {
  const RearrangeScreen({super.key});

  @override
  ConsumerState<RearrangeScreen> createState() => _RearrangeScreenState();
}

class _RearrangeScreenState extends ConsumerState<RearrangeScreen> {
  List<String>? _workingOrder;
  bool _saving = false;

  static const Map<String, IconData> _icons = <String, IconData>{
    'progress': Icons.donut_large_rounded,
    'tasks': Icons.task_alt_rounded,
    'habits': Icons.repeat_rounded,
    'insights': Icons.insights_rounded,
  };

  Future<void> _saveOrder(List<String> order) async {
    setState(() {
      _workingOrder = List<String>.of(order);
      _saving = true;
    });
    try {
      await ref.read(appDataProvider.notifier).saveSetting(
        AppSettingKeys.dashboardOrder,
        jsonEncode(order),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _workingOrder = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save section order: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> settings =
        ref.watch(appDataProvider).valueOrNull?.settings ?? const <String, String>{};
    final List<String> persistedOrder = dashboardSectionOrder(settings);
    final List<String> order = _workingOrder ?? persistedOrder;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rearrange'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Restore default order',
            onPressed: _saving ? null : () => _saveOrder(List<String>.of(dashboardSectionIds)),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Text(
              'Drag sections into the order you prefer. The Dashboard will use this order.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              itemCount: order.length,
              onReorder: (int oldIndex, int newIndex) {
                final List<String> updated = List<String>.of(order);
                if (newIndex > oldIndex) newIndex--;
                final String section = updated.removeAt(oldIndex);
                updated.insert(newIndex, section);
                _saveOrder(updated);
              },
              itemBuilder: (BuildContext context, int index) {
                final String id = order[index];
                return Container(
                  key: ValueKey<String>(id),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: Icon(_icons[id], color: AppColors.textSecondary),
                    title: Text(dashboardSectionLabels[id]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Position ${index + 1}', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                    trailing: const Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
