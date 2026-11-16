// fix_local_database_column.dart
// Quick fix to add the missing assessorExpiryDate column to local database

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'lib/utils/clocking_logger.dart';

Future<void> fixLocalDatabaseColumn() async {
  final logger = ClockingLogger.instance;
  await logger.initialize();

  try {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'local_data.db');

    final database = await openDatabase(path);

    await logger.logDatabaseOperation('CHECK_COLUMN', 'facilitator', 'SYSTEM',
        {'action': 'Checking if assessorExpiryDate column exists'});

    // Check if column exists
    final result = await database.rawQuery("PRAGMA table_info(facilitator)");
    bool columnExists = false;

    for (final row in result) {
      if (row['name'] == 'assessorExpiryDate') {
        columnExists = true;
        break;
      }
    }

    if (!columnExists) {
      await logger.logDatabaseOperation('ADD_COLUMN', 'facilitator', 'SYSTEM',
          {'column': 'assessorExpiryDate', 'type': 'TEXT'});
      await database.execute(
          'ALTER TABLE facilitator ADD COLUMN assessorExpiryDate TEXT');
      await logger.logDatabaseOperation('ADD_COLUMN_SUCCESS', 'facilitator',
          'SYSTEM', {'result': 'Column added successfully'});
    } else {
      await logger.logDatabaseOperation('COLUMN_EXISTS', 'facilitator',
          'SYSTEM', {'result': 'Column already exists'});
    }

    // Verify the column was added
    final verifyResult =
        await database.rawQuery("PRAGMA table_info(facilitator)");
    final columns =
        verifyResult.map((row) => '${row['name']} (${row['type']})').toList();
    await logger.logDatabaseOperation(
        'VERIFY_COLUMNS', 'facilitator', 'SYSTEM', {'columns': columns});

    await database.close();
    await logger.logDatabaseOperation('FIX_COMPLETE', 'facilitator', 'SYSTEM',
        {'result': 'Database fix completed'});
  } catch (e) {
    await logger.logError('DB_COLUMN_FIX', e);
  }
}

void main() async {
  await fixLocalDatabaseColumn();
}

/*
To run this fix:
1. Add this file to your Flutter project
2. Run: flutter run fix_local_database_column.dart
3. Or call fixLocalDatabaseColumn() from your app

This will add the missing assessorExpiryDate column to your local database.
*/
