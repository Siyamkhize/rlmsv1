import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:signature/signature.dart';
import 'package:intl/intl.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/secure_location_service.dart';
import '../database_helper.dart';
import '../config.dart';

/// Combined Camera + Signature widget for Facilitator Clocking
/// This widget handles the complete flow:
/// 1. Camera capture (selfie)
/// 2. Signature pad
/// 3. GPS location
/// Returns all data together for saving
class FacilitatorCameraSignatureWidget extends StatefulWidget {
  final int facilitatorId;
  final String facilitatorName;
  final String clockAction; // 'in' or 'out'

  const FacilitatorCameraSignatureWidget({
    super.key,
    required this.facilitatorId,
    required this.facilitatorName,
    required this.clockAction,
  });

  @override
  State<FacilitatorCameraSignatureWidget> createState() =>
      _FacilitatorCameraSignatureWidgetState();
}

enum _Status { searching, adjusting, ready }

class _FrameState {
  const _FrameState(this.status, this.hint, this.progress);

  final _Status status;
  final String hint;
  final double progress; // 0..1 hold-still progress
}

class _FacilitatorCameraSignatureWidgetState
    extends State<FacilitatorCameraSignatureWidget> {
  int _currentStep = 0; // 0 = camera, 1 = signature

  // Camera state
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;

  // Liveness detection
  final _state = ValueNotifier<_FrameState>(
    const _FrameState(_Status.searching, 'Position your face in the oval', 0),
  );
  Size _viewSize = Size.zero;
  Rect _oval = Rect.zero;
  bool _busy = false;
  DateTime? _goodSince;
  final _holdDuration = const Duration(milliseconds: 1000);

  // Captured data
  File? _photoFile;
  String? _photoBase64;

  // Signature state
  SignatureController? _signatureController;
  String? _signatureBase64;
  bool _isSubmitting = false;

  // Location data
  double? _latitude;
  double? _longitude;
  double? _accuracy;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true, // eyes-open probability
        minFaceSize: 0.3,
      ),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      // Find FRONT camera for selfie
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });

        // Start image stream for liveness detection
        await _cameraController!.startImageStream(_onFrame);
      }
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Camera error: $e');
      _showError('Camera initialization failed: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showError('Camera not ready');
      return;
    }

    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // Stop image stream
      await _cameraController!.stopImageStream();

      // Add haptic feedback
      HapticFeedback.mediumImpact();

      // Take picture
      final image = await _cameraController!.takePicture();

      // Read image bytes
      final bytes = await File(image.path).readAsBytes();

      // Convert to base64
      final base64Image = base64Encode(bytes);

      setState(() {
        _photoFile = File(image.path);
        _photoBase64 = base64Image;
        _isCapturing = false;
      });

      // Move to signature step
      _moveToSignatureStep();
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Capture error: $e');
      _showError('Photo capture failed: $e');
      setState(() {
        _isCapturing = false;
      });

      // Restart image stream if it stopped
      if (_cameraController != null &&
          !_cameraController!.value.isStreamingImages) {
        await _cameraController!.startImageStream(_onFrame);
      }
    }
  }

  void _moveToSignatureStep() {
    // Dispose camera to free resources
    _cameraController?.dispose();
    _cameraController = null;

    // Initialize signature controller
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.blue,
      exportBackgroundColor: Colors.white,
    );

    setState(() {
      _currentStep = 1;
    });
  }

  Future<void> _captureLocationAndVerifyGeofence() async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Verifying location...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

      // Get secure location
      final locationResult = await SecureLocationService.getSecurePosition();

      if (!locationResult.isTrusted) {
        throw Exception(
            'Location could not be verified - GPS accuracy too poor or mock location detected');
      }

      // Verify facilitator is within site geofence using server verification
      // We need to get the facilitator's class/site for verification
      final geofenceResult = await _verifyFacilitatorGeofence(locationResult);

      if (geofenceResult['success'] != true) {
        final errorMsg =
            geofenceResult['error'] ?? 'Geofence verification failed';
        final distance = geofenceResult['distance'];
        final effectiveRadius = geofenceResult['effective_radius'];

        String detailedError = errorMsg;
        if (distance != null && effectiveRadius != null) {
          detailedError =
              'You are ${distance.toStringAsFixed(0)}m from the site. '
              'You must be within ${effectiveRadius.toStringAsFixed(0)}m to clock ${widget.clockAction}.';
        }

        throw Exception(detailedError);
      }

      _latitude = locationResult.position.latitude;
      _longitude = locationResult.position.longitude;
      _accuracy = locationResult.position.accuracy;

      debugPrint(
          '[FAC_CAMERA_SIGNATURE] ✅ Location verified: $_latitude, $_longitude (${_accuracy}m)');
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Location/geofence error: $e');
      throw Exception('Location verification failed: $e');
    }
  }

  Future<Map<String, dynamic>> _verifyFacilitatorGeofence(
      SecurePositionResult securePosition) async {
    try {
      // Get facilitator's active classes/sites from database
      final facilitatorClassId = await _getFacilitatorClassId();

      if (facilitatorClassId == null) {
        return {
          'success': false,
          'error':
              'Unable to determine your assigned site. Please contact your administrator.',
        };
      }

      // Use the same geofence verification as learners
      return await SecureLocationService.verifyGeofenceOnServer(
        securePosition: securePosition,
        classID: facilitatorClassId,
        learnerID: widget.facilitatorId
            .toString(), // Use facilitator ID for verification
        action: widget.clockAction,
        baseUrl: AppConfig.baseUrl,
      );
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Geofence verification error: $e');
      return {
        'success': false,
        'error': 'Unable to verify location: $e',
      };
    }
  }

  Future<String?> _getFacilitatorClassId() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // Query facilitator's assigned class - assuming facilitators table has facilitator_id and class_id
      // Or get the most recent class they're working with
      final result = await db.rawQuery(
        'SELECT classID FROM facilitator WHERE facilitator_id = ?',
        [widget.facilitatorId.toString()],
      );

      if (result.isNotEmpty) {
        final classIdValue = result.first['classID'];
        if (classIdValue != null) {
          final classIdStr = classIdValue.toString();
          // If comma-separated, take the first one for geofence verification
          if (classIdStr.contains(',')) {
            return classIdStr.split(',').first.trim();
          }
          return classIdStr;
        }
      }

      // Fallback: if facilitator not found directly, we might need to handle this differently
      debugPrint(
          '[FAC_CAMERA_SIGNATURE] No classID found for facilitator ${widget.facilitatorId}');
      return null;
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Error getting facilitator class: $e');
      return null;
    }
  }

  Future<void> _completeFlow() async {
    // Validate signature
    if (_signatureController == null || _signatureController!.isEmpty) {
      _showError('Please provide your signature');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Convert signature to base64
      final signatureBytes = await _signatureController!.toPngBytes();
      if (signatureBytes != null) {
        _signatureBase64 = base64Encode(signatureBytes);
      }

      // Capture location and verify geofence - this will throw if not within site
      await _captureLocationAndVerifyGeofence();

      // Return all data if geofence verification passed
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'photo_base64': _photoBase64,
          'signature_base64': _signatureBase64,
          'latitude': _latitude,
          'longitude': _longitude,
          'accuracy': _accuracy,
        });
      }
    } catch (e) {
      debugPrint('[FAC_CAMERA_SIGNATURE] Complete error: $e');
      setState(() {
        _isSubmitting = false;
      });
      _showErrorDialog('Location Verification Failed', e.toString());
    }
  }

  void _showErrorDialog(String title, String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _cancelFlow() {
    Navigator.pop(context, {
      'success': false,
      'message': 'Clock-${widget.clockAction} cancelled',
    });
  }

  // ======== LIVENESS DETECTION METHODS ========

  /// Convert YUV_420_888 (3 planes) to NV21 (1 plane) for ML Kit on Android
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;

    final Uint8List nv21 = Uint8List(ySize + uvSize);

    // Y plane (luminance)
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    int nv21Index = 0;
    for (int y = 0; y < height; y++) {
      int yOffset = y * yRowStride;
      for (int x = 0; x < width; x++) {
        nv21[nv21Index++] = yBytes[yOffset];
        yOffset += yPixelStride;
      }
    }

    // UV planes (chrominance) - interleave V and U for NV21
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final int uvWidth = width ~/ 2;
    final int uvHeight = height ~/ 2;

    for (int y = 0; y < uvHeight; y++) {
      int uvOffset = y * uvRowStride;
      for (int x = 0; x < uvWidth; x++) {
        nv21[nv21Index++] = vBytes[uvOffset]; // V first for NV21
        nv21[nv21Index++] = uBytes[uvOffset]; // U second
        uvOffset += uvPixelStride;
      }
    }

    return nv21;
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription cam) {
    final rotation =
        InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    if (rotation == null) {
      debugPrint('[FAC_CAMERA] Invalid rotation');
      return null;
    }

    if (image.planes.isEmpty) {
      debugPrint('[FAC_CAMERA] No image planes available');
      return null;
    }

    // Android: Handle both NV21 (1 plane) and YUV_420_888 (3 planes)
    if (Platform.isAndroid) {
      Uint8List bytes;
      int bytesPerRow;

      if (image.planes.length == 1) {
        // Already NV21 - use directly
        bytes = image.planes[0].bytes;
        bytesPerRow = image.planes[0].bytesPerRow;
      } else if (image.planes.length == 3) {
        // YUV_420_888 - convert to NV21
        bytes = _yuv420ToNv21(image);
        bytesPerRow = image.width; // NV21 Y plane has no padding
      } else {
        debugPrint(
            '[FAC_CAMERA] Unsupported plane count: ${image.planes.length}');
        return null;
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: bytesPerRow,
        ),
      );
    }

    // iOS: BGRA8888
    if (Platform.isIOS) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  Future<void> _onFrame(CameraImage image) async {
    final controller = _cameraController;
    if (_busy || _isCapturing || controller == null || _oval.isEmpty) return;

    _busy = true;
    try {
      final input = _toInputImage(image, controller.description);
      if (input == null) {
        debugPrint('[FAC_CAMERA] Failed to convert camera image to InputImage');
        return;
      }

      final faces = await _faceDetector.processImage(input);
      if (!mounted || _isCapturing) return;

      // Upright image size (sensor is landscape, we are in portrait).
      final sensor = controller.description.sensorOrientation;
      final swap = sensor == 90 || sensor == 270;
      final uw = (swap ? image.height : image.width).toDouble();
      final uh = (swap ? image.width : image.height).toDouble();

      _evaluate(faces, Size(uw, uh), controller.description.lensDirection);
    } catch (e) {
      debugPrint('[FAC_CAMERA] Error processing frame: $e');
    } finally {
      _busy = false;
    }
  }

  /// Maps an ML Kit bounding box (upright image coords) to the on-screen
  /// preview, which is drawn with BoxFit.cover and mirrored for the front cam.
  Rect _toScreen(Rect box, Size img, CameraLensDirection lens) {
    final scale =
        math.max(_viewSize.width / img.width, _viewSize.height / img.height);
    final dx = (_viewSize.width - img.width * scale) / 2;
    final dy = (_viewSize.height - img.height * scale) / 2;

    var r = Rect.fromLTRB(
      box.left * scale + dx,
      box.top * scale + dy,
      box.right * scale + dx,
      box.bottom * scale + dy,
    );

    if (lens == CameraLensDirection.front) {
      r = Rect.fromLTRB(
          _viewSize.width - r.right, r.top, _viewSize.width - r.left, r.bottom);
    }

    return r;
  }

  void _evaluate(List<Face> faces, Size img, CameraLensDirection lens) {
    String? problem;

    if (faces.isEmpty) {
      _reset(_Status.searching, 'Position your face in the oval');
      return;
    }

    if (faces.length > 1) {
      _reset(_Status.adjusting, 'Only one person in the frame');
      return;
    }

    final face = faces.first;
    final r = _toScreen(face.boundingBox, img, lens);

    final sizeRatio = r.height / _oval.height;
    final off = r.center - _oval.center;

    // Check positioning
    if (sizeRatio < 0.55) {
      problem = 'Move closer';
    } else if (sizeRatio > 0.92) {
      problem = 'Move back a little';
    } else if (off.dx.abs() > _oval.width * 0.12 ||
        off.dy.abs() > _oval.height * 0.12) {
      problem = 'Centre your face in the oval';
    } else if ((face.headEulerAngleY ?? 0).abs() > 12 ||
        (face.headEulerAngleX ?? 0).abs() > 12 ||
        (face.headEulerAngleZ ?? 0).abs() > 12) {
      problem = 'Look straight at the camera';
    } else if ((face.leftEyeOpenProbability ?? 1) < 0.4 ||
        (face.rightEyeOpenProbability ?? 1) < 0.4) {
      problem = 'Open your eyes';
    }

    if (problem != null) {
      _reset(_Status.adjusting, problem);
      return;
    }

    // Perfect fit: require it to stay steady for holdDuration.
    _goodSince ??= DateTime.now();
    final elapsed = DateTime.now().difference(_goodSince!);
    final progress =
        (elapsed.inMilliseconds / _holdDuration.inMilliseconds).clamp(0.0, 1.0);

    _state.value = _FrameState(_Status.ready, 'Perfect — hold still', progress);

    if (progress >= 1.0) _capturePhoto();
  }

  void _reset(_Status s, String hint) {
    _goodSince = null;
    _state.value = _FrameState(s, hint, 0);
  }

  // ======== END LIVENESS DETECTION ========

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _state.dispose();
    _signatureController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          _cancelFlow();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _currentStep == 0
            ? AppBar(
                title: const Text('Facial Verification'),
                backgroundColor: Colors.teal,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelFlow,
                ),
              )
            : null, // No app bar for signature step
        body: _currentStep == 0 ? _buildCameraStep() : _buildSignatureStep(),
      ),
    );
  }

  Widget _buildCameraStep() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final p = _cameraController!.value.previewSize!; // landscape size

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final w = constraints.maxWidth * 0.72;
        _oval = Rect.fromCenter(
          center:
              Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.42),
          width: w,
          height: w * 1.35,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview with proper sizing
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: p.height,
                  height: p.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

            // Liveness detection overlay
            ValueListenableBuilder<_FrameState>(
              valueListenable: _state,
              builder: (_, s, __) => CustomPaint(
                painter: _FramePainter(_oval, s),
              ),
            ),

            // Instructions at top
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.facilitatorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Clock ${widget.clockAction.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Liveness status hint
            Positioned(
              left: 24,
              right: 24,
              top: _oval.bottom + 28,
              child: ValueListenableBuilder<_FrameState>(
                valueListenable: _state,
                builder: (_, s, __) => _HintPill(state: s),
              ),
            ),

            // Manual capture button (fallback)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.blue,
                        width: 4,
                      ),
                    ),
                    child: _isCapturing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            size: 40,
                            color: Colors.blue,
                          ),
                  ),
                ),
              ),
            ),

            // Close button
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: _cancelFlow,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSignatureStep() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Compact Teal Header - Smaller and more proportional
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.teal,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // Compact User Photo (smaller)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 60, // Reduced from 80
                          height: 60, // Reduced from 80
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipOval(
                            child: _photoFile != null
                                ? Image.file(
                                    _photoFile!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.white,
                                    child: const Icon(
                                      Icons.person,
                                      size: 30,
                                      color: Colors.teal,
                                    ),
                                  ),
                          ),
                        ),
                        // Smaller green check mark
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 18, // Reduced from 24
                            height: 18, // Reduced from 24
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12, // Reduced from 16
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8), // Reduced from 12

                    // User Name (smaller font)
                    Text(
                      widget.facilitatorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18, // Reduced from 22
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 6), // Reduced from 8

                    // Compact badges row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ID Badge (smaller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, // Reduced from 12
                            vertical: 4, // Reduced from 6
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.badge,
                                color: Colors.white,
                                size: 14, // Reduced from 16
                              ),
                              const SizedBox(width: 3), // Reduced from 4
                              Text(
                                'ID ${widget.facilitatorId}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12, // Reduced from 14
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8), // Reduced from 12

                        // Time Badge (smaller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                DateFormat('HH:mm').format(DateTime.now()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Clock In Badge (smaller)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.login,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Clock ${widget.clockAction == 'in' ? 'In' : 'Out'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Compact Signature Section - More proportional white card
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16), // Reduced from 20
              padding: const EdgeInsets.all(16), // Reduced from 20
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Compact Digital Signature Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6), // Reduced from 8
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.teal,
                          size: 18, // Reduced from 20
                        ),
                      ),
                      const SizedBox(width: 10), // Reduced from 12
                      const Expanded(
                        child: Text(
                          'Digital Signature',
                          style: TextStyle(
                            fontSize: 16, // Reduced from 18
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      // Clear button (smaller)
                      IconButton(
                        onPressed: () {
                          _signatureController?.clear();
                        },
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.grey,
                          size: 20, // Smaller icon
                        ),
                        tooltip: 'Clear',
                      ),
                    ],
                  ),

                  const SizedBox(height: 6), // Reduced from 8

                  Text(
                    'Sign below to confirm your clock ${widget.clockAction}',
                    style: TextStyle(
                      fontSize: 13, // Reduced from 14
                      color: Colors.grey[600],
                    ),
                  ),

                  const SizedBox(height: 12), // Reduced from 20

                  // Modern Signature Pad - Perfect balanced height
                  Container(
                    height:
                        180, // Perfect modern size - not too big, not too small
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey[300]!,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Signature(
                            controller: _signatureController!,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        // Modern placeholder text when empty
                        if (_signatureController?.isEmpty ?? true)
                          Positioned.fill(
                            child: Container(
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.edit,
                                    color: Colors.grey[300],
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sign here',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12), // Reduced from 20

                  // Compact Confirm Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _completeFlow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12), // Reduced from 16
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10), // Reduced from 12
                        ),
                      ),
                      child: _isSubmitting
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Verifying location...',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    size: 20), // Reduced from 22
                                const SizedBox(width: 6), // Reduced from 8
                                Text(
                                  'Confirm Clock ${widget.clockAction == 'in' ? 'In' : 'Out'}',
                                  style: const TextStyle(
                                    fontSize: 15, // Reduced from 16
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 8), // Reduced from 12

                  // Compact info note
                  Container(
                    padding: const EdgeInsets.all(10), // Reduced from 12
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6), // Reduced from 8
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16, // Reduced from 18
                          color: Colors.blue[700],
                        ),
                        const SizedBox(width: 6), // Reduced from 8
                        Expanded(
                          child: Text(
                            'Your signature confirms the accuracy of this clock record',
                            style: TextStyle(
                              fontSize: 11, // Reduced from 12
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======== LIVENESS DETECTION UI COMPONENTS ========

Color _colorFor(_Status s) => switch (s) {
      _Status.searching => Colors.white,
      _Status.adjusting => const Color(0xFFFFB020),
      _Status.ready => const Color(0xFF2ECC71),
    };

class _HintPill extends StatelessWidget {
  const _HintPill({required this.state});

  final _FrameState state;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(state.status);
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            state.status == _Status.ready
                ? Icons.check_circle_rounded
                : Icons.face_retouching_natural_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            state.hint,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.oval, this.state);

  final Rect oval;
  final _FrameState state;

  @override
  void paint(Canvas canvas, Size size) {
    // Dimmed background with an oval cut-out.
    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(oval),
    );

    canvas.drawPath(overlay, Paint()..color = Colors.black.withAlpha(165));

    final color = _colorFor(state.status);

    // Soft glow + border.
    canvas.drawOval(
      oval.inflate(2),
      Paint()
        ..color = color.withAlpha(70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawOval(
      oval,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Hold-still progress ring, starting at the top.
    if (state.progress > 0) {
      canvas.drawArc(
        oval.inflate(10),
        -math.pi / 2,
        2 * math.pi * state.progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.state.status != state.status ||
      old.state.progress != state.progress ||
      old.oval != oval;
}
