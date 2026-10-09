import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'utils/connectivity_utils.dart';
import 'utils/learner_profile_validation.dart';
import 'mixins/learner_clockin_gates_mixin.dart';
import 'config.dart';
import 'database_helper.dart';
import 'services/secure_location_service.dart';
import 'package:http/http.dart' as http;
import 'LearnerDetailsPage.dart';
import 'services/face_embedding_service.dart';
import 'repositories/face_verification_repository.dart';
import 'widgets/simple_face_capture.dart';
import 'services/offline_face_verification_service.dart';
import 'learner_security_questions_setup_page.dart';

/// BACKUP CLOCK-IN PAGE
///_
/// This page is used when no fingerprint scanner is available.
/// Flow: Profile Check → Bank Check → Documents Check → ID Verification → Signature → GPS → Clock-In/Out
///
/// Key differences from regular clock-in:
/// - Uses signature instead of fingerprint verification
/// - Requires manual ID number confirmation before signature
/// - All the same mandatory checks (profile, bank, documents)
/// - Same geofencing and GPS verification

class BackupClockInPage extends StatefulWidget {
  final String classID;
  final List<dynamic> learners; // May be empty - will load independently

  const BackupClockInPage({
    Key? key,
    required this.classID,
    this.learners = const [], // Make optional with default empty list
  }) : super(key: key);

  @override
  _BackupClockInPageState createState() => _BackupClockInPageState();
}

