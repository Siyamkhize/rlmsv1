import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';

/// Face Embedding Service
///
/// Handles face detection, quality validation, liveness checks, and embedding extraction
/// using ML Kit for detection and MobileFaceNet for embeddings.
class FaceEmbeddingService {
  static const int _embeddingLength = 192; // MobileFaceNet output size
  static const String _modelPath = 'assets/models/mobile_face_net.tflite';

  // Quality thresholds
  static const double minQualityScore = 0.5;
  static const double minEyeOpenProbability = 0.8;
  static const double maxHeadEulerAngleY =
      15.0; // degrees (yaw - looking left/right)
  static const double maxHeadEulerAngleZ = 10.0; // degrees (roll - head tilt)

  Interpreter? _interpreter;
  final FaceDetector _faceDetector;

  FaceEmbeddingService()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableClassification: true, // Enables eye open/smile probabilities
            enableTracking: false,
            minFaceSize: 0.15, // Minimum face size relative to image (15%)
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  /// Initialize the TFLite interpreter with MobileFaceNet model
  Future<void> initialize() async {
    if (_interpreter != null) return;

    try {
      debugPrint('🔷 FaceEmbeddingService: Loading MobileFaceNet model...');

      // Load the model
      _interpreter = await Interpreter.fromAsset(_modelPath);

      // Verify input/output shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint('🔷 Model loaded successfully');
      debugPrint('🔷 Input shape: $inputShape'); // Should be [1, 112, 112, 3]
      debugPrint('🔷 Output shape: $outputShape'); // Should be [1, 192]

      if (outputShape[1] != _embeddingLength) {
        throw Exception(
            'Model output mismatch: expected $_embeddingLength dims, got ${outputShape[1]}');
      }
    } catch (e) {
      debugPrint('❌ Failed to load MobileFaceNet model: $e');
      rethrow;
    }
  }

  /// Extract embedding from an image file path
  /// Returns the embedding vector (List<double>) or null if failed
  Future<List<double>?> extractEmbedding(String imagePath) async {
    if (_interpreter == null) {
      await initialize();
    }

    try {
      // Load image from file
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        debugPrint('❌ Image file not found: $imagePath');
        return null;
      }

      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        debugPrint('❌ Failed to decode image');
        return null;
      }

