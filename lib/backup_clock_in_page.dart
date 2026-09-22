import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'config.dart';
import 'database_helper.dart';
import 'services/secure_location_service.dart';
import 'package:http/http.dart' as http;
import 'LearnerDetailsPage.dart';
import 'services/face_embedding_service.dart';
import 'repositories/face_verification_repository.dart';
import 'widgets/simple_face_capture.dart';
import 'services/offline_face_verification_service.dart';

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

class _BackupClockInPageState extends State<BackupClockInPage> {
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
      // PRIORITY 1: Use learners passed from parent widget (server data - most current)
      if (widget.learners.isNotEmpty) {
        print(
            '[BACKUP_LOAD] Using ${widget.learners.length} learners from parent widget (server data)');
        setState(() {
          _learners = widget.learners;
          _isLoadingLearners = false;
        });
        // Load clocking status after learners are loaded
        await _loadClockingStatus();
        return;
      }

      // PRIORITY 2: Try offline database (fallback only)
      final db = await DatabaseHelper().database;
      final offlineResult = await db.rawQuery('''
        SELECT LearnerID, Name, Surname, IDNumber, ProfileImage
        FROM learnerdetails 
        WHERE classID = ? 
        ORDER BY Name, Surname
      ''', [widget.classID]);

      if (offlineResult.isNotEmpty) {
        print(
            '[BACKUP_LOAD] Loaded ${offlineResult.length} learners from offline DB for classID ${widget.classID}');
        setState(() {
          _learners = offlineResult;
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

    const preserveIfLocalHasData = [
      'Province',
      'District',
      'Municipality',
      'Title',
      'Name',
      'Surname',
      'IDNumber',
      'Race',
      'Language',
      'Disability',
      'PhoneNumber',
      'CellphoneNumber',
      'Email',
      'AddressLine1',
      'AddressLine2',
      'AddressLine3',
      'PostalCode',
      'KinName',
      'KinRelation',
      'KinContact',
      'SchoolName',
      'SchoolCompletion',
      'SchoolLocation',
      'SchoolGrade',
      'profile_image',
      'signature',
    ];

    for (final key in preserveIfLocalHasData) {
      final localValue = existing[key];
      final incomingValue = incoming[key];
      if (!isMissingValue(localValue) && isMissingValue(incomingValue)) {
        merged[key] = localValue;
      }
    }

    if (existing['synced'] == 0) {
      for (final entry in existing.entries) {
        if (!isMissingValue(entry.value) && isMissingValue(merged[entry.key])) {
          merged[entry.key] = entry.value;
        }
      }
    }

    return merged;
  }

  /// Load clocking status for all learners
  Future<void> _loadClockingStatus() async {
    // Wait for learners to load first
    if (_isLoadingLearners || _learners.isEmpty) {
      print('[BACKUP_STATUS] Waiting for learners to load...');
      return;
    }

    try {
      final db = await DatabaseHelper().database;
      final today = DateTime.now().toUtc().add(const Duration(hours: 2));
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      print('[BACKUP_STATUS] ===== LOADING STATUS =====');
      print('[BACKUP_STATUS] Loading status for date: $todayStr');
      print('[BACKUP_STATUS] Total learners: ${_learners.length}');

      for (var learner in _learners) {
        final learnerMap = learner as Map<String, dynamic>;
        final learnerId = learnerMap['LearnerID'].toString();
        final learnerName = '${learnerMap['Name']} ${learnerMap['Surname']}';

        // Check if learner has clocked in today but not clocked out
        final result = await db.rawQuery('''
          SELECT clock_in_time, clock_out_time, clock_date, synced
          FROM learner_clocking 
          WHERE LearnerID = ? 
            AND DATE(clock_date) = ?
          ORDER BY clock_in_time DESC
          LIMIT 1
        ''', [learnerId, todayStr]);

        print('[BACKUP_STATUS] --- Learner: $learnerName (ID: $learnerId) ---');
        print('[BACKUP_STATUS]     Records found: ${result.length}');

        if (result.isNotEmpty) {
          final record = result.first;
          final clockInTime = record['clock_in_time'];
          final clockOutTime = record['clock_out_time'];
          final clockDate = record['clock_date'];
          final synced = record['synced'];

          print('[BACKUP_STATUS]     clock_date=$clockDate');
          print('[BACKUP_STATUS]     clock_in=$clockInTime');
          print('[BACKUP_STATUS]     clock_out=$clockOutTime');
          print('[BACKUP_STATUS]     synced=$synced');

          if (mounted) {
            setState(() {
              // Clocked in if there's a clock-in time but no clock-out time (or empty string)
              final hasClockIn =
                  clockInTime != null && clockInTime.toString().isNotEmpty;
              final hasClockOut = clockOutTime != null &&
                  clockOutTime.toString().isNotEmpty &&
                  clockOutTime.toString() != 'null';

              // Check if day is completed (both clock in AND clock out)
              _hasCompletedDay[learnerId] = hasClockIn && hasClockOut;

              // Clocked in only if they have clock-in but NO clock-out
              _isClockedIn[learnerId] = hasClockIn && !hasClockOut;

              final isClockedIn = _isClockedIn[learnerId] ?? false;
              final hasCompleted = _hasCompletedDay[learnerId] ?? false;

              print(
                  '[BACKUP_STATUS]     Status: ${hasCompleted ? "✓✓ COMPLETED DAY" : isClockedIn ? "✓ CLOCKED IN" : "✗ NOT CLOCKED IN"} (hasClockIn=$hasClockIn, hasClockOut=$hasClockOut)');
            });
          }
        } else {
          print('[BACKUP_STATUS]     Status: ✗ NO RECORDS FOR TODAY');
          if (mounted) {
            setState(() {
              _isClockedIn[learnerId] = false;
              _hasCompletedDay[learnerId] = false;
            });
          }
        }
      }
      print('[BACKUP_STATUS] ===== STATUS LOADING COMPLETE =====');
    } catch (e) {
      print('[BACKUP] Error loading clocking status: $e');
      print('[BACKUP] Stack trace: ${StackTrace.current}');
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
                                    const Text(
                                      'Already clocked in',
                                      style: TextStyle(
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

      // Step 5: ID verification
      setState(() => _currentStep = 'id_verification');
      print('[BACKUP_CLOCKIN] ===== STEP 5: ID VERIFICATION =====');
      final idVerified = await _verifyLearnerID(learnerId);
      print('[BACKUP_CLOCKIN] ID verification result: $idVerified');

      if (!idVerified) {
        print(
            '[BACKUP_CLOCKIN] ID verification FAILED or CANCELLED - stopping');
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 5.5: Face Recognition (NEW)
      print('[BACKUP_CLOCKIN] ===== STEP 5.5: FACE RECOGNITION =====');
      setState(() => _currentStep = 'face_check');

      // Check if face is enrolled
      final hasEnrolledFace = await _checkFaceEnrollment(learnerId);

      if (!hasEnrolledFace) {
        // Offer to enroll face
        print('[BACKUP_CLOCKIN] No face enrolled - offering enrollment');
        final enrolled = await _enrollFace(learnerId);
        if (!enrolled) {
          print(
              '[BACKUP_CLOCKIN] Face enrollment skipped or failed - continuing without face verification');
        }
      }

      // If face is enrolled (either already or just enrolled), verify it
      if (_isFaceEnrolled) {
        print('[BACKUP_CLOCKIN] Face enrolled - starting verification');
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
                '[BACKUP_CLOCKIN] Security questions verification FAILED - stopping');
            setState(() {
              _isClockingIn[learnerId] = false;
              _currentStep = null;
            });
            return;
          }

          print('[BACKUP_CLOCKIN] Security questions verification SUCCESS');
        } else {
          print('[BACKUP_CLOCKIN] Face verification SUCCESS - photo captured');
        }
      } else {
        print('[BACKUP_CLOCKIN] No face enrolled - skipping face verification');
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

      // Step 2: ID verification
      setState(() => _currentStep = 'id_verification');
      print('[BACKUP_CLOCKOUT] ===== STEP 2: ID VERIFICATION =====');
      final idVerified = await _verifyLearnerID(learnerId);
      print('[BACKUP_CLOCKOUT] ID verification result: $idVerified');

      if (!idVerified) {
        print('[BACKUP_CLOCKOUT] ID verification FAILED - stopping');
        setState(() {
          _isClockingIn[learnerId] = false;
          _currentStep = null;
        });
        return;
      }

      // Step 3: Face Recognition (VERIFY IDENTITY)
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

  Future<bool> _ensureLearnerProfileComplete(String learnerId) async {
    final learner = await _getLearnerForValidation(learnerId);
    if (learner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load learner profile. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    final missingFieldLabels = _getMissingRequiredProfileFieldLabels(learner);
    final missingFieldKeys = _getMissingRequiredProfileFieldKeys(learner);
    if (missingFieldLabels.isEmpty) {
      return true;
    }

    final learnerIdInt = int.tryParse(learnerId);
    if (learnerIdInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid learner ID for profile completion.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    final shouldOpenProfile = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Complete Learner Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This learner profile is incomplete. Please fill in missing fields and press Update Data before clock-in.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Missing fields:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...missingFieldLabels.map((field) => Text('- $field')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open Profile'),
            ),
          ],
        );
      },
    );

    if (shouldOpenProfile != true) {
      return false;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LearnerDetailsPage(
          learnerID: learnerId,
          missingProfileOnlyMode: true,
          missingProfileFields: missingFieldKeys,
        ),
      ),
    );

    if (!mounted) return false;

    final refreshedLearner = await _getLearnerForValidation(learnerId);
    final refreshedMissing =
        _getMissingRequiredProfileFieldLabels(refreshedLearner ?? {});

    if (refreshedMissing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile still incomplete: ${refreshedMissing.join(', ')}. Please update before clock-in.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    return true;
  }

  Future<bool> _ensureLearnerBankDetailsComplete(String learnerId) async {
    print(
        '[BACKUP] Bank check skipped in backup mode - not required for clock-in');
    // Bank details validation is optional in backup clock-in mode
    // The focus is on attendance tracking, not payment processing
    return true;
  }

  Future<bool> _checkDocumentCompleteness(String learnerId) async {
    print('[BACKUP] Checking documents for learner $learnerId');

    while (true) {
      // Get detailed document statuses (not just missing, but with status info)
      final docStatuses = await _getDetailedDocumentStatuses(learnerId);

      if (docStatuses['allApproved'] == true) {
        return true; // All 3 mandatory docs are approved
      }

      final List<Map<String, dynamic>> problemDocs =
          docStatuses['documents'] ?? [];

      final action = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
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
                  ...problemDocs.map((doc) {
                    final docName = doc['name'] ?? '';
                    final status = doc['status'] ?? 'Not Uploaded';
                    final reason = doc['reason'];

                    Color iconColor = Colors.orange;
                    IconData icon = Icons.error_outline;
                    if (status == 'Declined') {
                      iconColor = Colors.red;
                      icon = Icons.cancel;
                    } else if (status == 'Not Uploaded') {
                      iconColor = Colors.grey;
                      icon = Icons.upload_file;
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
                          if (reason != null &&
                              reason.toString().isNotEmpty) ...[
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

      if (action != null && action['action'] == 'reupload') {
        // Handle re-upload for declined document
        final docName = action['document'];
        await _handleDocumentReupload(learnerId, docName);
        continue; // Check again after re-upload
      }

      // User clicked OK - block clock-in
      return false;
    }
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

      // CHECK FOR DUPLICATES - prevent creating duplicate records locally
      final existingRecord =
          await DatabaseHelper().getAttendanceForDay(learnerId, date);
      if (existingRecord != null && existingRecord['clock_in_time'] != null) {
        print(
            '[BACKUP] ⚠️ Clock-in record already exists for today - skipping duplicate insert');
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

      // Try to sync to server if online
      bool synced = false;
      try {
        final body = {
          'clock_in': '1',
          'LearnerID': learnerId,
          'clock_in_time': now,
          'clock_date': date,
          'classID': widget.classID,
          'signature': clockInSignatureFilename,
          'method': 'manual',
        };

        // Add GPS data if available (CRITICAL for server-side geofencing)
        if (clockInLatitude != null && clockInLongitude != null) {
          body['latitude'] = clockInLatitude.toString();
          body['longitude'] = clockInLongitude.toString();
          body['accuracy'] = (clockInAccuracy ?? 999).toString();
          body['is_mocked'] = (isMocked ?? false).toString();
          body['passed_sanity'] = (passedSanity ?? true).toString();
          print('[BACKUP] ✅ Including GPS data in POST request');
        } else {
          print('[BACKUP] ⚠️⚠️⚠️ NO GPS DATA - server will bypass geofence!');
        }

        final response = await http
            .post(
              Uri.parse(AppConfig.buildUrl('clocking/clockin.php')),
              body: body,
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          synced = decoded['success'] == true;
          if (synced) {
            print('[BACKUP] ✅ Clock-in saved to server');
          }
        }
      } catch (e) {
        print('[BACKUP] ⚠️ Server sync failed (will retry later): $e');
      }

      // Update synced flag
      dbData['synced'] = synced ? 1 : 0;

      // Insert into local database with clock-in signature - NO DUPLICATES
      await DatabaseHelper().insertClocking(dbData);
      print('[BACKUP] ✅ Clock-in saved to local database WITH signature');

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
          print(
              '[BACKUP] ℹ️ Verification method: SIGNATURE (no face enrolled or used)');
        }

        // Check if online - if yes, save directly to server
        final connectivityResult = await Connectivity().checkConnectivity();
        final isOnline = connectivityResult != ConnectivityResult.none;

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

                // AUTOMATICALLY upload images to server (non-blocking)
                print('[BACKUP] Starting automatic image upload to server...');
                _uploadClockingImagesToServer(
                  learnerId: learnerId,
                  signatureFilename: clockInSignatureFilename,
                  photoFilename: _capturedFacePhotoFilename,
                  suffix: 'in',
                ).then((success) {
                  if (success) {
                    print('[BACKUP] ✅ Images automatically uploaded to server');
                  } else {
                    print(
                        '[BACKUP] ⚠️ Image upload failed (images remain on device)');
                  }
                }).catchError((e) {
                  print('[BACKUP] ⚠️ Image upload error: $e');
                });
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

      // Get existing attendance record (created at clock-in WITH clock-in signature)
      final existingAttendance =
          await DatabaseHelper().getAttendanceForDay(learnerId, date);

      if (existingAttendance == null ||
          existingAttendance['clock_in_time'] == null) {
        throw Exception('No clock-in record found for today');
      }

      final clockInTime = existingAttendance['clock_in_time'].toString();
      final clockingId = existingAttendance['clocking_id'];
      final contactTime = _calculateContactTime(clockInTime, now);
      final clockInSignature =
          existingAttendance['signature']?.toString() ?? '';

      // Try to sync to server first
      bool synced = false;
      try {
        final response = await http.post(
          Uri.parse(AppConfig.buildUrl('clocking/clockout.php')),
          body: {
            'clock_out': '1',
            'LearnerID': learnerId,
            'clock_in_time': clockInTime,
            'clock_out_time': now,
            'contact_time': contactTime,
            'clock_date': date,
            'classID': widget.classID,
            'method': 'signature',
            'signature_in': clockInSignature, // Clock-in signature
            'signature_out': clockOutSignatureFilename, // Clock-out signature
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          synced = decoded['success'] == true;
          if (synced) {
            print('[BACKUP] ✅ Clock-out with signature saved to server');
          }
        }
      } catch (e) {
        print('[BACKUP] ⚠️ Server sync failed (will retry later): $e');
      }

      // Update database record with clock-out time AND clock-out signature ONLY
      // Replace clock-in signature with clock-out signature (keep only the last one)
      final updatedAttendance = {
        'clock_out_time': now,
        'contact_time': contactTime,
        'signature':
            clockOutSignatureFilename, // Store ONLY clock-out signature (replaces clock-in)
        'synced': synced ? 1 : 0,
      };

      await DatabaseHelper().updateClocking(clockingId, updatedAttendance);
      print(
          '[BACKUP] ✅ Clock-out saved to local database with clock-out signature (synced=$synced)');

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
        final connectivityResult = await Connectivity().checkConnectivity();
        final isOnline = connectivityResult != ConnectivityResult.none;

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

                // AUTOMATICALLY upload images to server (non-blocking)
                print(
                    '[BACKUP_CLOCKOUT] Starting automatic image upload to server...');
                _uploadClockingImagesToServer(
                  learnerId: learnerId,
                  signatureFilename: clockOutSignatureFilename,
                  photoFilename: null, // Usually no face photo on clock-out
                  suffix: 'out',
                ).then((success) {
                  if (success) {
                    print(
                        '[BACKUP_CLOCKOUT] ✅ Images automatically uploaded to server');
                  } else {
                    print(
                        '[BACKUP_CLOCKOUT] ⚠️ Image upload failed (images remain on device)');
                  }
                }).catchError((e) {
                  print('[BACKUP_CLOCKOUT] ⚠️ Image upload error: $e');
                });
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
    final localLearner = await DatabaseHelper().getLearnerById(learnerId);
    final hasUnsynced = localLearner != null && localLearner['synced'] == 0;

    if (localLearner != null) {
      print('[BACKUP] _getLearnerForValidation learnerId=$learnerId');
      print('[BACKUP] Local Province=${localLearner['Province']} '
          'District=${localLearner['District']} '
          'Municipality=${localLearner['Municipality']}');
    }

    if (!forceServerRefresh) {
      return localLearner;
    }

    if (hasUnsynced) {
      print(
          '[BACKUP] Learner $learnerId has unsynced local edits — skipping server refresh to preserve them');
      return localLearner;
    }

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        print(
            '[BACKUP] Offline — cannot refresh learner $learnerId from server');
        return localLearner;
      }

      print('[BACKUP] Refreshing learner $learnerId from server DB...');
      final url =
          '${AppConfig.learnerDetailsUrl}?LearnerID=${Uri.encodeQueryComponent(learnerId.toString())}';

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print('[BACKUP] Server refresh failed status=${response.statusCode}');
        return localLearner;
      }

      final payload = jsonDecode(response.body);
      if (payload['success'] != true || payload['data'] == null) {
        print('[BACKUP] Server refresh: ${payload['message'] ?? 'no data'}');
        return localLearner;
      }

      final serverLearner = Map<String, dynamic>.from(payload['data']);
      serverLearner['synced'] = 1;

      final merged = localLearner == null
          ? serverLearner
          : _mergeLearnerLocalPreferred(localLearner, serverLearner);

      await DatabaseHelper().updateLearnerDetails(learnerId, merged);
      print('[BACKUP] Learner $learnerId refreshed from server. '
          'Province=${merged['Province']} District=${merged['District']} '
          'Municipality=${merged['Municipality']}');
      return merged;
    } catch (e) {
      print('[BACKUP] Server refresh exception: $e');
      return localLearner;
    }
  }

  Map<String, dynamic> _mergeLearnerLocalPreferred(
    Map<String, dynamic> local,
    Map<String, dynamic> server,
  ) {
    final merged = Map<String, dynamic>.from(server);
    const preserveIfLocalHasData = [
      'Province',
      'District',
      'Municipality',
      'Title',
      'Name',
      'Surname',
      'IDNumber',
      'Race',
      'Language',
      'Disability',
      'CellphoneNumber',
      'PhoneNumber',
      'Email',
      'AddressLine1',
      'AddressLine2',
      'AddressLine3',
      'PostalCode',
      'KinName',
      'KinRelation',
      'KinContact',
      'SchoolName',
      'SchoolCompletion',
      'SchoolLocation',
      'SchoolGrade',
      'profile_image',
      'signature',
    ];

    for (final key in preserveIfLocalHasData) {
      final localValue = local[key];
      final serverValue = server[key];
      if (!isMissingValue(localValue) && isMissingValue(serverValue)) {
        merged[key] = localValue;
      }
    }

    if (local['synced'] == 0) {
      for (final e in local.entries) {
        if (!isMissingValue(e.value) && isMissingValue(merged[e.key])) {
          merged[e.key] = e.value;
        }
      }
      merged['synced'] = 0;
    } else {
      merged['synced'] = 1;
    }
    return merged;
  }

  List<String> _getMissingRequiredProfileFieldLabels(
      Map<String, dynamic> learner) {
    final missing = <String>[];
    for (final rule in _requiredProfileRules) {
      if (_isRuleMissing(learner, rule.keys)) {
        missing.add(rule.label);
      }
    }
    return missing;
  }

  List<String> _getMissingRequiredProfileFieldKeys(
      Map<String, dynamic> learner) {
    final missingKeys = <String>[];
    for (final rule in _requiredProfileRules) {
      if (!_isRuleMissing(learner, rule.keys)) continue;
      final bestKey = _resolveBestFieldKey(learner, rule.keys);
      missingKeys.add(bestKey);
    }
    return missingKeys;
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

  bool isMissingValue(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized.isEmpty ||
        normalized == 'null' ||
        normalized == 'n/a' ||
        normalized == 'na' ||
        normalized == '-' ||
        normalized == 'unknown' ||
        normalized.startsWith('1900-01-01');
  }

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

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();

      // Prepare multipart request
      final url = AppConfig.buildUrl('upload_clocking_evidence_images.php');
      final request = http.MultipartRequest('POST', Uri.parse(url));

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
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.face, color: Colors.blue, size: 28),
                SizedBox(width: 12),
                Text('Face Recognition Setup'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No face registered for this learner.',
                  style: TextStyle(fontSize: 15),
                ),
                SizedBox(height: 12),
                Text(
                  'Would you like to register your face now? This will be used for future clock-ins.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Text(
                  'Tips for best results:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text('• Look directly at the camera',
                    style: TextStyle(fontSize: 13)),
                Text('• Ensure good lighting', style: TextStyle(fontSize: 13)),
                Text('• Remove glasses if possible',
                    style: TextStyle(fontSize: 13)),
                Text('• Keep a neutral expression',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Skip for Now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('Register Face'),
              ),
            ],
          );
        },
      );

      if (shouldEnroll != true) {
        print('[FACE] Enrollment cancelled by user');
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

  /// Fallback: Verify with security questions
  Future<bool> _verifyWithSecurityQuestions(String learnerId) async {
    print(
        '[FACE] Starting security questions verification for learner $learnerId');

    // Get learner info
    Map<String, dynamic>? learner;
    try {
      learner = _learners.firstWhere(
        (l) => (l as Map<String, dynamic>)['LearnerID'].toString() == learnerId,
      ) as Map<String, dynamic>;
    } catch (e) {
      print('[FACE] Learner $learnerId not found for security questions: $e');
      learner = null;
    }

    if (learner == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Learner not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    final idNumber = learner['IDNumber']?.toString() ?? '';
    if (idNumber.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ID number not available for verification'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    // Show security questions dialog
    final TextEditingController answer1Controller = TextEditingController();
    final TextEditingController answer2Controller = TextEditingController();

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Security Verification'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Face verification failed. Please answer security questions:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Question 1: What is your date of birth?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('Enter first 6 digits of ID number (YYMMDD)',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: answer1Controller,
                  decoration: const InputDecoration(
                    hintText: 'YYMMDD',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Question 2: Confirm your full ID number',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: answer2Controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter full ID number',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 13,
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
              onPressed: () {
                final answer1 = answer1Controller.text.trim();
                final answer2 = answer2Controller.text.trim();

                // Verify answers
                final dobMatch = idNumber.startsWith(answer1);
                final idMatch = idNumber == answer2;

                if (dobMatch && idMatch) {
                  Navigator.of(dialogContext).pop(true);
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Incorrect answers. Please try again.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Verify'),
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
  }

  /// ========== END FACE RECOGNITION METHODS ==========

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
