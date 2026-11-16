import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';
import 'lib/database_lock_fix.dart';
import 'lib/database_helper.dart';

/// Test script to verify database lock fixes
/// Run this with: flutter run test_database_fix.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('=== Database Lock Fix Test ===');
  debugPrint('Testing database connectivity and lock prevention...\n');

  try {
    // Test 1: Basic connectivity
    debugPrint('1. Testing basic database connectivity...');
    final dbHelper = DatabaseHelper();
    final isConnected = await dbHelper.isDatabaseConnected();
    debugPrint('   Result: ${isConnected ? 'CONNECTED' : 'FAILED'}');

    if (!isConnected) {
      debugPrint('   Attempting quick fix...');
      final fixed = await DatabaseLockFix.quickFix();
      debugPrint('   Quick fix: ${fixed ? 'SUCCESS' : 'FAILED'}');
    }

    // Test 2: Run full diagnostics
    debugPrint('\n2. Running full database diagnostics...');
    final diagnostics = await DatabaseLockFix.diagnoseAndFix();
    debugPrint('   Overall status: ${diagnostics['overall_status']}');

    if (diagnostics['tests'] != null) {
      debugPrint('   Test results:');
      diagnostics['tests'].forEach((testName, result) {
        if (result is Map && result.containsKey('status')) {
          debugPrint(
              '     - $testName: ${result['status']} (${result['time_ms'] ?? 'N/A'}ms)');
        }
      });
    }

    if (diagnostics['recommendations'] != null &&
        diagnostics['recommendations'].isNotEmpty) {
      debugPrint('   Recommendations:');
      for (final rec in diagnostics['recommendations']) {
        debugPrint('     - $rec');
      }
    }

    // Test 3: WAL mode
    debugPrint('\n3. Testing WAL mode...');
    final walEnabled = await DatabaseLockFix.enableWALMode();
    debugPrint('   WAL mode: ${walEnabled ? 'ENABLED' : 'FAILED'}');

    // Test 4: Concurrent access simulation
    debugPrint('\n4. Testing concurrent database access...');
    final futures = List.generate(5, (index) async {
      try {
        final db = await dbHelper.database;
        final result = await db
            .rawQuery('SELECT $index as test_id, datetime("now") as timestamp')
            .timeout(const Duration(seconds: 3));
        return 'Query $index: SUCCESS (${result.first['timestamp']})';
      } catch (e) {
        return 'Query $index: FAILED ($e)';
      }
    });

    final results = await Future.wait(futures);
    for (final result in results) {
      debugPrint('   $result');
    }

    debugPrint('\n=== Test Complete ===');
    debugPrint(
        'If you see any FAILED results, the database lock issue may still exist.');
    debugPrint('Try restarting the app or running the quick fix again.');
  } catch (e) {
    debugPrint('ERROR: Test failed with exception: $e');
  }
}
