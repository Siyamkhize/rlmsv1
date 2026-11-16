// smart_framed_camera_capture.dart
//
// Intelligent face capture with ML Kit face detection
// Auto-captures when face is properly positioned and held steady
//
// Requirements:
//   pubspec.yaml:
//     camera: ^0.11.0
//     google_mlkit_face_detection: ^0.12.0
//
//   Android: minSdkVersion 21+
//   iOS: NSCameraUsageDescription in Info.plist
//   Lock to portrait orientation for this screen

import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

/// Smart Framed Camera Capture Widget
///
/// Opens camera with oval frame overlay and captures photo with watermark
/// Uses ML Kit to detect face position and auto-capture when ready
/// Used for manual clocking evidence (face photo before signature)
class SmartFramedCameraCapture extends StatefulWidget {
  final int learnerID;
  final String learnerName;
  final Function(File imageFile, Uint8List imageBytes) onCapture;
  final CameraLensDirection lens;
  final Duration holdDuration;

  const SmartFramedCameraCapture({
    super.key,
    required this.learnerID,
    required this.learnerName,
    required this.onCapture,
    this.lens = CameraLensDirection.back,
    this.holdDuration = const Duration(milliseconds: 1000),
  });

  @override
  State<SmartFramedCameraCapture> createState() =>
      _SmartFramedCameraCaptureState();
}

enum _Status { searching, adjusting, livenessCheck, ready }

class _FrameState {
  const _FrameState(this.status, this.hint, this.progress);

  final _Status status;
  final String hint;
  final double progress; // 0..1 hold-still progress or liveness progress
}

class _SmartFramedCameraCaptureState extends State<SmartFramedCameraCapture> {
  CameraController? _controller;
  late final FaceDetector _detector;
  final _state = ValueNotifier<_FrameState>(
    const _FrameState(_Status.searching, 'Position your face in the oval', 0),
  );

  Size _viewSize = Size.zero;
  Rect _oval = Rect.zero;
  bool _busy = false;
  bool _captured = false;
  DateTime? _goodSince;
  
