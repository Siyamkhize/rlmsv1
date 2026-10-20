import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'utils/sqflite_platform.dart';
import 'utils/connectivity_utils.dart';
import 'package:signature/signature.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:math';
import 'dart:typed_data';
import 'services/comprehensive_manual_clocking_sync.dart';
import 'package:uuid/uuid.dart';

import 'DetailsPage.dart';
import 'LearnerDetailsPage.dart';
import 'sick_note_page.dart';
import 'database_helper.dart';
import 'services/secure_location_service.dart';
import 'services/timezone_validator.dart';
import 'services/offline_sync_queue_service.dart';
import 'widgets/smart_framed_camera_capture.dart';
import 'config.dart';
import 'mixins/learner_clockin_gates_mixin.dart';
import 'widgets/smart_framed_camera_capture.dart';

/// Signature + Geofencing Clock-In Page
/// Works like clock_in_page.dart but uses signature capture and geofencing validation
/// Based on LearnerListPage_signature.dart structure
class SignatureGeofenceClockInPage extends StatefulWidget {
  final String classID;
  final List<dynamic> learners;

  const SignatureGeofenceClockInPage({
    super.key,
    required this.classID,
    required this.learners,
  });

  @override
  State<SignatureGeofenceClockInPage> createState() =>
      _SignatureGeofenceClockInPageState();
}

