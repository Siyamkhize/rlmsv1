import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import 'database_helper.dart';
import 'config.dart';
import 'widgets/simple_face_capture.dart';
import 'services/face_embedding_service.dart';
import 'repositories/facilitator_face_repository.dart';
import 'services/secure_location_service.dart';

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
  String _statusMessage = 'Starting face verification...';
  int _currentStep = 0;

  File? _capturedFaceImage;
  String? _faceBase64;
  List<double>? _faceEmbedding;
  int? _faceLogId;

  SignatureController? _signatureController;
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

  @override
  void dispose() {
    _signatureController?.dispose();
    super.dispose();
  }

  Future<void> _startClockInFlow() async {
    // Step 1: Capture and verify face
    await _captureFace();
  }

  Future<void> _captureFace() async {
    setState(() {
      _currentStep = 1;
      _statusMessage = 'Please position your face for verification';
    });

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleFaceCapture(
          mode: FaceCaptureMode.verify,
          title: 'Verify Your Identity',
          instruction: 'Position your face in the oval',
          onCapture: (File imageFile, String base64Image) async {
            Navigator.pop(context, {
              'imageFile': imageFile,
              'base64Image': base64Image,
            });
          },
          onCancel: () {
            Navigator.pop(context, null);
          },
        ),
      ),
    );

    if (result == null) {
      // User cancelled - exit entire flow
      if (mounted) {
        // Show cancellation message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face verification cancelled'),
            duration: Duration(seconds: 2),
          ),
        );
        // Exit to dashboard
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    // Save captured face data
    _capturedFaceImage = result['imageFile'] as File;
    _faceBase64 = result['base64Image'] as String;

    // Verify face
    await _verifyFace();
  }

  Future<void> _verifyFace() async {
    setState(() {
      _currentStep = 2;
      _statusMessage = 'Verifying your identity...';
      _isProcessing = true;
    });

    try {
      // Extract face embedding
      final faceService = FaceEmbeddingService();
      final embedding = await faceService.extractEmbedding(
        _capturedFaceImage!.path,
      );

      if (embedding == null) {
        throw Exception('Could not extract face features. Please try again.');
      }

      _faceEmbedding = embedding;

      // Verify face with server
      final faceRepo = FacilitatorFaceRepository();
      final verifyResult = await faceRepo.verifyFace(
        facilitatorId: widget.facilitatorId,
        embedding: embedding,
        qualityScore: 0.8,
        livenessPassed: true,
        verificationType: 'clock_in',
      );

      if (verifyResult['verified'] != true) {
        // Verification failed - allow retry
        setState(() {
          _isProcessing = false;
        });

        if (mounted) {
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 32),
                    SizedBox(width: 12),
                    Text('Verification Failed'),
                  ],
                ),
                content: Text(
                  verifyResult['message']?.toString() ??
                      'Face verification failed. Please try again.',
                  style: const TextStyle(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child:
                        const Text('Try Again', style: TextStyle(fontSize: 16)),
                  ),
                ],
              );
            },
          );

          if (retry == true) {
            // Retry face capture
            await _captureFace();
            return;
          } else {
            // User cancelled, exit to dashboard
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Face verification cancelled'),
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
            return;
          }
        }
      }

      // Save face log ID if returned
      _faceLogId = verifyResult['log_id'] as int?;

      setState(() {
        _isProcessing = false;
      });

      // Move to signature step
      await _showNameAndSignature();
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        _showError('Verification failed: $e');
        Navigator.pop(context, false);
      }
    }
  }

  Future<void> _showNameAndSignature() async {
    setState(() {
      _currentStep = 3;
      _statusMessage = 'Face verified successfully!';
    });

    // Show dialog with facilitator name and signature pad
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.blue,
      exportBackgroundColor: Colors.white,
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Identity Verified',
                      style: TextStyle(fontSize: 18),
                    ),
                    Text(
                      widget.facilitatorName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please sign below to confirm clock-in',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Signature(
                      controller: _signatureController!,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _signatureController?.clear();
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_signatureController!.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide your signature'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: const Text('Confirm Clock In'),
            ),
          ],
        );
      },
    );

    if (result == true && _signatureController!.isNotEmpty) {
      // Convert signature to base64
      final signatureBytes = await _signatureController!.toPngBytes();
      if (signatureBytes != null) {
        _signatureBase64 = base64Encode(signatureBytes);
      }

      // Move to location/geofencing step
      await _verifyLocationAndGeofence();
    } else {
      // User cancelled
      if (mounted) {
        Navigator.pop(context, false);
      }
    }
  }

  Future<void> _verifyLocationAndGeofence() async {
    setState(() {
      _currentStep = 4;
      _statusMessage = 'Verifying location and geofence...';
      _isProcessing = true;
    });

    try {
      // Get current location
      final locationResult = await SecureLocationService.getSecurePosition();

      if (!locationResult.isTrusted) {
        throw Exception(
            'Location could not be verified. Please ensure GPS is enabled and location services are allowed.');
      }

      _latitude = locationResult.position.latitude;
      _longitude = locationResult.position.longitude;
      _accuracy = locationResult.position.accuracy;

      debugPrint(
          '[FAC_FACE_CLOCKIN] Location: $_latitude, $_longitude (accuracy: ${_accuracy}m)');

      // Verify geofence
      final geofenceResult = await _verifyGeofence();

      if (!geofenceResult['success']) {
        throw Exception(geofenceResult['message'] ??
            'You are outside the allowed geofence area');
      }

      setState(() {
        _isProcessing = false;
      });

      // Save clock-in data
      await _saveClockIn();
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        _showError('Location verification failed: $e');
        Navigator.pop(context, false);
      }
    }
  }

  Future<Map<String, dynamic>> _verifyGeofence() async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/verify_geofence.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'user_id': widget.facilitatorId,
              'user_type': 'facilitator',
              'latitude': _latitude,
              'longitude': _longitude,
              'accuracy': _accuracy,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'] == true,
          'message': data['message'],
          'distance': data['distance'],
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}'
        };
      }
    } catch (e) {
      debugPrint('[FAC_FACE_CLOCKIN] Geofence verification error: $e');
      // In offline mode or error, allow clock-in but log it
      return {
        'success': true,
        'message': 'Geofence check skipped (offline mode)',
      };
    }
  }

  Future<void> _saveClockIn() async {
    setState(() {
      _currentStep = 5;
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

        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        _showError('Failed to save clock-in: $e');
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
        faceLogId: _faceLogId,
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
      if (connectivityResult.first == ConnectivityResult.none) {
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
              'face_log_id': _faceLogId,
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
        title: const Text('Clock In - Face Recognition'),
        automaticallyImplyLeading: false,
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
        _buildStep(1, 'Face', _currentStep >= 1),
        _buildStepLine(_currentStep >= 2),
        _buildStep(2, 'Verify', _currentStep >= 2),
        _buildStepLine(_currentStep >= 3),
        _buildStep(3, 'Sign', _currentStep >= 3),
        _buildStepLine(_currentStep >= 4),
        _buildStep(4, 'Location', _currentStep >= 4),
        _buildStepLine(_currentStep >= 5),
        _buildStep(5, 'Done', _currentStep >= 5),
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