  // LIVENESS DETECTION ADDITIONS
  bool _livenessCheckPassed = false;
  final List<double> _headYawHistory = []; // Track head rotation (left-right)
  DateTime? _livenessStartTime;
  static const double _livenessMotionThreshold = 8.0; // degrees of head movement required
  static const int _livenessMaxDuration = 8; // seconds to complete liveness check

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true, // eyes-open probability
        minFaceSize: 0.3,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final cam = cams.firstWhere(
        (c) => c.lensDirection == widget.lens,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted) return;

      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[SMART_FRAMED_CAMERA] Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------- frames

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
      debugPrint('[SMART_CAMERA] Invalid rotation');
      return null;
    }

    if (image.planes.isEmpty) {
      debugPrint('[SMART_CAMERA] No image planes available');
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
        debugPrint('[SMART_CAMERA] Unsupported plane count: ${image.planes.length}');
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
    final controller = _controller;
    if (_busy || _captured || controller == null || _oval.isEmpty) return;

    _busy = true;
    try {
      final input = _toInputImage(image, controller.description);
      if (input == null) {
        debugPrint('[SMART_CAMERA] Failed to convert camera image to InputImage');
        return;
      }

      final faces = await _detector.processImage(input);
      if (!mounted || _captured) return;

      debugPrint('[SMART_CAMERA] Detected ${faces.length} face(s)');

      // Upright image size (sensor is landscape, we are in portrait).
      final sensor = controller.description.sensorOrientation;
      final swap = sensor == 90 || sensor == 270;
      final uw = (swap ? image.height : image.width).toDouble();
      final uh = (swap ? image.width : image.height).toDouble();

      _evaluate(faces, Size(uw, uh), controller.description.lensDirection);
    } catch (e) {
      debugPrint('[SMART_CAMERA] Error processing frame: $e');
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

    if (sizeRatio < 0.55) {
      problem = 'Move closer';
    } else if (sizeRatio > 0.92) {
      problem = 'Move back a little';
    } else if (off.dx.abs() > _oval.width * 0.12 ||
        off.dy.abs() > _oval.height * 0.12) {
      problem = 'Centre your face in the oval';
    }

    if (problem != null) {
      _reset(_Status.adjusting, problem);
      return;
    }

    // LIVENESS CHECK: Require head movement to prove it's a live person
    if (!_livenessCheckPassed) {
      _performLivenessCheck(face);
      return;
    }

    // FINAL POSITION CHECK: After liveness passed, check head angle and eyes
    if ((face.headEulerAngleY ?? 0).abs() > 12 ||
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
        (elapsed.inMilliseconds / widget.holdDuration.inMilliseconds)
            .clamp(0.0, 1.0);

    _state.value = _FrameState(_Status.ready, 'Perfect — hold still', progress);

    if (progress >= 1.0) _capture();
  }

  /// Liveness detection: Require user to turn their head slightly
  void _performLivenessCheck(Face face) {
    _livenessStartTime ??= DateTime.now();
    
    final headYaw = face.headEulerAngleY ?? 0.0;
    _headYawHistory.add(headYaw);
    
    // Keep only last 30 frames (~1 second at 30fps)
    if (_headYawHistory.length > 30) {
      _headYawHistory.removeAt(0);
    }
    
    // Check if enough time has passed (timeout after 8 seconds)
    final elapsed = DateTime.now().difference(_livenessStartTime!);
    if (elapsed.inSeconds > _livenessMaxDuration) {
      // FAILED: No movement detected - likely a photo/screen
      debugPrint('[LIVENESS] ✗ FAILED - No natural movement detected (possible photo/screen)');
      
      // Show error dialog and block clocking
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Expanded(child: Text('Liveness Check Failed')),
              ],
            ),
            content: const Text(
              'Unable to verify a real person. This appears to be a photo or screen image. '
              'Clock in/out requires a live person.\n\n'
              'Please try again with the actual person present.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close camera
                },
                child: const Text('Cancel', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    // Need at least 10 samples to analyze motion
    if (_headYawHistory.length < 10) {
      _state.value = _FrameState(
        _Status.livenessCheck,
        'Slowly turn your head left, then right',
        _headYawHistory.length / 10.0,
      );
      return;
    }
    
    // Calculate range of head movement
    final minYaw = _headYawHistory.reduce(math.min);
    final maxYaw = _headYawHistory.reduce(math.max);
    final yawRange = (maxYaw - minYaw).abs();
    
    debugPrint('[LIVENESS] Yaw range: $yawRange degrees (need $_livenessMotionThreshold+)');
    
    // Check if sufficient head movement detected
    if (yawRange >= _livenessMotionThreshold) {
      // PASSED: Real person detected (head moved naturally)
      debugPrint('[LIVENESS] ✓ PASSED - Natural head movement detected');
      _livenessCheckPassed = true;
      HapticFeedback.lightImpact();
      _state.value = const _FrameState(
        _Status.ready,
        '✓ Live person verified - now look straight',
        1.0,
      );
      // Give user a moment to see the success message
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _reset(_Status.adjusting, 'Center your face and look straight');
        }
      });
    } else {
      // Still waiting for movement
      final progress = (yawRange / _livenessMotionThreshold).clamp(0.0, 1.0);
      _state.value = _FrameState(
        _Status.livenessCheck,
        'Slowly turn your head left, then right',
        progress,
      );
    }
  }

  void _reset(_Status s, String hint) {
    _goodSince = null;
    // Don't reset liveness if it already passed
    if (s == _Status.searching || s == _Status.adjusting) {
      if (!_livenessCheckPassed) {
        _headYawHistory.clear();
        _livenessStartTime = null;
      }
    }
    _state.value = _FrameState(s, hint, 0);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_captured || controller == null) return;

    _captured = true;
    debugPrint('[SMART_FRAMED_CAMERA] Starting capture...');

    try {
      await controller.stopImageStream();
      debugPrint('[SMART_FRAMED_CAMERA] Image stream stopped, taking picture...');

      final photo = await controller.takePicture();
      HapticFeedback.mediumImpact();
      debugPrint('[SMART_FRAMED_CAMERA] Picture taken, reading bytes...');

      // Read image bytes
      final Uint8List imageBytes = await photo.readAsBytes();
      debugPrint(
          '[SMART_FRAMED_CAMERA] Image bytes read: ${imageBytes.length} bytes');

      // Add watermark with timeout
      Uint8List watermarkedBytes;
      try {
        debugPrint('[SMART_FRAMED_CAMERA] Starting watermark process...');
        watermarkedBytes = await _addWatermarkToImage(imageBytes)
            .timeout(const Duration(seconds: 10));
        debugPrint('[SMART_FRAMED_CAMERA] Watermark completed successfully');
      } catch (e) {
        debugPrint(
            '[SMART_FRAMED_CAMERA] Watermark failed, using original image: $e');
        watermarkedBytes = imageBytes; // Fallback to original image
      }

      // Create temp file with processed image
      final File tempFile = File(photo.path);
      await tempFile.writeAsBytes(watermarkedBytes);
      debugPrint('[SMART_FRAMED_CAMERA] File written, calling onCapture...');

      if (mounted) {
        widget.onCapture(tempFile, watermarkedBytes);
        debugPrint('[SMART_FRAMED_CAMERA] onCapture called, closing camera...');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[SMART_FRAMED_CAMERA] Capture error: $e');
      _captured = false;
      _goodSince = null;
      if (mounted &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(_onFrame);
      }
    }
  }

  Future<Uint8List> _addWatermarkToImage(Uint8List imageBytes) async {
    // Decode image
    final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image image = frameInfo.image;

    // Create canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw original image
    canvas.drawImage(image, Offset.zero, Paint());

    final width = image.width.toDouble();
    final height = image.height.toDouble();

    // Draw frame border
    final framePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      framePaint,
    );

    // Draw watermark background
    final watermarkHeight = height * 0.15;
    final watermarkRect = Rect.fromLTWH(
      0,
      height - watermarkHeight,
      width,
      watermarkHeight,
    );

    canvas.drawRect(
      watermarkRect,
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );

    // Prepare text
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    // Draw title using ui.ParagraphBuilder
    final titleBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: width * 0.04,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText(widget.learnerName); // Just name, no label

    final titleParagraph = titleBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 40));

    canvas.drawParagraph(
      titleParagraph,
      Offset(20, height - watermarkHeight + 20),
    );

    // Draw timestamp (moved up, no learner info line)
    final timestampBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: width * 0.038,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFF0000)))
      ..addText(timestamp);

    final timestampParagraph = timestampBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 40));

    canvas.drawParagraph(
      timestampParagraph,
      Offset(20, height - watermarkHeight + 55),
    );

    // Add corner timestamp
    final cornerTimestamp =
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final cornerBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: width * 0.04,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText(cornerTimestamp);

    final cornerParagraph = cornerBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width));

    canvas.drawParagraph(
      cornerParagraph,
      const Offset(20, 20),
    );

    // Convert to image
    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(
      image.width,
      image.height,
    );

    // Convert to bytes
    final ByteData? byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    _state.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, c) {
              _viewSize = Size(c.maxWidth, c.maxHeight);
              final w = c.maxWidth * 0.72;
              _oval = Rect.fromCenter(
                center: Offset(c.maxWidth / 2, c.maxHeight * 0.42),
                width: w,
                height: w * 1.35,
              );

              final p = controller.value.previewSize!; // landscape size
              return Stack(fit: StackFit.expand, children: [
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: p.height,
                      height: p.width,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
                ValueListenableBuilder<_FrameState>(
                  valueListenable: _state,
                  builder: (_, s, __) => CustomPaint(
                    painter: _FramePainter(_oval, s),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: _oval.bottom + 28,
                  child: ValueListenableBuilder<_FrameState>(
                    valueListenable: _state,
                    builder: (_, s, __) => _HintPill(state: s),
                  ),
                ),

                // Manual capture button REMOVED - auto-capture only for security
                // Prevents users from manually capturing photos/screens
              ]);
            }),
    );
  }
}

Color _colorFor(_Status s) => switch (s) {
      _Status.searching => Colors.white,
      _Status.adjusting => const Color(0xFFFFB020),
      _Status.livenessCheck => const Color(0xFF9B59B6), // Purple for liveness
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
