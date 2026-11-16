import 'database_helper.dart';

class CompleteDatabaseInspector {
  static final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Complete database inspection - shows everything
  static Future<void> inspectEntireDatabase() async {
    try {
      debugPrint('');
      debugPrint('██████████████████████████████████████████████████████████████████');
      debugPrint('█                 COMPLETE DATABASE INSPECTION                  █');
      debugPrint('██████████████████████████████████████████████████████████████████');
      debugPrint('');

      final db = await _dbHelper.database;

      // 1. Show all tables
      debugPrint('📋 STEP 1: ALL TABLES IN DATABASE');
      debugPrint('▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      );
      
      if (tables.isEmpty) {
        debugPrint('❌ NO TABLES FOUND IN DATABASE!');
        return;
      }

      debugPrint('Found ${tables.length} tables:');
      for (int i = 0; i < tables.length; i++) {
        final tableName = tables[i]['name'] as String;
        
        // Get row count for each table
        try {
          final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM `$tableName`');
          final rowCount = countResult.first['count'] as int;
          debugPrint('  ${i + 1}. $tableName ($rowCount rows)');
        } catch (e) {
          debugPrint('  ${i + 1}. $tableName (error counting: $e)');
        }
      }
      debugPrint('');

      // 2. Focus on manual_clocking_evidence table
      debugPrint('🔍 STEP 2: MANUAL CLOCKING EVIDENCE TABLE DETAILS');
      debugPrint('▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔');
      
      final evidenceTableExists = tables.any((table) => table['name'] == 'manual_clocking_evidence');
      
      if (!evidenceTableExists) {
        debugPrint('❌ manual_clocking_evidence table does NOT exist!');
        debugPrint('💡 This table should be created when manual clocking is first used.');
        
        // Check if the creation SQL files exist
        debugPrint('');
        debugPrint('📄 Checking table creation files...');
        // This would need file system access to check for SQL files
      } else {
        debugPrint('✅ manual_clocking_evidence table EXISTS');
        
        // Get table schema
        try {
          final schema = await db.rawQuery("PRAGMA table_info(manual_clocking_evidence)");
          debugPrint('');
          debugPrint('📊 Table Schema:');
          for (final column in schema) {
            final name = column['name'];
            final type = column['type'];
            final notNull = column['notnull'] == 1 ? 'NOT NULL' : 'nullable';
            final defaultValue = column['dflt_value'] ?? 'no default';
            final pk = column['pk'] == 1 ? ' (PRIMARY KEY)' : '';
            debugPrint('   • $name: $type - $notNull - default: $defaultValue$pk');
          }
        } catch (e) {
          debugPrint('❌ Error getting table schema: $e');
        }

        // Get all data from manual_clocking_evidence
        try {
          final evidenceData = await db.query('manual_clocking_evidence', orderBy: 'evidence_id DESC');
          debugPrint('');
          debugPrint('📋 ALL DATA IN manual_clocking_evidence (${evidenceData.length} records):');
          
          if (evidenceData.isEmpty) {
            debugPrint('   ⚠️  TABLE IS EMPTY - No manual clocking evidence recorded yet');
          } else {
            for (int i = 0; i < evidenceData.length; i++) {
              final record = evidenceData[i];
              debugPrint('');
              debugPrint('   ╔═══════════════ RECORD ${i + 1}/${evidenceData.length} ═══════════════╗');
              debugPrint('   ║ Evidence ID: ${record['evidence_id']}');
              debugPrint('   ║ Learner ID: ${record['LearnerID']}');
              debugPrint('   ║ Clock Date: ${record['clock_date']}');
              debugPrint('   ║ Signature In: ${_formatDataSize(record['signature_in'])}');
              debugPrint('   ║ Signature Out: ${_formatDataSize(record['signature_out'])}');
              debugPrint('   ║ Face In: ${_formatDataSize(record['face_in'])}');
              debugPrint('   ║ Face Out: ${_formatDataSize(record['face_out'])}');
              debugPrint('   ║ Synced: ${record['synced'] == 1 ? '✅ YES' : '❌ NO'}');
              debugPrint('   ║ Created: ${record['created_at']}');
              debugPrint('   ║ Updated: ${record['updated_at']}');
              debugPrint('   ╚══════════════════════════════════════════════════════╝');
              
              // Show sample data for images (first 50 characters)
              if (record['signature_in'] != null) {
                final sig = record['signature_in'].toString();
                final sample = sig.length > 50 ? '${sig.substring(0, 50)}...' : sig;
                debugPrint('   📝 Signature In Sample: $sample');
              }
              if (record['face_in'] != null) {
                final face = record['face_in'].toString();
                final sample = face.length > 50 ? '${face.substring(0, 50)}...' : face;
                debugPrint('   📷 Face In Sample: $sample');
              }
            }
          }
        } catch (e) {
          debugPrint('❌ Error reading manual_clocking_evidence data: $e');
        }
      }

      // 3. Check other important tables
      debugPrint('');
      debugPrint('🗂️  STEP 3: OTHER IMPORTANT TABLES');
      debugPrint('▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔');
      
      final importantTables = [
        'learnerDetails',
        'learner_clocking',
        'learner_clocking_evidence',
        'facilitator_clocking_evidence',
        'class',
        'sites',
        'project',
        'unsynced_data'
      ];
      
      for (final tableName in importantTables) {
        try {
          final exists = tables.any((table) => table['name'] == tableName);
          if (exists) {
            final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM `$tableName`');
            final rowCount = countResult.first['count'] as int;
            debugPrint('   ✅ $tableName: $rowCount records');
            
            // For learnerDetails, show a few sample records
            if (tableName == 'learnerDetails' && rowCount > 0) {
              final sampleData = await db.query(tableName, limit: 3);
              debugPrint('      Sample records:');
              for (final record in sampleData) {
                debugPrint('        • ID: ${record['learnerId']}, Name: ${record['name']} ${record['surname']}, IDNo: ${record['idNumber']}');
              }
            }
          } else {
            debugPrint('   ❌ $tableName: does not exist');
          }
        } catch (e) {
          debugPrint('   ⚠️  $tableName: error ($e)');
        }
      }

      // 4. Check database file info
      debugPrint('');
      debugPrint('💾 STEP 4: DATABASE FILE INFORMATION');
      debugPrint('▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔');
      try {
        final pragmaResult = await db.rawQuery('PRAGMA database_list');
        for (final dbInfo in pragmaResult) {
          debugPrint('   Database: ${dbInfo['name']}, File: ${dbInfo['file']}');
        }
      } catch (e) {
        debugPrint('   ⚠️  Could not get database file info: $e');
      }

      debugPrint('');
      debugPrint('██████████████████████████████████████████████████████████████████');
      debugPrint('█                    INSPECTION COMPLETE                        █');
      debugPrint('██████████████████████████████████████████████████████████████████');
      debugPrint('');

    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌❌❌ CRITICAL ERROR DURING DATABASE INSPECTION ❌❌❌');
      debugPrint('Error: $e');
      debugPrint('Stack Trace: $stackTrace');
      debugPrint('');
    }
  }

  static String _formatDataSize(dynamic data) {
    if (data == null) return '❌ NULL';
    final size = data.toString().length;
    if (size == 0) return '⚠️  EMPTY';
    return '✅ $size chars';
  }
}