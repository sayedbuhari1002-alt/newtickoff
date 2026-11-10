import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../tasks/task_analytics_screen.dart';
import 'analytics_screen.dart';
import 'productivity_analytics_tab.dart';

/// Single Analytics destination containing the existing habit and task
/// analytics plus productivity-score trends.
class UnifiedAnalyticsScreen extends StatelessWidget {
  const UnifiedAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Analytics'),
            bottom: TabBar(
              isScrollable: false,
              indicatorColor: AppColors.gold,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const <Widget>[
                Tab(text: 'Tasks', icon: Icon(Icons.task_alt_rounded)),
                Tab(text: 'Productivity', icon: Icon(Icons.insights_rounded)),
                Tab(text: 'Habits', icon: Icon(Icons.repeat_rounded)),
              ],
            ),
          ),
          body: const TabBarView(
            children: <Widget>[
              TaskAnalyticsScreen(embedded: true),
              ProductivityAnalyticsTab(),
              AnalyticsScreen(embedded: true),
            ],
          ),
        ),
      );
}
