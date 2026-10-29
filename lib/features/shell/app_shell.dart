import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../shared/widgets/widgets.dart';

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
        onAdd: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF202126),
          builder: (BuildContext sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Text('Create new', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                ListTile(leading: const Icon(Icons.check_circle_outline_rounded), title: const Text('Add Habit'), onTap: () { Navigator.pop(sheetContext); context.push(AppRoutes.habitNew); }),
                ListTile(leading: const Icon(Icons.task_alt_rounded), title: const Text('Add Task'), onTap: () { Navigator.pop(sheetContext); context.push(AppRoutes.taskNew); }),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
