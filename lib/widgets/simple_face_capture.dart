import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

enum FaceCaptureMode {
  register,
  verify,
}

class SimpleFaceCapture extends StatefulWidget {
  final String title;
  final String instruction;
  final Function(File imageFile, String base64Image) onCapture;
  final VoidCallback? onCancel;

  final FaceCaptureMode mode;

  @Deprecated('autoCapture is ignored - capture is always automatic. '
      'This parameter exists only so existing calls compile.')
  final bool autoCapture;

  final Duration? timeout;
  final VoidCallback? onTimeout;

  const SimpleFaceCapture({
    super.key,
    this.mode = FaceCaptureMode.register,
    required this.title,
    required this.instruction,
    required this.onCapture,
    this.onCancel,
    this.autoCapture = true,
    this.timeout,
    this.onTimeout,
  });

  @override
  State<SimpleFaceCapture> createState() => _SimpleFaceCaptureState();
}

class _Eval {
  final bool ok;
  final String label;
  final String hint;
  final Color color;
  final IconData icon;
  const _Eval(this.ok, this.label, this.hint, this.color, this.icon);
}

class _SimpleFaceCaptureState extends State<SimpleFaceCapture>
    with TickerProviderStateMixin {
  FaceCaptureMode get _mode => widget.mode;

  int get _streakRequired => _mode == FaceCaptureMode.register ? 4 : 3;

  Duration get _analysisInterval => const Duration(milliseconds: 500);

  Duration get _tipAfter => const Duration(seconds: 20);

  double get _minFaceWidthRatio => 0.25;
  double get _maxFaceWidthRatio => 1.10;

  double get _maxCenterOffset =>
      _mode == FaceCaptureMode.register ? 0.25 : 0.30;

  double get _maxYaw => _mode == FaceCaptureMode.register ? 25 : 30;
  double get _maxRoll => _mode == FaceCaptureMode.register ? 25 : 30;
  double get _maxPitch => _mode == FaceCaptureMode.register ? 20 : 25;
  double get _minEyeOpen => 0.25;

  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  FaceDetector? _faceDetector;

  bool _isCameraInitialized = false;
  bool _captureTriggered = false;
  bool _isCapturing = false;
  bool _isAnalyzing = false;
  bool _isFrontCamera = true;
  bool _isSwitchingCamera = false;
  int _sensorOrientation = 90;

  String _bannerText = 'Starting camera...';
  String _alignmentHint = 'Starting camera...';
  Color _qualityColor = Colors.orange;
  IconData _icon = Icons.face;

  List<Face> _faces = [];
  Size _lastImageSize = Size.zero;
  Rect _ovalRect = Rect.zero;
  Size _previewSize = Size.zero;

  int _goodStreak = 0;
  DateTime _lastGoodAt = DateTime.now();
  DateTime _streakStartedAt = DateTime.now();
  bool _showTip = false;
  String _lastError = '';
  Timer? _analysisTimer;
  Timer? _smoothTimer;
  Timer? _timeoutTimer;
  DateTime _startedAt = DateTime.now();

  double _displayProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    _startedAt = DateTime.now();
    _initializeFaceDetector();
    // Start with BACK camera by default (99% of use cases)
    await _initializeCamera(useBackCamera: true);
    if (mounted && _isCameraInitialized) {
      _startPeriodicAnalysis();
      _startSmoothProgressTicker();
      _startTimeoutIfAny();
    }
  }

  void _startTimeoutIfAny() {
    _timeoutTimer?.cancel();
    final timeout = widget.timeout;
    if (timeout == null) return;
    _timeoutTimer = Timer(timeout, () {
      if (!mounted) return;
      debugPrint(
          '[FaceCapture] Mode=$_mode timeout reached after ${timeout.inSeconds}s');
      _analysisTimer?.cancel();
      _smoothTimer?.cancel();
      setState(() {
        _captureTriggered = true;
      });
      if (widget.onTimeout != null) {
        widget.onTimeout!();
      }
    });
  }

  Future<void> _initializeCamera({bool useBackCamera = false}) async {
    try {
      final cameras = await availableCameras();

      // Select camera based on preference
      if (useBackCamera) {
        final backCameras = cameras
            .where((c) => c.lensDirection == CameraLensDirection.back)
            .toList();
        _cameraDescription =
            backCameras.isNotEmpty ? backCameras.first : cameras.first;
      } else {
        final frontCameras = cameras
            .where((c) => c.lensDirection == CameraLensDirection.front)
            .toList();
        _cameraDescription =
            frontCameras.isNotEmpty ? frontCameras.first : cameras.first;
      }

      _isFrontCamera =
          _cameraDescription?.lensDirection == CameraLensDirection.front;
      _sensorOrientation = _cameraDescription?.sensorOrientation ?? 90;

      _cameraController = CameraController(
        _cameraDescription!,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _isSwitchingCamera = false;
        _qualityColor = Colors.red;
        _bannerText = 'No face found';
        _alignmentHint = 'Put your face inside the oval';
        _icon = Icons.face;
        _lastGoodAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _lastError = e.toString();
          _alignmentHint = 'Camera error: $e';
          _isSwitchingCamera = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera) return;

    setState(() {
      _isSwitchingCamera = true;
      _captureTriggered = false;
      _goodStreak = 0;
    });

    _analysisTimer?.cancel();

    try {
      await _cameraController?.dispose();
      _cameraController = null;
      _isCameraInitialized = false;

      // Switch to opposite camera
      await _initializeCamera(useBackCamera: _isFrontCamera);

      if (mounted && _isCameraInitialized) {
        _startPeriodicAnalysis();
        HapticFeedback.selectionClick();
      }
    } catch (e) {
      debugPrint('Camera switch error: $e');
      if (mounted) {
        setState(() => _isSwitchingCamera = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch camera: $e')),
        );
      }
    }
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
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

  void _startSmoothProgressTicker() {
    _smoothTimer?.cancel();
    _smoothTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      double target;
      if (_isCapturing || _captureTriggered) {
        target = 1.0;
      } else if (_goodStreak == 0) {
        target = 0.0;
      } else {
        final totalMs = _streakRequired * _analysisInterval.inMilliseconds;
        final elapsed =
            DateTime.now().difference(_streakStartedAt).inMilliseconds;
        final fromCount = (_goodStreak - 1) / _streakRequired;
        final fromTime = elapsed.clamp(0, totalMs) / totalMs;
        target = math.max<double>(fromCount, fromTime).clamp(0.0, 1.0);
      }
      final newVal = _displayProgress + (target - _displayProgress) * 0.35;
      if ((newVal - _displayProgress).abs() > 0.001) {
        setState(() => _displayProgress = newVal.clamp(0.0, 1.0));
      }
    });
  }

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
        if (_goodStreak == 0) {
          _streakStartedAt = now;
          HapticFeedback.selectionClick();
        }
        _goodStreak++;
        _lastGoodAt = now;
        _showTip = false;
        _bannerText = 'Perfect — hold still';
        _alignmentHint =
            'Do not move ($_goodStreak/$_streakRequired). Capturing automatically.';
      } else {
        if (_goodStreak > 0) {
          debugPrint('Streak broken: rule "${eval.label}" failed');
        }
        _goodStreak = 0;
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
      if (mounted) setState(() => _lastError = e.toString());
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
      final decW = decoded.width.toDouble();
      final decH = decoded.height.toDouble();

      final faces = await _faceDetector!.processImage(inputImage);

      final bool sensorNeedsSwap =
          (_sensorOrientation == 90 || _sensorOrientation == 270);
      final bool decodedIsLandscape = decW > decH;
      final bool needSwap = sensorNeedsSwap == decodedIsLandscape;

      final upright = needSwap ? Size(decH, decW) : Size(decW, decH);

      decoded.dispose();

      if (faces.isNotEmpty) {
        final b = faces.first.boundingBox;
        debugPrint(
            '[FACE] raw bbox: L=${b.left.toStringAsFixed(0)} T=${b.top.toStringAsFixed(0)} R=${b.right.toStringAsFixed(0)} B=${b.bottom.toStringAsFixed(0)}  '
            'decoded=${decW.toStringAsFixed(0)}x${decH.toStringAsFixed(0)}  '
            'upright=${upright.width.toStringAsFixed(0)}x${upright.height.toStringAsFixed(0)}  '
            'swap=$needSwap sensor=$_sensorOrientation front=$_isFrontCamera');
        final yaw = faces.first.headEulerAngleY;
        final roll = faces.first.headEulerAngleZ;
        final pitch = faces.first.headEulerAngleX;
        debugPrint('[FACE] angles — yaw=$yaw  roll=$roll  pitch=$pitch');
        final le = faces.first.leftEyeOpenProbability;
        final re = faces.first.rightEyeOpenProbability;
        debugPrint('[FACE] eye-open — left=$le  right=$re');
      }

      return _FaceDetectionResult(detected: faces, imageSize: upright);
    } catch (e) {
      debugPrint('Face detection error: $e');
      return _FaceDetectionResult(error: e.toString());
    }
  }

  Rect _mapFaceRect(Face face, Size img, Size canvas) {
    final imgAspect = img.width / img.height;
    final canvasAspect = canvas.width / canvas.height;

    final double scale;
    final double dispW;
    final double dispH;
    if (imgAspect > canvasAspect) {
      scale = canvas.height / img.height;
      dispH = canvas.height;
      dispW = img.width * scale;
    } else {
      scale = canvas.width / img.width;
      dispW = canvas.width;
      dispH = img.height * scale;
    }
    final offX = (canvas.width - dispW) / 2;
    final offY = (canvas.height - dispH) / 2;

    final b = face.boundingBox;
    var left = b.left * scale + offX;
    var right = b.right * scale + offX;
    var top = b.top * scale + offY;
    var bottom = b.bottom * scale + offY;

    if (_isFrontCamera) {
      final l = canvas.width - right;
      right = canvas.width - left;
      left = l;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  _Eval _evaluate(List<Face> faces, Size img) {
    if (_previewSize == Size.zero || _ovalRect == Rect.zero) {
      return const _Eval(false, 'Getting ready', 'One moment...', Colors.orange,
          Icons.hourglass_top);
    }

    if (faces.isEmpty) {
      final hint = _lastError.isNotEmpty
          ? 'Detection: ${_lastError.length > 60 ? _lastError.substring(0, 60) : _lastError}'
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

    final tol = math.max(img.width * 0.015, 6.0);
    if (b.left < -tol ||
        b.top < -tol ||
        b.right > img.width + tol ||
        b.bottom > img.height + tol) {
      debugPrint(
          '[RULE FAIL] Whole-face: L=${b.left.toStringAsFixed(0)} T=${b.top.toStringAsFixed(0)} R=${b.right.toStringAsFixed(0)} B=${b.bottom.toStringAsFixed(0)}  img=${img.width.toStringAsFixed(0)}x${img.height.toStringAsFixed(0)}  tol=$tol');
      return const _Eval(
          false,
          'Show your whole face',
          'Keep your whole face inside the picture',
          Colors.orange,
          Icons.crop_free);
    }

    final widthRatio = b.width / img.width;
    if (widthRatio < _minFaceWidthRatio) {
      debugPrint(
          '[RULE FAIL] Too far: widthRatio=$widthRatio < min=$_minFaceWidthRatio');
      return const _Eval(false, 'Move closer',
          'Bring the phone closer to your face', Colors.orange, Icons.zoom_in);
    }
    if (widthRatio > _maxFaceWidthRatio) {
      debugPrint(
          '[RULE FAIL] Too near: widthRatio=$widthRatio > max=$_maxFaceWidthRatio');
      return const _Eval(
          false,
          'Move back',
          'Move the phone a bit further from your face',
          Colors.orange,
          Icons.zoom_out);
    }

    final rect = _mapFaceRect(face, img, _previewSize);
    final dx = (rect.center.dx - _ovalRect.center.dx) / _ovalRect.width;
    final dy = (rect.center.dy - _ovalRect.center.dy) / _ovalRect.height;
    if (dx.abs() > _maxCenterOffset || dy.abs() > _maxCenterOffset) {
      if (dx.abs() >= dy.abs()) {
        if (_isFrontCamera) {
          return dx > 0
              ? const _Eval(
                  false,
                  'Move left ←',
                  'Slide your face left until it is in the middle of the oval',
                  Colors.orange,
                  Icons.arrow_back)
              : const _Eval(
                  false,
                  'Move right →',
                  'Slide your face right until it is in the middle of the oval',
                  Colors.orange,
                  Icons.arrow_forward);
        } else {
          return dx < 0
              ? const _Eval(
                  false,
                  'Move left ←',
                  'Slide your face left until it is in the middle of the oval',
                  Colors.orange,
                  Icons.arrow_back)
              : const _Eval(
                  false,
                  'Move right →',
                  'Slide your face right until it is in the middle of the oval',
                  Colors.orange,
                  Icons.arrow_forward);
        }
      }
      if (dy > 0) {
        return const _Eval(
            false,
            'Move up ↑',
            'Raise the phone or your face until it is in the middle of the oval',
            Colors.orange,
            Icons.arrow_upward);
      } else {
        return const _Eval(
            false,
            'Move down ↓',
            'Lower the phone or your face until it is in the middle of the oval',
            Colors.orange,
            Icons.arrow_downward);
      }
    }

    final yawRaw = face.headEulerAngleY ?? 0;
    final rollRaw = face.headEulerAngleZ ?? 0;
    final pitchRaw = face.headEulerAngleX ?? 0;
    if (yawRaw.abs() > _maxYaw) {
      debugPrint('[RULE FAIL] yaw=$yawRaw > $_maxYaw');
      return const _Eval(
          false,
          'Look straight',
          'Face the camera, do not turn your head left or right',
          Colors.orange,
          Icons.face);
    }
    if (rollRaw.abs() > _maxRoll) {
      debugPrint('[RULE FAIL] roll=$rollRaw > $_maxRoll');
      return const _Eval(
          false,
          'Keep head straight',
          'Do not tilt your head to the side',
          Colors.orange,
          Icons.screen_rotation);
    }
    if (pitchRaw.abs() > _maxPitch) {
      debugPrint('[RULE FAIL] pitch=$pitchRaw > $_maxPitch');
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

    final le = face.leftEyeOpenProbability;
    final re = face.rightEyeOpenProbability;
    if ((le != null && le < _minEyeOpen) || (re != null && re < _minEyeOpen)) {
      debugPrint('[RULE FAIL] eyes: left=$le right=$re min=$_minEyeOpen');
      return const _Eval(false, 'Open your eyes', 'Keep both eyes open',
          Colors.orange, Icons.visibility);
    }

    return const _Eval(true, 'Perfect', 'Hold still, photo about to be taken',
        Colors.green, Icons.check_circle);
  }

  void _resumeAnalysis() {
    _captureTriggered = false;
    _goodStreak = 0;
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _displayProgress = 0.0;
      });
      _startPeriodicAnalysis();
      // Timeout continues counting from the original startedAt.
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _resumeAnalysis();
      return;
    }

    if (mounted) setState(() => _isCapturing = true);
    _analysisTimer?.cancel();

    while (_isAnalyzing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    File? imageFile;
    try {
      final image = await _cameraController!.takePicture();
      imageFile = File(image.path);

      final check = await _detectFacesInFile(imageFile);
      final eval = check.detected == null
          ? null
          : _evaluate(check.detected!, check.imageSize);
      if (eval == null || !eval.ok) {
        final reason = eval?.label ?? check.error ?? 'detection failed';
        debugPrint('Final photo rejected: $reason');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Moved at the last moment ($reason) — retrying...')),
          );
        }
        await imageFile.delete();
        _resumeAnalysis();
        return;
      }

      // Compress image to reduce size for POST upload
      // Target: under 10KB base64 for reliable HTTP POST
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        imageFile.path,
        quality: 70, // Start with 70% quality
        minWidth:
            400, // Resize to max 400px width (enough for face recognition)
        minHeight: 400,
      );

      // If still too large, compress more aggressively
      Uint8List finalBytes;
      if (compressedBytes != null && compressedBytes.length < 10240) {
        // Under 10KB raw - good!
        finalBytes = compressedBytes;
        debugPrint(
            '[FACE_CAPTURE] Compressed to ${compressedBytes.length} bytes');
      } else if (compressedBytes != null) {
        // Still too large, try more aggressive compression
        final moreCompressed = await FlutterImageCompress.compressWithFile(
          imageFile.path,
          quality: 50,
          minWidth: 300,
          minHeight: 300,
        );
        finalBytes = moreCompressed ?? compressedBytes;
        debugPrint(
            '[FACE_CAPTURE] Aggressively compressed to ${finalBytes.length} bytes');
      } else {
        // Compression failed, read original bytes as fallback
        final originalBytes = await imageFile.readAsBytes();
        finalBytes = originalBytes;
        debugPrint(
            '[FACE_CAPTURE] ⚠️ Compression failed, using original ${originalBytes.length} bytes');
      }

      final base64Image = base64Encode(finalBytes);
      debugPrint(
          '[FACE_CAPTURE] Base64 length: ${base64Image.length} chars (approx ${(base64Image.length * 0.75 / 1024).toStringAsFixed(1)}KB)');

      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final permanentPath = '${appDir.path}/face_$timestamp.jpg';
      final permanentFile = await imageFile.copy(permanentPath);
      try {
        await imageFile.delete();
      } catch (_) {}

      HapticFeedback.mediumImpact();
      if (mounted) widget.onCapture(permanentFile, base64Image);
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
    _smoothTimer?.cancel();
    _analysisTimer?.cancel();
    _timeoutTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            color: Colors.blue.shade50,
            child: Text(
              widget.instruction,
              style: const TextStyle(fontSize: 16, height: 1.35),
              textAlign: TextAlign.center,
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

                      // Oval size - fits full face with some margin
                      final ovalWidth = previewSize.width * 0.75;
                      final ovalHeight = ovalWidth * 1.45;
                      final ovalLeft = (previewSize.width - ovalWidth) / 2;
                      final ovalTop = previewSize.height * 0.15;
                      _previewSize = previewSize;
                      _ovalRect = Rect.fromLTWH(
                        ovalLeft,
                        ovalTop,
                        ovalWidth,
                        ovalHeight,
                      );

                      final cameraAspect = _cameraController!.value.aspectRatio;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: 1,
                                height: 1 / cameraAspect,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          ),
                          CustomPaint(
                            painter: FaceGuidePainter(
                              ovalRect: _ovalRect,
                              faces: _faces,
                              qualityColor: _qualityColor,
                              progress: _isCapturing ? 1.0 : _displayProgress,
                              faceRectMapper: (face) =>
                                  _lastImageSize == Size.zero
                                      ? null
                                      : _mapFaceRect(
                                          face, _lastImageSize, previewSize),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            left: 16,
                            right: 16,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _qualityColor.withOpacity(
                                    _qualityColor == Colors.red ? 0.94 : 0.92),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: _qualityColor == Colors.green
                                    ? [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.55),
                                          blurRadius: 22,
                                          spreadRadius: 3,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.18),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(_icon, color: Colors.white, size: 32),
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
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _alignmentHint,
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.95),
                                            fontSize: 13.5,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Camera indicator and flip button
                          Positioned(
                            top: 130,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap:
                                      _isSwitchingCamera ? null : _switchCamera,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.75),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isFrontCamera
                                              ? Icons.camera_front
                                              : Icons.camera_rear,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _isSwitchingCamera
                                              ? 'Switching...'
                                              : (_isFrontCamera
                                                  ? 'Using front camera'
                                                  : 'Using back camera'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.flip_camera_android,
                                          color: _isSwitchingCamera
                                              ? Colors.white.withOpacity(0.5)
                                              : Colors.white,
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_isCapturing)
                            Container(
                              color: Colors.black38,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 4),
                                    SizedBox(height: 14),
                                    Text(
                                      'Capturing — hold still…',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Builder(
              builder: (context) {
                String txt;
                if (_isCapturing) {
                  txt = 'Please hold still…';
                } else if (_showTip) {
                  txt =
                      'Tip: face a light source, remove any cap or glasses, and hold the phone at eye level';
                } else {
                  final modeLabel = _mode == FaceCaptureMode.register
                      ? 'Registering'
                      : 'Verifying';
                  txt =
                      '$modeLabel — auto-capture when your face is centered in the oval';
                }
                final timeout = widget.timeout;
                if (timeout != null) {
                  final remaining =
                      timeout - DateTime.now().difference(_startedAt);
                  final s = remaining.inSeconds;
                  if (s > 0) {
                    txt += ' · ${s}s left';
                  }
                }
                return Text(
                  txt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 13.5, height: 1.3),
                );
              },
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
  final Color qualityColor;
  final double progress;
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

    final bgPaint = Paint()..color = Colors.black.withOpacity(0.35);
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);
    final cutout = Path.combine(PathOperation.difference, outerPath, ovalPath);
    canvas.drawPath(cutout, bgPaint);

    if (isAligned) {
      final glowOuter = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..color = Colors.green.withOpacity(0.22);
      final glowMid = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = Colors.greenAccent.withOpacity(0.35);
      canvas.drawOval(ovalRect.inflate(10), glowOuter);
      canvas.drawOval(ovalRect.inflate(5), glowMid);
    } else {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = qualityColor.withOpacity(0.28);
      canvas.drawOval(ovalRect, glowPaint);
    }

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 7 : 4.5
      ..color = isAligned
          ? Colors.greenAccent.shade400
          : (qualityColor == Colors.red ? Colors.white : qualityColor);
    canvas.drawOval(ovalRect, guidePaint);

    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = (qualityColor == Colors.red ? Colors.white : Colors.white)
          .withOpacity(isAligned ? 0.55 : 0.40);
    canvas.drawLine(
      Offset(ovalRect.center.dx, ovalRect.top + 10),
      Offset(ovalRect.center.dx, ovalRect.bottom - 10),
      crossPaint,
    );
    canvas.drawLine(
      Offset(ovalRect.left + 10, ovalRect.center.dy),
      Offset(ovalRect.right - 10, ovalRect.center.dy),
      crossPaint,
    );

    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [
            Color(0xFFA7FFC1),
            Color(0xFF4ADE80),
            Color(0xFF22D3EE),
            Color(0xFFA7FFC1),
          ],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(ovalRect.inflate(16));
      canvas.drawArc(
        ovalRect.inflate(16),
        -math.pi / 2,
        2 * math.pi * clampedProgress,
        false,
        ringPaint,
      );
    }

    if (faces.isEmpty) return;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 3.0 : 2.2
      ..color =
          isAligned ? Colors.lightGreenAccent.shade400 : Colors.cyanAccent;

    for (final face in faces) {
      final rect = faceRectMapper(face);
      if (rect == null) continue;
      canvas.drawRect(rect, boxPaint);
      if (isAligned) {
        final glowBox = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = Colors.greenAccent.withOpacity(0.25);
        canvas.drawRect(rect.inflate(3), glowBox);
      }
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.ovalRect != ovalRect ||
        oldDelegate.qualityColor != qualityColor ||
        (oldDelegate.progress - progress).abs() > 0.005;
  }
}
