import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import 'database_helper.dart';
import 'config.dart';
import 'widgets/facilitator_camera_signature_widget.dart';

class FacilitatorFaceClockInPage extends StatefulWidget {
  final int facilitatorId;
  final String facilitatorName;

  const FacilitatorFaceClockInPage({
    super.key,
    required this.facilitatorId,
    required this.facilitatorName,
  });

  @override
  State<FacilitatorFaceClockInPage> createState() =>
      _FacilitatorFaceClockInPageState();
}

class _FacilitatorFaceClockInPageState
    extends State<FacilitatorFaceClockInPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isProcessing = false;
  String _statusMessage = 'Starting clock-in...';
  int _currentStep = 0;

  String? _faceBase64;
  String? _signatureBase64;
  double? _latitude;
  double? _longitude;
  double? _accuracy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startClockInFlow();
    });
  }

  Future<void> _startClockInFlow() async {
    // FIRST: Check if already clocked in today
    final alreadyClockedIn = await _checkIfAlreadyClockedInToday();

    if (alreadyClockedIn) {
      // Already clocked in - show message and navigate to dashboard
      if (mounted) {
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Text('Already Clocked In'),
              ],
            ),
            content: Text(
              'Hi ${widget.facilitatorName},\n\nYou have already clocked in today. You cannot clock in twice on the same day.\n\nTaking you to your dashboard...',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        );

        // Navigate back - returning true indicates already clocked in
        // The calling page should handle navigation to dashboard
        Navigator.pop(context, true);
      }
      return;
    }

    // Not clocked in yet - proceed with camera and signature
    await _captureCameraAndSignature();
  }

  /// Check if facilitator has already clocked in today
  /// Checks local database first, then server if online
  Future<bool> _checkIfAlreadyClockedInToday() async {
    try {
      setState(() {
        _statusMessage = 'Checking clock-in status...';
        _isProcessing = true;
      });

      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);

      // 1. Check local database first
      debugPrint(
          '[FAC_FACE_CLOCKIN] Checking local database for clock-in on $today');
      final localRecord = await _dbHelper.getFacilitatorAttendanceForDay(
        widget.facilitatorId.toString(),
        today,
      );

      if (localRecord != null && localRecord['clock_in_time'] != null) {
        debugPrint('[FAC_FACE_CLOCKIN] Found existing clock-in in local DB');
        setState(() {
          _isProcessing = false;
        });
        return true;
      }

      // 2. Check server if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        debugPrint('[FAC_FACE_CLOCKIN] Checking server for existing clock-in');
        final serverHasRecord = await _checkServerForClockIn(today);

        if (serverHasRecord) {
          debugPrint('[FAC_FACE_CLOCKIN] Found existing clock-in on server');
          setState(() {
            _isProcessing = false;
          });
          return true;
        }
      } else {
        debugPrint('[FAC_FACE_CLOCKIN] Offline - cannot check server');
      }

      // 3. No record found anywhere
      setState(() {
        _isProcessing = false;
      });
      return false;
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Error checking clock-in status: $e');
      setState(() {
        _isProcessing = false;
      });
      // On error, allow clock-in to proceed (fail open)
      return false;
    }
  }

  /// Check server for existing clock-in record
  Future<bool> _checkServerForClockIn(String clockDate) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/check_facilitator_clockin.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'facilitator_id': widget.facilitatorId,
              'clock_date': clockDate,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['clocked_in'] == true) {
          // Found existing record on server - save it locally
          if (data['clock_in_time'] != null) {
            await _dbHelper.insertFacilitatorClocking({
              'facilitator_id': widget.facilitatorId,
              'clock_in_time': data['clock_in_time'],
              'clock_date': clockDate,
              'clock_in_method': data['clock_in_method'] ?? 'signature',
              'synced': 1, // Mark as synced since it came from server
              'user_latitude': data['user_latitude']?.toString() ?? '0.0',
              'user_longitude': data['user_longitude']?.toString() ?? '0.0',
              'user_accuracy': data['user_accuracy']?.toString() ?? '10.0',
            });
            debugPrint('[FAC_FACE_CLOCKIN] Saved server record to local DB');
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Server check error: $e');
      return false;
    }
  }

  Future<void> _captureCameraAndSignature() async {
    setState(() {
      _currentStep = 1;
      _statusMessage = 'Please take selfie and sign';
    });

    if (!context.mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FacilitatorCameraSignatureWidget(
          facilitatorId: widget.facilitatorId,
          facilitatorName: widget.facilitatorName,
          clockAction: 'in',
        ),
      ),
    );

    if (result == null || result['success'] != true) {
      // User cancelled or error
      if (mounted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result?['message'] ?? 'Clock-in cancelled'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (!context.mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    // Save captured data
    _faceBase64 = result['photo_base64'] as String?;
    _signatureBase64 = result['signature_base64'] as String?;
    _latitude = result['latitude'] as double?;
    _longitude = result['longitude'] as double?;
    _accuracy = result['accuracy'] as double?;

    // Save clock-in
    await _saveClockIn();
  }

  Future<void> _saveClockIn() async {
    setState(() {
      _currentStep = 2;
      _statusMessage = 'Saving clock-in data...';
      _isProcessing = true;
    });

    try {
      final now = DateTime.now();
      final clockDate = DateFormat('yyyy-MM-dd').format(now);
      final clockInTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      // Save to facilitator_clocking table
      await _dbHelper.insertFacilitatorClocking({
        'facilitator_id': widget.facilitatorId,
        'clock_in_time': clockInTime,
        'clock_date': clockDate,
        'clock_in_method': 'face',
        'synced': 0,
        'user_latitude': _latitude?.toString() ?? '0.0',
        'user_longitude': _longitude?.toString() ?? '0.0',
        'user_accuracy': _accuracy?.toString() ?? '10.0',
      });

      debugPrint('[FAC_FACE_CLOCKIN] Saved clock-in to local database');

      // Save clocking evidence (signature + face photo)
      await _saveClockingEvidence(clockDate);

      // Try to sync to server
      await _syncToServer(clockDate, clockInTime);

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Clock-in completed successfully!';
      });

      // Show success and return
      if (mounted) {
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Success!'),
              ],
            ),
            content: Text(
              'Welcome, ${widget.facilitatorName}!\n\nYou have successfully clocked in at ${DateFormat('HH:mm').format(now)}.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Continue to Dashboard'),
              ),
            ],
          ),
        );

        if (!context.mounted) return;
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        _showError('Failed to save clock-in: $e');
        if (!context.mounted) return;
        Navigator.pop(context, false);
      }
    }
  }

  Future<void> _saveClockingEvidence(String clockDate) async {
    try {
      // Save evidence locally
      await _dbHelper.saveFacilitatorClockingEvidence(
        facilitatorId: widget.facilitatorId,
        clockDate: clockDate,
        action: 'in',
        signatureFilename:
            'facilitator_${widget.facilitatorId}_${clockDate}_in_signature.png',
        photoFilename:
            'facilitator_${widget.facilitatorId}_${clockDate}_in_photo.jpg',
        latitude: _latitude,
        longitude: _longitude,
        accuracy: _accuracy,
        verificationMethod: 'face',
        faceLogId: null,
        timestamp: DateTime.now().toIso8601String(),
      );

      debugPrint(
          '[FAC_FACE_CLOCKIN] Saved clocking evidence to local database');
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Error saving evidence locally: $e');
    }
  }

  Future<void> _syncToServer(String clockDate, String clockInTime) async {
    try {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('[FAC_FACE_CLOCKIN] Offline - will sync later');
        return;
      }

      // Upload clocking evidence (signature + photo)
      await _uploadClockingEvidence(clockDate);

      // Sync clock-in time to server
      await _syncClockInTime(clockDate, clockInTime);

      debugPrint('[FAC_FACE_CLOCKIN] Successfully synced to server');
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Sync error (will retry later): $e');
    }
  }

  Future<void> _uploadClockingEvidence(String clockDate) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '${AppConfig.baseUrl}/save_facilitator_clocking_evidence.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'facilitator_id': widget.facilitatorId,
              'clock_date': clockDate,
              'action': 'in',
              'signature': _signatureBase64,
              'photo': _faceBase64,
              'latitude': _latitude,
              'longitude': _longitude,
              'accuracy': _accuracy,
              'verification_method': 'face',
              'face_log_id': null,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Mark as synced in local database
          await _dbHelper.markFacilitatorEvidenceSynced(
            facilitatorId: widget.facilitatorId,
            clockDate: clockDate,
          );
          debugPrint('[FAC_FACE_CLOCKIN] Evidence uploaded successfully');
        }
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Evidence upload error: $e');
    }
  }

  Future<void> _syncClockInTime(String clockDate, String clockInTime) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/facilitator_clock_in.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'facilitator_id': widget.facilitatorId,
              'clock_in_time': clockInTime,
              'clock_date': clockDate,
              'clock_in_method': 'face',
              'user_latitude': _latitude,
              'user_longitude': _longitude,
              'user_accuracy': _accuracy,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[FAC_FACE_CLOCKIN] Clock-in time synced to server');
        }
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Clock-in sync error: $e');
    }
  }

  void _showError(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock In - Facial Verification'),
        backgroundColor: Colors.teal,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Progress indicator
              if (_isProcessing) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],

              // Step indicator
              _buildStepIndicator(),
              const SizedBox(height: 32),

              // Status message
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Facilitator info
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Icon(Icons.person, size: 48, color: Colors.blue),
                      const SizedBox(height: 12),
                      Text(
                        widget.facilitatorName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ID: ${widget.facilitatorId}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStep(1, 'Capture', _currentStep >= 1),
        _buildStepLine(_currentStep >= 2),
        _buildStep(2, 'Save', _currentStep >= 2),
        _buildStepLine(_currentStep >= 3),
        _buildStep(3, 'Done', _currentStep >= 3),
      ],
    );
  }

  Widget _buildStep(int stepNumber, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.green : Colors.grey[300],
          ),
          child: Center(
            child: isActive
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    stepNumber.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Container(
      width: 20,
      height: 2,
      color: isActive ? Colors.green : Colors.grey[300],
      margin: const EdgeInsets.only(bottom: 20),
    );
  }
}
