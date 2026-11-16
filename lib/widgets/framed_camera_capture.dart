import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

/// Framed Camera Capture Widget
///
/// Opens camera with frame overlay and captures photo with watermark
/// Used for manual clocking evidence (face photo before signature)
class FramedCameraCapture extends StatefulWidget {
  final int learnerID;
  final String learnerName;
  final Function(File imageFile, Uint8List imageBytes) onCapture;

  const FramedCameraCapture({
    super.key,
    required this.learnerID,
    required this.learnerName,
    required this.onCapture,
  });

  @override
  State<FramedCameraCapture> createState() => _FramedCameraCaptureState();
}

class _FramedCameraCaptureState extends State<FramedCameraCapture> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  final GlobalKey _cameraKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras found');
      }

      // Use back camera if available, otherwise front camera
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[FRAMED_CAMERA] Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      // Capture image
      final XFile imageFile = await _controller!.takePicture();

      // Read image bytes
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Add watermark
      final Uint8List watermarkedBytes = await _addWatermarkToImage(imageBytes);

      // Create temp file with watermark
      final File tempFile = File(imageFile.path);
      await tempFile.writeAsBytes(watermarkedBytes);

      // Return to caller
      widget.onCapture(tempFile, watermarkedBytes);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[FRAMED_CAMERA] Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
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
      ..addText('RLMSS Manual Clock-In');

    final titleParagraph = titleBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 40));

    canvas.drawParagraph(
      titleParagraph,
      Offset(20, height - watermarkHeight + 10),
    );

    // Draw learner info
    final learnerBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: width * 0.035,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText('Learner: ${widget.learnerName} (ID: ${widget.learnerID})');

    final learnerParagraph = learnerBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width - 40));

    canvas.drawParagraph(
      learnerParagraph,
      Offset(20, height - watermarkHeight + 40),
    );

    // Draw timestamp
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
      Offset(20, height - watermarkHeight + 70),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Take Photo'),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !_isInitialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : Stack(
              children: [
                // Camera preview
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),

                // Frame overlay
                CustomPaint(
                  painter: FrameOverlayPainter(),
                  child: Container(),
                ),

                // Instructions
                Positioned(
                  top: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          widget.learnerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Position face within the frame',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // Capture button
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
              ],
            ),
    );
  }
}

/// Frame Overlay Painter
/// Draws guide frame over camera preview
class FrameOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    // Draw frame border
    final frameRect = Rect.fromLTWH(
      size.width * 0.1,
      size.height * 0.2,
      size.width * 0.8,
      size.height * 0.6,
    );

    canvas.drawRect(frameRect, paint);

    // Draw corner markers
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    // Top-left
    canvas.drawLine(
      Offset(frameRect.left, frameRect.top),
      Offset(frameRect.left + cornerLength, frameRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.left, frameRect.top),
      Offset(frameRect.left, frameRect.top + cornerLength),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(frameRect.right, frameRect.top),
      Offset(frameRect.right - cornerLength, frameRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.right, frameRect.top),
      Offset(frameRect.right, frameRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(frameRect.left, frameRect.bottom),
      Offset(frameRect.left + cornerLength, frameRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.left, frameRect.bottom),
      Offset(frameRect.left, frameRect.bottom - cornerLength),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(frameRect.right, frameRect.bottom),
      Offset(frameRect.right - cornerLength, frameRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.right, frameRect.bottom),
      Offset(frameRect.right, frameRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
