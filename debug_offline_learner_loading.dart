// Debug script to test offline learner loading
// Run this from your main.dart or as a separate test

import 'package:flutter/material.dart';
import 'lib/database_helper.dart';

class DebugOfflineLearnerLoading extends StatelessWidget {
  final String classID = '134'; // Your class ID

  const DebugOfflineLearnerLoading({super.key});

  Future<void> debugLearnerLoading(BuildContext context) async {
    final dbHelper = DatabaseHelper();
    
    // Test 1: Check if database exists and is accessible
    try {
      final db = await dbHelper.database;
      debugPrint('✅ Database connection successful');
      
      // Test 2: Check if learnerdetails table has data
      final allLearners = await db.query('learnerdetails');
      debugPrint('📊 Total learners in database: ${allLearners.length}');
      
      // Test 3: Check learners for specific class
      final classLearners = await db.query('learnerdetails', where: 'classID = ?', whereArgs: [classID]);
      debugPrint('👥 Learners in class $classID: ${classLearners.length}');
      
      if (classLearners.isNotEmpty) {
        debugPrint('📋 Sample learners in class $classID:');
        for (int i = 0; i < classLearners.take(3).length; i++) {
          final learner = classLearners[i];
          debugPrint('   - ID: ${learner['LearnerID']}, Name: ${learner['Name']} ${learner['Surname']}');
        }
      }
      
      // Test 4: Check the exact query used by getLearnersWithClockingData
      final currentDate = DateTime.now().toUtc().add(const Duration(hours: 2));
      final dateString = '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
      
      debugPrint('📅 Checking for date: $dateString');
      
      final result = await db.rawQuery('''
        SELECT 
          l.LearnerID, 
          l.Name, 
          l.Surname,
          l.IDNumber,
          l.classID,
          lc.clock_in_time, 
          lc.clock_out_time,
          lc.contact_time
        FROM learnerdetails l
        LEFT JOIN (
          SELECT LearnerID, clock_date, 
                 MIN(clock_in_time) as clock_in_time, 
                 MAX(clock_out_time) as clock_out_time,
                 MAX(contact_time) as contact_time
          FROM learner_clocking
          WHERE clock_date = ?
          GROUP BY LearnerID
        ) lc ON l.LearnerID = lc.LearnerID 
        WHERE l.classID = ?
      ''', [dateString, classID]);
      
      debugPrint('🔍 Query result: ${result.length} learners found');
      
      if (result.isNotEmpty) {
        debugPrint('📋 Sample results:');
        for (int i = 0; i < result.take(3).length; i++) {
          final learner = result[i];
          debugPrint('   - ID: ${learner['LearnerID']}, Name: ${learner['Name']} ${learner['Surname']}, Clock In: ${learner['clock_in_time']}');
        }
      }
      
      // Test 5: Check learner_clocking table
      final clockingRecords = await db.query('learner_clocking', where: 'clock_date = ?', whereArgs: [dateString]);
      debugPrint('⏰ Clocking records for today: ${clockingRecords.length}');
      
      // Test 6: Check if classID in database matches what we're searching for
      final distinctClasses = await db.rawQuery('SELECT DISTINCT classID FROM learnerdetails ORDER BY classID');
      debugPrint('📚 All class IDs in database: ${distinctClasses.map((c) => c['classID']).toList()}');
      
    } catch (e) {
      debugPrint('❌ Database error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Offline Learner Loading')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => debugLearnerLoading(context),
          child: const Text('Run Debug Test'),
        ),
      ),
    );
  }
}