class _SignatureGeofenceClockInPageState
    extends State<SignatureGeofenceClockInPage> with LearnerClockInGatesMixin {
  Map<String, String> clockInTimes = {};
  Map<String, String> clockOutTimes = {};
  Map<String, String> contactTimes = {};
  Map<String, bool> _unsyncedLearners = {}; // Track learners with offline data
  final Map<String, bool> _isClockingIn = {};

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<dynamic> _filteredLearners = [];

  // Signature controller
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // Photo capture state (FIXED - per learner to prevent race conditions)
  Map<int, File> _learnerPhotoFiles = {}; // Store photo files per learner ID
  Map<int, Uint8List> _learnerPhotoBytes =
      {}; // Store photo bytes per learner ID
  Map<int, Uint8List> _learnerSignatureBytes =
      {}; // Store signature bytes per learner ID
  String? _currentLearnerForCapture;
  bool _isClockInProcess = false; // true for clock-in, false for clock-out

  // Track which learners have completed evidence capture
  Map<int, bool> _learnerHasPhoto = {};
  Map<int, bool> _learnerHasSignature = {};

  // Batch mode state
  bool _batchMode = false;
  bool _isSubmittingBatch = false;
  Map<String, Map<String, dynamic>> _batchClockings = {};
  int get _pendingBatchCount => _batchClockings.length;

  // Geofencing state
  double? _currentGpsAccuracy;
  double? _siteLat;
  double? _siteLon;
  bool _isWithinRange = false;
  Position? _currentPosition;
  StreamSubscription? _liveGpsSub;
  bool _isLoadingLocation = false;

  // Connectivity
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    ensureSqflitePlatformInitialized();
    _filteredLearners = List.from(widget.learners);
    _initializeData();
    _startConnectivityMonitoring();
    _startLocationMonitoring();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _searchController.dispose();
    _liveGpsSub?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final wasOffline = !_isOnline;
      setState(() {
        _isOnline = isDeviceOnline(results);
      });
      
      // If just came online, trigger sync of offline records
      if (wasOffline && _isOnline) {
        print('[SIGNATURE_GEO] 🌐 Network restored - triggering sync of offline records');
        _triggerOfflineSync();
      }
    });
  }

  Future<void> _startLocationMonitoring() async {
    try {
      setState(() => _isLoadingLocation = true);

      // Check location permission
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final newPermission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (newPermission == LocationPermission.denied ||
            newPermission == LocationPermission.deniedForever) {
          print('[SIGNATURE_GEO] Location permission denied');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Location permission required for geofencing'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      // Load site coordinates
      await _loadSiteCoordinates();

      // Try to get GPS position first (30 second timeout for better acquisition)
      try {
        print('[SIGNATURE_GEO] Acquiring GPS position (high accuracy)...');
        final gpsPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 30));
        if (!mounted) return;

        setState(() {
          _currentPosition = gpsPosition;
          _currentGpsAccuracy = gpsPosition.accuracy;
          if (_siteLat != null && _siteLon != null) {
            final distance = _calculateDistance(
              gpsPosition.latitude,
              gpsPosition.longitude,
              _siteLat!,
              _siteLon!,
            );
            _isWithinRange = distance <= 50; // 50m radius STRICT
          }
          _isLoadingLocation = false;
        });

        print(
            '[SIGNATURE_GEO] ✅ GPS position obtained: ${gpsPosition.latitude}, ${gpsPosition.longitude}, accuracy: ${gpsPosition.accuracy}m');
      } catch (e) {
        print('[SIGNATURE_GEO] GPS acquisition failed: $e');
        
        // Fallback to network location (less accurate but better than nothing)
        try {
          print('[SIGNATURE_GEO] Trying network location fallback...');
          final networkPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 15));
          if (!mounted) return;

          setState(() {
            _currentPosition = networkPosition;
            _currentGpsAccuracy = networkPosition.accuracy;
            if (_siteLat != null && _siteLon != null) {
              final distance = _calculateDistance(
                networkPosition.latitude,
                networkPosition.longitude,
                _siteLat!,
                _siteLon!,
              );
              _isWithinRange = distance <= 50; // 50m radius STRICT
            }
            _isLoadingLocation = false;
          });

          print(
              '[SIGNATURE_GEO] ⚠️ Network location obtained: ${networkPosition.latitude}, ${networkPosition.longitude}, accuracy: ${networkPosition.accuracy}m');
          
          // Show warning that network location is less accurate
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '⚠️ Using network location (accuracy: ${networkPosition.accuracy.toStringAsFixed(0)}m). For best results, go outdoors.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        } catch (e2) {
          print('[SIGNATURE_GEO] ❌ Network location also failed: $e2');
          setState(() => _isLoadingLocation = false);
          
          // Show error with retry option
          if (!mounted) return;
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ GPS not available. Go outdoors and retry.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _startLocationMonitoring(),
              ),
            ),
          );
        }
      }

      // Start live GPS monitoring (if position was obtained)
      if (_currentPosition != null) {
        _liveGpsSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // Update every 5 meters
          ),
        ).listen((Position position) {
          setState(() {
            _currentPosition = position;
            _currentGpsAccuracy = position.accuracy;
            if (_siteLat != null && _siteLon != null) {
              final distance = _calculateDistance(
                position.latitude,
                position.longitude,
                _siteLat!,
                _siteLon!,
              );
              _isWithinRange = distance <= 50; // 50m radius STRICT
            }
          });
        });
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Error starting location monitoring: $e');
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _loadSiteCoordinates() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final result = await db.rawQuery(
        'SELECT s.latitude, s.longitude FROM class c JOIN sites s ON c.siteID = s.siteID WHERE c.classID = ?',
        [widget.classID.toString()],
      );

      if (result.isNotEmpty) {
        _siteLat = double.tryParse(result.first['latitude'].toString());
        _siteLon = double.tryParse(result.first['longitude'].toString());
        print(
          '[SIGNATURE_GEO] Site coordinates loaded: ($_siteLat, $_siteLon)',
        );
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Error loading site coordinates: $e');
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6371e3; // Earth radius in meters
    final double phi1 = lat1 * pi / 180;
    final double phi2 = lat2 * pi / 180;
    final double deltaPhi = (lat2 - lat1) * pi / 180;
    final double deltaLambda = (lon2 - lon1) * pi / 180;

    final double a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  Future<void> _initializeData() async {
    // Step 1: Sync learners from server API (if online)
    if (_isOnline) {
      try {
        print('[SIGNATURE_GEO] Syncing learners from server API...');
        final dbHelper = DatabaseHelper();
        await dbHelper.syncLearnersFromServer(widget.classID);
        print('[SIGNATURE_GEO] ✅ Successfully synced learners from server');
      } catch (e) {
        print('[SIGNATURE_GEO] ⚠️ Server sync failed, will use local data: $e');
      }
    } else {
      print('[SIGNATURE_GEO] Offline mode - skipping server sync');
    }

    // Step 2: Load learners from local database (now contains fresh server data if online)
    await _loadLearnersFromLocalDatabase();
    
    // Step 3: Fetch today's clocking status from server API
    await _fetchClockingDataFromServer();
    
    // Step 4: Check for unsynced offline records
    await _checkUnsyncedRecords();
  }

  Future<void> _loadLearnersFromLocalDatabase() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      print('[SIGNATURE_GEO] ===== DATABASE DIAGNOSTIC =====');
      print('[SIGNATURE_GEO] Looking for classID: ${widget.classID}');
      print('[SIGNATURE_GEO] ClassID type: ${widget.classID.runtimeType}');

      // Check if class exists in database
      final classCheck = await db.rawQuery('''
        SELECT classID FROM class WHERE classID = ?
      ''', [widget.classID]);
      print('[SIGNATURE_GEO] Class exists in DB: ${classCheck.isNotEmpty}');

      if (classCheck.isNotEmpty) {
        print(
            '[SIGNATURE_GEO] Found class with ID: ${classCheck.first['classID']} (type: ${classCheck.first['classID'].runtimeType})');
      }

      // Count total learners in database
      final countResult = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE CAST(classID AS TEXT) = ?
      ''', [normalizeClassId(widget.classID)]);
      print(
          '[SIGNATURE_GEO] Total learners in DB for classID ${widget.classID}: ${countResult.first['total']}');

      // Check for type mismatches - try both STRING and INTEGER
      final countAsString = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ?
      ''', [widget.classID.toString()]);
      print(
          '[SIGNATURE_GEO] Learners found with STRING classID: ${countAsString.first['total']}');

      final countAsInt = await db.rawQuery('''
        SELECT COUNT(*) as total FROM learnerdetails WHERE classID = ?
      ''', [int.tryParse(widget.classID.toString()) ?? 0]);
      print(
          '[SIGNATURE_GEO] Learners found with INTEGER classID: ${countAsInt.first['total']}');

      // Show sample classID values in database
      final sampleClassIDs = await db.rawQuery('''
        SELECT DISTINCT classID FROM learnerdetails ORDER BY classID LIMIT 10
      ''');
      print(
          '[SIGNATURE_GEO] Sample classIDs in DB: ${sampleClassIDs.map((r) => '${r['classID']} (${r['classID'].runtimeType})').join(', ')}');

      final learnersWithClockingData =
          await dbHelper.getLearnersWithClockingData(widget.classID);

      print(
          '[SIGNATURE_GEO] getLearnersWithClockingData returned: ${learnersWithClockingData.length} records');

      if (learnersWithClockingData.isNotEmpty) {
        print(
            '[SIGNATURE_GEO] First 3 learners: ${learnersWithClockingData.take(3).map((l) => '${l['Name']} ${l['Surname']} (ID: ${l['LearnerID']})').join(', ')}');
      }
      print('[SIGNATURE_GEO] ===== END DIAGNOSTIC =====');

      // If no learners found, try to create test learners for offline functionality
      if (learnersWithClockingData.isEmpty) {
        print(
            '[SIGNATURE_GEO] 🔄 No learners found, attempting to create test learners...');
        try {
          await dbHelper.ensureClassDataExists(widget.classID);
          await dbHelper.ensureTestLearnersExist(widget.classID,
              learnerCount: 5);

          // Retry loading after creating test data
          final retryData =
              await dbHelper.getLearnersWithClockingData(widget.classID);

          if (retryData.isNotEmpty) {
            print(
                '[SIGNATURE_GEO] ✅ Successfully created ${retryData.length} test learners');
            setState(() {
              widget.learners.clear();
              for (var learner in retryData) {
                Map<String, dynamic> learnerMap =
                    Map<String, dynamic>.from(learner);
                widget.learners.add(learnerMap);
              }
              _filteredLearners = List.from(widget.learners);
            });
            print(
                '[SIGNATURE_GEO] Loaded ${widget.learners.length} test learners for class ${widget.classID}');
            return;
          } else {
            print('[SIGNATURE_GEO] ❌ Failed to create test learners');
          }
        } catch (e) {
          print('[SIGNATURE_GEO] ❌ Error creating test learners: $e');
        }
      }

      if (learnersWithClockingData.isEmpty && widget.learners.isNotEmpty) {
        print(
            '[SIGNATURE_GEO] Using ${widget.learners.length} learners from dashboard (offline cache)');
        setState(() {
          _filteredLearners = List.from(widget.learners);
        });
        return;
      }

      setState(() {
        widget.learners.clear();
        for (var learner in learnersWithClockingData) {
          // Convert QueryRow to Map<String, dynamic> if needed
          Map<String, dynamic> learnerMap = Map<String, dynamic>.from(learner);

          String learnerId = learnerMap['LearnerID']?.toString() ?? 'N/A';
          String clockInTime = learnerMap['clock_in_time']?.toString() ?? '';
          String clockOutTime = learnerMap['clock_out_time']?.toString() ?? '';
          String contactTime = learnerMap['contact_time']?.toString() ?? '';

          if (clockInTime.isNotEmpty &&
              clockInTime != 'N/A' &&
              clockInTime != 'null') {
            clockInTimes[learnerId] = clockInTime;
          }
          if (clockOutTime.isNotEmpty &&
              clockOutTime != 'N/A' &&
              clockOutTime != 'null') {
            clockOutTimes[learnerId] = clockOutTime;
          }
          if (contactTime.isNotEmpty &&
              contactTime != 'N/A' &&
              contactTime != 'null') {
            contactTimes[learnerId] = contactTime;
          }

          widget.learners.add(learnerMap);
        }
        _filteredLearners = List.from(widget.learners);
      });

      print(
        '[SIGNATURE_GEO] Loaded ${widget.learners.length} learners for class ${widget.classID}',
      );
    } catch (e) {
      print('[SIGNATURE_GEO] Error loading learners: $e');
      print('[SIGNATURE_GEO] Stack trace: ${StackTrace.current}');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading learners: $e')));
    }
  }

  Future<void> _fetchClockingDataFromServer() async {
    final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (_isOnline) {
      // ONLINE: Fetch from server
      try {
        final url = Uri.parse(
          AppConfig.buildUrl(
              'get_manual_clocking_status.php?clock_date=$currentDate&classID=${widget.classID}'),
        );

        final response =
            await http.get(url).timeout(const Duration(seconds: 10));

        print('[SIGNATURE_GEO] Fetch status response code: ${response.statusCode}');
        print('[SIGNATURE_GEO] Fetch status URL: $url');

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          
          print('[SIGNATURE_GEO] Endpoint response keys: ${result.keys.toList()}');
          print('[SIGNATURE_GEO] success=${result['success']}, count=${result['count']}');

          if (result['success'] == true && result['records'] is List) {
            print('[SIGNATURE_GEO] Processing ${result['records'].length} records...');
            
            // Track which learners are confirmed on server
            Set<String> serverLearnerIDs = {};
            
            for (var record in result['records']) {
              final learnerID = record['learner_id'].toString();
              final clockInTime = record['clock_in_time']?.toString() ?? '';
              final clockOutTime = record['clock_out_time']?.toString() ?? '';
              final contactTime = record['contact_time']?.toString() ?? '';

              if (clockInTime.isNotEmpty) {
                print('[SIGNATURE_GEO] Setting clock-in for learner $learnerID: $clockInTime');
                serverLearnerIDs.add(learnerID); // Mark as on server
              }

              setState(() {
                if (clockInTime.isNotEmpty)
                  clockInTimes[learnerID] = clockInTime;
                if (clockOutTime.isNotEmpty)
                  clockOutTimes[learnerID] = clockOutTime;
                if (contactTime.isNotEmpty)
                  contactTimes[learnerID] = contactTime;
                  
                // Mark as synced (on server) - GREEN
                if (clockInTime.isNotEmpty) {
                  _unsyncedLearners[learnerID] = false;
                }
              });
            }

            print('[SIGNATURE_GEO] ✅ Loaded ${result['count']} manual clocking records from server');
            print('[SIGNATURE_GEO] ✅ clockInTimes map now has ${clockInTimes.length} entries');
            print('[SIGNATURE_GEO] 🟢 Server learners (synced): $serverLearnerIDs');
          } else {
            print('[SIGNATURE_GEO] ⚠️ Unexpected response format or empty records');
          }
        }
      } catch (e) {
        print(
            '[SIGNATURE_GEO] Server fetch failed, falling back to local: $e');
        await _loadClockingDataFromLocal(currentDate);
      }
    } else {
      // OFFLINE: Load from local database
      print('[SIGNATURE_GEO] Offline mode - loading from local database');
      await _loadClockingDataFromLocal(currentDate);
    }
  }

  /// Load today's clocking data from local manual_clocking table (offline fallback)
  Future<void> _loadClockingDataFromLocal(String currentDate) async {
    try {
      final db = await DatabaseHelper().database;
      final records = await db.query(
        'manual_clocking',
        where: 'clock_date = ?',
        whereArgs: [currentDate],
      );

      for (var record in records) {
        final learnerID = record['LearnerID'].toString();
        final clockInTime = record['clock_in_time']?.toString() ?? '';
        final clockOutTime = record['clock_out_time']?.toString() ?? '';
        final contactTime = record['contact_time']?.toString() ?? '';

        setState(() {
          if (clockInTime.isNotEmpty) clockInTimes[learnerID] = clockInTime;
          if (clockOutTime.isNotEmpty)
            clockOutTimes[learnerID] = clockOutTime;
          if (contactTime.isNotEmpty) contactTimes[learnerID] = contactTime;
        });
      }

      print(
          '[SIGNATURE_GEO] Loaded ${records.length} records from local manual_clocking table');
    } catch (e) {
      print('[SIGNATURE_GEO] Error loading local clocking data: $e');
    }
  }

  /// Check for unsynced records - learners in local DB but NOT confirmed by server
  Future<void> _checkUnsyncedRecords() async {
    try {
      final db = await DatabaseHelper().database;
      final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      // Get all learners from local manual_clocking for today
      final localRecords = await db.query(
        'manual_clocking',
        where: 'clock_date = ?',
        whereArgs: [currentDate],
      );

      print('[SIGNATURE_GEO] Found ${localRecords.length} local records for today');
      
      setState(() {
        for (var record in localRecords) {
          final learnerID = record['LearnerID'].toString();
          final clockInTime = record['clock_in_time']?.toString() ?? '';
          
          if (clockInTime.isEmpty) continue;
          
          // Check if this learner was confirmed by server
          // If _unsyncedLearners already has entry with false (from server fetch), keep it green
          // If no entry exists, it means server didn't return this learner = ORANGE
          if (!_unsyncedLearners.containsKey(learnerID)) {
            _unsyncedLearners[learnerID] = true; // Mark as ORANGE (not on server yet)
            
            // Also add to clockInTimes if not already there
            if (!clockInTimes.containsKey(learnerID)) {
              clockInTimes[learnerID] = clockInTime;
            }
            
            print('[SIGNATURE_GEO] 🟠 Learner $learnerID in local DB but NOT on server - marked UNSYNCED');
          } else {
            print('[SIGNATURE_GEO] 🟢 Learner $learnerID confirmed on server - SYNCED');
          }
        }
      });
      
      final unsyncedCount = _unsyncedLearners.values.where((v) => v == true).length;
      final syncedCount = _unsyncedLearners.values.where((v) => v == false).length;
      print('[SIGNATURE_GEO] === Sync Summary ===');
      print('[SIGNATURE_GEO] 🟢 Synced (on server): $syncedCount learners');
      print('[SIGNATURE_GEO] 🟠 Unsynced (offline only): $unsyncedCount learners');
    } catch (e) {
      print('[SIGNATURE_GEO] Error checking unsynced records: $e');
    }
  }

  Future<void> _syncOfflineClockIns() async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final offlineRecords = await db.query(
      'manual_clocking',
      where: 'synced = ?',
      whereArgs: [0],
    );

    for (var record in offlineRecords) {
      try {
        final learnerID = record['LearnerID'].toString();
        final signaturePath = record['signature']?.toString() ?? '';
        await _clockInOnline(learnerID, signaturePath);
        await db.update(
          'manual_clocking',
          {'synced': 1},
          where: 'LearnerID = ? AND clock_date = ?',
          whereArgs: [learnerID, record['clock_date'].toString()],
        );
        print('[SIGNATURE_GEO] Synced offline clock-in for $learnerID');
      } catch (e) {
        print('[SIGNATURE_GEO] Failed to sync offline clock-in: $e');
      }
    }
  }

  void _filterLearners(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredLearners = List.from(widget.learners);
      } else {
        _filteredLearners = widget.learners.where((learner) {
          final name = learner['Name']?.toString().toLowerCase() ?? '';
          final surname = learner['Surname']?.toString().toLowerCase() ?? '';
          final idNumber = learner['IDNumber']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          return name.contains(searchLower) ||
              surname.contains(searchLower) ||
              idNumber.contains(searchLower);
        }).toList();
      }
    });
  }

  Future<void> _showSignatureDialog(String learnerID, bool isClockIn) async {
    // This method is called AFTER photo capture is complete
    // It only handles geofencing validation and signature capture
    
    final learnerIdInt = int.parse(learnerID);

    // Step 1: STRICT GEOFENCING - Check if location is available and within range
    if (_currentPosition == null || _siteLat == null || _siteLon == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ GPS location not available. Please wait for GPS signal.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Calculate distance from site
    final distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _siteLat!,
      _siteLon!,
    );

    // STRICT ENFORCEMENT: Block if outside 50m radius
    if (distance > 50) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.error, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Outside Site Range'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are ${distance.toStringAsFixed(0)} meters away from the site.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                  'Clock-in is only allowed within 50 meters of the site location.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red, width: 2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_off, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Required: ≤ 50m\nYour distance: ${distance.toStringAsFixed(0)}m',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Step 2: Now show signature dialog (photo was already captured in _handleClockIn/_handleClockOut)
    _signatureController.clear();

    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          isClockIn ? 'Clock In - Signature' : 'Clock Out - Signature',
        ),
        content: SizedBox(
          height: 420,
          width: 300,
          child: Column(
            children: [
              // Photo captured indicator (already done before this dialog)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple, width: 2),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.photo_camera, color: Colors.purple),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Face photo captured with liveness ✓',
                        style: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Geofencing success indicator
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Within site range (${distance.toStringAsFixed(0)}m)',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // GPS accuracy indicator
              if (_currentGpsAccuracy != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gps_fixed, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 4),
                      Text(
                        'GPS Accuracy: ${_currentGpsAccuracy!.toStringAsFixed(1)}m',
                        style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                      ),
                    ],
                  ),
                ),
              // Signature pad
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Signature(
                    controller: _signatureController,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _signatureController.clear(),
                child: const Text('Clear Signature'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_signatureController.isEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a signature')),
                );
                return;
              }

              // Store signature per learner ID
              try {
                final signatureBytes = await _signatureController.toPngBytes();
                if (!mounted) return;
                if (signatureBytes != null) {
                  final learnerIdInt = int.parse(learnerID);
                  _learnerSignatureBytes[learnerIdInt] = signatureBytes;
                  _learnerHasSignature[learnerIdInt] = true;
                }
              } catch (e) {
                print('Error storing signature: $e');
              }

              if (!context.mounted) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    // REMOVED RECURSIVE CALL: The signature is already stored in _learnerSignatureBytes
    // by the dialog's onPressed handler. We don't need to call _handleClockIn again
    // because we're already inside the clock-in flow.
    // The calling function (_handleClockIn or _handleClockOut) will continue
    // after this dialog returns.
  }

  Future<void> _handleClockIn(String learnerID) async {
    debugPrint('[SIGNATURE_GEO] ===== CLOCK-IN STARTED for learner: $learnerID =====');
    
    if (_isClockingIn[learnerID] == true) {
      debugPrint('[SIGNATURE_GEO] Already clocking in - skipping');
      return;
    }

    // CRITICAL: Verify device time is correct before allowing clock-in
    debugPrint('[SIGNATURE_GEO] Checking device time...');
    final timeOk = await TimezoneValidator.ensureCorrectTime(context);
    if (!mounted) return;
    if (!timeOk) {
      debugPrint('[SIGNATURE_GEO] ❌ Device time check failed');
      // User cancelled or time is wrong - block clock-in
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clock-in cancelled: Device time must be corrected first'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    debugPrint('[SIGNATURE_GEO] ✓ Device time OK');

    // Check if learner already clocked in today (prevent duplicates)
    final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (clockInTimes[learnerID]?.isNotEmpty == true) {
      debugPrint('[SIGNATURE_GEO] ⚠️ Already clocked in at ${clockInTimes[learnerID]}');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Learner already clocked in today at ${clockInTimes[learnerID]}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isClockingIn[learnerID] = true);

    try {
      debugPrint('[SIGNATURE_GEO] Step 1: Checking profile completion...');
      final profileOk = await ensureLearnerProfileCompleteForClockIn(learnerID);
      if (!mounted) return;
      if (!profileOk) {
        debugPrint('[SIGNATURE_GEO] ❌ Profile check failed - stopping');
        return;
      }
      debugPrint('[SIGNATURE_GEO] ✓ Profile check passed');

      debugPrint('[SIGNATURE_GEO] Step 2: Checking documents...');
      final docsOk = await ensureLearnerDocumentsCompleteForClockIn(learnerID);
      if (!mounted) return;
      if (!docsOk) {
        debugPrint('[SIGNATURE_GEO] ❌ Document check failed - stopping');
        return;
      }
      debugPrint('[SIGNATURE_GEO] ✓ Document check passed');

      // CRITICAL FIX: First capture face photo using SmartFramedCameraCapture
      print('[SIGNATURE_GEO] Starting face capture for learner: $learnerID');

      // Step 1: Navigate to SmartFramedCameraCapture for face photo
      final learnerData = widget.learners.firstWhere(
        (l) => l['LearnerID'].toString() == learnerID,
        orElse: () => {'Name': 'Unknown', 'Surname': ''},
      );
      final learnerName = '${learnerData['Name']} ${learnerData['Surname']}';

      if (!context.mounted) return;
      final faceResult = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => SmartFramedCameraCapture(
            learnerID: int.parse(learnerID),
            learnerName: learnerName,
            onCapture: (file, bytes) {
              // Store the captured photo
              _learnerPhotoBytes[int.parse(learnerID)] = bytes;
              // Don't call Navigator.pop here - SmartFramedCameraCapture handles it
            },
          ),
        ),
      );
      if (!mounted) return;

      // Check if camera was closed without capturing (user cancelled)
      if (!_learnerPhotoBytes.containsKey(int.parse(learnerID))) {
        print('[SIGNATURE_GEO] Face capture failed or cancelled');
        return;
      }

      // CRITICAL FIX: Mark that learner has photo captured
      setState(() {
        _learnerHasPhoto[int.parse(learnerID)] = true;
      });
      print('[SIGNATURE_GEO] Face photo captured successfully for: $learnerID');

      // Step 2: Capture signature using existing signature dialog
      print(
          '[SIGNATURE_GEO] Starting signature capture for learner: $learnerID');
      await _showSignatureDialog(learnerID, true); // true = isClockIn
      if (!mounted) return;

      // Check if signature was captured successfully
      if (!_learnerSignatureBytes.containsKey(int.parse(learnerID))) {
        print('[SIGNATURE_GEO] Signature capture failed or cancelled');
        return;
      }

      // Step 3: Branch based on mode
      if (_batchMode) {
        await _storeLearnerClockingData(learnerID, 'in');
      } else {
        // EXISTING INDIVIDUAL MODE - keep exactly as is
        final clockInTime = DateFormat('HH:mm:ss').format(DateTime.now());

        print('[SIGNATURE_GEO] 🌐 Network status: ${_isOnline ? "ONLINE" : "OFFLINE"}');
        
        if (_isOnline) {
          print('[SIGNATURE_GEO] 🚀 Attempting ONLINE clock-in for learner: $learnerID');
          try {
            await _clockInOnline(learnerID, '');
            if (!mounted) return;
            print('[SIGNATURE_GEO] ✅ ONLINE clock-in succeeded');
          } catch (onlineError) {
            print('[SIGNATURE_GEO] ❌ ONLINE clock-in FAILED: $onlineError');
            print('[SIGNATURE_GEO] 🔄 Falling back to OFFLINE mode');
            
            // Fall back to offline mode if online fails
            await _clockInOffline(learnerID, clockInTime);
            if (!mounted) return;
            
            // Trigger sync immediately (will try to upload what we just saved)
            print('[SIGNATURE_GEO] 🔄 Triggering immediate sync after offline save');
            _triggerOfflineSync();
          }
        } else {
          print('[SIGNATURE_GEO] 💾 Using OFFLINE clock-in (no network)');
          await _clockInOffline(learnerID, clockInTime);
          if (!mounted) return;
        }

        setState(() {
          clockInTimes[learnerID] = clockInTime;
        });
      }
    } catch (e) {
      print('[SIGNATURE_GEO] ⚠️ CRITICAL Clock-in error: $e');
      print('[SIGNATURE_GEO] Stack trace: ${StackTrace.current}');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text('Clock-in failed: $e'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ));
    } finally {
      setState(() => _isClockingIn[learnerID] = false);
    }
  }

  Future<void> _handleClockOut(String learnerID) async {
    if (_isClockingIn[learnerID] == true) return;

    // Check if learner hasn't clocked in yet
    if (clockInTimes[learnerID]?.isEmpty != false) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Learner must clock in first before clocking out'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if learner already clocked out today (prevent duplicates)
    if (clockOutTimes[learnerID]?.isNotEmpty == true) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Learner already clocked out today at ${clockOutTimes[learnerID]}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isClockingIn[learnerID] = true);

    try {
      // CRITICAL FIX: Capture face photo for clock-out
      print('[SIGNATURE_GEO] Starting face capture for clock-out: $learnerID');

      final learnerData = widget.learners.firstWhere(
        (l) => l['LearnerID'].toString() == learnerID,
        orElse: () => {'Name': 'Unknown', 'Surname': ''},
      );
      final learnerName = '${learnerData['Name']} ${learnerData['Surname']}';

      if (!context.mounted) return;
      final faceResult = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => SmartFramedCameraCapture(
            learnerID: int.parse(learnerID),
            learnerName: learnerName,
            onCapture: (file, bytes) {
              _learnerPhotoBytes[int.parse(learnerID)] = bytes;
              // Don't call Navigator.pop here - SmartFramedCameraCapture handles it
            },
          ),
        ),
      );
      if (!mounted) return;

      // Check if camera was closed without capturing (user cancelled)
      if (!_learnerPhotoBytes.containsKey(int.parse(learnerID))) {
        print('[SIGNATURE_GEO] Face capture failed or cancelled for clock-out');
        return;
      }

      // CRITICAL FIX: Mark that learner has photo captured for clock-out
      setState(() {
        _learnerHasPhoto[int.parse(learnerID)] = true;
      });
      print('[SIGNATURE_GEO] Face photo captured successfully for clock-out: $learnerID');

      // Capture signature for clock-out
      print(
          '[SIGNATURE_GEO] Starting signature capture for clock-out: $learnerID');
      await _showSignatureDialog(learnerID, false); // false = isClockOut
      if (!mounted) return;

      // Check if signature was captured successfully
      if (!_learnerSignatureBytes.containsKey(int.parse(learnerID))) {
        print('[SIGNATURE_GEO] Signature capture failed or cancelled');
        return;
      }

      // Branch based on mode
      if (_batchMode) {
        await _storeLearnerClockingData(learnerID, 'out');
      } else {
        // EXISTING INDIVIDUAL MODE - keep exactly as is
        final clockOutTime = DateFormat('HH:mm:ss').format(DateTime.now());
        final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

        if (_isOnline) {
          await _clockOutOnline(learnerID, '', synced: false);
          if (!mounted) return;
        } else {
          await _clockOutOffline(learnerID, clockOutTime, clockDate);
          if (!mounted) return;
        }

        setState(() {
          clockOutTimes[learnerID] = clockOutTime;
        });
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Clock-out error: $e');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Clock-out failed: $e')));
    } finally {
      setState(() => _isClockingIn[learnerID] = false);
    }
  }

  /// Batch mode: Store learner clocking data for later submission
  Future<void> _storeLearnerClockingData(String learnerID, String type) async {
    // Warn at 14 so the 15th addition triggers the alert (>= 15 was off-by-one)
    if (_batchClockings.length >= 14 && !_batchClockings.containsKey(learnerID)) {
      if (!context.mounted) return;
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Batch Size Warning'),
            content: const Text(
              'You have reached 15 learners (recommended maximum for batch mode). '
              'Batches larger than 15 may timeout on slow connections.\n\n'
              'Would you like to submit this batch now?'
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Submit Batch Now'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              TextButton(
                child: const Text('Add Learner Anyway'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          );
        },
      );
      if (!mounted) return;

      if (shouldContinue == true) {
        await _submitBatch();
        if (!mounted) return;
        return;
      }
    }
    
    // Step 1: Get learner details for display
    final learner = widget.learners.firstWhere(
      (l) => l['LearnerID'].toString() == learnerID,
      orElse: () => {'Name': 'Unknown', 'Surname': 'Learner'},
    );
    final learnerName = '${learner['Name']} ${learner['Surname']}';

    // Step 2: Get the already-captured data from current session
    final learnerIdInt = int.parse(learnerID);
    
    // Verify photo and signature were already captured in current flow
    if (!_learnerPhotoBytes.containsKey(learnerIdInt)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo not captured. Batch collection aborted.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    if (!_learnerSignatureBytes.containsKey(learnerIdInt)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signature not captured. Batch collection aborted.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Step 3: Store in batch map with all required data
    final uuid = const Uuid();
    final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final clockTime = DateFormat('HH:mm:ss').format(DateTime.now());
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final deviceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _batchClockings[learnerID] = {
      'learner_id': learnerID,
      'name': learner['Name']?.toString() ?? '',
      'surname': learner['Surname']?.toString() ?? '',
      'type': type,
      'face_image': base64Encode(_learnerPhotoBytes[learnerIdInt]!),
      'signature_image': base64Encode(_learnerSignatureBytes[learnerIdInt]!),
      'latitude': _currentPosition?.latitude ?? 0.0,
      'longitude': _currentPosition?.longitude ?? 0.0,
      'accuracy': _currentGpsAccuracy ?? 999.0,
      'clock_date': clockDate,
      'clock_time': clockTime,
      'timestamp': timestamp,
      'device_epoch': deviceEpoch,
      'idempotency_key': uuid.v4(),
    };

    setState(() {});

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added to batch ($_pendingBatchCount pending): ${learner['Name']} ${learner['Surname']} - ${type == 'in' ? 'Clock-in' : 'Clock-out'}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Submit collected batch clockings using OfflineSyncQueueService
  Future<void> _submitBatch() async {
    if (_batchClockings.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No learner clockings collected'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmittingBatch = true);

    try {
      // Prepare learner clockings list for batch service
      final learnerClockings = _batchClockings.values.toList();

      // Call existing queueForBatchProcessing method
      final syncService = OfflineSyncQueueService();
      final result = await syncService.queueForBatchProcessing(
        widget.classID,
        learnerClockings,
      );
      if (!mounted) return;

      // Handle batch size rejection from queue service
      if (result['success'] == false) {
        if (mounted && context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Batch Size Limit Exceeded'),
              content: Text(result['error'] ?? 'Batch could not be processed'),
              actions: [
                TextButton(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
        setState(() => _isSubmittingBatch = false);
        return; // Don't proceed with success handling
      }

      if (result['success'] == true) {
        // Update local state based on submitted data
        for (final clocking in learnerClockings) {
          final learnerID = clocking['learner_id'] as String;
          final clockTime = clocking['clock_time'] as String;
          if (clocking['type'] == 'in') {
            setState(() {
              clockInTimes[learnerID] = clockTime;
            });
          } else if (clocking['type'] == 'out') {
            setState(() {
              clockOutTimes[learnerID] = clockTime;
            });
          }
        }

        // Clear batch data and evidence maps
        _batchClockings.clear();
        _learnerPhotoFiles.clear();
        _learnerPhotoBytes.clear();
        _learnerSignatureBytes.clear();
        _learnerHasPhoto.clear();
        _learnerHasSignature.clear();
        _signatureController.clear();

        setState(() {});

        // Show success message
        final wasProcessedImmediately = result['processed_immediately'] == true;
        final message = wasProcessedImmediately
            ? '✅ Batch submitted successfully (${learnerClockings.length} learners)'
            : '📤 Batch queued for sync (${learnerClockings.length} learners)';

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception(result['message'] ?? 'Batch submission failed');
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Batch submission error: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Batch submission failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isSubmittingBatch = false);
    }
  }

  Future<void> _clockInOnline(String learnerID, String signaturePath) async {
    print('[SIGNATURE_GEO] 📡 Starting ONLINE clock-in for learner: $learnerID');
    try {
      if (widget.classID.isEmpty) {
        throw Exception('ClassID is missing or empty');
      }

      // Step 1: Prepare signature from per-learner storage
      print('[SIGNATURE_GEO] Step 1: Preparing signature...');
      String signatureBase64 = '';
      final learnerIdInt = int.parse(learnerID);

      if (_learnerSignatureBytes.containsKey(learnerIdInt)) {
        signatureBase64 = base64Encode(_learnerSignatureBytes[learnerIdInt]!);
        print('[SIGNATURE_GEO] ✅ Signature prepared (${signatureBase64.length} chars)');
      } else {
        throw Exception('Signature not captured for this learner');
      }

      // Step 2: Prepare face photo from per-learner storage
      print('[SIGNATURE_GEO] Step 2: Preparing face photo...');
      String? faceImageBase64;
      if (_learnerPhotoBytes.containsKey(learnerIdInt)) {
        faceImageBase64 = base64Encode(_learnerPhotoBytes[learnerIdInt]!);
        print('[SIGNATURE_GEO] ✅ Face photo prepared (${faceImageBase64.length} chars)');
      } else {
        throw Exception('Face photo not captured for this learner');
      }

      // Step 3: Upload images to server and get filenames
      print('[SIGNATURE_GEO] Step 3: Uploading images to server...');
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final clockInTime = DateFormat('HH:mm:ss').format(DateTime.now());

      // Get authentication token
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('Authentication token not available');
      }
      print('[SIGNATURE_GEO] ✅ Auth token retrieved');

      final uploadUrl =
          Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
      print('[SIGNATURE_GEO] Upload URL: $uploadUrl');
      
      final uploadPayload = {
        'learner_id': learnerID,
        'clock_date': currentDate,
        'type': 'in',
        'face_image': faceImageBase64,
        'signature_image': signatureBase64,
        'timestamp': timestamp,
      };

      print('[SIGNATURE_GEO] 📤 Sending image upload request...');
      final uploadResponse = await _makeAuthenticatedRequest(
        () => http.post(
          uploadUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(uploadPayload),
        ),
        maxRetries: 2,
      );

      print('[SIGNATURE_GEO] 📥 Upload response status: ${uploadResponse.statusCode}');
      print('[SIGNATURE_GEO] 📥 Upload response body: ${uploadResponse.body}');
      
      final uploadResult = jsonDecode(uploadResponse.body);

      if (uploadResponse.statusCode != 200 || uploadResult['success'] != true) {
        final errorMsg = uploadResult['error'] ?? uploadResult['message'] ?? 'Unknown error';
        throw Exception('Image upload failed: $errorMsg');
      }

      // Get filenames from upload response
      final faceInFilename = uploadResult['files']?['face_in'];
      final signatureInFilename = uploadResult['files']?['signature_in'];

      print('[SIGNATURE_GEO] ✅ Images uploaded successfully');
      print('[SIGNATURE_GEO] Face filename: $faceInFilename');
      print('[SIGNATURE_GEO] Signature filename: $signatureInFilename');

      // Step 4: Save clock-in record with filenames
      print('[SIGNATURE_GEO] Step 4: Saving clock-in record...');
      final clockInUrl =
          Uri.parse(AppConfig.buildUrl('save_manual_clockin.php'));

      // Prepare location data
      double userLat = _currentPosition?.latitude ?? 0.0;
      double userLon = _currentPosition?.longitude ?? 0.0;
      double userAccuracy = _currentGpsAccuracy ?? 999.0;

      final payload = {
        'learner_id': learnerID,
        'clock_date': currentDate,
        'clock_in_time': clockInTime,
        'signature_in': signatureInFilename,
        'face_in': faceInFilename,
        'latitude': userLat,
        'longitude': userLon,
        'accuracy': userAccuracy,
        'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_offline_sync': false, // Real-time manual clock-in
      };

      print('[SIGNATURE_GEO] 📤 Sending clock-in record...');
      final response = await _makeAuthenticatedRequest(
        () => http.post(
          clockInUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ),
        maxRetries: 2,
        endpoint: 'save_manual_clockin',
      );

      print('[SIGNATURE_GEO] 📥 Clock-in response status: ${response.statusCode}');
      print('[SIGNATURE_GEO] 📥 Clock-in response body: ${response.body}');
      
      final result = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          result is Map<String, dynamic> &&
          result['success'] == true) {
        setState(() {
          clockInTimes[learnerID] = result['clock_in_time'] ?? clockInTime;
          clockOutTimes[learnerID] = '';
          contactTimes[learnerID] = '';
          
          // Mark as synced (remove from unsynced list)
          _unsyncedLearners.remove(learnerID);

          // Clear captured evidence after successful clock-in
          final learnerIdInt = int.parse(learnerID);
          _learnerPhotoFiles.remove(learnerIdInt);
          _learnerPhotoBytes.remove(learnerIdInt);
          _learnerSignatureBytes.remove(learnerIdInt);
          _learnerHasPhoto.remove(learnerIdInt);
          _learnerHasSignature.remove(learnerIdInt);

          // Clear signature pad for next use
          _signatureController.clear();
        });

        print('[SIGNATURE_GEO] ✅✅✅ Clock-in COMPLETELY SUCCESSFUL for learner: $learnerID (SYNCED TO SERVER)');

        if (!mounted) return;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Clock-in successful'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMsg = result['error'] ?? result['message'] ?? 'Server error';
        throw Exception('Server rejected clock-in: $errorMsg');
      }
    } catch (e, stackTrace) {
      print('[SIGNATURE_GEO] ❌❌❌ Online clock-in FAILED: $e');
      print('[SIGNATURE_GEO] Stack trace: $stackTrace');
      throw Exception('Online clock-in failed: $e');
    }
  }

  Future<void> _clockOutOnline(
    String learnerID,
    String signaturePath, {
    bool synced = false,
  }) async {
    final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      if (widget.classID.isEmpty) {
        throw Exception('ClassID is missing or empty');
      }

      // Step 1: Prepare signature from per-learner storage
      String signatureBase64 = '';
      final learnerIdInt = int.parse(learnerID);

      if (_learnerSignatureBytes.containsKey(learnerIdInt)) {
        signatureBase64 = base64Encode(_learnerSignatureBytes[learnerIdInt]!);
      } else {
        throw Exception('Signature not captured for this learner');
      }

      // Step 2: Prepare face photo from per-learner storage
      String? faceImageBase64;
      if (_learnerPhotoBytes.containsKey(learnerIdInt)) {
        faceImageBase64 = base64Encode(_learnerPhotoBytes[learnerIdInt]!);
      } else {
        throw Exception('Face photo not captured for this learner');
      }

      // Step 3: Upload images to server and get filenames
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final clockOutTime = DateFormat('HH:mm:ss').format(DateTime.now());

      print('[SIGNATURE_GEO] Uploading images for clock-out: $learnerID');

      // Get authentication token
      final token = await AppConfig.getAuthToken();
      if (token == null) {
        throw Exception('Authentication token not available');
      }

      final uploadUrl =
          Uri.parse(AppConfig.buildUrl('save_manual_clocking_images.php'));
      final uploadPayload = {
        'learner_id': learnerID,
        'clock_date': currentDate,
        'type': 'out',
        'face_image': faceImageBase64,
        'signature_image': signatureBase64,
        'timestamp': timestamp,
      };

      final uploadResponse = await _makeAuthenticatedRequest(
        () => http.post(
          uploadUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(uploadPayload),
        ),
        maxRetries: 2,
        endpoint: 'save_manual_clocking_images',
      );

      final uploadResult = jsonDecode(uploadResponse.body);

      if (uploadResponse.statusCode != 200 || uploadResult['success'] != true) {
        throw Exception(
            'Image upload failed: ${uploadResult['error'] ?? 'Unknown error'}');
      }

      // Get filenames from upload response
      final faceOutFilename = uploadResult['files']?['face_out'];
      final signatureOutFilename = uploadResult['files']?['signature_out'];

      print(
          '[SIGNATURE_GEO] Images uploaded. Face: $faceOutFilename, Signature: $signatureOutFilename');

      // Step 4: Save clock-out record with filenames
      final url = Uri.parse(AppConfig.buildUrl('save_manual_clockout.php'));

      // Prepare location data
      double userLat = _currentPosition?.latitude ?? 0.0;
      double userLon = _currentPosition?.longitude ?? 0.0;
      double userAccuracy = _currentGpsAccuracy ?? 999.0;

      final payload = {
        'learner_id': learnerID,
        'clock_date': currentDate,
        'clock_out_time': clockOutTime,
        'signature_out': signatureOutFilename,
        'face_out': faceOutFilename,
        'latitude': userLat,
        'longitude': userLon,
        'accuracy': userAccuracy,
        'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_offline_sync': false, // Real-time manual clock-out
      };

      print('[SIGNATURE_GEO] Sending manual clock-out for learner: $learnerID');

      final response = await _makeAuthenticatedRequest(
        () => http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ),
        maxRetries: 2,
        endpoint: 'save_manual_clockout',
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          result is Map<String, dynamic> &&
          result['success'] == true) {
        // Calculate contact time
        String? contactTime;
        final clockInTime = clockInTimes[learnerID];
        if (clockInTime != null && clockInTime.isNotEmpty) {
          try {
            final timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
            final clockInDateTime = timeFormat.parse(
              '$currentDate $clockInTime',
            );
            final clockOutDateTime = timeFormat.parse(
              '$currentDate $clockOutTime',
            );
            final contactTimeDuration = clockOutDateTime.difference(
              clockInDateTime,
            );
            contactTime = formatDuration(contactTimeDuration);
          } catch (e) {
            print('[SIGNATURE_GEO] Error calculating contact time: $e');
          }
        }

        setState(() {
          clockOutTimes[learnerID] = result['clock_out_time'] ?? clockOutTime;
          contactTimes[learnerID] = contactTime ?? '';

          // Clear captured evidence after successful clock-out
          final learnerIdInt = int.parse(learnerID);
          _learnerPhotoFiles.remove(learnerIdInt);
          _learnerPhotoBytes.remove(learnerIdInt);
          _learnerSignatureBytes.remove(learnerIdInt);
          _learnerHasPhoto.remove(learnerIdInt);
          _learnerHasSignature.remove(learnerIdInt);

          // Clear signature pad for next use
          _signatureController.clear();
        });

        print('[SIGNATURE_GEO] Clock-out successful for learner: $learnerID');

        // Check if record is now complete (both clock-in and clock-out)
        final hasClockIn = clockInTimes[learnerID]?.isNotEmpty == true;
        final hasClockOut = clockOutTimes[learnerID]?.isNotEmpty == true;
        final isComplete = hasClockIn && hasClockOut;

        if (!mounted) return;
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text(isComplete
                ? '✅ Record Completed - Clock-in and Clock-out successful'
                : (result['message'] ?? 'Clock-out successful')),
            backgroundColor: isComplete ? Colors.blue : Colors.green,
            duration: Duration(seconds: isComplete ? 4 : 2)));
      } else {
        throw Exception(result['message'] ?? 'Server error');
      }
    } catch (e) {
      print('[SIGNATURE_GEO] Online clock-out failed: $e');
      throw Exception('Online clock-out failed: $e');
    }
  }

  Future<void> _clockInOffline(String learnerID, String clockInTime) async {
    try {
      print('[SIGNATURE_GEO] Starting offline clock-in for: $learnerID');
      final dbHelper = DatabaseHelper();
      final clockDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final appDir = await getApplicationDocumentsDirectory();

      // Save signature from per-learner storage
      final signaturePath =
          '${appDir.path}/signature_${learnerID}_$clockDate.png';
      String finalSignaturePath = '';

      final learnerIdInt = int.parse(learnerID);
      if (_learnerSignatureBytes.containsKey(learnerIdInt)) {
        try {
          final signatureFile = File(signaturePath);
          await signatureFile
              .writeAsBytes(_learnerSignatureBytes[learnerIdInt]!);
          finalSignaturePath = signaturePath;
          print('[SIGNATURE_GEO] Signature saved to: $finalSignaturePath');
        } catch (e) {
          print('[SIGNATURE_GEO] Signature save failed: $e');
        }
      } else {
        print('[SIGNATURE_GEO] No signature found for learner $learnerID');
      }

      // Save face photo from per-learner storage
      final facePhotoPath =
          '${appDir.path}/face_${learnerID}_$clockDate.png';
      String finalFacePhotoPath = '';

      if (_learnerPhotoBytes.containsKey(learnerIdInt)) {
        try {
          final facePhotoFile = File(facePhotoPath);
          await facePhotoFile.writeAsBytes(_learnerPhotoBytes[learnerIdInt]!);
          finalFacePhotoPath = facePhotoPath;
          print('[SIGNATURE_GEO] Face photo saved to: $finalFacePhotoPath');
        } catch (e) {
          print('[SIGNATURE_GEO] Face photo save failed: $e');
        }
      } else {
        print('[SIGNATURE_GEO] No face photo found for learner $learnerID');
      }

      // Get location data
      double userLat = _currentPosition?.latitude ?? 0.0;
      double userLon = _currentPosition?.longitude ?? 0.0;
      double userAccuracy = _currentGpsAccuracy ?? 999.0;

      final clockInData = {
        'LearnerID': learnerID,
        'clock_in_time': clockInTime,
        'clock_date': clockDate,
        'signature_in': finalSignaturePath, // Correct key for database_helper
        'face_in': finalFacePhotoPath, // Correct key for database_helper
        'synced': 0,
        'user_latitude': userLat.toString(),
        'user_longitude': userLon.toString(),
        'user_accuracy': userAccuracy.toString(),
        'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_offline_sync': 'true',
      };

      await dbHelper.insertManualClockInOffline(clockInData);
      print(
          '[SIGNATURE_GEO] Offline clock-in saved for: $learnerID to manual_clocking + manual_clocking_evidence');

      setState(() {
        clockInTimes[learnerID] = clockInTime;
        _unsyncedLearners[learnerID] = true; // Mark as unsynced (offline)
      });

      print('[SIGNATURE_GEO] 🟠 Learner $learnerID marked as UNSYNCED (offline data)');

      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Clock-in saved locally. Will sync when online.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print('[SIGNATURE_GEO] Offline clock-in error: $e');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving offline clock-in: $e')),
      );
      rethrow;
    }
  }

  /// Clock-out offline - saves signature and face photo to manual_clocking_evidence
  Future<void> _clockOutOffline(
    String learnerID,
    String clockOutTime,
    String clockDate,
  ) async {
    try {
      print('[SIGNATURE_GEO] Starting offline clock-out for: $learnerID');
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      final appDir = await getApplicationDocumentsDirectory();

      // Check if clock-in record exists
      final existingRecords = await db.query(
        'manual_clocking',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerID, clockDate],
      );

      if (existingRecords.isEmpty) {
        if (!mounted) return;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No clock-in record found for today.')),
        );
        return;
      }

      // Calculate contact time
      final clockInTime = existingRecords[0]['clock_in_time']?.toString();
      String? contactTime;
      if (clockInTime != null && clockInTime.isNotEmpty) {
        try {
          final timeFormat = DateFormat('HH:mm:ss');
          final clockInDateTime = timeFormat.parse(clockInTime);
          final clockOutDateTime = timeFormat.parse(clockOutTime);
          final contactTimeDuration = clockOutDateTime.difference(
            clockInDateTime,
          );
          contactTime = formatDuration(contactTimeDuration);
        } catch (e) {
          print('[SIGNATURE_GEO] Error calculating contact time: $e');
        }
      }

      // Save signature for clock-out from per-learner storage
      final signaturePath =
          '${appDir.path}/signature_out_${learnerID}_$clockDate.png';
      String finalSignaturePath = '';

      final learnerIdInt = int.parse(learnerID);
      if (_learnerSignatureBytes.containsKey(learnerIdInt)) {
        try {
          final signatureFile = File(signaturePath);
          await signatureFile
              .writeAsBytes(_learnerSignatureBytes[learnerIdInt]!);
          finalSignaturePath = signaturePath;
          print('[SIGNATURE_GEO] Clock-out signature saved to: $finalSignaturePath');
        } catch (e) {
          print('[SIGNATURE_GEO] Clock-out signature save failed: $e');
        }
      } else {
        print('[SIGNATURE_GEO] No signature found for learner $learnerID clock-out');
      }

      // Save face photo for clock-out from per-learner storage
      final facePhotoPath =
          '${appDir.path}/face_out_${learnerID}_$clockDate.png';
      String finalFacePhotoPath = '';

      if (_learnerPhotoBytes.containsKey(learnerIdInt)) {
        try {
          final facePhotoFile = File(facePhotoPath);
          await facePhotoFile.writeAsBytes(_learnerPhotoBytes[learnerIdInt]!);
          finalFacePhotoPath = facePhotoPath;
          print('[SIGNATURE_GEO] Clock-out face photo saved to: $finalFacePhotoPath');
        } catch (e) {
          print('[SIGNATURE_GEO] Clock-out face photo save failed: $e');
        }
      } else {
        print('[SIGNATURE_GEO] No face photo found for learner $learnerID clock-out');
      }

      // Prepare clock-out data
      final clockOutData = {
        'LearnerID': learnerID,
        'clock_out_time': clockOutTime,
        'clock_date': clockDate,
        'contact_time': contactTime,
        'signature_out': finalSignaturePath, // Correct key for database_helper
        'face_out': finalFacePhotoPath, // Correct key for database_helper
        'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_offline_sync': 'true',
      };

      await dbHelper.updateManualClockOutOffline(clockOutData);
      print(
          '[SIGNATURE_GEO] Offline clock-out saved for: $learnerID to manual_clocking + manual_clocking_evidence');

      setState(() {
        clockOutTimes[learnerID] = clockOutTime;
        if (contactTime != null) {
          contactTimes[learnerID] = contactTime;
        }

        // Clear captured evidence after successful clock-out
        _learnerPhotoFiles.remove(learnerIdInt);
        _learnerPhotoBytes.remove(learnerIdInt);
        _learnerSignatureBytes.remove(learnerIdInt);
        _learnerHasPhoto.remove(learnerIdInt);
        _learnerHasSignature.remove(learnerIdInt);

        // Clear signature pad for next use
        _signatureController.clear();
      });

      // Check if record is now complete (both clock-in and clock-out)
      final hasClockIn = clockInTimes[learnerID]?.isNotEmpty == true;
      final hasClockOut = clockOutTimes[learnerID]?.isNotEmpty == true;
      final isComplete = hasClockIn && hasClockOut;

      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isComplete
              ? '✅ Record Completed - Clock-in and Clock-out saved offline'
              : 'Clock-out saved locally. Will sync when online.'),
          backgroundColor: isComplete ? Colors.blue : Colors.green,
          duration: Duration(seconds: isComplete ? 4 : 2),
        ),
      );
    } catch (e) {
      print('[SIGNATURE_GEO] Offline clock-out error: $e');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving offline clock-out: $e')),
      );
      rethrow;
    }
  }

  /// DEPRECATED: Old method that only updated manual_clocking table
  /// Kept for reference but no longer used
  Future<void> updateClockOut(
    String learnerID,
    String clockOutTime,
    String clockDate,
  ) async {
    try {
      final db = await DatabaseHelper().database;
      final existingRecords = await db.query(
        'manual_clocking',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerID, clockDate],
      );

      if (existingRecords.isEmpty) {
        if (!mounted) return;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No clock-in record found for today.')),
        );
        return;
      }

      final clockInTime = existingRecords[0]['clock_in_time']?.toString();
      String? contactTime;
      if (clockInTime != null && clockInTime.isNotEmpty) {
        try {
          final timeFormat = DateFormat('HH:mm:ss');
          final clockInDateTime = timeFormat.parse(clockInTime);
          final clockOutDateTime = timeFormat.parse(clockOutTime);
          final contactTimeDuration = clockOutDateTime.difference(
            clockInDateTime,
          );
          contactTime = formatDuration(contactTimeDuration);
        } catch (e) {
          print('[SIGNATURE_GEO] Error calculating contact time: $e');
        }
      }

      final updatedData = {
        'clock_out_time': clockOutTime,
        'contact_time': contactTime,
      };

      await db.update(
        'manual_clocking',
        updatedData,
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerID, clockDate],
      );

      setState(() {
        clockOutTimes[learnerID] = clockOutTime;
        if (contactTime != null) {
          contactTimes[learnerID] = contactTime;
        }
      });

      // Check if record is now complete (both clock-in and clock-out)
      final hasClockIn = clockInTimes[learnerID]?.isNotEmpty == true;
      final hasClockOut = clockOutTimes[learnerID]?.isNotEmpty == true;
      final isComplete = hasClockIn && hasClockOut;

      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isComplete
              ? '✅ Record Completed - Clock-in and Clock-out saved offline'
              : 'Clock-out saved locally. Will sync when online.'),
          backgroundColor: isComplete ? Colors.blue : Colors.green,
          duration: Duration(seconds: isComplete ? 4 : 2),
        ),
      );
    } catch (e) {
      print('[SIGNATURE_GEO] Error updating clock-out: $e');
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating clock-out: $e')));
    }
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature + Geofence Clock-In'),
        backgroundColor: Colors.teal,
        actions: [
          // Batch mode toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Batch',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Switch(
                value: _batchMode,
                onChanged: (value) {
                  setState(() {
                    _batchMode = value;
                    if (!value) {
                      // Clear batch data when switching back to individual mode
                      _batchClockings.clear();
                    }
                  });
                },
                activeColor: Colors.white,
              ),
            ],
          ),
          // Connectivity indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? Colors.white : Colors.red[200],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // GPS Loading banner
          if (_isLoadingLocation)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue[100],
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Acquiring GPS location... (may take 30-60s on first load)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // GPS Not Available banner (with retry)
          if (!_isLoadingLocation && _currentPosition == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red[100],
              child: Row(
                children: [
                  Icon(Icons.gps_off, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '⚠️ GPS not available. Go outdoors and tap retry.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _startLocationMonitoring(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          // Geofencing status banner
          if (_currentPosition != null && _siteLat != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: _isWithinRange ? Colors.green[100] : Colors.orange[100],
              child: Row(
                children: [
                  Icon(
                    _isWithinRange ? Icons.location_on : Icons.location_off,
                    color: _isWithinRange ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isWithinRange
                          ? 'Within site range (${_calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, _siteLat!, _siteLon!).toStringAsFixed(0)}m)'
                          : 'Outside site range (${_calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, _siteLat!, _siteLon!).toStringAsFixed(0)}m from site)',
                      style: TextStyle(
                        color: _isWithinRange
                            ? Colors.green[900]
                            : Colors.orange[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_currentGpsAccuracy != null)
                    Chip(
                      label: Text(
                        'GPS: ${_currentGpsAccuracy!.toStringAsFixed(1)}m',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: Colors.white,
                    ),
                ],
              ),
            ),
          // Batch mode status banner
          if (_batchMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Row(
                children: [
                  const Icon(Icons.playlist_add_check, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Batch Mode: ${_batchClockings.length} learner(s) collected',
                      style: TextStyle(
                        color: Colors.blue[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_batchClockings.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _batchClockings.clear());
                      },
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                ],
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search learners by name or ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterLearners('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _filterLearners,
            ),
          ),
          // Learners list
          Expanded(
            child: _filteredLearners.isEmpty
                ? const Center(
                    child: Text(
                      'No learners found',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredLearners.length,
                    itemBuilder: (context, index) {
                      final learner = _filteredLearners[index];
                      final learnerID = learner['LearnerID']?.toString() ?? '';
                      final name = learner['Name']?.toString() ?? 'N/A';
                      final surname = learner['Surname']?.toString() ?? 'N/A';
                      final idNumber = learner['IDNumber']?.toString() ?? 'N/A';
                      final clockInTime = clockInTimes[learnerID] ?? '';
                      final clockOutTime = clockOutTimes[learnerID] ?? '';
                      final contactTime = contactTimes[learnerID] ?? '';
                      final isClockedIn = clockInTime.isNotEmpty;
                      final isClockedOut = clockOutTime.isNotEmpty;
                      final isProcessing = _isClockingIn[learnerID] == true;
                      
                      // Check if this learner has unsynced offline data
                      final isUnsynced = _unsyncedLearners[learnerID] == true;

                      // Check evidence status for this learner
                      final learnerIdInt = int.tryParse(learnerID) ?? 0;
                      final hasPhoto = _learnerHasPhoto[learnerIdInt] == true;
                      final hasSignature =
                          _learnerHasSignature[learnerIdInt] == true;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isClockedOut
                                ? Colors.grey
                                : isClockedIn
                                    ? (isUnsynced ? Colors.orange : Colors.green)  // Orange if offline, Green if synced
                                    : Colors.orange,
                            child: Icon(
                              isClockedOut
                                  ? Icons.check_circle
                                  : isClockedIn
                                      ? (isUnsynced ? Icons.cloud_off : Icons.cloud_done)  // Different icons for sync status
                                      : Icons.person,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            '$name $surname',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: $idNumber'),
                              // Evidence status indicators
                              Row(
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 14,
                                    color: isClockedIn
                                        ? (isUnsynced
                                            ? Colors.orange
                                            : Colors.green)
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Photo',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isClockedIn
                                          ? (isUnsynced
                                              ? Colors.orange
                                              : Colors.green)
                                          : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.edit,
                                    size: 14,
                                    color: isClockedIn
                                        ? (isUnsynced
                                            ? Colors.orange
                                            : Colors.green)
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Signature',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isClockedIn
                                          ? (isUnsynced
                                              ? Colors.orange
                                              : Colors.green)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              if (clockInTime.isNotEmpty)
                                Row(
                                  children: [
                                    Text(
                                      'In: $clockInTime',
                                      style: TextStyle(
                                        color: isUnsynced ? Colors.orange : Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (isUnsynced) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.sync,
                                        size: 12,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 2),
                                      const Text(
                                        'Needs sync',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.cloud_done,
                                        size: 12,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 2),
                                      const Text(
                                        'Synced',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              if (clockOutTime.isNotEmpty)
                                Text(
                                  'Out: $clockOutTime',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              if (contactTime.isNotEmpty)
                                Text(
                                  'Duration: $contactTime',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: isProcessing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isClockedIn)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.login,
                                          color: Colors.green,
                                        ),
                                        onPressed: () => _handleClockIn(
                                          learnerID,
                                        ),
                                        tooltip: 'Clock In',
                                      ),
                                    if (isClockedIn && !isClockedOut)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.logout,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => _handleClockOut(
                                          learnerID,
                                        ),
                                        tooltip: 'Clock Out',
                                      ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _batchMode && _pendingBatchCount > 0
          ? FloatingActionButton.extended(
              onPressed: _isSubmittingBatch ? null : _submitBatch,
              icon: _isSubmittingBatch
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isSubmittingBatch
                  ? 'Submitting...'
                  : 'Submit Batch ($_pendingBatchCount)'),
              backgroundColor: _isSubmittingBatch ? Colors.grey : Colors.teal,
            )
          : null,
    );
  }

  // Rate limiting and retry logic
  static final Map<String, DateTime> _lastRequestTimes = {};
  static final Map<String, int> _requestCounts = {};
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  static const int _maxRequestsPerWindow = 10;
  static const List<int> _retryDelaysMs = [
    1000,
    2000,
    4000
  ]; // Exponential backoff

  /// Check if request is rate limited
  bool _isRateLimited(String endpoint) {
    final now = DateTime.now();
    final key = endpoint;

    // Clean old entries
    _lastRequestTimes.removeWhere(
        (k, lastTime) => now.difference(lastTime) > _rateLimitWindow);
    _requestCounts.removeWhere((k, count) => !_lastRequestTimes.containsKey(k));

    // Check current rate
    final requestCount = _requestCounts[key] ?? 0;
    if (requestCount >= _maxRequestsPerWindow) {
      print(
          '[RATE_LIMIT] Endpoint $endpoint exceeded rate limit: $requestCount requests');
      return true;
    }

    // Update counters
    _lastRequestTimes[key] = now;
    _requestCounts[key] = requestCount + 1;

    return false;
  }

  /// Make authenticated HTTP request with retry logic and rate limiting
  Future<http.Response> _makeAuthenticatedRequest(
    Future<http.Response> Function() requestFunction, {
    int maxRetries = 0,
    String? endpoint,
  }) async {
    endpoint ??= 'unknown';

    // Check rate limiting
    if (_isRateLimited(endpoint)) {
      throw Exception(
          'Rate limit exceeded for $endpoint. Please wait before retrying.');
    }

    Exception? lastException;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        print(
            '[HTTP_REQUEST] Attempt ${attempt + 1}/${maxRetries + 1} for $endpoint');

        final response = await requestFunction().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
              'Request timeout', const Duration(seconds: 30)),
        );

        // Success
        if (response.statusCode >= 200 && response.statusCode < 300) {
          print(
              '[HTTP_REQUEST] Success for $endpoint (${response.statusCode})');
          return response;
        }

        // Server errors that might be temporary - retry
        if (response.statusCode >= 500 && attempt < maxRetries) {
          lastException = HttpException('Server error: ${response.statusCode}',
              uri: Uri.parse(endpoint));
          print(
              '[HTTP_REQUEST] Server error ${response.statusCode}, will retry...');
          continue;
        }

        // Client errors - don't retry
        if (response.statusCode == 401) {
          throw HttpException('Authentication failed. Please login again.',
              uri: Uri.parse(endpoint));
        } else if (response.statusCode == 429) {
          throw HttpException(
              'Rate limited by server. Please wait before retrying.',
              uri: Uri.parse(endpoint));
        } else {
          throw HttpException(
              'HTTP ${response.statusCode}: ${response.reasonPhrase}',
              uri: Uri.parse(endpoint));
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception('Request failed: $e');
        print('[HTTP_REQUEST] Error on attempt ${attempt + 1}: $e');

        // Don't retry on authentication or client errors
        if (e is HttpException && e.message.contains('Authentication failed')) {
          rethrow;
        }

        // Exponential backoff delay before retry
        if (attempt < maxRetries) {
          final delayMs =
              _retryDelaysMs[attempt.clamp(0, _retryDelaysMs.length - 1)];
          print('[HTTP_REQUEST] Waiting ${delayMs}ms before retry...');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    // All retries failed
    throw lastException ??
        Exception('Request failed after $maxRetries retries');
  }

  /// Trigger sync of offline clock-in records
  /// This runs in the background and doesn't block the UI
  /// Uses rate limiting (max 10 records per batch, 500ms delay between records)
  Future<void> _triggerOfflineSync() async {
    try {
      final syncService = ComprehensiveManualClockingSync();
      final unsyncedCount = await syncService.getUnsyncedCount();
      
      if (unsyncedCount == 0) {
        print('[SIGNATURE_GEO] 📊 No unsynced records to upload');
        return;
      }
      
      print('[SIGNATURE_GEO] 🔄 Starting queued sync of $unsyncedCount unsynced records...');
      print('[SIGNATURE_GEO] ⏱️  Rate limit: 10 records/batch, 500ms delay between records');
      
      final result = await syncService.syncAllUnsyncedClockIns();
      
      if (result['success']) {
        final syncedCount = result['syncedCount'] ?? 0;
        final failedCount = result['failedCount'] ?? 0;
        final remainingCount = result['remainingCount'] ?? 0;
        
        print('[SIGNATURE_GEO] ✅ Sync complete: $syncedCount uploaded, $failedCount failed');
        
        if (remainingCount > 0) {
          print('[SIGNATURE_GEO] ⏳ $remainingCount records remaining (will sync in next batch)');
        }
        
        if (syncedCount > 0 && mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Synced $syncedCount offline record(s) to server${remainingCount > 0 ? ' ($remainingCount remaining)' : ''}'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          
          // Refresh the clock-in status display
          // Note: Method _loadTodayClockingData not implemented yet
          // await _loadTodayClockingData();
          setState(() {}); // Refresh UI instead
        }
      } else {
        print('[SIGNATURE_GEO] ❌ Sync failed: ${result['error']}');
      }
    } catch (e) {
      print('[SIGNATURE_GEO] ❌ Error during sync: $e');
      // Don't show error to user - sync will retry later
    }
  }
}
