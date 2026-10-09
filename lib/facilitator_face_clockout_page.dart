import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import 'database_helper.dart';
import 'config.dart';
import 'widgets/facilitator_camera_signature_widget.dart';

class FacilitatorFaceClockOutPage extends StatefulWidget {
  final int facilitatorId;
  final String facilitatorName;

  const FacilitatorFaceClockOutPage({
    super.key,
    required this.facilitatorId,
    required this.facilitatorName,
  });

  @override
  State<FacilitatorFaceClockOutPage> createState() =>
      _FacilitatorFaceClockOutPageState();
}

class _FacilitatorFaceClockOutPageState
    extends State<FacilitatorFaceClockOutPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isProcessing = false;
  String _statusMessage = 'Starting clock-out...';
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
      _startClockOutFlow();
    });
  }

  Future<void> _startClockOutFlow() async {
    // FIRST: Check if already clocked out today or not clocked in
    final clockingStatus = await _checkClockingStatus();

    if (clockingStatus == 'not_clocked_in') {
      // Not clocked in yet - show message
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_outlined, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Text('Not Clocked In'),
              ],
            ),
            content: Text(
              'Hi ${widget.facilitatorName},\n\nYou have not clocked in today. You need to clock in before you can clock out.\n\nTaking you back...',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        Navigator.pop(context, false);
      }
      return;
    }

    if (clockingStatus == 'already_clocked_out') {
      // Already clocked out - show message
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 32),
                SizedBox(width: 12),
                Text('Already Clocked Out'),
              ],
            ),
            content: Text(
              'Hi ${widget.facilitatorName},\n\nYou have already clocked out today. You cannot clock out twice on the same day.\n\nTaking you to your dashboard...',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
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

        Navigator.pop(context, true);
      }
      return;
    }

    // Clocked in but not clocked out yet - proceed with camera and signature
    await _captureCameraAndSignature();
  }

  /// Check clocking status for today
  /// Returns: 'not_clocked_in', 'already_clocked_out', or 'can_clock_out'
  Future<String> _checkClockingStatus() async {
    try {
      setState(() {
        _statusMessage = 'Checking clock-out status...';
        _isProcessing = true;
      });

      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);

      // 1. Check local database first
      debugPrint(
          '[FAC_FACE_CLOCKOUT] Checking local database for clocking on $today');
      final localRecord = await _dbHelper.getFacilitatorAttendanceForDay(
        widget.facilitatorId.toString(),
        today,
      );

      if (localRecord != null) {
        // Check if clocked in
        if (localRecord['clock_in_time'] == null) {
          debugPrint('[FAC_FACE_CLOCKOUT] Not clocked in yet');
          setState(() {
            _isProcessing = false;
          });
          return 'not_clocked_in';
        }

        // Check if already clocked out
        if (localRecord['clock_out_time'] != null) {
          debugPrint('[FAC_FACE_CLOCKOUT] Already clocked out');
          setState(() {
            _isProcessing = false;
          });
          return 'already_clocked_out';
        }

        // Clocked in but not clocked out
        debugPrint('[FAC_FACE_CLOCKOUT] Can clock out');
        setState(() {
          _isProcessing = false;
        });
        return 'can_clock_out';
      }

      // 2. Check server if online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.first != ConnectivityResult.none) {
        debugPrint('[FAC_FACE_CLOCKOUT] Checking server for clocking status');
        final serverStatus = await _checkServerForClockingStatus(today);

        setState(() {
          _isProcessing = false;
        });
        return serverStatus;
      } else {
        debugPrint('[FAC_FACE_CLOCKOUT] Offline - cannot check server');
        setState(() {
          _isProcessing = false;
        });
        // Assume not clocked in if no local record and offline
        return 'not_clocked_in';
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Error checking clocking status: $e');
      setState(() {
        _isProcessing = false;
      });
      // On error, assume can clock out (fail open)
      return 'can_clock_out';
    }
  }

  /// Check server for clocking status
  Future<String> _checkServerForClockingStatus(String clockDate) async {
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
        if (data['success'] == true) {
          // Save server record locally
          if (data['clock_in_time'] != null || data['clock_out_time'] != null) {
            await _dbHelper.insertFacilitatorClocking({
              'facilitator_id': widget.facilitatorId,
              'clock_in_time': data['clock_in_time'],
              'clock_out_time': data['clock_out_time'],
              'clock_date': clockDate,
              'clock_in_method': data['clock_in_method'] ?? 'signature',
              'clock_out_method': data['clock_out_method'] ?? 'signature',
              'synced': 1, // Mark as synced since it came from server
              'user_latitude': data['user_latitude']?.toString() ?? '0.0',
              'user_longitude': data['user_longitude']?.toString() ?? '0.0',
              'user_accuracy': data['user_accuracy']?.toString() ?? '10.0',
            });
            debugPrint('[FAC_FACE_CLOCKOUT] Saved server record to local DB');
          }

          // Check status
          if (data['clock_in_time'] == null) {
            return 'not_clocked_in';
          } else if (data['clock_out_time'] != null) {
            return 'already_clocked_out';
          } else {
            return 'can_clock_out';
          }
        }
      }
      
      // No record found - not clocked in
      return 'not_clocked_in';
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Server check error: $e');
      return 'can_clock_out'; // Fail open
    }
  }

  Future<void> _captureCameraAndSignature() async {
    setState(() {
      _currentStep = 1;
      _statusMessage = 'Please take selfie and sign';
    });

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FacilitatorCameraSignatureWidget(
          facilitatorId: widget.facilitatorId,
          facilitatorName: widget.facilitatorName,
          clockAction: 'out',
        ),
      ),
    );

    if (result == null || result['success'] != true) {
      // User cancelled or error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result?['message'] ?? 'Clock-out cancelled'),
            duration: const Duration(seconds: 2),
          ),
        );
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

    // Save clock-out
    await _saveClockOut();
  }

  Future<void> _saveClockOut() async {
    setState(() {
      _currentStep = 2;
      _statusMessage = 'Saving clock-out data...';
      _isProcessing = true;
    });

    try {
      final now = DateTime.now();
      final clockDate = DateFormat('yyyy-MM-dd').format(now);
      final clockOutTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      // Update facilitator_clocking table with clock-out time
      await _dbHelper.updateFacilitatorClockOut(
        facilitatorId: widget.facilitatorId,
        clockDate: clockDate,
        clockOutTime: clockOutTime,
        clockOutMethod: 'face',
      );

      debugPrint('[FAC_FACE_CLOCKOUT] Saved clock-out to local database');

      // Save clocking evidence (signature + face photo)
      await _saveClockingEvidence(clockDate);

      // Try to sync to server
      await _syncToServer(clockDate, clockOutTime);

      setState(() {
        _isProcessing = false;
        _currentStep = 3;
        _statusMessage = 'Clock-out completed successfully!';
      });

      // Show success and return
      if (mounted) {
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
              'Goodbye, ${widget.facilitatorName}!\n\nYou have successfully clocked out at ${DateFormat('HH:mm').format(now)}.\n\nHave a great day!',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );

        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        _showError('Failed to save clock-out: $e');
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
        action: 'out',
        signatureFilename:
            'facilitator_${widget.facilitatorId}_${clockDate}_out_signature.png',
        photoFilename:
            'facilitator_${widget.facilitatorId}_${clockDate}_out_photo.jpg',
        latitude: _latitude,
        longitude: _longitude,
        accuracy: _accuracy,
        verificationMethod: 'face',
        faceLogId: null,
        timestamp: DateTime.now().toIso8601String(),
      );

      debugPrint(
          '[FAC_FACE_CLOCKOUT] Saved clocking evidence to local database');
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Error saving evidence locally: $e');
    }
  }

  Future<void> _syncToServer(String clockDate, String clockOutTime) async {
    try {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.first == ConnectivityResult.none) {
        debugPrint('[FAC_FACE_CLOCKOUT] Offline - will sync later');
        return;
      }

      // Upload clocking evidence (signature + photo)
      await _uploadClockingEvidence(clockDate);

      // Sync clock-out time to server
      await _syncClockOutTime(clockDate, clockOutTime);

      debugPrint('[FAC_FACE_CLOCKOUT] Successfully synced to server');
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Sync error (will retry later): $e');
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
              'action': 'out',
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
          debugPrint('[FAC_FACE_CLOCKOUT] Evidence uploaded successfully');
        }
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Evidence upload error: $e');
    }
  }

  Future<void> _syncClockOutTime(String clockDate, String clockOutTime) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/facilitator_clock_out.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'facilitator_id': widget.facilitatorId,
              'clock_out_time': clockOutTime,
              'clock_date': clockDate,
              'clock_out_method': 'face',
              'contact_time': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[FAC_FACE_CLOCKOUT] Clock-out time synced to server');
        }
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKOUT] Clock-out sync error: $e');
    }
  }

  void _showError(String message) {
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
        title: const Text('Clock Out - Facial Verification'),
        backgroundColor: Colors.orange,
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
                      const Icon(Icons.logout, size: 48, color: Colors.orange),
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