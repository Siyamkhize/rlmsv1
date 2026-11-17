import 'package:flutter/foundation.dart';
// Quick test to verify methods exist
import 'lib/database_helper.dart';

void main() async {
  final db = DatabaseHelper();

  // Test 1: getUnsyncedPOE
  debugPrint('Testing getUnsyncedPOE...');
  final unsynced = await db.getUnsyncedPOE(123);
  debugPrint('✓ getUnsyncedPOE works: ${unsynced.length} records');

  // Test 2: saveLearnerPathwaysCache
  debugPrint('Testing saveLearnerPathwaysCache...');
  await db.saveLearnerPathwaysCache(123, {'test': 'data'});
  debugPrint('✓ saveLearnerPathwaysCache works');

  // Test 3: getLearnerPathwaysCache
  debugPrint('Testing getLearnerPathwaysCache...');
  final cache = await db.getLearnerPathwaysCache(123);
  debugPrint('✓ getLearnerPathwaysCache works: ${cache != null}');

  debugPrint('\n✅ All methods exist and are callable!');
}
