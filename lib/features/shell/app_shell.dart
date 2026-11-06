import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../shared/widgets/widgets.dart';
import '../../shared/utils/modal_navigation.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: TickoffBottomBar(
        currentIndex: navigationShell.currentIndex,
        onSelect: (int index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        onAdd: () async {
          await _showCreateMenu(context);
        },
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    // Wait for the actual route transition to finish before pushing the form.
    final String? choice = await showModalBottomSheetAndWait<String>(
      context: context,
      backgroundColor: const Color(0xFF202126),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Create new',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: const Text('Add Habit'),
                onTap: () => Navigator.pop(sheetContext, 'habit'),
              ),
              ListTile(
                leading: const Icon(Icons.task_alt_rounded),
                title: const Text('Add Task'),
                onTap: () => Navigator.pop(sheetContext, 'task'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'habit':
        context.push(AppRoutes.habitNew);
        return;
      case 'task':
        context.push(AppRoutes.taskNew);
        return;
    }
  }
}
