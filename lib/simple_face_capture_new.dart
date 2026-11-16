import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Face registration screen.
///
/// The photo is captured AUTOMATICALLY, and only when every check passes
/// for several consecutive frames. There is no manual capture button, so a
/// half face or misaligned photo can never be registered.
class SimpleFaceCapture extends StatefulWidget {
  final String title;
  final String instruction;
  final Function(File imageFile, String base64Image) onCapture;
  final VoidCallback? onCancel;

  /// Kept only so existing callers still compile. Capture is always automatic.
  final bool autoCapture;

  const SimpleFaceCapture({
    super.key,
    required this.title,
    required this.instruction,
    required this.onCapture,
    this.onCancel,
    this.autoCapture = true,
  });

  @override
  State<SimpleFaceCapture> createState() => _SimpleFaceCaptureState();
}

/// Result of checking one detection result against all rules.
class _Eval {
  final bool ok;
  final String label; // short, big instruction e.g. "Move closer"
  final String hint; // one clear sentence explaining what to do
  final Color color;
  final IconData icon;
  const _Eval(this.ok, this.label, this.hint, this.color, this.icon);
}

class _SimpleFaceCaptureState extends State<SimpleFaceCapture> {
  // ---- Tunable thresholds (used for the live check AND the final photo) ----
  static const int _streakRequired = 4; // good frames in a row (~2 seconds)
  static const Duration _analysisInterval = Duration(milliseconds: 500);
  static const Duration _tipAfter = Duration(seconds: 20);

  static const double _minFaceWidthRatio = 0.38; // face width / image width
  static const double _maxFaceWidthRatio = 0.85;
  static const double _maxCenterOffset = 0.25; // fraction of oval size
  static const double _maxYaw = 25; // turned left/right
  static const double _maxRoll = 25; // head tilted sideways
  static const double _maxPitch = 20; // looking up/down
  static const double _minEyeOpen = 0.4;

  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  FaceDetector? _faceDetector;

  bool _isCameraInitialized = false;
  bool _captureTriggered = false;
  bool _isCapturing = false;
  bool _isAnalyzing = false;
  bool _isFrontCamera = true;

  String _faceQuality = 'Initializing...';
  String _alignmentHint = 'Starting camera...';
  Color _qualityColor = Colors.orange;
  String _bannerText = 'Starting camera...';
  IconData _icon = Icons.face;

  List<Face> _faces = [];
  Size _lastImageSize = Size.zero; // UPRIGHT size of the analysed photo
  Rect _ovalRect = Rect.zero;
  Size _previewSize = Size.zero;

  int _goodStreak = 0;
  DateTime _lastGoodAt = DateTime.now();
  bool _showTip = false;
  String _lastError = '';
  Timer? _analysisTimer;

