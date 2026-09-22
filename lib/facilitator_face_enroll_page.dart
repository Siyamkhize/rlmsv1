import 'dart:io';
import 'package:flutter/material.dart';
import 'widgets/simple_face_capture.dart';
import 'repositories/facilitator_face_repository.dart';
import 'services/face_embedding_service.dart';
import 'services/offline_face_verification_service.dart';

/// Facilitator Face Enrollment Page
///
/// Allows facilitators to enroll their face as an alternative authentication method
/// when fingerprint scanners are not available. One-time setup process.
class FacilitatorFaceEnrollPage extends StatefulWidget {
  final int facilitatorId;
  final String facilitatorName;
  final bool isFirstTimeSetup;

  const FacilitatorFaceEnrollPage({
    Key? key,
    required this.facilitatorId,
    required this.facilitatorName,
    this.isFirstTimeSetup = false,
  }) : super(key: key);

  @override
  State<FacilitatorFaceEnrollPage> createState() =>
      _FacilitatorFaceEnrollPageState();
}

class _FacilitatorFaceEnrollPageState extends State<FacilitatorFaceEnrollPage> {
  final _faceRepo = FacilitatorFaceRepository();
  final _faceService = FaceEmbeddingService();
  final _offlineFaceService = OfflineFaceVerificationService();
  bool _isEnrolling = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Enrollment'),
        automaticallyImplyLeading: !widget.isFirstTimeSetup,
      ),
      body: WillPopScope(
        onWillPop: () async {
          if (widget.isFirstTimeSetup) {
            // Don't allow back navigation during first-time setup
            _showExitConfirmation();
            return false;
          }
          return true;
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome section
              const Icon(
                Icons.face_outlined,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              Text(
                widget.isFirstTimeSetup
                    ? 'Welcome, ${widget.facilitatorName}!'
                    : 'Face Enrollment',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                widget.isFirstTimeSetup
                    ? 'Set up face recognition as an alternative login method. This is useful when a fingerprint scanner is not available.'
                    : 'Enroll your face for quick and secure authentication.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Benefits
              _buildBenefitTile(
                icon: Icons.speed,
                title: 'Fast & Convenient',
                subtitle:
                    'Log in quickly without needing a fingerprint scanner',
              ),
              const SizedBox(height: 16),
              _buildBenefitTile(
                icon: Icons.security,
                title: 'Secure',
                subtitle:
                    'Your face data is encrypted and never leaves our system',
              ),
              const SizedBox(height: 16),
              _buildBenefitTile(
                icon: Icons.offline_bolt,
                title: 'Works Offline',
                subtitle:
                    'Authentication works even without internet connection',
              ),

              const Spacer(),

              // Privacy notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined,
                        color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your privacy matters. Face data is stored securely and used only for authentication.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Enroll button
              ElevatedButton(
                onPressed: _isEnrolling ? null : _startEnrollment,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isEnrolling
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Enrolling...'),
                        ],
                      )
                    : const Text(
                        'Start Face Enrollment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              if (!widget.isFirstTimeSetup) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue.shade700, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _startEnrollment() async {
    debugPrint(
        '[FAC_FACE_ENROLL] Starting enrollment for facilitator ${widget.facilitatorId}');

    // Navigate to face capture screen
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleFaceCapture(
          mode: FaceCaptureMode.register,
          title: 'Register Your Face',
          instruction: 'Position your face in the oval and stay still',
          onCapture: (File imageFile, String base64Image) async {
            // This callback is called when face is captured
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
      debugPrint('[FAC_FACE_ENROLL] Face capture cancelled');
      return;
    }

    // Process the captured face
    await _processCapturedFace(
      result['imageFile'] as File,
      result['base64Image'] as String,
    );
  }

  Future<void> _processCapturedFace(File imageFile, String base64Image) async {
    setState(() => _isEnrolling = true);

    try {
      debugPrint('[FAC_FACE_ENROLL] Extracting face embedding...');

      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing your face...'),
              ],
            ),
          ),
        );
      }

      // Extract embedding from the captured image
      final embedding = await _faceService.extractEmbedding(imageFile.path);

      if (embedding == null) {
        throw Exception(
            'Failed to extract face features. Please try again with better lighting.');
      }

      debugPrint('[FAC_FACE_ENROLL] Embedding extracted successfully');

      // Enroll face on server
      final enrollResult = await _faceRepo.enrollFace(
        facilitatorId: widget.facilitatorId,
        embedding: embedding,
        qualityScore:
            0.8, // Default quality score (FaceEmbeddingService validates internally)
        consentGiven: true,
      );

      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (enrollResult['success'] == true) {
        debugPrint('[FAC_FACE_ENROLL] Enrollment successful!');

        // Show success message
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
              content: const Text(
                'Your face has been enrolled successfully. You can now use face recognition to log in.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }

        // Return success to caller
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(enrollResult['message'] ?? 'Enrollment failed');
      }
    } catch (e) {
      debugPrint('[FAC_FACE_ENROLL] Enrollment error: $e');

      // Close progress dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Text('Enrollment Failed'),
              ],
            ),
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEnrolling = false);
      }
    }
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Face Enrollment?'),
        content: const Text(
          'Face enrollment is recommended but not required. You can enroll later from your profile settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Enrollment'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, false); // Exit enrollment page
            },
            child: const Text('Skip for Now'),
          ),
        ],
      ),
    );
  }
}