      // Create InputImage for face detection
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('⚠️ No face detected in image');
        return null;
      }

      if (faces.length > 1) {
        debugPrint('⚠️ Multiple faces detected (${faces.length})');
        return null;
      }

      final face = faces.first;

      // Check face quality
      final qualityResult = _checkFaceQuality(face);
      if (!qualityResult['passed']) {
        debugPrint('⚠️ Face quality check failed: ${qualityResult['reason']}');
        return null;
      }

      // Crop face region with some padding
      final faceCrop = _cropFace(image, face.boundingBox);
      if (faceCrop == null) {
        debugPrint('❌ Failed to crop face');
        return null;
      }

      // Resize to 112x112 for MobileFaceNet
      final resized = img.copyResize(faceCrop, width: 112, height: 112);

      // Normalize and prepare input tensor
      final input = _prepareInputTensor(resized);

      // Run inference
      final output =
          List.filled(_embeddingLength, 0.0).reshape([1, _embeddingLength]);
      _interpreter!.run(input, output);

      // Extract embedding vector
      final embedding = List<double>.from(output[0]);

      debugPrint('✅ Face embedding extracted from file');
      debugPrint(
          '🔷 Quality score: ${qualityResult['score']?.toStringAsFixed(2)}');

      return embedding;
    } catch (e, stackTrace) {
      debugPrint('❌ Error extracting embedding from file: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Detect faces and extract embedding from a camera image
  /// Returns a map with 'embedding', 'quality_score', and 'liveness_passed'
  Future<Map<String, dynamic>?> extractFaceEmbedding(
    CameraImage cameraImage,
  ) async {
    if (_interpreter == null) {
      await initialize();
    }

    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _cameraImageToInputImage(cameraImage);
      if (inputImage == null) {
        debugPrint('❌ Failed to convert CameraImage to InputImage');
        return null;
      }

      // Detect faces
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('⚠️ No face detected');
        return null;
      }

      if (faces.length > 1) {
        debugPrint('⚠️ Multiple faces detected (${faces.length})');
        return null;
      }

      final face = faces.first;

      // Check face quality
      final qualityResult = _checkFaceQuality(face);
      if (!qualityResult['passed']) {
        debugPrint('⚠️ Face quality check failed: ${qualityResult['reason']}');
        return null;
      }

      // Check liveness (basic check using eye open probability and head pose)
      final livenessResult = _checkLiveness(face);

      // Convert CameraImage to img.Image for cropping
      final image = _convertCameraImageToImage(cameraImage);
      if (image == null) {
        debugPrint('❌ Failed to convert CameraImage to Image');
        return null;
      }

      // Crop face region with some padding
      final faceCrop = _cropFace(image, face.boundingBox);
      if (faceCrop == null) {
        debugPrint('❌ Failed to crop face');
        return null;
      }

      // Resize to 112x112 for MobileFaceNet
      final resized = img.copyResize(faceCrop, width: 112, height: 112);

      // Normalize and prepare input tensor
      final input = _prepareInputTensor(resized);

      // Run inference
      final output =
          List.filled(_embeddingLength, 0.0).reshape([1, _embeddingLength]);
      _interpreter!.run(input, output);

      // Extract embedding vector
      final embedding = List<double>.from(output[0]);

      debugPrint('✅ Face embedding extracted successfully');
      debugPrint(
          '🔷 Quality score: ${qualityResult['score']?.toStringAsFixed(2)}');
      debugPrint('🔷 Liveness passed: ${livenessResult['passed']}');

      return {
        'embedding': embedding,
        'quality_score': qualityResult['score'],
        'liveness_passed': livenessResult['passed'],
        'liveness_details': livenessResult,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ Error extracting face embedding: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Check face quality based on pose, size, and classification probabilities
  Map<String, dynamic> _checkFaceQuality(Face face) {
    double qualityScore = 1.0;
    String? reason;

    // Check head pose (should be facing forward)
    final headEulerAngleY = face.headEulerAngleY ?? 0.0; // Yaw (left/right)
    final headEulerAngleZ = face.headEulerAngleZ ?? 0.0; // Roll (tilt)

    if (headEulerAngleY.abs() > maxHeadEulerAngleY) {
      qualityScore -= 0.3;
      reason = 'Head turned too far (${headEulerAngleY.toStringAsFixed(1)}°)';
    }

    if (headEulerAngleZ.abs() > maxHeadEulerAngleZ) {
      qualityScore -= 0.2;
      reason ??=
          'Head tilted too much (${headEulerAngleZ.toStringAsFixed(1)}°)';
    }

    // Check if eyes are open (classification available)
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;

    if (leftEyeOpen != null && leftEyeOpen < minEyeOpenProbability) {
      qualityScore -= 0.3;
      reason ??=
          'Left eye not open (${(leftEyeOpen * 100).toStringAsFixed(0)}%)';
    }

    if (rightEyeOpen != null && rightEyeOpen < minEyeOpenProbability) {
      qualityScore -= 0.3;
      reason ??=
          'Right eye not open (${(rightEyeOpen * 100).toStringAsFixed(0)}%)';
    }

    final passed = qualityScore >= minQualityScore;

    return {
      'passed': passed,
      'score': qualityScore,
      'reason': reason,
      'head_yaw': headEulerAngleY,
      'head_roll': headEulerAngleZ,
      'left_eye_open': leftEyeOpen,
      'right_eye_open': rightEyeOpen,
    };
  }

  /// Basic liveness check using eye open probability and head movement
  /// For production, consider more advanced liveness checks (blink detection, challenge-response)
  Map<String, dynamic> _checkLiveness(Face face) {
    // Simple liveness: check if eyes are detected as open
    // More advanced: require a blink or head turn during capture
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

    final eyesOpen = (leftEyeOpen > 0.5 && rightEyeOpen > 0.5);

    return {
      'passed': eyesOpen,
      'left_eye_open': leftEyeOpen,
      'right_eye_open': rightEyeOpen,
      'method': 'eye_open_check',
    };
  }

  /// Check liveness across multiple frames (blink or head turn detection)
  /// Call this with 2-3 consecutive frames to detect movement
  Future<bool> checkLivenessAcrossFrames(List<CameraImage> frames) async {
    if (frames.length < 2) return false;

    final faceDataList = <Map<String, dynamic>>[];

    for (final frame in frames) {
      final inputImage = _cameraImageToInputImage(frame);
      if (inputImage == null) continue;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty || faces.length > 1) continue;

      final face = faces.first;
      faceDataList.add({
        'left_eye_open': face.leftEyeOpenProbability ?? 1.0,
        'right_eye_open': face.rightEyeOpenProbability ?? 1.0,
        'head_yaw': face.headEulerAngleY ?? 0.0,
      });
    }

    if (faceDataList.length < 2) return false;

    // Check for blink (eye open → closed → open)
    bool blinkDetected = false;
    for (int i = 0; i < faceDataList.length - 1; i++) {
      final current = faceDataList[i];
      final next = faceDataList[i + 1];

      // Detect if either eye closed in one frame then opened in next
      final leftBlink =
          (current['left_eye_open'] > 0.8 && next['left_eye_open'] < 0.3) ||
              (current['left_eye_open'] < 0.3 && next['left_eye_open'] > 0.8);
      final rightBlink =
          (current['right_eye_open'] > 0.8 && next['right_eye_open'] < 0.3) ||
              (current['right_eye_open'] < 0.3 && next['right_eye_open'] > 0.8);

      if (leftBlink || rightBlink) {
        blinkDetected = true;
        break;
      }
    }

    // Check for head movement
    bool headMovement = false;
    final firstYaw = faceDataList.first['head_yaw'] as double;
    final lastYaw = faceDataList.last['head_yaw'] as double;
    if ((firstYaw - lastYaw).abs() > 5.0) {
      headMovement = true;
    }

    return blinkDetected || headMovement;
  }

  /// Crop face from image with padding
  img.Image? _cropFace(img.Image image, Rect boundingBox) {
    try {
      // Add 20% padding around face
      const padding = 0.2;
      final width = boundingBox.width;
      final height = boundingBox.height;

      final x = (boundingBox.left - width * padding)
          .clamp(0, image.width.toDouble())
          .toInt();
      final y = (boundingBox.top - height * padding)
          .clamp(0, image.height.toDouble())
          .toInt();
      final w = (width * (1 + 2 * padding))
          .clamp(0, image.width - x.toDouble())
          .toInt();
      final h = (height * (1 + 2 * padding))
          .clamp(0, image.height - y.toDouble())
          .toInt();

      return img.copyCrop(image, x: x, y: y, width: w, height: h);
    } catch (e) {
      debugPrint('❌ Error cropping face: $e');
      return null;
    }
  }

  /// Prepare input tensor for MobileFaceNet (normalize to [-1, 1])
  List<List<List<List<double>>>> _prepareInputTensor(img.Image image) {
    final input = List.generate(
      1,
      (b) => List.generate(
        112,
        (y) => List.generate(
          112,
          (x) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = image.getPixel(x, y);
        // Normalize to [-1, 1]
        input[0][y][x][0] = (pixel.r / 127.5) - 1.0;
        input[0][y][x][1] = (pixel.g / 127.5) - 1.0;
        input[0][y][x][2] = (pixel.b / 127.5) - 1.0;
      }
    }

    return input;
  }

  /// Convert CameraImage to img.Image
  /// IMPLEMENTATION REQUIRED: This depends on your camera plugin version and platform
  img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    // TODO: Implement based on your camera plugin and platform
    // This is a stub that needs to be completed for your specific setup

    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error converting CameraImage: $e');
      return null;
    }
  }

  /// Convert YUV420 to img.Image (Android)
  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final img.Image image = img.Image(width: width, height: height);

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2);

        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        // YUV to RGB conversion
        final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
        final g =
            (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                .clamp(0, 255)
                .toInt();
        final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return image;
  }

  /// Convert BGRA8888 to img.Image (iOS)
  img.Image? _convertBGRA8888ToImage(CameraImage cameraImage) {
    final img.Image image = img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
    return image;
  }

  /// Convert CameraImage to ML Kit InputImage
  /// IMPLEMENTATION REQUIRED: This depends on your camera plugin version
  InputImage? _cameraImageToInputImage(CameraImage cameraImage) {
    // TODO: Implement based on your camera plugin version
    // This is a stub that needs platform-specific implementation

    try {
      // Get image format
      final format = cameraImage.format.group == ImageFormatGroup.yuv420
          ? InputImageFormat.yuv420
          : InputImageFormat.bgra8888;

      // Create InputImage metadata
      final metadata = InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: InputImageRotation
            .rotation0deg, // Adjust based on device orientation
        format: format,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      // Create InputImage from bytes
      return InputImage.fromBytes(
        bytes: cameraImage.planes[0].bytes,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('❌ Error converting to InputImage: $e');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
  }
}