  @override
  void initState() {
    super.initState();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    _initializeFaceDetector();
    await _initializeCamera();
    if (mounted && _isCameraInitialized) {
      _startPeriodicAnalysis();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCameras = cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .toList();
      _cameraDescription =
          frontCameras.isNotEmpty ? frontCameras.first : cameras.first;
      _isFrontCamera =
          _cameraDescription?.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        _cameraDescription!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _faceQuality = 'None';
        _qualityColor = Colors.red;
        _alignmentHint = 'Put your face inside the oval';
        _bannerText = 'No face found';
        _icon = Icons.face;
        _lastGoodAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _lastError = e.toString();
          _alignmentHint = 'Camera error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // needed for eye-open probability
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  void _startPeriodicAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(_analysisInterval, (_) {
      if (!mounted) return;
      _runAnalysisCycle();
    });
  }

  // ---------------------------------------------------------------------
  // Live analysis
  // ---------------------------------------------------------------------

  Future<void> _runAnalysisCycle() async {
    if (_isAnalyzing ||
        _isCapturing ||
        _captureTriggered ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    _isAnalyzing = true;
    XFile? picture;

    try {
      picture = await _cameraController!.takePicture();
      final result = await _detectFacesInFile(File(picture.path));
      if (!mounted || _captureTriggered) return;

      if (result.detected != null) {
        _faces = result.detected!;
        _lastImageSize = result.imageSize;
        _lastError = '';
      } else {
        _faces = [];
        _lastError = result.error ?? '';
      }

      final eval = _evaluate(_faces, _lastImageSize);
      final now = DateTime.now();

      if (eval.ok) {
        _goodStreak++;
        if (_goodStreak == 1) HapticFeedback.selectionClick();
        _lastGoodAt = now;
        _showTip = false;
        _faceQuality = 'Good — hold still ($_goodStreak/$_streakRequired)';
        _bannerText = 'Perfect — hold still';
        _alignmentHint = 'Do not move, capturing automatically...';
      } else {
        _goodStreak = 0;
        _faceQuality = eval.label;
        _bannerText = eval.label;
        _alignmentHint = eval.hint;
        if (now.difference(_lastGoodAt) > _tipAfter) _showTip = true;
      }
      _icon = eval.icon;
      _qualityColor = eval.color;

      setState(() {});

      if (_goodStreak >= _streakRequired) {
        _captureTriggered = true;
        unawaited(_captureImage());
      }
    } catch (e) {
      debugPrint('Analysis error: $e');
      if (mounted) {
        setState(() {
          _lastError = e.toString();
        });
      }
    } finally {
      if (picture != null) {
        try {
          final f = File(picture.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _isAnalyzing = false;
    }
  }

  Future<_FaceDetectionResult> _detectFacesInFile(File file) async {
    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      var decW = decoded.width.toDouble();
      var decH = decoded.height.toDouble();

      final faces = await _faceDetector!.processImage(inputImage);
      Size upright;
      if (faces.isNotEmpty) {
        final b = faces.first.boundingBox;
        final bWiderThanTall = b.width > b.height;
        final decWiderThanTall = decW > decH;
        final uprightWiderThanTall =
            !bWiderThanTall; // face is always taller-than-wide when upright
        if (decWiderThanTall != uprightWiderThanTall) {
          final t = decW;
          decW = decH;
          decH = t;
        }
        upright = Size(decW, decH);
      } else {
        upright = decW >= decH ? Size(decW, decH) : Size(decH, decW);
      }
      decoded.dispose();

      return _FaceDetectionResult(detected: faces, imageSize: upright);
    } catch (e) {
      debugPrint('Face detection error: $e');
      return _FaceDetectionResult(error: e.toString());
    }
  }

  /// Maps a detected face box (upright image coordinates) to the preview
  /// canvas. The preview is sized by height and centred, and the front camera
  /// preview is mirrored while the saved photo is not.
  Rect _mapFaceRect(Face face, Size img, Size canvas) {
    final scale = canvas.height / img.height;
    final dispW = img.width * scale;
    final offX = (canvas.width - dispW) / 2;

    final b = face.boundingBox;
    var left = b.left * scale + offX;
    var right = b.right * scale + offX;
    final top = b.top * scale;
    final bottom = b.bottom * scale;

    if (_isFrontCamera) {
      final l = canvas.width - right;
      right = canvas.width - left;
      left = l;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // ---------------------------------------------------------------------
  // The single set of rules. Used for live frames AND the final photo.
  // ---------------------------------------------------------------------

  _Eval _evaluate(List<Face> faces, Size img) {
    if (_previewSize == Size.zero || _ovalRect == Rect.zero) {
      return const _Eval(false, 'Getting ready', 'One moment...', Colors.orange,
          Icons.hourglass_top);
    }

    if (faces.isEmpty) {
      final hint = _lastError.isNotEmpty
          ? 'Detection: ${_lastError.length > 50 ? _lastError.substring(0, 50) : _lastError}'
          : 'Put your face inside the oval';
      return _Eval(false, 'No face found', hint, Colors.red, Icons.face);
    }

    if (faces.length > 1) {
      return const _Eval(
          false,
          'Only one person',
          'Make sure only your face is in the picture',
          Colors.orange,
          Icons.groups);
    }

    if (img == Size.zero) {
      return const _Eval(false, 'Detecting...', 'Hold on a moment',
          Colors.orange, Icons.hourglass_top);
    }

    final face = faces.first;
    final b = face.boundingBox;

    // 1. Whole face must be inside the photo (no half faces)
    final tol = img.width * 0.01;
    if (b.left < -tol ||
        b.top < -tol ||
        b.right > img.width + tol ||
        b.bottom > img.height + tol) {
      return const _Eval(
          false,
          'Show your whole face',
          'Keep your whole face inside the picture',
          Colors.orange,
          Icons.crop_free);
    }

    // 2. Distance (raw detector numbers, no canvas mapping)
    final widthRatio = b.width / img.width;
    if (widthRatio < _minFaceWidthRatio) {
      return const _Eval(false, 'Move closer',
          'Bring the phone closer to your face', Colors.orange, Icons.zoom_in);
    }
    if (widthRatio > _maxFaceWidthRatio) {
      return const _Eval(
          false,
          'Move back',
          'Move the phone a bit further from your face',
          Colors.orange,
          Icons.zoom_out);
    }

    // 3. Centred in the oval (directions are as you see them on screen)
    final rect = _mapFaceRect(face, img, _previewSize);
    final dx = (rect.center.dx - _ovalRect.center.dx) / _ovalRect.width;
    final dy = (rect.center.dy - _ovalRect.center.dy) / _ovalRect.height;
    if (dx.abs() > _maxCenterOffset || dy.abs() > _maxCenterOffset) {
      if (dx.abs() >= dy.abs()) {
        return dx > 0
            ? const _Eval(
                false,
                'Move left',
                'Slide your face left until it is in the middle of the oval',
                Colors.orange,
                Icons.arrow_back)
            : const _Eval(
                false,
                'Move right',
                'Slide your face right until it is in the middle of the oval',
                Colors.orange,
                Icons.arrow_forward);
      }
      return dy > 0
          ? const _Eval(
              false,
              'Move up',
              'Raise the phone or your face until it is in the middle of the oval',
              Colors.orange,
              Icons.arrow_upward)
          : const _Eval(
              false,
              'Move down',
              'Lower the phone or your face until it is in the middle of the oval',
              Colors.orange,
              Icons.arrow_downward);
    }

    // 4. Head straight
    final yawRaw = face.headEulerAngleY ?? 0;
    final rollRaw = face.headEulerAngleZ ?? 0;
    final pitchRaw = face.headEulerAngleX ?? 0;
    if (yawRaw.abs() > _maxYaw) {
      return const _Eval(
          false,
          'Look straight',
          'Face the camera, do not turn your head left or right',
          Colors.orange,
          Icons.face);
    }
    if (rollRaw.abs() > _maxRoll) {
      return const _Eval(
          false,
          'Keep head straight',
          'Do not tilt your head to the side',
          Colors.orange,
          Icons.screen_rotation);
    }
    if (pitchRaw.abs() > _maxPitch) {
      // ML Kit: positive X angle means the face is looking up
      return pitchRaw > 0
          ? const _Eval(
              false,
              'Lower your chin',
              'You are looking up, look straight at the camera',
              Colors.orange,
              Icons.arrow_downward)
          : const _Eval(
              false,
              'Raise your chin',
              'You are looking down, look straight at the camera',
              Colors.orange,
              Icons.arrow_upward);
    }

    // 5. Eyes open
    final le = face.leftEyeOpenProbability;
    final re = face.rightEyeOpenProbability;
    if ((le != null && le < _minEyeOpen) || (re != null && re < _minEyeOpen)) {
      return const _Eval(false, 'Open your eyes', 'Keep both eyes open',
          Colors.orange, Icons.visibility);
    }

    return const _Eval(
        true, 'Good', 'Do not move', Colors.green, Icons.check_circle);
  }

  // ---------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------

  void _resumeAnalysis() {
    _captureTriggered = false;
    _goodStreak = 0;
    if (mounted) {
      setState(() {
        _isCapturing = false;
      });
      _startPeriodicAnalysis();
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _resumeAnalysis();
      return;
    }

    if (mounted) {
      setState(() {
        _isCapturing = true;
      });
    }
    _analysisTimer?.cancel();

    // Never run two takePicture() calls at once
    while (_isAnalyzing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    File? imageFile;
    try {
      final image = await _cameraController!.takePicture();
      imageFile = File(image.path);

      // Re-verify the ACTUAL photo we are about to save. The person may have
      // moved between the last analysed frame and this shot.
      final check = await _detectFacesInFile(imageFile);
      final eval = check.detected == null
          ? null
          : _evaluate(check.detected!, check.imageSize);
      if (eval == null || !eval.ok) {
        debugPrint('Final photo rejected: ${eval?.label ?? check.error}');
        await imageFile.delete();
        _resumeAnalysis(); // quietly go back to analysing, nothing saved
        return;
      }

      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final permanentPath = '${appDir.path}/face_$timestamp.jpg';
      final permanentFile = await imageFile.copy(permanentPath);
      try {
        await imageFile.delete();
      } catch (_) {}

      HapticFeedback.mediumImpact();
      if (mounted) {
        widget.onCapture(permanentFile, base64Image);
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
      _resumeAnalysis();
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.blue,
        actions: [
          if (widget.onCancel != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onCancel,
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Text(
              widget.instruction,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: _qualityColor.withValues(alpha: 0.2),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _qualityColor == Colors.green
                          ? Icons.check_circle
                          : Icons.warning,
                      color: _qualityColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Face Quality: $_faceQuality',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _qualityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _alignmentHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _qualityColor.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isCameraInitialized && _cameraController != null
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final previewSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );

                      final ovalWidth = previewSize.width * 0.74;
                      final ovalHeight = ovalWidth * 1.32;
                      final ovalLeft = (previewSize.width - ovalWidth) / 2;
                      final ovalTop = previewSize.height * 0.16;
                      _previewSize = previewSize;
                      _ovalRect = Rect.fromLTWH(
                        ovalLeft,
                        ovalTop,
                        ovalWidth,
                        ovalHeight,
                      );

                      final cameraAspect = _cameraController!.value.aspectRatio;
                      final dispW = cameraAspect >= 1
                          ? (previewSize.height * cameraAspect)
                          : previewSize.height * cameraAspect;
                      final dispH = previewSize.height;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: SizedBox(
                              width: previewSize.width,
                              height: previewSize.height,
                              child: ClipRect(
                                child: OverflowBox(
                                  maxWidth: double.infinity,
                                  maxHeight: double.infinity,
                                  child: SizedBox(
                                    width: dispW,
                                    height: dispH,
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: 1,
                                        height: 1 / cameraAspect,
                                        child:
                                            CameraPreview(_cameraController!),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          CustomPaint(
                            painter: FaceGuidePainter(
                              ovalRect: _ovalRect,
                              faces: _faces,
                              qualityColor: _qualityColor,
                              progress: _isCapturing
                                  ? 1.0
                                  : _goodStreak / _streakRequired,
                              faceRectMapper: (face) =>
                                  _lastImageSize == Size.zero
                                      ? null
                                      : _mapFaceRect(
                                          face, _lastImageSize, previewSize),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 16,
                            right: 16,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _qualityColor.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_icon, color: Colors.white, size: 34),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _bannerText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _alignmentHint,
                                          style: TextStyle(
                                            color:
                                                Colors.white.withValues(alpha: 0.95),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isCapturing)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Capturing...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Initializing camera...'),
                      ],
                    ),
                  ),
          ),
          // No manual capture button on purpose: capture is automatic and only
          // happens when every check passes.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _isCapturing
                  ? 'Please hold still...'
                  : _showTip
                      ? 'Tip: face a light source, remove any cap or glasses, '
                          'and hold the phone at eye level'
                      : 'Auto-capture when your face is centered in the oval',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceDetectionResult {
  final List<Face>? detected;
  final Size imageSize;
  final String? error;

  _FaceDetectionResult({
    this.detected,
    this.imageSize = Size.zero,
    this.error,
  });
}

class FaceGuidePainter extends CustomPainter {
  final Rect ovalRect;
  final List<Face> faces;
  final Color qualityColor; // red = no face, orange = adjust, green = good
  final double progress; // 0..1 hold-still progress
  final Rect? Function(Face face) faceRectMapper;

  FaceGuidePainter({
    required this.ovalRect,
    required this.faces,
    required this.qualityColor,
    required this.progress,
    required this.faceRectMapper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isAligned = qualityColor == Colors.green;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 16 : 10
      ..color = qualityColor.withValues(alpha: 0.28);

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 6 : 4
      ..color = qualityColor;

    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = qualityColor.withValues(alpha: 0.5);

    canvas.drawOval(ovalRect, glowPaint);
    canvas.drawOval(ovalRect, guidePaint);
    canvas.drawLine(
      Offset(ovalRect.center.dx, ovalRect.top),
      Offset(ovalRect.center.dx, ovalRect.bottom),
      crossPaint,
    );
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.center.dy),
      Offset(ovalRect.right, ovalRect.center.dy),
      crossPaint,
    );

    // Hold-still progress ring around the oval
    if (progress > 0) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = Colors.lightGreenAccent;
      canvas.drawArc(
        ovalRect.inflate(14),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        ringPaint,
      );
    }

    if (faces.isEmpty) return;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = isAligned ? Colors.lightGreenAccent : Colors.white70;

    for (final face in faces) {
      final rect = faceRectMapper(face);
      if (rect == null) continue;
      canvas.drawRect(rect, boxPaint);
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.ovalRect != ovalRect ||
        oldDelegate.qualityColor != qualityColor ||
        oldDelegate.progress != progress;
  }
}
