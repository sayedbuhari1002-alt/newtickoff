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
    // Wait for the modal route's reverse transition to finish before pushing
    // another route. Pushing during Navigator.pop can leave the sheet above
    // the new page in the route stack and cause the next pop to close the sheet
    // instead of the page the user intended to leave.
    final String? choice = await showModalBottomSheet<String>(
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
    await waitForModalDismissal();
    if (!context.mounted) return;
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