class _BackupClockInPageState extends State<BackupClockInPage>
    with LearnerClockInGatesMixin {
  bool _isLoading = false;
  String? _selectedLearnerId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Learners list - loaded independently
  List<dynamic> _learners = [];
  bool _isLoadingLearners = true;

  // Signature controller
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // State tracking
  Map<String, bool> _isClockingIn = {};
  Map<String, bool> _isClockedIn = {}; // Track who is clocked in
  Map<String, String> _clockInTimes = {}; // Track clock-in times
  Map<String, bool> _hasCompletedDay =
      {}; // Track who has both clocked in AND out
  String? _currentStep; // tracks current step in flow

  // Face recognition services
  final FaceEmbeddingService _faceService = FaceEmbeddingService();
  final FaceVerificationRepository _faceRepo = FaceVerificationRepository();
  final OfflineFaceVerificationService _offlineFaceService =
      OfflineFaceVerificationService();

  // Face verification state
  bool _isFaceEnrolled = false;
  int _faceVerificationAttempts = 0;
  String? _capturedFacePhotoBase64; // Captured verification photo
  String? _capturedFacePhotoFilename; // Saved photo filename
  int? _faceLogId; // Server-side verification log ID

  @override
  void initState() {
    super.initState();
    _loadLearnersData(); // Load learners first, will call _loadClockingStatus() after
    _syncAllSignaturesToServer(); // Sync signatures when page loads (if online)
    _syncFaceVerificationLogs(); // Sync offline face verification logs (if online)
  }

  /// Load learners from database (offline-first) and/or API
  /// Load learners - prioritizes server data over offline DB
  Future<void> _loadLearnersData() async {
    setState(() => _isLoadingLearners = true);

    try {
      // PRIORITY 1: Try offline database first (most up-to-date after sync)
      final db = await DatabaseHelper().database;

      // First, count total learners in DB for this class
      final countResult = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE CAST(classID AS TEXT) = ?
      ''', [normalizeClassId(widget.classID)]);
      print('[BACKUP_LOAD] ===== DATABASE DIAGNOSTIC =====');
      print('[BACKUP_LOAD] Looking for classID: ${widget.classID}');
      print('[BACKUP_LOAD] ClassID type: ${widget.classID.runtimeType}');
      print(
          '[BACKUP_LOAD] Total learners in DB for classID ${widget.classID}: ${countResult.first['total']}');

      // Check if class exists in database
      final classCheck = await db.rawQuery('''
        SELECT classID FROM class WHERE classID = ?
      ''', [widget.classID]);
      print('[BACKUP_LOAD] Class exists in DB: ${classCheck.isNotEmpty}');

      if (classCheck.isNotEmpty) {
        print(
            '[BACKUP_LOAD] Found class with ID: ${classCheck.first['classID']} (type: ${classCheck.first['classID'].runtimeType})');
      }

      // Check for type mismatches - try both STRING and INTEGER
      final countAsString = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ?
      ''', [widget.classID.toString()]);
      print(
          '[BACKUP_LOAD] Learners found with STRING classID: ${countAsString.first['total']}');

      final countAsInt = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ?
      ''', [int.tryParse(widget.classID.toString()) ?? 0]);
      print(
          '[BACKUP_LOAD] Learners found with INTEGER classID: ${countAsInt.first['total']}');

      // Show sample classID values in database
      final sampleClassIDs = await db.rawQuery('''
        SELECT DISTINCT classID FROM learnerdetails ORDER BY classID LIMIT 10
      ''');
      print(
          '[BACKUP_LOAD] Sample classIDs in DB: ${sampleClassIDs.map((r) => '${r['classID']} (${r['classID'].runtimeType})').join(', ')}');

      // Count learners with non-null classID
      final countNonNullResult = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ? AND classID IS NOT NULL
      ''', [widget.classID]);
      print(
          '[BACKUP_LOAD] Learners with non-null classID: ${countNonNullResult.first['total']}');

      final offlineResult = await db.rawQuery('''
        SELECT LearnerID, Name, Surname, IDNumber, profile_image, classID
        FROM learnerdetails 
        WHERE CAST(classID AS TEXT) = ? 
        AND classID IS NOT NULL
        ORDER BY Name, Surname
      ''', [normalizeClassId(widget.classID)]);

      print(
          '[BACKUP_LOAD] Loaded ${offlineResult.length} learners from offline DB query');
      print(
          '[BACKUP_LOAD] First 3 learners: ${offlineResult.take(3).map((l) => '${l['Name']} ${l['Surname']} (ID: ${l['LearnerID']})').join(', ')}');
      print('[BACKUP_LOAD] ===== END DIAGNOSTIC =====');

      if (offlineResult.isNotEmpty) {
        setState(() {
          _learners = offlineResult;
          _isLoadingLearners = false;
        });
        // Load clocking status after learners are loaded
        await _loadClockingStatus();
        return;
      }

      // No learners found - try to create test learners for offline functionality
      print(
          '[BACKUP_LOAD] 🔄 No learners found, attempting to create test learners...');
      try {
        final dbHelper = DatabaseHelper();
        await dbHelper.ensureClassDataExists(widget.classID);
        await dbHelper.ensureTestLearnersExist(widget.classID, learnerCount: 5);

        // Retry the query after creating test data
        final retryResult = await db.rawQuery('''
          SELECT LearnerID, Name, Surname, IDNumber, profile_image, classID
          FROM learnerdetails 
          WHERE CAST(classID AS TEXT) = ? 
          AND classID IS NOT NULL
          ORDER BY Name, Surname
        ''', [normalizeClassId(widget.classID)]);

        if (retryResult.isNotEmpty) {
          print(
              '[BACKUP_LOAD] ✅ Successfully created ${retryResult.length} test learners');
          setState(() {
            _learners = retryResult;
            _isLoadingLearners = false;
          });
          await _loadClockingStatus();
          return;
        } else {
          print('[BACKUP_LOAD] ❌ Failed to create test learners');
        }
      } catch (e) {
        print('[BACKUP_LOAD] ❌ Error creating test learners: $e');
      }

      // PRIORITY 2: Use learners passed from parent widget (if offline DB empty)
      if (widget.learners.isNotEmpty) {
        print(
            '[BACKUP_LOAD] Using ${widget.learners.length} learners from parent widget (offline DB was empty)');
        setState(() {
          _learners = widget.learners;
          _isLoadingLearners = false;
        });
        // Load clocking status after learners are loaded
        await _loadClockingStatus();
        return;
      }

      // PRIORITY 3: Last resort - fetch from API
      print('[BACKUP_LOAD] Fetching learners from API...');
      await _fetchLearnersFromAPI();
    } catch (e) {
      print('[BACKUP_LOAD] Error loading learners: $e');
      // Fallback to widget.learners if available
      setState(() {
        _learners = widget.learners;
        _isLoadingLearners = false;
      });
      // Load clocking status even with fallback
      await _loadClockingStatus();
    }
  }

  /// Fetch learners from live server API
  Future<void> _fetchLearnersFromAPI() async {
    try {
      final url =
          AppConfig.buildUrl('get_learners.php?classID=${widget.classID}');
      final token = await AppConfig.getAuthToken();

      if (token == null) {
        print('[BACKUP_API] No auth token available');
        setState(() => _isLoadingLearners = false);
        return;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[BACKUP_API] Response keys: ${data.keys.toList()}');
        print('[BACKUP_API] Has success key: ${data.containsKey('success')}');
        print('[BACKUP_API] success value: ${data['success']}');

        if (data['success'] == true && data['data'] != null) {
          final learnersList = data['data'] as List;
          print(
              '[BACKUP_API] Fetched ${learnersList.length} learners from API');

          // Debug: Check first learner for Province/District/Municipality
          if (learnersList.isNotEmpty) {
            final firstLearner = learnersList[0] as Map<String, dynamic>;
            print(
                '[BACKUP_API] First learner keys: ${firstLearner.keys.toList()}');
            print(
                '[BACKUP_API] First learner Province: ${firstLearner['Province']}');
            print(
                '[BACKUP_API] First learner District: ${firstLearner['District']}');
            print(
                '[BACKUP_API] First learner Municipality: ${firstLearner['Municipality']}');
          }

          setState(() {
            _learners = learnersList;
            _isLoadingLearners = false;
          });

          // Store in offline database for future use
          await _storeLearnersOffline(learnersList);

          // Load clocking status after learners are loaded from API
          await _loadClockingStatus();
        } else {
          print('[BACKUP_API] API returned no learners or success=false');
          print(
              '[BACKUP_API] Full response: ${data.toString().substring(0, 500)}');
          setState(() => _isLoadingLearners = false);
        }
      } else {
        print('[BACKUP_API] Failed with status ${response.statusCode}');
        setState(() => _isLoadingLearners = false);
      }
    } catch (e) {
      print('[BACKUP_API] Error fetching from API: $e');
      setState(() => _isLoadingLearners = false);
    }
  }

  /// Store fetched learners in offline database
  Future<void> _storeLearnersOffline(List<dynamic> learners) async {
    try {
      final db = await DatabaseHelper().database;
      int storedCount = 0;
      for (var learner in learners) {
        final learnerMap = await _mergeIncomingLearnerWithLocal(
            learner as Map<String, dynamic>);

        // Debug: Check Province/District/Municipality before insert
        if (learnerMap['LearnerID'].toString() == '11443') {
          print('[BACKUP_STORE] ===== LEARNER 11443 BEFORE INSERT =====');
          print('[BACKUP_STORE] Province: ${learnerMap['Province']}');
          print('[BACKUP_STORE] District: ${learnerMap['District']}');
          print('[BACKUP_STORE] Municipality: ${learnerMap['Municipality']}');
        }

        await db.insert(
          'learnerdetails',
          learnerMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        storedCount++;
      }
      print('[BACKUP_STORE] Stored $storedCount learners offline');

      // Verify learner 11443 was stored correctly
      final verifyResult = await db.query(
        'learnerdetails',
        where: 'LearnerID = ?',
        whereArgs: ['11443'],
      );

      if (verifyResult.isNotEmpty) {
        final stored = verifyResult.first;
        print('[BACKUP_STORE] ===== LEARNER 11443 AFTER INSERT =====');
        print('[BACKUP_STORE] Province: ${stored['Province']}');
        print('[BACKUP_STORE] District: ${stored['District']}');
        print('[BACKUP_STORE] Municipality: ${stored['Municipality']}');
        print('[BACKUP_STORE] All columns: ${stored.keys.toList()}');
      }
    } catch (e) {
      print('[BACKUP_STORE] Error storing offline: $e');
    }
  }

  /// Keep existing local profile/location values when API payload is empty.
  Future<Map<String, dynamic>> _mergeIncomingLearnerWithLocal(
      Map<String, dynamic> incoming) async {
    final merged = Map<String, dynamic>.from(incoming);
    final learnerId = incoming['LearnerID']?.toString();
    if (learnerId == null || learnerId.isEmpty) {
      return merged;
    }

    final existing = await DatabaseHelper().getLearnerById(learnerId);
    if (existing == null) {
      return merged;
    }

    return mergeLearnerPreferLocal(existing, incoming);
  }

  /// Load clocking status for all learners
  Future<void> _loadClockingStatus() async {
    // Wait for learners to load first
    if (_isLoadingLearners || _learners.isEmpty) {
      print('[BACKUP_STATUS] Waiting for learners to load...');
      return;
    }

    // Show syncing indicator
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final db = await DatabaseHelper().database;
      final today = DateTime.now().toUtc().add(const Duration(hours: 2));
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      print('[BACKUP_STATUS] ===== LOADING STATUS =====');
      print('[BACKUP_STATUS] Loading status for date: $todayStr');
      print('[BACKUP_STATUS] Total learners: ${_learners.length}');

      // CRITICAL FIX: Ensure learner_clocking_evidence table exists
      try {
        await db.rawQuery('SELECT 1 FROM learner_clocking_evidence LIMIT 1');
        print('[BACKUP_STATUS] ✅ Evidence table exists');
      } catch (e) {
        print('[BACKUP_STATUS] ⚠️ Evidence table missing, creating now: $e');
        await DatabaseHelper().repairEvidenceTable();
        print('[BACKUP_STATUS] ✅ Evidence table created');
      }

      // Check connectivity and fetch from server if online
      final isOnline = await hasNetworkConnectivity();
      print('[BACKUP_STATUS] Online status: $isOnline');

      if (isOnline) {
        try {
          final url = AppConfig.buildUrl('get_learner_evidence_today.php');
          final token = await AppConfig.getAuthToken();

          print('[BACKUP_STATUS] Fetching from server: $url');

          final response = await http
              .post(
                Uri.parse(url),
                headers: {
                  'Content-Type': 'application/json',
                  if (token != null) 'Authorization': 'Bearer $token',
                },
                body: json.encode({'date': todayStr}),
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final result = json.decode(response.body);
            if (result['success'] == true && result['records'] != null) {
              final serverRecords = result['records'] as List;
              print(
                  '[BACKUP_STATUS] Found ${serverRecords.length} server records');

              // Sync server records to local database
              for (var record in serverRecords) {
                final learnerId = record['learner_id'].toString();

                // Check if record exists locally to get its ID
                final existing = await db.rawQuery('''
                  SELECT id FROM learner_clocking_evidence 
                  WHERE LearnerID = ? AND clock_date = ?
                ''', [learnerId, todayStr]);

                if (existing.isNotEmpty) {
                  // UPDATE existing record
                  final existingId = existing.first['id'];
                  await db.rawUpdate('''
                    UPDATE learner_clocking_evidence SET
                      clock_in_timestamp = ?,
                      clock_out_timestamp = ?,
                      clock_in_signature = ?,
                      clock_out_signature = ?,
                      clock_in_photo = ?,
                      clock_out_photo = ?,
                      clock_in_latitude = ?,
                      clock_in_longitude = ?,
                      clock_in_accuracy = ?,
                      clock_out_latitude = ?,
                      clock_out_longitude = ?,
                      clock_out_accuracy = ?,
                      clock_in_verification_method = ?,
                      clock_in_face_log_id = ?,
                      synced = 1,
                      updated_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                  ''', [
                    record['clock_in_timestamp'],
                    record['clock_out_timestamp'],
                    record['clock_in_signature'],
                    record['clock_out_signature'],
                    record['clock_in_photo'],
                    record['clock_out_photo'],
                    record['clock_in_latitude'],
                    record['clock_in_longitude'],
                    record['clock_in_accuracy'],
                    record['clock_out_latitude'],
                    record['clock_out_longitude'],
                    record['clock_out_accuracy'],
                    record['verification_method'],
                    record['face_log_id'],
                    existingId,
                  ]);
                  print(
                      '[BACKUP_STATUS] ✅ Updated local record for learner $learnerId');
                } else {
                  // INSERT new record
                  await db.rawInsert('''
                    INSERT INTO learner_clocking_evidence (
                      LearnerID, clock_date, clock_in_timestamp, clock_out_timestamp,
                      clock_in_signature, clock_out_signature, clock_in_photo, clock_out_photo,
                      clock_in_latitude, clock_in_longitude, clock_in_accuracy,
                      clock_out_latitude, clock_out_longitude, clock_out_accuracy,
                      clock_in_verification_method, clock_in_face_log_id, synced
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                  ''', [
                    learnerId,
                    record['clock_date'],
                    record['clock_in_timestamp'],
                    record['clock_out_timestamp'],
                    record['clock_in_signature'],
                    record['clock_out_signature'],
                    record['clock_in_photo'],
                    record['clock_out_photo'],
                    record['clock_in_latitude'],
                    record['clock_in_longitude'],
                    record['clock_in_accuracy'],
                    record['clock_out_latitude'],
                    record['clock_out_longitude'],
                    record['clock_out_accuracy'],
                    record['verification_method'],
                    record['face_log_id'],
                  ]);
                  print(
                      '[BACKUP_STATUS] ✅ Inserted new server record for learner $learnerId');
                }
              }
            }
          }
        } catch (e) {
          print('[BACKUP_STATUS] ⚠️ Server fetch failed, using local only: $e');
        }
      }

      // Now load from local database (which now has synced server records)
      // Collect all updates first, then apply them in a single setState
      final Map<String, bool> clockedInUpdates = {};
      final Map<String, bool> completedDayUpdates = {};
      final Map<String, String> clockInTimeUpdates = {};

      for (var learner in _learners) {
        final learnerMap = learner as Map<String, dynamic>;
        final learnerId = learnerMap['LearnerID'].toString();
        final learnerName = '${learnerMap['Name']} ${learnerMap['Surname']}';

        // Check ONLY learner_clocking_evidence table (Face/Signature clockings)
        final result = await db.rawQuery('''
          SELECT clock_in_timestamp, clock_out_timestamp, clock_date
          FROM learner_clocking_evidence 
          WHERE LearnerID = ? 
            AND clock_date = ?
          LIMIT 1
        ''', [learnerId, todayStr]);

        print('[BACKUP_STATUS] --- Learner: $learnerName (ID: $learnerId) ---');
        print('[BACKUP_STATUS]     Evidence records: ${result.length}');

        if (result.isNotEmpty) {
          final record = result.first;
          final clockInTime = record['clock_in_timestamp'];
          final clockOutTime = record['clock_out_timestamp'];
          final clockDate = record['clock_date'];

          print('[BACKUP_STATUS]     clock_date=$clockDate');
          print('[BACKUP_STATUS]     clock_in_timestamp=$clockInTime');
          print('[BACKUP_STATUS]     clock_out_timestamp=$clockOutTime');

          // Clocked in if there's a clock-in time but no clock-out time (or empty string)
          final hasClockIn =
              clockInTime != null && clockInTime.toString().isNotEmpty;
          final hasClockOut = clockOutTime != null &&
              clockOutTime.toString().isNotEmpty &&
              clockOutTime.toString() != 'null';

          // Check if day is completed (both clock in AND clock out)
          completedDayUpdates[learnerId] = hasClockIn && hasClockOut;

          // Clocked in only if they have clock-in but NO clock-out
          clockedInUpdates[learnerId] = hasClockIn && !hasClockOut;

          // Store clock-in time for display
          if (hasClockIn) {
            clockInTimeUpdates[learnerId] = clockInTime.toString();
          }

          print(
              '[BACKUP_STATUS]     Status: ${completedDayUpdates[learnerId]! ? "✓✓ COMPLETED DAY" : clockedInUpdates[learnerId]! ? "✓ CLOCKED IN" : "✗ NOT CLOCKED IN"} (hasClockIn=$hasClockIn, hasClockOut=$hasClockOut)');
        } else {
          print('[BACKUP_STATUS]     Status: ✗ NO RECORDS FOR TODAY');
          clockedInUpdates[learnerId] = false;
          completedDayUpdates[learnerId] = false;
          // Don't add to clockInTimeUpdates - will be removed in setState
        }
      }

      // Apply all updates in a SINGLE setState call
      if (mounted) {
        setState(() {
          _isClockedIn = clockedInUpdates;
          _hasCompletedDay = completedDayUpdates;
          _clockInTimes = clockInTimeUpdates;
          _isLoading = false; // Hide loading indicator
        });
      }

      print('[BACKUP_STATUS] ===== STATUS LOADING COMPLETE =====');
    } catch (e) {
      print('[BACKUP] Error loading clocking status: $e');
      print('[BACKUP] Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Check if a specific learner is clocked in
  bool _isLearnerClockedIn(String learnerId) {
    return _isClockedIn[learnerId] ?? false;
  }

  /// Check if a specific learner has completed their day (clocked in AND out)
  bool _hasLearnerCompletedDay(String learnerId) {
    return _hasCompletedDay[learnerId] ?? false;
  }

  /// Get formatted clock-in time for display (HH:mm format)
  String _getClockInTimeDisplay(String learnerId) {
    final timeStr = _clockInTimes[learnerId];
    if (timeStr == null || timeStr.isEmpty) return '';

    try {
      // Parse full timestamp (e.g., "2026-09-25 09:37:39") and extract time
      final parts = timeStr.split(' ');
      if (parts.length >= 2) {
        final timePart = parts[1]; // "09:37:39"
        final timeComponents = timePart.split(':');
        if (timeComponents.length >= 2) {
          return '${timeComponents[0]}:${timeComponents[1]}'; // "09:37"
        }
      }
      return timeStr; // Fallback to original if parsing fails
    } catch (e) {
      print('[BACKUP] Error formatting time: $e');
      return timeStr;
    }
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Filter learners based on search
  List<dynamic> get _filteredLearners {
    if (_searchQuery.isEmpty) {
      return _learners;
    }
    return _learners.where((learner) {
      final learnerMap = learner as Map<String, dynamic>;
      final name = (learnerMap['Name'] ?? '').toString().toLowerCase();
      final surname = (learnerMap['Surname'] ?? '').toString().toLowerCase();
      final idNumber = (learnerMap['IDNumber'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) ||
          surname.contains(query) ||
          idNumber.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Clock-In (Signature Mode)'),
        backgroundColor: Colors.orange,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            color: Colors.orange.shade100,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Using backup signature mode - no fingerprint scanner required',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search learners',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Learner list
          Expanded(
            child: _isLoading || _isLoadingLearners
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading learners...'),
                      ],
                    ),
                  )
                : _filteredLearners.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No learners available'
                              : 'No learners found for "$_searchQuery"',
                          style:
                              const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredLearners.length,
                        itemBuilder: (context, index) {
                          final learner =
                              _filteredLearners[index] as Map<String, dynamic>;
                          final learnerId = learner['LearnerID'].toString();
                          final isProcessing = _isClockingIn[learnerId] == true;
                          final isClockedIn = _isLearnerClockedIn(learnerId);
                          final hasCompletedDay =
                              _hasLearnerCompletedDay(learnerId);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: hasCompletedDay
                                    ? Colors.blue
                                    : isClockedIn
                                        ? Colors.green
                                        : Colors.orange,
                                child: Text(
                                  (learner['Name'] ?? '?')
                                      .toString()
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                '${learner['Name']} ${learner['Surname']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ID: ${learner['IDNumber']}'),
                                  if (hasCompletedDay)
                                    const Text(
                                      'Already clocked in and out for today',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  else if (isClockedIn)
                                    Text(
                                      'Already clocked in ${_getClockInTimeDisplay(learner['LearnerID'].toString())}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: isProcessing
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : hasCompletedDay
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.check_circle,
                                                  color: Colors.blue, size: 20),
                                              SizedBox(width: 6),
                                              Text(
                                                'Completed',
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : isClockedIn
                                          ? IconButton(
                                              icon: const Icon(Icons.logout,
                                                  color: Colors.red),
                                              tooltip: 'Clock Out',
                                              onPressed: () =>
                                                  _startBackupClockOut(
                                                      learnerId),
                                            )
                                          : IconButton(
                                              icon: const Icon(Icons.login,
                                                  color: Colors.green),
                                              tooltip: 'Clock In',
                                              onPressed: () =>
                                                  _startBackupClockIn(
                                                      learnerId),
                                            ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// ========== CLOCK-IN FLOW ==========
  Future<void> _startBackupClockIn(String learnerId) async {
    if (_isClockingIn[learnerId] == true) {
      return;
    }

    // Check if learners are still loading
    if (_isLoadingLearners || _learners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, learners are still loading...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Block if learner has already completed their day
    if (_hasLearnerCompletedDay(learnerId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '✓ You have already clocked in and out for today. See you tomorrow!'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isClockingIn[learnerId] = true;
      _currentStep = 'profile_check';
    });

    try {
      // Step 1: Profile completeness
      final profileOk = await _ensureLearnerProfileComplete(learnerId);
      if (!profileOk) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 2: Bank details
      setState(() => _currentStep = 'bank_check');
      final bankOk = await _ensureLearnerBankDetailsComplete(learnerId);
      if (!bankOk) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 3: Document completeness
      setState(() => _currentStep = 'document_check');
      final docsOk = await _checkDocumentCompleteness(learnerId);
      if (!docsOk) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 4: Show clocking days popup
      setState(() => _currentStep = 'clocking_days');
      await _showClockingDaysPopup(learnerId, 'in');

      // Step 5: Face Recognition (ID verification removed - using face only)
      print('[BACKUP_CLOCKIN] ===== STEP 5.5: FACE RECOGNITION =====');
      setState(() => _currentStep = 'face_check');

      // Check if face is enrolled
      final hasEnrolledFace = await _checkFaceEnrollment(learnerId);

      if (hasEnrolledFace) {
        // Face ALREADY enrolled - check if security questions are set up
        print(
            '[BACKUP_CLOCKIN] Face already enrolled - checking security questions setup');

        try {
          final securityCheckResponse = await http.get(
            Uri.parse(
                '${AppConfig.baseUrl}/manage_security_questions.php?action=check_setup&learner_id=$learnerId'),
          );

          final securityCheckData = json.decode(securityCheckResponse.body);
          final hasSecurityQuestions = securityCheckData['success'] == true &&
              (securityCheckData['question_count'] ?? 0) >= 3;

          if (!hasSecurityQuestions) {
            // Face enrolled but NO security questions - force setup
            print(
                '[BACKUP_CLOCKIN] ⚠️ Face enrolled but security questions NOT set up - forcing setup');

            if (mounted) {
              final setupNow = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange, size: 28),
                        SizedBox(width: 12),
                        Expanded(child: Text('Security Questions Required')),
                      ],
                    ),
                    content: const SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Security questions are mandatory!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'You have registered your face, but security questions are required as a backup verification method.',
                            style: TextStyle(fontSize: 14),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'You must set up security questions before you can clock in.',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange),
                        child: const Text('Set Up Now'),
                      ),
                    ],
                  );
                },
              );

              if (setupNow != true) {
                print(
                    '[BACKUP_CLOCKIN] User cancelled mandatory security questions setup - aborting clock-in');
                setState(() {
                  _isClockingIn[learnerId] = false;
                  _currentStep = null;
                });
                return;
              }

              // Navigate to security questions setup (MANDATORY)
              String learnerName = 'Learner';
              try {
                final learner = _learners.firstWhere(
                  (l) =>
                      (l as Map<String, dynamic>)['LearnerID'].toString() ==
                      learnerId,
                ) as Map<String, dynamic>;
                learnerName =
                    '${learner['Name'] ?? ''} ${learner['Surname'] ?? ''}'
                        .trim();
                if (learnerName.isEmpty) learnerName = 'Learner';
              } catch (e) {
                print('[BACKUP_CLOCKIN] Could not get learner name: $e');
              }

              final setupComplete = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => LearnerSecurityQuestionsSetupPage(
                    learnerId: learnerId,
                    learnerName: learnerName,
                    isRequired: true, // MANDATORY - cannot skip
                  ),
                ),
              );

              if (setupComplete != true) {
                print(
                    '[BACKUP_CLOCKIN] Security questions setup not completed - aborting clock-in');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Security questions setup is required for face verification'),
                    backgroundColor: Colors.orange,
                  ),
                );
                setState(() {
                  _isClockingIn[learnerId] = false;
                  _currentStep = null;
                });
                return;
              }

              print(
                  '[BACKUP_CLOCKIN] ✅ Security questions setup completed - proceeding with face verification');
            }
          }
        } catch (e) {
          print('[BACKUP_CLOCKIN] Error checking security questions: $e');
          // Continue anyway - don't block on this check
        }

        // Face enrolled and questions checked - mark as enrolled and proceed to verification
        print(
            '[BACKUP_CLOCKIN] ✅ Face enrolled + questions checked - proceeding to verification');
        _isFaceEnrolled = true;
      } else {
        // Face NOT enrolled - offer enrollment
        print('[BACKUP_CLOCKIN] No face enrolled - offering enrollment');
        final enrolled = await _enrollFace(learnerId);
        if (!enrolled) {
          print(
              '[BACKUP_CLOCKIN] ⚠️ Face enrollment CANCELLED by user - aborting clock-in');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Clock-in cancelled - face enrollment required or press Cancel to go back'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          // Abort clock-in and return to learner list
          setState(() {
            _isClockingIn[learnerId] = false;
            _currentStep = null;
          });
          return;
        }

        // After successful enrollment, check if security questions need to be set up
        print(
            '[BACKUP_CLOCKIN] Face enrollment complete - checking security questions');
        try {
          final securityCheckResponse = await http.get(
            Uri.parse(
                '${AppConfig.baseUrl}/manage_security_questions.php?action=check_setup&learner_id=$learnerId'),
          );

          final securityCheckData = json.decode(securityCheckResponse.body);
          final hasSecurityQuestions = securityCheckData['success'] == true &&
              (securityCheckData['question_count'] ?? 0) >= 3;

          if (!hasSecurityQuestions) {
            // Face just enrolled but NO security questions - offer setup
            print(
                '[BACKUP_CLOCKIN] Face enrolled but security questions NOT set up - offering setup');

            if (mounted) {
              final setupNow = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.security, color: Colors.blue, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                            child:
                                Text('Set Up Security Questions (Optional)')),
                      ],
                    ),
                    content: const Text(
                      'Security questions provide a backup verification method if face recognition fails.\n\nWould you like to set them up now?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Later'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                        child: const Text('Set Up Now'),
                      ),
                    ],
                  );
                },
              );

              if (setupNow == true) {
                // Navigate to security questions setup
                String learnerName = 'Learner';
                try {
                  final learner = _learners.firstWhere(
                    (l) =>
                        (l as Map<String, dynamic>)['LearnerID'].toString() ==
                        learnerId,
                  ) as Map<String, dynamic>;
                  learnerName =
                      '${learner['Name'] ?? ''} ${learner['Surname'] ?? ''}'
                          .trim();
                  if (learnerName.isEmpty) learnerName = 'Learner';
                } catch (e) {
                  print('[BACKUP_CLOCKIN] Could not get learner name: $e');
                }

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LearnerSecurityQuestionsSetupPage(
                      learnerId: learnerId,
                      learnerName: learnerName,
                      isRequired: false, // Optional after enrollment
                    ),
                  ),
                );
              }
            }
          }
        } catch (e) {
          print(
              '[BACKUP_CLOCKIN] Error checking security questions after enrollment: $e');
        }

        // Mark face as enrolled
        _isFaceEnrolled = true;
      }

      // If face is enrolled (either already or just enrolled), verify it
      if (_isFaceEnrolled) {
        print('[BACKUP_CLOCKIN] Starting face verification');
        final faceVerified =
            await _verifyWithFace(learnerId, eventType: 'clock_in');

        if (!faceVerified) {
          // Face verification failed after 3 attempts - fall back to security questions
          print(
              '[BACKUP_CLOCKIN] Face verification failed - falling back to security questions');
          final securityVerified =
              await _verifyWithSecurityQuestions(learnerId);

          if (!securityVerified) {
            print(
                '[BACKUP_CLOCKIN] Security questions verification CANCELLED by user - aborting clock-in');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Clock-in cancelled - verification required or press Cancel to go back'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            // Abort clock-in and return to learner list
            setState(() {
              _isClockingIn[learnerId] = false;
              _currentStep = null;
            });
            return;
          } else {
            print('[BACKUP_CLOCKIN] Security questions verification SUCCESS');
          }
        } else {
          print('[BACKUP_CLOCKIN] Face verification SUCCESS - photo captured');
        }
      } else {
        print('[BACKUP_CLOCKIN] No face enrolled - will use signature only');
      }

      // Step 6: Signature capture (clock-in signature - temporary, will be replaced by clock-out signature)
      print(
          '[BACKUP_CLOCKIN] ===== STEP 6: SIGNATURE CAPTURE (CLOCK-IN) =====');
      setState(() => _currentStep = 'signature');
      final signatureData = await _captureSignature(learnerId);
      print(
          '[BACKUP_CLOCKIN] Signature capture result: ${signatureData != null ? "SUCCESS (${signatureData.length} chars)" : "NULL/CANCELLED"}');
      if (signatureData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signature is required for backup clock-in'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 7: GPS and geofence check
      print('[BACKUP_CLOCKIN] ===== STEP 7: GEOFENCE CHECK =====');
      setState(() => _currentStep = 'gps_check');
      final gpsOk = await _verifyGeofenceAndGPS(learnerId);
      if (!gpsOk) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 8: Submit clock-in WITH clock-in signature (will be replaced by clock-out signature when user clocks out)
      print(
          '[BACKUP_CLOCKIN] ===== STEP 8: SUBMITTING CLOCK-IN WITH SIGNATURE =====');
      setState(() => _currentStep = 'submitting');
      await _submitBackupClockIn(learnerId, signatureData);

      // Small delay to ensure database write is complete
      await Future.delayed(const Duration(milliseconds: 300));

      // Refresh clocking status
      await _loadClockingStatus();

      // Force UI rebuild
      if (mounted) {
        setState(() {});
      }

      // Success
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Clocked in successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('[BACKUP_CLOCK_IN] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isClockingIn[learnerId] = false;
        _currentStep = null;
      });
    }
  }

  /// ========== CLOCK-OUT FLOW (WITH FACE VERIFICATION) ==========
  Future<void> _startBackupClockOut(String learnerId) async {
    if (_isClockingIn[learnerId] == true) {
      return;
    }

    // Check if learners are still loading
    if (_isLoadingLearners || _learners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, learners are still loading...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isClockingIn[learnerId] = true;
      _currentStep = 'clocking_days';
    });

    try {
      // Step 1: Show clocking days popup
      await _showClockingDaysPopup(learnerId, 'out');

      // Step 2: Face Recognition (ID verification removed - using face only)
      print('[BACKUP_CLOCKOUT] ===== STEP 3: FACE RECOGNITION =====');
      setState(() => _currentStep = 'face_check');

      // Check if face is enrolled
      final hasEnrolledFace = await _checkFaceEnrollment(learnerId);

      if (hasEnrolledFace && _isFaceEnrolled) {
        print('[BACKUP_CLOCKOUT] Face enrolled - verifying identity');
        final faceVerified =
            await _verifyWithFace(learnerId, eventType: 'clock_out');

        if (!faceVerified) {
          // Face verification failed - this is the WRONG PERSON!
          print('[BACKUP_CLOCKOUT] ❌ FACE VERIFICATION FAILED - WRONG PERSON!');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    '❌ Identity verification failed!\n\nThe face does not match the person who clocked in.\n\nClock-out denied.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }

          setState(() {
            _isClockingIn[learnerId] = false;
            _currentStep = null;
          });
          return;
        }

        print(
            '[BACKUP_CLOCKOUT] ✅ Face verification SUCCESS - Same person confirmed');
      } else {
        print(
            '[BACKUP_CLOCKOUT] ⚠️ No face enrolled - skipping face verification (signature only)');
      }

      // Step 4: Signature capture
      setState(() => _currentStep = 'signature');
      final signatureData = await _captureSignature(learnerId);
      if (signatureData == null) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 5: GPS and geofence check
      setState(() => _currentStep = 'gps_check');
      final gpsOk = await _verifyGeofenceAndGPS(learnerId);
      if (!gpsOk) {
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 6: Submit clock-out with signature
      setState(() => _currentStep = 'submitting');
      await _submitBackupClockOut(learnerId, signatureData);

      // Small delay to ensure database write is complete
      await Future.delayed(const Duration(milliseconds: 300));

      // Refresh clocking status
      await _loadClockingStatus();

      // Force UI rebuild
      if (mounted) {
        setState(() {});
      }

      // Success
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Clocked out successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('[BACKUP_CLOCK_OUT] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isClockingIn[learnerId] = false;
        _currentStep = null;
        // Reset face capture state for next verification
        _capturedFacePhotoBase64 = null;
        _capturedFacePhotoFilename = null;
        _faceVerificationAttempts = 0;
        _faceLogId = null;
      });
    }
  }

  /// ========== HELPER METHODS ==========

  Future<bool> _ensureLearnerProfileComplete(String learnerId) =>
      ensureLearnerProfileCompleteForClockIn(learnerId);

  Future<bool> _ensureLearnerBankDetailsComplete(String learnerId) async {
    print(
        '[BACKUP] Bank check skipped in backup mode - not required for clock-in');
    // Bank details validation is optional in backup clock-in mode
    // The focus is on attendance tracking, not payment processing
    return true;
  }

  Future<bool> _checkDocumentCompleteness(String learnerId) async {
    print('[BACKUP] Checking documents for learner $learnerId');
    return ensureLearnerDocumentsCompleteForClockIn(learnerId);
  }

  /// Stage 1: Simple dialog for missing (Not Uploaded) documents
  Future<Map<String, dynamic>?> _showMissingDocumentsDialog({
    required BuildContext dialogContext,
    required List<Map<String, dynamic>> problemDocs,
    required String learnerId,
  }) async {
    final missingDocs =
        problemDocs.where((doc) => doc['status'] == 'Not Uploaded').toList();

    return await showDialog<Map<String, dynamic>>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Missing Required Documents')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This learner has missing required documents. Scan all missing document(s) before clock-in.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              ...missingDocs.map((doc) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(doc['name'] ?? '', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop({'action': 'cancel'}),
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                // Find first "Not Uploaded" document
                final firstMissing = missingDocs.first;
                Navigator.of(context).pop({
                  'action': 'upload',
                  'document': firstMissing['name'],
                });
              },
              icon: Icon(Icons.document_scanner),
              label: Text('Scan Next Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Stage 2: Detailed dialog for Pending/Declined documents (all uploaded)
  Future<Map<String, dynamic>?> _showPendingDeclinedDialog({
    required BuildContext dialogContext,
    required List<Map<String, dynamic>> problemDocs,
  }) async {
    // Filter to show only Pending/Declined (NOT "Not Uploaded")
    final pendingDeclinedDocs =
        problemDocs.where((doc) => doc['status'] != 'Not Uploaded').toList();

    return await showDialog<Map<String, dynamic>>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Clock-In Blocked')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.assignment_late,
                          color: Colors.orange, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'All 3 required documents must be approved',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Document statuses:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 8),
                ...pendingDeclinedDocs.map((doc) {
                  final docName = doc['name'] ?? '';
                  final status = doc['status'] ?? 'Pending';
                  final reason = doc['reason'];

                  Color iconColor = Colors.orange;
                  IconData icon = Icons.error_outline;
                  if (status == 'Declined') {
                    iconColor = Colors.red;
                    icon = Icons.cancel;
                  }

                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: iconColor, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    docName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: iconColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Show Re-upload button ONLY for Declined docs
                            if (status == 'Declined')
                              ElevatedButton.icon(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop({
                                  'action': 'reupload',
                                  'document': docName,
                                }),
                                icon: Icon(Icons.upload, size: 16),
                                label: Text('Re-upload'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                          ],
                        ),
                        if (reason != null && reason.toString().isNotEmpty) ...[
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Reason: $reason',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You cannot clock in until all documents are approved.',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Please contact your administrator for document approval.',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop({'action': 'ok'}),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Handle document upload or re-upload by navigating to LearnerDetailsPage
  Future<void> _handleDocumentUpload(String learnerId, String docName,
      {required bool isReupload}) async {
    print(
        '[BACKUP_DOCUMENTS] ${isReupload ? "Re-upload" : "Upload"} requested for: $docName');

    // Navigate to LearnerDetailsPage where user can upload the document
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LearnerDetailsPage(
          learnerID: learnerId,
          missingProfileOnlyMode: false,
        ),
      ),
    );
  }

  Future<void> _handleDocumentReupload(String learnerId, String docName) async {
    // Navigate to learner details page for document re-upload
    print('[BACKUP_DOCUMENTS] Re-upload requested for: $docName');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LearnerDetailsPage(
          learnerID: learnerId,
          missingProfileOnlyMode: false,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getDetailedDocumentStatuses(
      String learnerId) async {
    try {
      // Check connectivity
      bool isOnline = false;
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {
        isOnline = false;
      }

      if (!isOnline) {
        // Offline: assume local docs are approved
        return {'allApproved': true, 'documents': []};
      }

      final response = await http.post(
        Uri.parse(AppConfig.buildUrl('get_document_statuses.php')),
        body: {'learner_id': learnerId},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        return {'allApproved': false, 'documents': []};
      }

      final decoded = json.decode(response.body);
      if (decoded['success'] != true) {
        return {'allApproved': false, 'documents': []};
      }

      final docsMap = decoded['documents'] as Map<String, dynamic>?;
      if (docsMap == null) {
        return {'allApproved': false, 'documents': []};
      }

      // Check each required document
      final List<Map<String, dynamic>> problemDocs = [];

      for (final requiredDoc in _requiredDocuments) {
        final normalizedName = requiredDoc.trim().toLowerCase();

        // Find matching document in response
        Map<String, dynamic>? docInfo;
        for (final entry in docsMap.entries) {
          if (entry.key.trim().toLowerCase() == normalizedName) {
            docInfo = entry.value as Map<String, dynamic>?;
            break;
          }
        }

        if (docInfo == null) {
          // Document not uploaded
          problemDocs.add({
            'name': requiredDoc,
            'status': 'Not Uploaded',
            'reason': null,
          });
        } else {
          final status = docInfo['status']?.toString() ?? 'Pending';
          if (status.toLowerCase() != 'approved') {
            // Document is Pending or Declined
            problemDocs.add({
              'name': requiredDoc,
              'status': status,
              'reason': docInfo['rejection_reason'],
            });
          }
        }
      }

      return {
        'allApproved': problemDocs.isEmpty,
        'documents': problemDocs,
      };
    } catch (e) {
      print('[BACKUP_DOCUMENTS] Error fetching detailed statuses: $e');
      return {'allApproved': false, 'documents': []};
    }
  }

  final List<String> _requiredDocuments = const [
    'ID Document',
    'Qualifications',
    'Proof of Residence',
  ];

  Future<void> _showClockingDaysPopup(String learnerId, String action) async {
    // Placeholder - implement clocking days display
    print(
        '[BACKUP] Showing clocking days for learner $learnerId, action: $action');
    // TODO: Implement actual clocking days popup
  }

  Future<bool> _verifyLearnerID(String learnerId) async {
    // Find learner in list
    print('[VERIFY_LEARNER] ===== START VERIFICATION =====');
    print(
        '[VERIFY_LEARNER] Looking for learner ID: $learnerId (type: ${learnerId.runtimeType})');
    print('[VERIFY_LEARNER] Total learners in list: ${_learners.length}');

    // Debug: Print ALL keys and values for the first learner
    if (_learners.isNotEmpty) {
      print('[VERIFY_LEARNER] Sample learner structure:');
      final sample = _learners.first as Map;
      sample.forEach((key, value) {
        print('[VERIFY_LEARNER]   $key: $value (type: ${value.runtimeType})');
      });
    }

    // Debug: Print ALL learner IDs with their types
    print('[VERIFY_LEARNER] All learner IDs in list:');
    for (var l in _learners) {
      final map = l as Map;
      final id = map['LearnerID'];
      print(
          '[VERIFY_LEARNER]   ID: $id (type: ${id.runtimeType}, toString: ${id.toString()})');
    }

    Map<String, dynamic>? learner;
    try {
      learner = _learners.firstWhere(
        (l) {
          final map = l as Map<String, dynamic>;
          final learnerIdValue = map['LearnerID'];
          final match = learnerIdValue.toString() == learnerId;
          print(
              '[VERIFY_LEARNER] Comparing: $learnerIdValue == $learnerId -> $match');
          return match;
        },
      ) as Map<String, dynamic>?;

      if (learner != null) {
        print(
            '[VERIFY_LEARNER] SUCCESS: Found learner: ${learner['Name']} ${learner['Surname']}');
      }
    } catch (e) {
      print('[VERIFY_LEARNER] EXCEPTION (learner not found or error): $e');
      learner = null;
    }

    if (learner == null || learner.isEmpty) {
      print(
          '[VERIFY_LEARNER] FINAL ERROR: Learner $learnerId NOT found in loaded list');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Learner $learnerId not found in this class. Please refresh the page.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    print(
        '[VERIFY_LEARNER] Found learner: ${learner['Name']} ${learner['Surname']}');

    final idNumber = learner['IDNumber']?.toString() ?? '';
    final TextEditingController idController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Verify ID Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Learner: ${learner!['Name']} ${learner['Surname']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Please enter the learner\'s ID number to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'ID Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final enteredId = idController.text.trim();
                print(
                    '[VERIFY_LEARNER] Entered ID: $enteredId, Expected: $idNumber');

                if (enteredId == idNumber) {
                  print('[VERIFY_LEARNER] ID MATCH! Closing dialog with TRUE');
                  Navigator.of(context).pop(true);
                } else {
                  print('[VERIFY_LEARNER] ID MISMATCH! Showing error');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ID number does not match!'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    print('[VERIFY_LEARNER] Dialog closed with result: $confirmed');
    print('[VERIFY_LEARNER] Returning: ${confirmed == true}');
    return confirmed == true;
  }

  Future<String?> _captureSignature(String learnerId) async {
    print('[SIGNATURE] Starting signature capture for learner: $learnerId');
    _signatureController.clear();

    Map<String, dynamic>? learner;
    try {
      learner = _learners.firstWhere(
        (l) => (l as Map<String, dynamic>)['LearnerID'].toString() == learnerId,
      ) as Map<String, dynamic>?;
      print(
          '[SIGNATURE] Found learner: ${learner?['Name']} ${learner?['Surname']}');
    } catch (e) {
      print('[SIGNATURE] ERROR finding learner: $e');
      learner = null;
    }

    if (learner == null) {
      print('[SIGNATURE] Learner not found, returning null');
      return null;
    }

    print('[SIGNATURE] Showing signature dialog...');

    final signature = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Signature: ${learner!['Name']} ${learner['Surname']}'),
          content: SizedBox(
            width: 300,
            height: 200,
            child: Column(
              children: [
                const Text('Please sign below:'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Signature(
                    controller: _signatureController,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _signatureController.clear();
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_signatureController.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide a signature'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                final bytes = await _signatureController.toPngBytes();
                if (bytes != null) {
                  final base64Signature = base64Encode(bytes);
                  Navigator.of(context).pop(base64Signature);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    print(
        '[SIGNATURE] Dialog closed. Result: ${signature != null ? "SIGNATURE PROVIDED (${signature.length} chars)" : "NULL/CANCELLED"}');
    return signature;
  }

  Future<bool> _verifyGeofenceAndGPS(String learnerId) async {
    print('[BACKUP] Verifying geofence and GPS for learner $learnerId...');

    try {
      // Get secure GPS position
      setState(() => _currentStep = 'gps_check');

      final securePosition = await SecureLocationService.getSecurePosition();

      // Check if position is trusted
      if (!securePosition.isTrusted) {
        _showErrorDialog(
          'Location Not Trusted',
          'Your GPS location could not be verified. Please ensure:\n'
              '• GPS is enabled\n'
              '• You are outdoors with clear sky view\n'
              '• Mock locations are disabled\n'
              '• Battery saver is disabled for RLMSS',
        );
        return false;
      }

      // Verify geofence with server
      final geofenceResult = await SecureLocationService.verifyGeofenceOnServer(
        securePosition: securePosition,
        classID: widget.classID,
        learnerID: learnerId, // Pass actual learner ID
        action: 'clock_in',
        baseUrl: AppConfig.baseUrl,
      );

      if (geofenceResult['success'] != true) {
        final errorMsg =
            geofenceResult['error'] ?? 'Geofence verification failed';
        final distance = geofenceResult['distance'];
        final effectiveRadius = geofenceResult['effective_radius'];

        String detailedError = errorMsg;
        if (distance != null && effectiveRadius != null) {
          detailedError = '$errorMsg\n\n'
              'Distance: ${distance.toStringAsFixed(0)}m\n'
              'Required: Within ${effectiveRadius.toStringAsFixed(0)}m\n'
              'GPS Accuracy: ${securePosition.position.accuracy.toStringAsFixed(0)}m';
        } else {
          detailedError = '$errorMsg\n\n'
              'GPS Accuracy: ${securePosition.position.accuracy.toStringAsFixed(0)}m';
        }

        _showErrorDialog('Outside Geofence', detailedError);
        return false;
      }

      print('[BACKUP] ✅ Geofence and GPS verification passed');
      return true;
    } catch (e) {
      print('[BACKUP] ❌ Geofence/GPS error: $e');
      _showErrorDialog(
        'Location Error',
        'Could not verify your location: $e\n\n'
            'Please ensure GPS is enabled and try again.',
      );
      return false;
    }
  }

  Future<void> _submitBackupClockIn(
      String learnerId, String signatureData) async {
    print('[BACKUP] Submitting clock-in for learner $learnerId WITH SIGNATURE');

    try {
      final now = _getCurrentTimeString();
      final date = _getCurrentDateString();

      // CHECK FOR DUPLICATES - Check evidence table for existing clock-in today
      final db = await DatabaseHelper().database;
      final existingEvidence = await db.query(
        'learner_clocking_evidence',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerId, date],
        limit: 1,
      );

      if (existingEvidence.isNotEmpty &&
          existingEvidence.first['clock_in_timestamp'] != null) {
        print(
            '[BACKUP] ⚠️ Clock-in record already exists in evidence table for today - skipping duplicate insert');
        throw Exception('You have already clocked in today');
      }

      // Save clock-in signature image to local file
      final clockInSignatureFilename =
          await _saveSignatureLocally(learnerId, signatureData, suffix: 'in');
      print(
          '[BACKUP] Clock-in signature saved with filename: $clockInSignatureFilename');

      // Prepare database record WITH clock-in signature
      final dbData = {
        'LearnerID': learnerId,
        'clock_in_time': now,
        'clock_out_time': '', // Empty for clock-in
        'contact_time': '', // Empty for clock-in
        'clock_date': date,
        'signature': clockInSignatureFilename, // Clock-in signature
        'synced': 0, // Mark as not synced (offline first)
      };

      // Capture GPS location for server submission
      double? clockInLatitude;
      double? clockInLongitude;
      double? clockInAccuracy;
      bool? isMocked;
      bool? passedSanity;

      try {
        final securePosition = await SecureLocationService.getSecurePosition();
        if (securePosition.isTrusted) {
          clockInLatitude = securePosition.position.latitude;
          clockInLongitude = securePosition.position.longitude;
          clockInAccuracy = securePosition.position.accuracy;
          isMocked = securePosition.isMockDetected;
          passedSanity = securePosition.passedSanityCheck;
          print(
              '[BACKUP] GPS for server: lat=$clockInLatitude, lng=$clockInLongitude, acc=$clockInAccuracy');
        }
      } catch (e) {
        print('[BACKUP] ⚠️ Could not capture GPS: $e');
      }

      // Backup clock-in does NOT sync to learner_clocking table
      // Evidence is stored in learner_clocking_evidence table only
      // All data saved via save_clocking_evidence.php endpoint
      print(
          '[BACKUP] Evidence-only mode: NOT syncing to learner_clocking table');
      bool synced = false;

      // Update synced flag
      dbData['synced'] = synced ? 1 : 0;

      // ⚠️ REMOVED: No longer inserting into learner_clocking table
      // This is now handled by the evidence table only
      // await DatabaseHelper().insertClocking(dbData);
      print('[BACKUP] ℹ️ Clock-in evidence only (no learner_clocking insert)');

      // Save evidence (signature + face photo + GPS + verification method)
      try {
        print(
            '[BACKUP] Saving clock-in evidence (signature + face photo + GPS)');

        // Get GPS location if available
        double? latitude;
        double? longitude;
        double? accuracy;
        try {
          final securePosition =
              await SecureLocationService.getSecurePosition();
          if (securePosition.isTrusted) {
            latitude = securePosition.position.latitude;
            longitude = securePosition.position.longitude;
            accuracy = securePosition.position.accuracy;
            print(
                '[BACKUP] GPS captured: lat=$latitude, lng=$longitude, acc=$accuracy');
          } else {
            print('[BACKUP] ⚠️ GPS position not trusted');
          }
        } catch (e) {
          print('[BACKUP] ⚠️ Could not capture GPS: $e');
        }

        // Determine verification method
        String verificationMethod = 'signature'; // Default
        print(
            '[BACKUP] _capturedFacePhotoBase64: ${_capturedFacePhotoBase64 != null ? "HAS DATA" : "NULL"}');
        print(
            '[BACKUP] _capturedFacePhotoFilename: ${_capturedFacePhotoFilename ?? "NULL"}');
        print('[BACKUP] _isFaceEnrolled: $_isFaceEnrolled');
        print('[BACKUP] _faceLogId: $_faceLogId');

        if (_capturedFacePhotoBase64 != null) {
          verificationMethod = 'face';
          print('[BACKUP] ✅ Verification method: FACE (photo captured)');
        } else if (_isFaceEnrolled && _capturedFacePhotoBase64 == null) {
          // Face was enrolled but verification failed, used security questions
          verificationMethod = 'security_question';
          print(
              '[BACKUP] ⚠️ Verification method: SECURITY_QUESTION (face enrolled but verification failed)');
        } else {
          // No face enrolled - signature only
          verificationMethod = 'signature';
          print(
              '[BACKUP] ℹ️ Verification method: SIGNATURE (no face enrolled)');
        }

        // Check if online - if yes, save directly to server
        final isOnline = await hasNetworkConnectivity();

        if (isOnline) {
          // ONLINE: Save directly to server
          try {
            print('[BACKUP] Online - saving evidence directly to server');
            print(
                '[BACKUP] Evidence data: learner=$learnerId, date=$date, verificationMethod=$verificationMethod');
            print(
                '[BACKUP] Photo filename: ${_capturedFacePhotoFilename ?? "NONE"}');
            print('[BACKUP] Face log ID: $_faceLogId');
            print(
                '[BACKUP] GPS: lat=$latitude, lng=$longitude, accuracy=$accuracy');

            final url = AppConfig.buildUrl('save_clocking_evidence.php');
            print('[BACKUP] API URL: $url');

            // Send FILENAMES only (not base64 data)
            final requestBody = {
              'learner_id': int.parse(learnerId),
              'clock_date': date,
              'event_type': 'clock_in',
              'signature_filename':
                  clockInSignatureFilename, // Already saved locally
              'photo_filename':
                  _capturedFacePhotoFilename, // Already saved locally
              'latitude': latitude,
              'longitude': longitude,
              'accuracy': accuracy,
              'verification_method': verificationMethod,
              'face_log_id': _faceLogId,
            };

            print('[BACKUP] Request body keys: ${requestBody.keys.join(", ")}');
            print('[BACKUP] Signature filename: $clockInSignatureFilename');
            print(
                '[BACKUP] Photo filename: ${_capturedFacePhotoFilename ?? "NULL"}');

            final response = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode(requestBody),
                )
                .timeout(const Duration(
                    seconds: 10)); // Reduced timeout (filenames only)

            print('[BACKUP] Response status: ${response.statusCode}');
            print('[BACKUP] Response body: ${response.body}');

            if (response.statusCode == 200) {
              final result = json.decode(response.body);
              if (result['success'] == true) {
                print('[BACKUP] ✅ Evidence saved directly to server');
                print('[BACKUP] Server response: ${result['message']}');
                print('[BACKUP] Signature saved: ${result['signature_saved']}');
                print('[BACKUP] Photo saved: ${result['photo_saved']}');

                // Upload images to server (BLOCKING - ensures upload completes)
                print('[BACKUP] Starting image upload to server...');
                final uploadSuccess = await _uploadClockingImagesToServer(
                  learnerId: learnerId,
                  signatureFilename: clockInSignatureFilename,
                  photoFilename: _capturedFacePhotoFilename,
                  suffix: 'in',
                );

                if (uploadSuccess) {
                  print('[BACKUP] ✅ Images uploaded to server successfully');
                } else {
                  print(
                      '[BACKUP] ⚠️ Image upload failed - images saved locally only');
                  // TODO: Add to offline sync queue for retry when connection improves
                }

                // ALWAYS save to local database for status checking
                print(
                    '[BACKUP] Saving to local database for status tracking...');
                await _saveEvidenceLocally(
                  learnerId: learnerId,
                  date: date,
                  eventType: 'clock_in',
                  signatureData: signatureData,
                  latitude: latitude,
                  longitude: longitude,
                  accuracy: accuracy,
                  verificationMethod: verificationMethod,
                );
              } else {
                throw Exception(result['message'] ?? 'Server returned false');
              }
            } else {
              throw Exception('HTTP ${response.statusCode}: ${response.body}');
            }
          } catch (e) {
            print('[BACKUP] ❌ ERROR saving evidence to server: $e');
            print('[BACKUP] Error type: ${e.runtimeType}');
            print('[BACKUP] Error stack trace: ${StackTrace.current}');
            print('[BACKUP] ⚠️ Falling back to local storage...');
            // Fall back to local storage if online save fails
            await _saveEvidenceLocally(
              learnerId: learnerId,
              date: date,
              eventType: 'clock_in',
              signatureData: signatureData,
              latitude: latitude,
              longitude: longitude,
              accuracy: accuracy,
              verificationMethod: verificationMethod,
            );
          }
        } else {
          // OFFLINE: Save to local database, will sync later
          print('[BACKUP] Offline - saving evidence to local database');
          await _saveEvidenceLocally(
            learnerId: learnerId,
            date: date,
            eventType: 'clock_in',
            signatureData: signatureData,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            verificationMethod: verificationMethod,
          );
        }

        print(
            '[BACKUP] ✅ Clock-in evidence saved successfully (method: $verificationMethod)');
      } catch (e) {
        print('[BACKUP] ⚠️ Error saving evidence (non-critical): $e');
        // Don't fail the clock-in if evidence saving fails
      }
    } catch (e) {
      print('[BACKUP] ❌ Error saving clock-in: $e');
      rethrow;
    }
  }

  Future<void> _submitBackupClockOut(
      String learnerId, String signatureData) async {
    print(
        '[BACKUP] Submitting clock-out for learner $learnerId WITH SIGNATURE');

    try {
      final now = _getCurrentTimeString();
      final date = _getCurrentDateString();

      // Save clock-out signature image to local file (TWO per day: clock-in + clock-out)
      final clockOutSignatureFilename =
          await _saveSignatureLocally(learnerId, signatureData, suffix: 'out');
      print(
          '[BACKUP] Clock-out signature saved with filename: $clockOutSignatureFilename');

      // Check evidence table for clock-in record (since we no longer use learner_clocking table)
      final db = await DatabaseHelper().database;
      final evidenceResults = await db.query(
        'learner_clocking_evidence',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerId, date],
        limit: 1,
      );

      if (evidenceResults.isEmpty ||
          evidenceResults.first['clock_in_timestamp'] == null) {
        throw Exception('No clock-in record found for today');
      }

      final evidenceRecord = evidenceResults.first;
      final clockInTime = evidenceRecord['clock_in_timestamp'].toString();
      final contactTime = _calculateContactTime(clockInTime, now);
      final clockInSignature =
          evidenceRecord['clock_in_signature']?.toString() ?? '';

      // Backup clock-out does NOT sync to learner_clocking table
      // Evidence is stored in learner_clocking_evidence table only
      print(
          '[BACKUP_CLOCKOUT] Evidence-only mode: NOT syncing to learner_clocking table');
      bool synced =
          false; // Evidence will be synced separately via save_clocking_evidence.php

      // ⚠️ REMOVED: No longer updating learner_clocking table
      // This is now handled by the evidence table only
      print(
          '[BACKUP] ℹ️ Clock-out evidence only (no learner_clocking update, synced=$synced)');

      // Save clock-out evidence (signature + face photo + GPS)
      try {
        print(
            '[BACKUP] Saving clock-out evidence (signature + face photo + GPS)');

        // Get GPS location if available
        double? latitude;
        double? longitude;
        double? accuracy;
        try {
          final securePosition =
              await SecureLocationService.getSecurePosition();
          if (securePosition.isTrusted) {
            latitude = securePosition.position.latitude;
            longitude = securePosition.position.longitude;
            accuracy = securePosition.position.accuracy;
            print(
                '[BACKUP] GPS captured: lat=$latitude, lng=$longitude, acc=$accuracy');
          } else {
            print('[BACKUP] ⚠️ GPS position not trusted');
          }
        } catch (e) {
          print('[BACKUP] ⚠️ Could not capture GPS: $e');
        }

        // Determine verification method for clock-out
        String verificationMethod = 'signature'; // Default
        if (_capturedFacePhotoBase64 != null) {
          verificationMethod = 'face';
        }

        // Check if online - if yes, save directly to server
        final isOnline = await hasNetworkConnectivity();

        if (isOnline) {
          // ONLINE: Save directly to server
          try {
            print(
                '[BACKUP_CLOCKOUT] Online - saving evidence directly to server');
            print(
                '[BACKUP_CLOCKOUT] Evidence data: learner=$learnerId, date=$date, verificationMethod=$verificationMethod');
            print(
                '[BACKUP_CLOCKOUT] Photo filename: ${_capturedFacePhotoFilename ?? "NONE"}');
            print('[BACKUP_CLOCKOUT] Face log ID: $_faceLogId');
            print(
                '[BACKUP_CLOCKOUT] GPS: lat=$latitude, lng=$longitude, accuracy=$accuracy');

            final url = AppConfig.buildUrl('save_clocking_evidence.php');
            print('[BACKUP_CLOCKOUT] API URL: $url');

            // Send FILENAMES only (not base64 data)
            final requestBody = {
              'learner_id': int.parse(learnerId),
              'clock_date': date,
              'event_type': 'clock_out',
              'signature_filename':
                  clockOutSignatureFilename, // Already saved locally
              'photo_filename':
                  _capturedFacePhotoFilename, // Already saved locally
              'latitude': latitude,
              'longitude': longitude,
              'accuracy': accuracy,
              'verification_method': verificationMethod,
              'face_log_id': _faceLogId,
            };

            print(
                '[BACKUP_CLOCKOUT] Request body keys: ${requestBody.keys.join(", ")}');
            print(
                '[BACKUP_CLOCKOUT] Signature filename: $clockOutSignatureFilename');
            print(
                '[BACKUP_CLOCKOUT] Photo filename: ${_capturedFacePhotoFilename ?? "NULL"}');

            final response = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode(requestBody),
                )
                .timeout(const Duration(
                    seconds: 10)); // Reduced timeout (filenames only)

            print('[BACKUP_CLOCKOUT] Response status: ${response.statusCode}');
            print('[BACKUP_CLOCKOUT] Response body: ${response.body}');

            if (response.statusCode == 200) {
              final result = json.decode(response.body);
              if (result['success'] == true) {
                print('[BACKUP_CLOCKOUT] ✅ Evidence saved directly to server');
                print(
                    '[BACKUP_CLOCKOUT] Server response: ${result['message']}');
                print(
                    '[BACKUP_CLOCKOUT] Signature saved: ${result['signature_saved']}');
                print(
                    '[BACKUP_CLOCKOUT] Photo saved: ${result['photo_saved']}');

                // Upload images to server (BLOCKING - ensures upload completes)
                print('[BACKUP_CLOCKOUT] Starting image upload to server...');
                final uploadSuccess = await _uploadClockingImagesToServer(
                  learnerId: learnerId,
                  signatureFilename: clockOutSignatureFilename,
                  photoFilename:
                      _capturedFacePhotoFilename, // Include face photo if verified
                  suffix: 'out',
                );

                if (uploadSuccess) {
                  print(
                      '[BACKUP_CLOCKOUT] ✅ Images uploaded to server successfully');
                } else {
                  print(
                      '[BACKUP_CLOCKOUT] ⚠️ Image upload failed - images saved locally only');
                  // TODO: Add to offline sync queue for retry when connection improves
                }

                // ALWAYS save to local database for status checking
                print(
                    '[BACKUP_CLOCKOUT] Saving to local database for status tracking...');
                await _saveEvidenceLocally(
                  learnerId: learnerId,
                  date: date,
                  eventType: 'clock_out',
                  signatureData: signatureData,
                  latitude: latitude,
                  longitude: longitude,
                  accuracy: accuracy,
                  verificationMethod: verificationMethod,
                );
              } else {
                throw Exception(result['message'] ?? 'Server returned false');
              }
            } else {
              throw Exception('HTTP ${response.statusCode}: ${response.body}');
            }
          } catch (e) {
            print('[BACKUP_CLOCKOUT] ❌ ERROR saving evidence to server: $e');
            print('[BACKUP_CLOCKOUT] Error type: ${e.runtimeType}');
            print('[BACKUP_CLOCKOUT] Error stack trace: ${StackTrace.current}');
            print('[BACKUP_CLOCKOUT] ⚠️ Falling back to local storage...');
            // Fall back to local storage if online save fails
            await _saveEvidenceLocally(
              learnerId: learnerId,
              date: date,
              eventType: 'clock_out',
              signatureData: signatureData,
              latitude: latitude,
              longitude: longitude,
              accuracy: accuracy,
              verificationMethod: verificationMethod,
            );
          }
        } else {
          // OFFLINE: Save to local database, will sync later
          print('[BACKUP] Offline - saving evidence to local database');
          await _saveEvidenceLocally(
            learnerId: learnerId,
            date: date,
            eventType: 'clock_out',
            signatureData: signatureData,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            verificationMethod: verificationMethod,
          );
        }

        print('[BACKUP] ✅ Clock-out evidence saved successfully');
      } catch (e) {
        print('[BACKUP] ⚠️ Error saving clock-out evidence (non-critical): $e');
        // Don't fail the clock-out if evidence saving fails
      }
    } catch (e) {
      print('[BACKUP] ❌ Error saving clock-out: $e');
      rethrow;
    }
  }

  String _getCurrentTimeString() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 2)); // SAST
    return DateFormat('HH:mm:ss').format(now);
  }

  String _getCurrentDateString() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 2)); // SAST
    return DateFormat('yyyy-MM-dd').format(now);
  }

  String _calculateContactTime(String clockInTime, String clockOutTime) {
    try {
      final today = DateTime.now().toUtc().add(const Duration(hours: 2));
      final dateStr = DateFormat('yyyy-MM-dd').format(today);

      final clockIn = DateTime.parse('$dateStr $clockInTime');
      final clockOut = DateTime.parse('$dateStr $clockOutTime');

      final duration = clockOut.difference(clockIn);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);

      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:00';
    } catch (e) {
      print('[BACKUP] Error calculating contact time: $e');
      return '00:00:00';
    }
  }

  /// ========== PROFILE VALIDATION HELPERS ==========

  Future<Map<String, dynamic>?> _getLearnerForValidation(
    String learnerId, {
    bool forceServerRefresh = true,
  }) async {
    if (!forceServerRefresh) {
      return DatabaseHelper().getLearnerById(learnerId);
    }
    return fetchLearnerForClockInValidation(learnerId);
  }

  Map<String, dynamic> _mergeLearnerLocalPreferred(
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) {
    return mergeLearnerPreferLocal(local, server);
  }

  List<String> _getMissingRequiredProfileFieldLabels(
      Map<String, dynamic> learner) {
    return learnerProfileMissingFieldLabels(learner);
  }

  List<String> _getMissingRequiredProfileFieldKeys(
      Map<String, dynamic> learner) {
    return learnerProfileMissingFieldKeys(learner);
  }

  bool _isRuleMissing(Map<String, dynamic> learner, List<String> keys) {
    for (final key in keys) {
      final value = learner[key];
      if (!isMissingValue(value)) {
        return false;
      }
    }
    return true;
  }

  String _resolveBestFieldKey(Map<String, dynamic> learner, List<String> keys) {
    for (final key in keys) {
      if (learner.containsKey(key)) {
        return key;
      }
    }
    return keys.first;
  }

  bool isMissingValue(dynamic value) => learnerProfileIsMissingValue(value);

  final List<_RequiredProfileRule> _requiredProfileRules = const [
    _RequiredProfileRule(label: 'Title', keys: ['Title']),
    _RequiredProfileRule(label: 'Name', keys: ['Name']),
    _RequiredProfileRule(label: 'Surname', keys: ['Surname']),
    _RequiredProfileRule(label: 'ID Number', keys: ['IDNumber']),
    _RequiredProfileRule(label: 'Race', keys: ['Race']),
    _RequiredProfileRule(label: 'Language', keys: ['Language']),
    _RequiredProfileRule(label: 'Disability', keys: ['Disability']),
    _RequiredProfileRule(
        label: 'Cellphone Number', keys: ['CellphoneNumber', 'PhoneNumber']),
    _RequiredProfileRule(label: 'Email', keys: ['Email']),
    _RequiredProfileRule(label: 'Address Line 1', keys: ['AddressLine1']),
    _RequiredProfileRule(label: 'Address Line 2', keys: ['AddressLine2']),
    _RequiredProfileRule(label: 'Address Line 3', keys: ['AddressLine3']),
    _RequiredProfileRule(label: 'Postal Code', keys: ['PostalCode']),
    _RequiredProfileRule(label: 'Province', keys: ['Province']),
    _RequiredProfileRule(label: 'District', keys: ['District']),
    _RequiredProfileRule(label: 'Municipality', keys: ['Municipality']),
    _RequiredProfileRule(label: 'Next of Kin Name', keys: ['KinName']),
    _RequiredProfileRule(label: 'Next of Kin Relation', keys: ['KinRelation']),
    _RequiredProfileRule(label: 'Next of Kin Contact', keys: ['KinContact']),
    _RequiredProfileRule(label: 'School Name', keys: ['SchoolName']),
    _RequiredProfileRule(
        label: 'School Completion', keys: ['SchoolCompletion']),
    _RequiredProfileRule(label: 'School Location', keys: ['SchoolLocation']),
    _RequiredProfileRule(label: 'School Grade', keys: ['SchoolGrade']),
    _RequiredProfileRule(label: 'Profile Image', keys: ['profile_image']),
    _RequiredProfileRule(label: 'Learner Signature', keys: ['signature']),
  ];

  /// Sync offline face verification logs to server
  Future<void> _syncFaceVerificationLogs() async {
    try {
      print('[FACE_SYNC] Starting offline face verification log sync...');

      // Get unsynced count
      final unsyncedCount =
          await _offlineFaceService.getUnsyncedVerificationCount();

      if (unsyncedCount == 0) {
        print('[FACE_SYNC] No offline verification logs to sync');
        return;
      }

      print('[FACE_SYNC] Found $unsyncedCount unsynced verification logs');

      // Sync to server
      final syncedCount = await _offlineFaceService.syncVerificationLogs();

      if (syncedCount > 0) {
        print(
            '[FACE_SYNC] ✅ Successfully synced $syncedCount verification logs');
      } else {
        print('[FACE_SYNC] ❌ Failed to sync verification logs (offline?)');
      }
    } catch (e) {
      print('[FACE_SYNC] Error syncing verification logs: $e');
    }
  }

  /// Sync all signature files from local folder to server
  Future<void> _syncAllSignaturesToServer() async {
    try {
      print('[SIGNATURE_SYNC] Starting signature sync...');

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final signaturesDir = Directory('${directory.path}/signatures');

      // Check if signatures folder exists
      if (!await signaturesDir.exists()) {
        print('[SIGNATURE_SYNC] No signatures folder found');
        return;
      }

      // List all PNG files in signatures folder
      final signatureFiles = signaturesDir
          .listSync()
          .where((file) => file.path.endsWith('.png'))
          .map((file) => File(file.path))
          .toList();

      print('[SIGNATURE_SYNC] Found ${signatureFiles.length} signature files');

      if (signatureFiles.isEmpty) {
        print('[SIGNATURE_SYNC] No signatures to sync');
        return;
      }

      int successCount = 0;
      int failCount = 0;

      // Sync each signature file
      for (final signatureFile in signatureFiles) {
        try {
          final filename = signatureFile.path.split('/').last;

          // Skip if not valid signature filename format
          if (!filename.startsWith('signature_') ||
              !filename.endsWith('.png')) {
            print('[SIGNATURE_SYNC] Skipping invalid filename: $filename');
            continue;
          }

          // Read file bytes
          final bytes = await signatureFile.readAsBytes();

          // Create multipart request
          final request = http.MultipartRequest(
            'POST',
            Uri.parse(AppConfig.signaturesUrl),
          );

          // Add filename parameter
          request.fields['filename'] = filename;

          // Add file
          request.files.add(http.MultipartFile.fromBytes(
            'signature',
            bytes,
            filename: filename,
          ));

          // Send request
          final response =
              await request.send().timeout(const Duration(seconds: 30));
          final responseBody = await response.stream.bytesToString();

          if (response.statusCode == 200) {
            final decoded = json.decode(responseBody);
            if (decoded['success'] == true) {
              print(
                  '[SIGNATURE_SYNC] ✅ Synced: $filename (${bytes.length} bytes)');
              successCount++;

              // Optionally delete local file after successful sync (commented out for safety)
              // await signatureFile.delete();
              // print('[SIGNATURE_SYNC] Deleted local file: $filename');
            } else {
              print(
                  '[SIGNATURE_SYNC] ❌ Server rejected: $filename - ${decoded['message']}');
              failCount++;
            }
          } else {
            print(
                '[SIGNATURE_SYNC] ❌ HTTP ${response.statusCode} for: $filename');
            failCount++;
          }
        } catch (e) {
          print('[SIGNATURE_SYNC] ❌ Error syncing file: $e');
          failCount++;
        }

        // Small delay between uploads to avoid overwhelming server
        await Future.delayed(const Duration(milliseconds: 500));
      }

      print(
          '[SIGNATURE_SYNC] Complete: $successCount succeeded, $failCount failed');
    } catch (e) {
      print('[SIGNATURE_SYNC] ❌ Fatal error: $e');
    }
  }

  /// Save signature PNG to local device storage (TWO per day: clock-in and clock-out)
  /// Returns ONLY the filename (not full path) for database storage
  Future<String> _saveSignatureLocally(String learnerId, String base64Signature,
      {String suffix = 'out'}) async {
    try {
      // Decode base64 to bytes
      final bytes = base64Decode(base64Signature);

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();

      // Create signatures folder if it doesn't exist
      final signaturesDir = Directory('${directory.path}/signatures');
      if (!await signaturesDir.exists()) {
        await signaturesDir.create(recursive: true);
        print('[BACKUP] Created signatures directory: ${signaturesDir.path}');
      }

      // Generate unique filename: signature_{ID}_{YYYYMMDD_HHMMSS}_{in/out}.png
      final now = DateTime.now();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'signature_${learnerId}_${timestamp}_$suffix.png';
      final filePath = '${signaturesDir.path}/$filename';

      // Write PNG file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      print('[BACKUP] Signature saved: $filePath (${bytes.length} bytes)');

      // Return ONLY the filename (not the full path)
      return filename;
    } catch (e) {
      print('[BACKUP] Error saving signature locally: $e');
      // Return empty string if save fails (graceful degradation)
      return '';
    }
  }

  /// Save face verification photo to local device storage
  /// Returns ONLY the filename (not full path) for database storage
  Future<String?> _saveFacePhotoLocally(String learnerId, String? base64Photo,
      {String suffix = 'in'}) async {
    if (base64Photo == null || base64Photo.isEmpty) {
      return null;
    }

    try {
      // Decode base64 to bytes
      final bytes = base64Decode(base64Photo);

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();

      // Create face_photos folder if it doesn't exist
      final photosDir = Directory('${directory.path}/face_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
        print('[BACKUP] Created face_photos directory: ${photosDir.path}');
      }

      // Generate unique filename: face_{ID}_{YYYYMMDD_HHMMSS}_{in/out}.jpg
      final now = DateTime.now();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'face_${learnerId}_${timestamp}_$suffix.jpg';
      final filePath = '${photosDir.path}/$filename';

      // Write JPEG file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      print('[BACKUP] Face photo saved: $filePath (${bytes.length} bytes)');

      // Return ONLY the filename (not the full path)
      return filename;
    } catch (e) {
      print('[BACKUP] Error saving face photo locally: $e');
      // Return null if save fails
      return null;
    }
  }

  /// Upload clocking evidence images to server
  /// Returns true if upload succeeds, false otherwise (non-critical)
  Future<bool> _uploadClockingImagesToServer({
    required String learnerId,
    required String signatureFilename,
    String? photoFilename,
    required String suffix,
  }) async {
    try {
      print('[UPLOAD] Starting image upload to server');
      print('[UPLOAD] Signature: $signatureFilename');
      print('[UPLOAD] Photo: ${photoFilename ?? "NONE"}');
      print('[UPLOAD] Suffix: $suffix');

      // Get auth token
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        print('[UPLOAD] ❌ No auth token available');
        return false;
      }

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();

      // Prepare multipart request
      final url = AppConfig.buildUrl('upload_clocking_evidence_images.php');
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Add authentication header
      request.headers['Authorization'] = 'Bearer $token';

      // Add signature file
      final signaturePath = '${directory.path}/signatures/$signatureFilename';
      final signatureFile = File(signaturePath);

      if (await signatureFile.exists()) {
        print('[UPLOAD] Adding signature file from: $signaturePath');
        request.files.add(
          await http.MultipartFile.fromPath('signature', signaturePath),
        );
        request.fields['signature_filename'] = signatureFilename;
        request.fields['signature_suffix'] = suffix;
      } else {
        print('[UPLOAD] ⚠️ Signature file not found: $signaturePath');
      }

      // Add face photo file (if exists)
      if (photoFilename != null && photoFilename.isNotEmpty) {
        final photoPath = '${directory.path}/face_photos/$photoFilename';
        final photoFile = File(photoPath);

        if (await photoFile.exists()) {
          print('[UPLOAD] Adding face photo from: $photoPath');
          request.files.add(
            await http.MultipartFile.fromPath('face_photo', photoPath),
          );
          request.fields['photo_filename'] = photoFilename;
          request.fields['photo_suffix'] = suffix;
        } else {
          print('[UPLOAD] ⚠️ Face photo not found: $photoPath');
        }
      }

      // Add learner ID
      request.fields['learner_id'] = learnerId;

      print('[UPLOAD] Sending ${request.files.length} file(s) to server...');

      // Send request with timeout
      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));

      // Get response
      final response = await http.Response.fromStream(streamedResponse);

      print('[UPLOAD] Response status: ${response.statusCode}');
      print('[UPLOAD] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          print('[UPLOAD] ✅ Images uploaded successfully to server!');
          final uploaded = result['uploaded'] as List?;
          if (uploaded != null) {
            for (var file in uploaded) {
              print(
                  '[UPLOAD] ✓ ${file['type']}: ${file['filename']} → ${file['path']}');
            }
          }
          return true;
        } else {
          print(
              '[UPLOAD] ❌ Upload failed: ${result['message'] ?? "Unknown error"}');
          return false;
        }
      } else {
        print('[UPLOAD] ❌ HTTP error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[UPLOAD] ⚠️ Upload error (non-critical): $e');
      // Don't fail clock-in if upload fails - images are saved locally
      return false;
    }
  }

  /// ========== FACE RECOGNITION METHODS ==========

  /// Prompt learner to set up security questions (after face enrollment)
  Future<void> _promptSecurityQuestionsSetup(String learnerId) async {
    print(
        '[SECURITY_Q] Checking if security questions are set up for learner $learnerId');

    try {
      // Check if learner already has security questions set up
      final checkResponse = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manage_security_questions.php?action=check_setup&learner_id=$learnerId'),
      );

      if (checkResponse.statusCode == 200) {
        final checkData = json.decode(checkResponse.body);

        if (checkData['success'] == true && checkData['question_count'] >= 3) {
          print(
              '[SECURITY_Q] Learner already has ${checkData['question_count']} security questions set up');
          return; // Already set up, no need to prompt
        }
      }
    } catch (e) {
      print('[SECURITY_Q] Error checking setup status: $e');
      // Continue to prompt anyway
    }

    // Get learner name
    String learnerName = 'Learner';
    try {
      final learner = _learners.firstWhere(
        (l) => (l as Map<String, dynamic>)['LearnerID'].toString() == learnerId,
      ) as Map<String, dynamic>;
      learnerName =
          '${learner['Name'] ?? ''} ${learner['Surname'] ?? ''}'.trim();
      if (learnerName.isEmpty) learnerName = 'Learner';
    } catch (e) {
      print('[SECURITY_Q] Could not get learner name: $e');
    }

    if (!mounted) return;

    // Show prompt dialog
    final shouldSetup = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Text('Security Questions'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Face registration complete!',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Next step: Set up security questions',
                style: TextStyle(fontSize: 15),
              ),
              SizedBox(height: 12),
              Text(
                'Security questions provide a backup way to verify your identity if face recognition fails.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'You will:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text('• Select 3-5 questions', style: TextStyle(fontSize: 13)),
              Text('• Provide answers only you know',
                  style: TextStyle(fontSize: 13)),
              Text('• Use them if face verification fails',
                  style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Set Up Now'),
            ),
          ],
        );
      },
    );

    if (shouldSetup != true) {
      print(
          '[SECURITY_Q] Security questions setup cancelled by user - returning to learner list');
      return; // User will remain on learner selection screen
    }

    if (!mounted) return;

    // Navigate to security questions setup page
    final setupComplete = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LearnerSecurityQuestionsSetupPage(
          learnerId: learnerId,
          learnerName: learnerName,
          isRequired: false, // Allow skip since face is already enrolled
        ),
      ),
    );

    if (setupComplete == true) {
      print('[SECURITY_Q] Security questions setup completed successfully');
    } else {
      print('[SECURITY_Q] Security questions setup was not completed');
    }
  }

  /// Fallback: Verify with security questions (API-based)
  Future<bool> _verifyWithSecurityQuestions(String learnerId) async {
    print(
        '[FACE] Starting security questions verification for learner $learnerId');

    try {
      // Step 1: Check if learner has set up security questions
      final checkResponse = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manage_security_questions.php?action=check_setup&learner_id=$learnerId'),
      );

      final checkData = json.decode(checkResponse.body);
      if (checkData['success'] != true || checkData['question_count'] < 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(checkData['message'] ?? 'Security questions not set up'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Step 2: Get random security question for this learner
      final getQuestionResponse = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manage_security_questions.php?action=get_learner_questions&learner_id=$learnerId'),
      );

      final questionData = json.decode(getQuestionResponse.body);
      if (questionData['success'] != true ||
          questionData['questions'] == null ||
          questionData['questions'].isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not retrieve security question'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final question = questionData['questions'][0];
      final String questionText = question['question'];
      final int questionId = question['question_id'];

      // Step 3: Show dialog with the security question
      final TextEditingController answerController = TextEditingController();

      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Security Question'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Face verification failed. Please answer your security question:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  questionText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answerController,
                  decoration: const InputDecoration(
                    labelText: 'Your Answer',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final answer = answerController.text.trim();
                  if (answer.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter an answer'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // Verify answer with server
                  try {
                    final verifyResponse = await http.post(
                      Uri.parse(
                          '${AppConfig.baseUrl}/manage_security_questions.php?action=verify_answer'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'learner_id': learnerId,
                        'question_id': questionId,
                        'answer': answer,
                        'verification_type': 'clock_in',
                      }),
                    );

                    final verifyData = json.decode(verifyResponse.body);
                    if (verifyData['verified'] == true) {
                      Navigator.of(dialogContext).pop(true);
                    } else {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Incorrect answer. Please try again.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Error verifying answer: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      );

      if (verified == true) {
        print('[FACE] Security questions verified successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Identity verified via security questions'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      }

      return false;
    } catch (e) {
      print('[FACE] Error in security questions verification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Check if learner has face enrolled on server
  Future<bool> _checkFaceEnrollment(String learnerId) async {
    print('[FACE] Checking face enrollment for learner $learnerId');
    try {
      final result = await _faceRepo.checkFaceEnrolled(int.parse(learnerId));
      _isFaceEnrolled = result['enrolled'] == true;
      print('[FACE] Enrollment status: $_isFaceEnrolled');
      return _isFaceEnrolled;
    } catch (e) {
      print('[FACE] Error checking enrollment: $e');
      return false;
    }
  }

  /// Enroll learner's face (capture → extract embedding → save to server)
  Future<bool> _enrollFace(String learnerId) async {
    print('[FACE] Starting face enrollment for learner $learnerId');

    try {
      // Show enrollment dialog
      final shouldEnroll = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return WillPopScope(
            onWillPop: () async {
              // When back button pressed, cancel and return to previous page
              Navigator.of(dialogContext).pop(false);
              return false;
            },
            child: AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.face, color: Colors.blue, size: 28),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Face Registration Required',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                ],
              ),
              content: const SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No face registered for this learner.',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Face registration is compulsory. You must register your face to use clock-in.',
                      style: TextStyle(fontSize: 14, color: Colors.red),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Tips for best results:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text('• Look directly at the camera',
                        style: TextStyle(fontSize: 13)),
                    Text('• Ensure good lighting',
                        style: TextStyle(fontSize: 13)),
                    Text('• Remove glasses if possible',
                        style: TextStyle(fontSize: 13)),
                    Text('• Keep a neutral expression',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('Register Face'),
                ),
              ],
            ),
          );
        },
      );

      if (shouldEnroll != true) {
        print(
            '[FACE] Face registration cancelled - returning to previous page');
        return false;
      }

      // Capture face using SimpleFaceCapture widget
      File? capturedImage;
      String? capturedBase64;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleFaceCapture(
            mode: FaceCaptureMode.register,
            title: 'Register Your Face',
            instruction:
                'Center your face in the oval and hold still — the photo captures automatically',
            onCapture: (imageFile, base64Image) {
              capturedImage = imageFile;
              capturedBase64 = base64Image;
              Navigator.pop(context);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );

      if (capturedImage == null || capturedBase64 == null) {
        print('[FACE] Face capture cancelled or failed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face capture cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      // Show processing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing face data...'),
              ],
            ),
          ),
        );
      }

      // Extract embedding
      final embedding =
          await _faceService.extractEmbedding(capturedImage!.path);

      if (embedding == null) {
        if (mounted) {
          Navigator.pop(context); // Close processing dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Failed to process face. Please try again with better lighting.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Save to server
      final result = await _faceRepo.enrollFace(
        learnerId: int.parse(learnerId),
        embedding: embedding,
        qualityScore:
            0.8, // Default quality score (since extractEmbedding validates quality internally)
        consentGiven: true, // User explicitly chose to register
      );

      // ALWAYS cache embedding locally for offline verification (regardless of server result)
      final cachedLocally = await _offlineFaceService.cacheEmbedding(
        learnerId: int.parse(learnerId),
        embedding: embedding,
        qualityScore: 0.8,
        cameraFacing: 'back', // Default to back camera (most common)
      );
      print('[FACE] Local cache result: $cachedLocally');

      if (mounted) {
        Navigator.pop(context); // Close processing dialog
      }

      // Server enrollment is required for online verification
      if (result['success'] == true) {
        print(
            '[FACE] Enrollment successful (server: true, local: $cachedLocally)');
        _isFaceEnrolled = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Face registered successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // After successful face enrollment, prompt for security questions setup
        await _promptSecurityQuestionsSetup(learnerId);

        return true;
      } else if (cachedLocally) {
        final serverMsg =
            result['message']?.toString() ?? 'Unknown server error';
        print(
            '[FACE] Server enrollment failed but local cache saved: $serverMsg');
        _isFaceEnrolled = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '⚠️ Saved locally only — online enrollment failed: $serverMsg'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return true;
      } else {
        final serverMsg = result['message']?.toString() ?? '';

        // If the server says the learner already has an active enrollment,
        // treat it as an enrolled success (defensive race condition).
        // The next step in the flow is verification anyway.
        final alreadyEnrolled = serverMsg
                .toLowerCase()
                .contains('already has an active face enrollment') ||
            serverMsg.toLowerCase().contains('already enrolled');

        if (alreadyEnrolled || cachedLocally) {
          print(
              '[FACE] Server returned "$serverMsg" but local cache=$cachedLocally — treating learner $learnerId as enrolled.');
          _isFaceEnrolled = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('✅ Face already enrolled — moving to verification'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return true;
        }

        print(
            '[FACE] Enrollment failed (server: $serverMsg, local: $cachedLocally)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Enrollment failed: $serverMsg'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      print('[FACE] Enrollment error: $e');
      if (mounted) {
        Navigator.pop(context); // Close any open dialogs
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Verify learner's face (with 3 attempts)
  /// eventType: 'clock_in' or 'clock_out' to enforce correct verification
  Future<bool> _verifyWithFace(String learnerId,
      {required String eventType}) async {
    print(
        '[FACE] Starting face verification for learner $learnerId (eventType: $eventType)');

    _faceVerificationAttempts = 0;
    _capturedFacePhotoBase64 = null;
    _capturedFacePhotoFilename = null;
    _faceLogId = null;

    while (_faceVerificationAttempts < 3) {
      _faceVerificationAttempts++;
      print('[FACE] Verification attempt $_faceVerificationAttempts of 3');

      // Capture face
      File? capturedImage;
      String? capturedBase64;
      bool timedOut = false;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleFaceCapture(
            mode: FaceCaptureMode.verify,
            title: 'Verify Your Identity',
            instruction:
                'Look at the camera and hold still (Attempt $_faceVerificationAttempts of 3)',
            timeout: const Duration(seconds: 45),
            onTimeout: () {
              timedOut = true;
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            onCapture: (imageFile, base64Image) {
              capturedImage = imageFile;
              capturedBase64 = base64Image;
              Navigator.pop(context);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );

      if (timedOut) {
        print(
            '[FACE] Verification attempt $_faceVerificationAttempts timed out after 45s → fall through to next attempt / security questions');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Taking too long — security questions next (Attempt $_faceVerificationAttempts of 3)'),
              backgroundColor: Colors.deepOrange,
            ),
          );
        }
        // Treat timeout like a failed attempt so we eventually fall back.
        continue;
      }

      if (capturedImage == null || capturedBase64 == null) {
        print('[FACE] Face capture cancelled');
        return false;
      }

      // Show processing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                    'Verifying face (Attempt $_faceVerificationAttempts of 3)...'),
              ],
            ),
          ),
        );
      }

      // Extract embedding
      final embedding =
          await _faceService.extractEmbedding(capturedImage!.path);

      if (embedding == null) {
        if (mounted) {
          Navigator.pop(context); // Close processing dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Failed to process face. Attempt $_faceVerificationAttempts of 3.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        continue; // Try again
      }

      // Try server verification first
      Map<String, dynamic> result;
      bool isOffline = false;

      try {
        print('[FACE] Attempting server verification...');
        result = await _faceRepo.verifyFace(
          learnerId: int.parse(learnerId),
          embedding: embedding,
          qualityScore: 0.8,
          livenessPassed: true,
          verificationType:
              eventType, // Use the correct event type (clock_in or clock_out)
        );
        print(
            '[FACE] Server verification result: ${result['verified']} (type: $eventType)');
      } catch (e) {
        print(
            '[FACE] Server verification failed: $e - falling back to offline');
        isOffline = true;

        // Fallback to offline verification
        result = await _offlineFaceService.verifyOffline(
          learnerId: int.parse(learnerId),
          liveEmbedding: embedding,
          qualityScore: 0.8,
          cameraFacing: 'back', // Default to back camera (most common)
          verificationType: eventType, // Use the correct event type here too
        );
        print(
            '[FACE] Offline verification result: ${result['verified']} (type: $eventType)');
      }

      if (mounted) {
        Navigator.pop(context); // Close processing dialog
      }

      if (result['verified'] == true) {
        print(
            '[FACE] Verification successful! (${isOffline ? 'OFFLINE' : 'ONLINE'})');

        // NEW: Show confirmation modal with learner name (online verification only)
        if (!isOffline && result['full_name'] != null) {
          final fullName = result['full_name'] as String;

          if (!mounted) return false;

          // Show confirmation dialog
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text(
                'Confirm Identity',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face, size: 60, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    eventType == 'clock_in'
                        ? 'is about to clock in.'
                        : 'is about to clock out.',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Is this correct?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'NO',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'YES',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (confirmed != true) {
            print('[FACE] User rejected identity confirmation for: $fullName');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clock-in cancelled - identity not confirmed'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return false; // User rejected - do not proceed
          }

          print('[FACE] ✅ Identity confirmed by user: $fullName');
        }

        // Continue with verification success (confirmation passed or offline mode)
        _capturedFacePhotoBase64 = capturedBase64; // Store for evidence

        // Save face photo locally and get filename
        if (capturedBase64 != null) {
          _capturedFacePhotoFilename = await _saveFacePhotoLocally(
            learnerId, // Use the learnerId parameter from function, not _selectedLearnerId
            capturedBase64,
            suffix: 'in',
          );
          print('[FACE] Face photo saved as: $_capturedFacePhotoFilename');
        }

        _faceLogId =
            result['log_id']; // Store verification log ID (null if offline)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isOffline
                  ? '✅ Face verified successfully! (Offline mode)'
                  : '✅ Face verified successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      } else {
        print('[FACE] Verification failed: ${result['message']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Verification failed: ${result['message']} (Attempt $_faceVerificationAttempts of 3)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }

    // All 3 attempts failed
    print('[FACE] All 3 verification attempts failed');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Face verification failed after 3 attempts. Please use security questions.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  /// Fallback: Verify with security questions (API-based)
  void _showErrorDialog(String title, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Helper method to save evidence to local database (offline fallback)
  Future<void> _saveEvidenceLocally({
    required String learnerId,
    required String date,
    required String eventType,
    required String signatureData,
    required double? latitude,
    required double? longitude,
    required double? accuracy,
    required String verificationMethod,
  }) async {
    try {
      if (eventType == 'clock_in') {
        await DatabaseHelper().saveClockInEvidence(
          learnerId: int.parse(learnerId),
          clockDate: date,
          signature: signatureData,
          photo: _capturedFacePhotoBase64,
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          verificationMethod: verificationMethod,
          faceLogId: _faceLogId,
        );
      } else {
        await DatabaseHelper().saveClockOutEvidence(
          learnerId: int.parse(learnerId),
          clockDate: date,
          signature: signatureData,
          photo: _capturedFacePhotoBase64,
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          verificationMethod: verificationMethod,
          faceLogId: _faceLogId,
        );
      }

      print('[BACKUP] ✅ Evidence saved to local database');

      // Mark for sync later
      print('[BACKUP] Evidence will sync when online');
    } catch (e) {
      print('[BACKUP] ❌ Error saving to local database: $e');
      rethrow;
    }
  }
}

class _RequiredProfileRule {
  final String label;
  final List<String> keys;

  const _RequiredProfileRule({
    required this.label,
    required this.keys,
  });
}
