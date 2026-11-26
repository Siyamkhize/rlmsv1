import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'database_helper.dart';
import 'config.dart';
import 'mixins/learner_clockin_gates_mixin.dart';

/// MTL Session-Based Clock-In Page
/// 
/// Implements SessionVerificationContract.md:
/// - User logs into MTL RLMS → receives sessionId
/// - MTL RLMS sends sessionId to this Scanning app
/// - This app uses auth_token (existing system) as the sessionId
/// - Clock-in sends auth_token in Authorization: Bearer <token>
/// - Server validates token before recording clock-in
/// 
/// See: EXISTING_AUTH_SYSTEM.md for authentication details
class MtlSessionClockInPage extends StatefulWidget {
  final String classID;
  final List<dynamic> learners;

  const MtlSessionClockInPage({
    super.key,
    required this.classID,
    required this.learners,
  });

  @override
  State<MtlSessionClockInPage> createState() => _MtlSessionClockInPageState();
}

class _MtlSessionClockInPageState extends State<MtlSessionClockInPage>
    with LearnerClockInGatesMixin {
  Map<String, String> clockInTimes = {};
  Map<String, String> clockOutTimes = {};
  Map<String, String> contactTimes = {};
  final Map<String, bool> _isClockingIn = {};

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<dynamic> _filteredLearners = [];

  // Session state
  String? _sessionId; // This will be the auth_token
  Map<String, dynamic>? _sessionUser; // Cached user details
  DateTime? _sessionExpiresAt;
  bool _isValidatingSession = false;
  String? _sessionError;

  // Geofencing state
  double? _currentGpsAccuracy;
  double? _siteLat;
  double? _siteLon;
  bool _isWithinRange = false;
  Position? _currentPosition;
  bool _isLoadingLocation = false;

  // Connectivity
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _filteredLearners = widget.learners;
    _searchController.addListener(_onSearchChanged);
    _loadClockingData();
    _loadSiteLocation();
    _checkConnectivity();
    _loadAndValidateSession(); // ✅ Load and validate auth_token
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Load auth_token (which serves as the sessionId)
  /// Per SessionVerificationContract.md section 1
  Future<void> _loadAndValidateSession() async {
    setState(() {
      _isValidatingSession = true;
      _sessionError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await AppConfig.getAuthToken();

      if (token == null || token.isEmpty) {
        setState(() {
          _sessionError = 'No session found. Please login via MTL RLMS first.';
          _isValidatingSession = false;
        });
        return;
      }

      // Store token as sessionId
      _sessionId = token;

      // Get cached user data from SharedPreferences
      // In a full implementation, we'd verify the session with MTL API
      // For now, we use the existing auth system (Option 1 approach)
      final userId = prefs.getString('user_id');
      final userName = prefs.getString('user_name');
      final userEmail = prefs.getString('user_email');
      final userRole = prefs.getString('user_role');

      if (userId != null && userName != null) {
        _sessionUser = {
          'id': userId,
          'name': userName,
          'email': userEmail,
          'role': userRole ?? 'Facilitator',
        };

        setState(() {
          _isValidatingSession = false;
        });

        debugPrint('[MTL_SESSION] ✅ Session loaded: User ${_sessionUser!['name']}');
      } else {
        setState(() {
          _sessionError = 'Session invalid. Please login again.';
          _isValidatingSession = false;
        });
      }
    } catch (e) {
      debugPrint('[MTL_SESSION] ❌ Error loading session: $e');
      setState(() {
        _sessionError = 'Error loading session: $e';
        _isValidatingSession = false;
      });
    }
  }

  /// Verify session with server (future implementation)
  /// This would call POST /api/sessions/verify per SessionVerificationContract.md section 5
  Future<bool> _verifySessionWithServer() async {
    if (_sessionId == null) return false;

    try {
      // TODO: Implement when MTL team provides verify endpoint
      // For now, we rely on existing auth_token validation
      // which happens on every API call automatically
      
      // Future implementation:
      // final response = await http.post(
      //   Uri.parse('${AppConfig.mtlApiBaseUrl}/api/sessions/verify'),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'X-Api-Key': AppConfig.mtlApiKey,
      //   },
      //   body: jsonEncode({'sessionId': _sessionId}),
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   return data['isValid'] == true;
      // }
      
      return true; // For now, trust the auth_token
    } catch (e) {
      debugPrint('[MTL_SESSION] Error verifying session: $e');
      return false;
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filteredLearners = widget.learners.where((learner) {
        final name = learner['Name']?.toString().toLowerCase() ?? '';
        final surname = learner['Surname']?.toString().toLowerCase() ?? '';
        final idNumber = learner['IDnumber']?.toString().toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
            surname.contains(_searchQuery) ||
            idNumber.contains(_searchQuery);
      }).toList();
    });
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = !connectivityResult.contains(ConnectivityResult.none);
    });

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      setState(() {
        _isOnline = !results.contains(ConnectivityResult.none);
      });
    });
  }

  Future<void> _loadSiteLocation() async {
    final db = await DatabaseHelper().database;
    final sites = await db.query(
      'sites',
      where: 'SiteID = (SELECT SiteID FROM class WHERE ClassID = ?)',
      whereArgs: [widget.classID],
    );

    if (sites.isNotEmpty && mounted) {
      setState(() {
        _siteLat = double.tryParse(sites.first['latitude']?.toString() ?? '0');
        _siteLon = double.tryParse(sites.first['longitude']?.toString() ?? '0');
      });
      _startLocationMonitoring();
    }
  }

  Future<void> _startLocationMonitoring() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (_siteLat != null && _siteLon != null && mounted) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _siteLat!,
          _siteLon!,
        );

        setState(() {
          _currentGpsAccuracy = _currentPosition!.accuracy;
          _isWithinRange = distance <= 100; // 100m radius
        });
      }
    } catch (e) {
      debugPrint('[MTL_SESSION] Location error: $e');
    }
  }

  Future<void> _loadClockingData() async {
    final db = await DatabaseHelper().database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (var learner in widget.learners) {
      final learnerId = learner['LearnerID'].toString();

      final clocking = await db.query(
        'learner_clocking',
        where: 'LearnerID = ? AND clock_date = ?',
        whereArgs: [learnerId, today],
      );

      if (clocking.isNotEmpty && mounted) {
        setState(() {
          if (clocking.first['clock_in_time'] != null) {
            clockInTimes[learnerId] = clocking.first['clock_in_time'].toString();
          }
          if (clocking.first['clock_out_time'] != null) {
            clockOutTimes[learnerId] = clocking.first['clock_out_time'].toString();
          }
          if (clocking.first['contact_time'] != null) {
            contactTimes[learnerId] = clocking.first['contact_time'].toString();
          }
        });
      }
    }
  }

  /// Clock-in with MTL session verification
  /// Sends auth_token in Authorization: Bearer header per SessionVerificationContract.md
  Future<void> _clockInWithSession(dynamic learner) async {
    // Validate session first
    if (_sessionId == null) {
      _showError('No active session. Please login via MTL RLMS.');
      return;
    }

    if (_sessionError != null) {
      _showError(_sessionError!);
      return;
    }

    // Check geofencing
    if (!_isWithinRange) {
      _showError('You are not within the site boundary (100m radius).');
      return;
    }

    final learnerId = learner['LearnerID'].toString();

    setState(() {
      _isClockingIn[learnerId] = true;
    });

    try {
      final now = DateTime.now();
      final clockInTime = DateFormat('HH:mm:ss').format(now);
      final clockDate = DateFormat('yyyy-MM-dd').format(now);

      final clockInData = {
        'learner_id': learnerId,
        'class_id': widget.classID,
        'clock_in_time': clockInTime,
        'clock_date': clockDate,
        'latitude': _currentPosition?.latitude.toString() ?? '0',
        'longitude': _currentPosition?.longitude.toString() ?? '0',
        'gps_accuracy': _currentGpsAccuracy?.toString() ?? '0',
        'clocking_type': 'mtl_session', // Identify this as MTL session-based
      };

      if (_isOnline) {
        // Send to server with auth_token (sessionId) in header
        final response = await http.post(
          Uri.parse(AppConfig.clockinUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_sessionId', // ✅ SessionVerificationContract.md section 1
          },
          body: jsonEncode(clockInData),
        );

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          if (responseData['success'] == true) {
            setState(() {
              clockInTimes[learnerId] = clockInTime;
            });
            _showSuccess('Clock-in successful for ${learner['Name']} ${learner['Surname']}');
          } else {
            _showError(responseData['message'] ?? 'Clock-in failed');
          }
        } else if (response.statusCode == 401) {
          _showError('Session expired. Please login again.');
          setState(() {
            _sessionError = 'Session expired';
            _sessionId = null;
          });
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } else {
        // Offline mode - save locally
        final db = await DatabaseHelper().database;
        await db.insert(
          'learner_clocking',
          {
            'LearnerID': learnerId,
            'ClassID': widget.classID,
            'clock_in_time': clockInTime,
            'clock_date': clockDate,
            'latitude': _currentPosition?.latitude ?? 0,
            'longitude': _currentPosition?.longitude ?? 0,
            'gps_accuracy': _currentGpsAccuracy ?? 0,
            'synced': 0, // Mark as unsynced
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        setState(() {
          clockInTimes[learnerId] = clockInTime;
        });
        _showSuccess('Clock-in saved offline for ${learner['Name']} ${learner['Surname']}');
      }
    } catch (e) {
      debugPrint('[MTL_SESSION] Clock-in error: $e');
      _showError('Clock-in failed: $e');
    } finally {
      setState(() {
        _isClockingIn[learnerId] = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MTL Session Clock-In'),
        backgroundColor: Colors.blue,
        actions: [
          // Session status indicator
          if (_isValidatingSession)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else if (_sessionError != null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.error, color: Colors.red),
            )
          else if (_sessionId != null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.check_circle, color: Colors.white),
            ),
          // Online/Offline indicator
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? Colors.white : Colors.orange,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Session info banner
          if (_sessionUser != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MTL Session Active',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          'User: ${_sessionUser!['name']} (${_sessionUser!['role']})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadAndValidateSession,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            )
          else if (_sessionError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sessionError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadAndValidateSession,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),

          // Geofence status
          Container(
            padding: const EdgeInsets.all(12),
            color: _isWithinRange ? Colors.green.shade50 : Colors.orange.shade50,
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
                        ? 'Within site boundary (100m)'
                        : 'Outside site boundary',
                    style: TextStyle(
                      color: _isWithinRange ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
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
                hintText: 'Search learners...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Learners list
          Expanded(
            child: _buildLearnersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLearnersList() {
    if (_filteredLearners.isEmpty) {
      return const Center(
        child: Text('No learners found'),
      );
    }

    return ListView.builder(
      itemCount: _filteredLearners.length,
      itemBuilder: (context, index) {
        final learner = _filteredLearners[index];
        final learnerId = learner['LearnerID'].toString();
        final hasClockIn = clockInTimes.containsKey(learnerId);
        final hasClockOut = clockOutTimes.containsKey(learnerId);
        final isProcessing = _isClockingIn[learnerId] == true;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: hasClockIn ? Colors.green : Colors.grey,
              child: Text(
                learner['Name']?.toString().substring(0, 1).toUpperCase() ?? 'L',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              '${learner['Name']} ${learner['Surname']}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${learner['IDnumber']}'),
                if (hasClockIn)
                  Text(
                    'Clock In: ${clockInTimes[learnerId]}',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                if (hasClockOut)
                  Text(
                    'Clock Out: ${clockOutTimes[learnerId]}',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
              ],
            ),
            trailing: isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ElevatedButton.icon(
                    onPressed: _sessionId != null && !hasClockIn
                        ? () => _clockInWithSession(learner)
                        : null,
                    icon: const Icon(Icons.login, size: 16),
                    label: Text(hasClockIn ? 'Clocked In' : 'Clock In'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasClockIn ? Colors.grey : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
