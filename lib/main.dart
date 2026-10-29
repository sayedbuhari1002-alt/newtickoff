import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'data/database/app_database.dart';
import 'data/services/task_reminder_service.dart';
import 'data/repositories/sqlite_app_repository.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TaskReminderService.instance.initialise();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    final Database db = await AppDatabase.open();
    runApp(
      ProviderScope(
        overrides: <Override>[
          repositoryProvider.overrideWithValue(SqliteAppRepository(db)),
        ],
        child: const TickOffApp(),
      ),
    );
  } catch (e) {
    runApp(StartupErrorApp(message: '$e'));
  }
}
