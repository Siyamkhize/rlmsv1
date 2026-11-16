import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Simple Camera Capture for Facilitator Clocking
/// - Uses FRONT camera (selfie mode)
/// - No ML Kit face detection
/// - Shows oval frame guide
/// - Manual capture button
/// - Adds watermark with facilitator name and timestamp
class FacilitatorSimpleCameraCapture extends StatefulWidget {
  final int facilitatorID;
  final String facilitatorName;
  final Function(File imageFile, Uint8List imageBytes) onCapture;

  const FacilitatorSimpleCameraCapture({
    super.key,
    required this.facilitatorID,
    required this.facilitatorName,
    required this.onCapture,
  });

  @override
  State<FacilitatorSimpleCameraCapture> createState() =>
      _FacilitatorSimpleCameraCaptureState();
}

class _FacilitatorSimpleCameraCaptureState
    extends State<FacilitatorSimpleCameraCapture> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      
      // Find FRONT camera
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('[FACILITATOR_CAMERA] Error initializing camera: $e');
      _showError('Camera initialization failed: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _showError('Camera not ready');
      return;
    }

    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // Take picture
      final image = await _controller!.takePicture();

      // Read image bytes
      final bytes = await File(image.path).readAsBytes();

      // Add watermark
      final watermarkedBytes = await _addWatermark(bytes);

      // Save to temp file
      final tempFile = File(image.path);
      await tempFile.writeAsBytes(watermarkedBytes);

      // Return to caller
      widget.onCapture(tempFile, watermarkedBytes);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[FACILITATOR_CAMERA] Capture error: $e');
      _showError('Photo capture failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<Uint8List> _addWatermark(Uint8List imageBytes) async {
    // Decode image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Create canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());

    // Draw original image
    canvas.drawImage(image, Offset.zero, Paint());

    // Watermark settings
    final watermarkHeight = size.height * 0.12;
    final watermarkY = size.height - watermarkHeight;

    // Draw semi-transparent background
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, watermarkY, size.width, watermarkHeight),
      bgPaint,
    );

    // Draw blue frame border
    final framePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;

    canvas.drawRect(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      framePaint,
    );

    // Add facilitator name
    final nameBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: size.width * 0.04,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText(widget.facilitatorName);

    final nameParagraph = nameBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.width - 40));

    canvas.drawParagraph(
      nameParagraph,
      Offset(20, watermarkY + 20),
    );

    // Add timestamp
    final timestamp =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final timestampBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: size.width * 0.038,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFF0000)))
      ..addText(timestamp);

    final timestampParagraph = timestampBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.width - 40));

    canvas.drawParagraph(
      timestampParagraph,
      Offset(20, watermarkY + 55),
    );

    // Add corner timestamp
    final cornerTimestamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final cornerBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: size.width * 0.04,
        fontWeight: FontWeight.bold,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText(cornerTimestamp);

    final cornerParagraph = cornerBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));

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
    final byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return byteData!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Facilitator Photo'),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Take Your Photo'),
        backgroundColor: Colors.teal,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),

          // Oval guide overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _OvalGuidePainter(),
            ),
          ),

          // Instructions at top
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Position your face in the oval',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Camera indicator
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_front, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Using front camera',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Capture button at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _capturePhoto,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.blue,
                      width: 4,
                    ),
                  ),
                  child: _isCapturing
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Colors.blue,
                          size: 36,
                        ),
                ),
              ),
            ),
          ),

          // Helper text
          const Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Text(
              'Tap to capture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for oval guide
class _OvalGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Oval cutout
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.4),
      width: size.width * 0.7,
      height: size.height * 0.5,
    );

    path.addOval(ovalRect);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw oval border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawOval(ovalRect, borderPaint);

    // Draw crosshair
    final crosshairPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1;

    // Vertical line
    canvas.drawLine(
      Offset(size.width / 2, ovalRect.top),
      Offset(size.width / 2, ovalRect.bottom),
      crosshairPaint,
    );

    // Horizontal line
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.center.dy),
      Offset(ovalRect.right, ovalRect.center.dy),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
