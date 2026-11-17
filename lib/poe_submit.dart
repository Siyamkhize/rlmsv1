import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:signature/signature.dart';
import 'package:geolocator/geolocator.dart';
import 'config.dart';
import 'services/fingerprint_service.dart';
import 'database_helper.dart';

class POESubmitPage extends StatefulWidget {
  final Map<String, dynamic> learner;
  final String classId;
  final String className;
  final String facilitatorName;
  final String logisticsId;
  final String logisticsName;

  const POESubmitPage({
    super.key,
    required this.learner,
    required this.classId,
    required this.className,
    required this.facilitatorName,
    required this.logisticsId,
    required this.logisticsName,
  });

  @override
  _POESubmitPageState createState() => _POESubmitPageState();
}

class _POESubmitPageState extends State<POESubmitPage> {
  // Add class-level fingerprint service instances like in DetailsPage.dart
  final FingerprintService _fingerprintService = FingerprintService();
  final FutronicService _futronicService = FutronicService();
  final facilitatorController = TextEditingController();
  final representativeController = TextEditingController();

  // Signature controllers - only representative signature needed
  final SignatureController _representativeSignatureController =
      SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool isLoading = false;
  bool fingerprintVerified = false;
  bool poeSubmitted = false;

  @override
  void initState() {
    super.initState();
    facilitatorController.text = widget.facilitatorName;

    // Add listener to signature controller to update UI when signature changes
    _representativeSignatureController.addListener(() {
      setState(() {
        // This will trigger UI rebuild when signature is drawn or cleared
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POE Collection'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Learner Information Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Learner Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildInfoRow(
                        'Name',
                        widget.learner['FullName'] ??
                            '${widget.learner['Name']} ${widget.learner['Surname']}'),
                    _buildInfoRow(
                        'ID Number', widget.learner['IDNumber'] ?? 'N/A'),
                    _buildInfoRow('Class', widget.className),
                    _buildInfoRow('Logistics Officer', widget.logisticsName),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // POE Collection Form Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.assignment, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'POE Collection Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: representativeController,
                      decoration: const InputDecoration(
                        labelText: 'Representative Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                        helperText:
                            'Person collecting the POE (required for verification)',
                      ),
                      onChanged: (value) {
                        // Reset fingerprint verification if representative name changes
                        if (fingerprintVerified) {
                          setState(() {
                            fingerprintVerified = false;
                          });
                        }
                        // Trigger UI update for signature pad
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: facilitatorController,
                      decoration: const InputDecoration(
                        labelText: 'Facilitator Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      enabled: false, // Read-only, pre-filled from class data
                    ),
                    const SizedBox(height: 20),

                    // Representative Signature Section
                    const Text(
                      'Representative Digital Signature',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please sign below to confirm POE collection:',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: representativeController.text.trim().isNotEmpty
                              ? Colors.grey
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: representativeController.text.trim().isNotEmpty
                            ? Colors.white
                            : Colors.grey.shade100,
                      ),
                      child: representativeController.text.trim().isNotEmpty
                          ? Signature(
                              controller: _representativeSignatureController,
                              backgroundColor: Colors.white,
                            )
                          : const Center(
                              child: Text(
                                'Enter representative name first',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (representativeController.text.trim().isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              _representativeSignatureController.clear();
                            },
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear Signature'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Biometric Verification Card - Moved to bottom
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.fingerprint,
                          color:
                              fingerprintVerified ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Biometric Verification',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (fingerprintVerified)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    const Divider(),
                    if (!fingerprintVerified) ...[
                      Text(
                        _representativeSignatureController.isEmpty
                            ? 'Please provide your signature above, then verify learner fingerprint.'
                            : 'Now verify the learner\'s fingerprint to complete POE collection.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (isLoading ||
                                  representativeController.text
                                      .trim()
                                      .isEmpty ||
                                  _representativeSignatureController.isEmpty)
                              ? null
                              : _verifyFingerprint,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Verify Learner Fingerprint'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (representativeController.text
                                        .trim()
                                        .isNotEmpty &&
                                    _representativeSignatureController
                                        .isNotEmpty)
                                ? Colors.blue
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (representativeController.text.trim().isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Enter representative name to enable signature',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        )
                      else if (_representativeSignatureController.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Provide signature to enable fingerprint verification',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                    ] else ...[
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fingerprint verified for ${widget.learner['FullName'] ?? '${widget.learner['Name']} ${widget.learner['Surname']}'}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status Display
            if (isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Submitting POE collection...',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (poeSubmitted)
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'POE collection completed successfully!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (fingerprintVerified &&
                _representativeSignatureController.isEmpty)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue.shade700),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Please provide your signature above to enable fingerprint verification',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyFingerprint() async {
    // Check if representative signature is provided
    if (_representativeSignatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide your signature first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if representative name is provided
    if (representativeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter representative name first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // GEOFENCING CHECK: Verify user is within 300 meters before allowing POE collection
      debugPrint('[POE_SUBMIT] Starting geofence check...');
      bool withinRadius = await _checkLocationAndRadius();

      if (!withinRadius) {
        debugPrint(
            '[POE_SUBMIT] ❌ Geofence check failed - user not within 300 meters');
        setState(() {
          isLoading = false;
        });
        return;
      }

      debugPrint(
          '[POE_SUBMIT] ✅ Geofence check passed - proceeding with fingerprint verification');

      // Use the EXACT same verification logic as clock_in_page.dart
      final verified = await _performDirectFingerprintVerification();
      if (verified) {
        setState(() {
          fingerprintVerified = true;
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Fingerprint verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Show confirmation dialog before submitting
        await _showSubmitConfirmationDialog();
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Fingerprint verification failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during verification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Direct fingerprint verification using EXACT same logic as clock_in_page.dart
  Future<bool> _performDirectFingerprintVerification() async {
    try {
      debugPrint('[POE_SUBMIT] Starting direct fingerprint verification...');

      // Get learner ID from learner data
      final learnerId =
          widget.learner['learnerID'] ?? widget.learner['LearnerID'] ?? 0;
      debugPrint('[POE_SUBMIT] Learner ID: $learnerId');

      if (learnerId == 0) {
        debugPrint('[POE_SUBMIT] ❌ Invalid learner ID');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid learner ID. Cannot verify fingerprint.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      final learnerIdInt = int.tryParse(learnerId.toString());
      if (learnerIdInt == null) {
        debugPrint('[POE_SUBMIT] ❌ Invalid learner ID format');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Invalid learner ID format. Cannot verify fingerprint.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      // Get learner templates from database - EXACT SAME AS CLOCK_IN_PAGE
      debugPrint('[POE_SUBMIT] Getting templates from database...');
      final templates = await DatabaseHelper().getAllTemplates(learnerIdInt);
      final scanner = await _detectScanner();
      debugPrint('[POE_SUBMIT] Scanner detected: $scanner');

      // Evaluate available templates per scanner - EXACT SAME AS CLOCK_IN_PAGE
      final hasZkLeft =
          (templates['zkteco_left_template']?.isNotEmpty ?? false);
      final hasZkRight =
          (templates['zkteco_right_template']?.isNotEmpty ?? false);
      final hasFutLeft =
          (templates['futronic_left_template']?.isNotEmpty ?? false);
      final hasFutRight =
          (templates['futronic_right_template']?.isNotEmpty ?? false);

      debugPrint(
          '[POE_SUBMIT] Template availability - ZK Left: $hasZkLeft, ZK Right: $hasZkRight, Fut Left: $hasFutLeft, Fut Right: $hasFutRight');

      // If current scanner has no templates but the other scanner does, guide user - EXACT SAME AS CLOCK_IN_PAGE
      if (scanner == 'futronic' &&
          !(hasFutLeft || hasFutRight) &&
          (hasZkLeft || hasZkRight)) {
        debugPrint('[POE_SUBMIT] ❌ Futronic scanner but only ZKTeco templates');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'This learner\'s fingerprint is enrolled on ZKTeco. Please use the ZKTeco scanner or re-enroll on Futronic for this learner.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }
      if (scanner == 'zkteco' &&
          !(hasZkLeft || hasZkRight) &&
          (hasFutLeft || hasFutRight)) {
        debugPrint('[POE_SUBMIT] ❌ ZKTeco scanner but only Futronic templates');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'This learner\'s fingerprint is enrolled on Futronic. Please use the Futronic scanner or re-enroll on ZKTeco for this learner.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Get template for verification - EXACT SAME AS CLOCK_IN_PAGE
      String? template;
      if (scanner == 'zkteco') {
        template = templates['zkteco_left_template'] ??
            templates['zkteco_right_template'];
      } else if (scanner == 'futronic') {
        template = templates['futronic_left_template'] ??
            templates['futronic_right_template'];
      }

      if (template == null || template.isEmpty) {
        debugPrint('[POE_SUBMIT] ❌ No templates available');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No fingerprints enrolled for this learner. Please enroll fingerprints first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Build guidance message based on available templates for active scanner - EXACT SAME AS CLOCK_IN_PAGE
      String guidance = 'Place finger on scanner for verification...';
      if (scanner == 'futronic') {
        if (hasFutLeft && hasFutRight) {
          guidance =
              'Place either thumb on Futronic scanner for verification...';
        } else if (hasFutLeft) {
          guidance = 'Place LEFT thumb on Futronic scanner for verification...';
        } else if (hasFutRight) {
          guidance =
              'Place RIGHT thumb on Futronic scanner for verification...';
        }
      } else if (scanner == 'zkteco') {
        if (hasZkLeft && hasZkRight) {
          guidance = 'Place either thumb on ZKTeco scanner for verification...';
        } else if (hasZkLeft) {
          guidance = 'Place LEFT thumb on ZKTeco scanner for verification...';
        } else if (hasZkRight) {
          guidance = 'Place RIGHT thumb on ZKTeco scanner for verification...';
        }
      }

      debugPrint('[POE_SUBMIT] Guidance: $guidance');
      _showProgressDialog(guidance);

      // Perform fingerprint verification - EXACT SAME AS CLOCK_IN_PAGE
      try {
        bool match = false;
        debugPrint('[POE_SUBMIT] Starting verification with scanner: $scanner');

        if (scanner == 'zkteco') {
          // EXACT SAME AS CLOCK_IN_PAGE
          debugPrint(
              '[POE_SUBMIT] ZKTeco verification - Template length: ${template.length}');
          match = await _fingerprintService.verify('left', template) ||
              await _fingerprintService.verify('right', template);
          debugPrint('[POE_SUBMIT] ZKTeco verification result: $match');
        } else if (scanner == 'futronic') {
          // EXACT SAME AS CLOCK_IN_PAGE
          try {
            debugPrint('[POE_SUBMIT] Attempting Futronic verification');
            final leftTemplate = templates['futronic_left_template'];
            final rightTemplate = templates['futronic_right_template'];
            final hint = (leftTemplate != null && leftTemplate.isNotEmpty)
                ? 'left'
                : 'right';

            debugPrint(
                '[POE_SUBMIT] Futronic verification - Left template length: ${leftTemplate?.length ?? 0}, Right template length: ${rightTemplate?.length ?? 0}, Hint: $hint');

            match = await _futronicService.verifyBoth(
              hintFinger: hint,
              leftTemplate: leftTemplate,
              rightTemplate: rightTemplate,
            );
            debugPrint('[POE_SUBMIT] Futronic verification result: $match');
          } catch (futronicError) {
            debugPrint(
                '[POE_SUBMIT] Futronic verification error: $futronicError');
            _hideProgressDialog();

            // Provide specific error messages for common Futronic issues - EXACT SAME AS CLOCK_IN_PAGE
            String errorMessage = 'Fingerprint verification failed';
            if (futronicError.toString().contains('USB_OPEN_FAILED') ||
                futronicError.toString().contains('DEVICE_OPEN_FAILED')) {
              errorMessage =
                  'Scanner connection failed. Please check USB connection and try again.';
            } else if (futronicError.toString().contains('CAPTURE_FAILED')) {
              errorMessage =
                  'Could not capture fingerprint. Please place finger firmly on scanner and try again.';
            } else if (futronicError.toString().contains('TIMEOUT') ||
                futronicError.toString().contains('Timeout')) {
              errorMessage =
                  'Timeout waiting for fingerprint. Please try again.';
            }

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
            return false;
          }
        } else {
          // No scanner detected - EXACT SAME AS CLOCK_IN_PAGE
          _hideProgressDialog();
          debugPrint('[POE_SUBMIT] ❌ No scanner detected');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No fingerprint scanner detected. Please connect a scanner.'),
              backgroundColor: Colors.orange,
            ),
          );
          return false;
        }

        _hideProgressDialog();
        debugPrint('[POE_SUBMIT] Final verification result: $match');

        return match;
      } catch (e) {
        debugPrint('[POE_SUBMIT] Verification error: $e');
        _hideProgressDialog();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } catch (e) {
      debugPrint('[POE_SUBMIT] Fingerprint verification error: $e');
      _hideProgressDialog();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  // Scanner detection methods - EXACT SAME AS CLOCK_IN_PAGE
  Future<String> _detectScanner() async {
    debugPrint('[POE_SUBMIT] Starting scanner detection...');

    // Try ZKTeco first
    try {
      debugPrint('[POE_SUBMIT] Trying ZKTeco scanner...');
      final isZkConnected = await _fingerprintService.isSensorConnected();
      debugPrint('[POE_SUBMIT] ZKTeco result: $isZkConnected');
      if (isZkConnected) {
        debugPrint('[POE_SUBMIT] ✅ ZKTeco scanner detected!');
        return 'zkteco';
      }
    } catch (e) {
      debugPrint('[POE_SUBMIT] ZKTeco detection failed: $e');
    }

    // Enhanced Futronic detection with retry
    debugPrint('[POE_SUBMIT] ZKTeco not found, trying Futronic...');
    return await _detectFutronicWithRetry();
  }

  Future<String> _detectFutronicWithRetry() async {
    const maxAttempts = 3;
    const delays = [500, 1000, 2000]; // Progressive delays

    debugPrint('[POE_SUBMIT] Starting Futronic detection with retry...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[POE_SUBMIT] Futronic attempt $attempt/$maxAttempts...');
        final isFutronicConnected =
            await _futronicService.isFutronicConnected();
        debugPrint(
            '[POE_SUBMIT] Futronic attempt $attempt result: $isFutronicConnected');

        if (isFutronicConnected) {
          debugPrint('[POE_SUBMIT] ✅ Futronic detected on attempt $attempt!');
          return 'futronic';
        }

        // Wait before next attempt (except on last)
        if (attempt < maxAttempts) {
          debugPrint('[POE_SUBMIT] Waiting before next attempt...');
          await Future.delayed(Duration(milliseconds: delays[attempt - 1]));
        }
      } catch (e) {
        debugPrint('[POE_SUBMIT] Futronic attempt $attempt failed: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }

    debugPrint(
        '[POE_SUBMIT] ❌ No Futronic scanner detected after all attempts');
    return 'none';
  }

  // Progress dialog methods from DetailsPage.dart
  void _showProgressDialog(String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void _hideProgressDialog() {
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
    }
  }

  bool _areSignaturesComplete() {
    return _representativeSignatureController.isNotEmpty;
  }

  bool _isReadyForSubmission() {
    return representativeController.text.trim().isNotEmpty &&
        _representativeSignatureController.isNotEmpty &&
        fingerprintVerified;
  }

  // Auto-submit when fingerprint is verified and signature is provided
  Future<void> _autoSubmitPOECollection() async {
    if (poeSubmitted) return; // Prevent double submission

    // Validate representative name is provided
    if (representativeController.text.trim().isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Representative name is required'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Ensure fingerprint is verified
    if (!fingerprintVerified) {
      return;
    }

    // Check if signature is provided
    if (_representativeSignatureController.isEmpty) {
      return;
    }

    setState(() {
      isLoading = true;
      poeSubmitted = true;
    });

    try {
      // Get current position for storing with POE collection
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      debugPrint(
          '[POE_SUBMIT] Location: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');

      // Convert signature to base64
      final representativeSignatureBytes =
          await _representativeSignatureController.toPngBytes();
      final representativeSignatureBase64 = representativeSignatureBytes != null
          ? base64Encode(representativeSignatureBytes)
          : '';

      final url = AppConfig.buildUrl('poe_collection_submit.php');

      // Step 1: Mark learner as received in material_receipt_form
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Step 1/2: Marking learner as received...')),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      final receiptResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'mark_received': '1',
          'classID': widget.classId,
          'received_learners[]':
              '${widget.learner['IDNumber']}|${widget.learner['FullName'] ?? '${widget.learner['Name']} ${widget.learner['Surname']}'}|${widget.learner['learnerID'] ?? widget.learner['LearnerID'] ?? ''}',
        },
      );

      // Step 2: Submit the POE form data with signatures to material_forms
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Step 2/2: Submitting POE form data...')),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      final formResponse = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'save_poe': '1',
          'classID': widget.classId,
          'facilitator_full_name': widget.facilitatorName,
          'representative_full_name': representativeController.text.trim(),
          'quantity': '1',
          'facilitator_signature': '', // Not needed for logistics workflow
          'representative_signature': representativeSignatureBase64,
          'fingerprint_verified': 'true',
          'learner_id':
              widget.learner['learnerID'] ?? widget.learner['LearnerID'] ?? '',
          'learner_name': widget.learner['FullName'] ??
              '${widget.learner['Name']} ${widget.learner['Surname']}',
          'user_latitude': position.latitude.toString(),
          'user_longitude': position.longitude.toString(),
          'user_accuracy': position.accuracy.toString(),
        },
      );

      // Check both responses
      if (receiptResponse.statusCode == 200 && formResponse.statusCode == 200) {
        // Parse responses to check for success
        final receiptData = json.decode(receiptResponse.body);
        final formData = json.decode(formResponse.body);

        if (receiptData['success'] == true && formData['success'] == true) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ POE collection completed successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          // Wait a moment for user to see success message, then navigate back
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            if (!context.mounted) return;
            Navigator.of(context).pop(true);
          }
        } else {
          throw Exception(
              'Server error: ${receiptData['error'] ?? formData['error'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception(
            'HTTP error: Receipt ${receiptResponse.statusCode}, Form ${formResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('Error submitting POE collection: $e');
      setState(() {
        poeSubmitted = false; // Allow retry
      });

      // Provide more specific error messages
      String errorMessage = 'Error submitting POE: ';
      if (e.toString().contains('SocketException') ||
          e.toString().contains('NetworkException')) {
        errorMessage +=
            'Network connection failed. Please check your internet connection and try again.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage += 'Request timed out. Please try again.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage += 'Invalid server response. Please contact support.';
      } else {
        errorMessage += e.toString();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              if (fingerprintVerified &&
                  _representativeSignatureController.isNotEmpty) {
                _autoSubmitPOECollection();
              }
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Show confirmation dialog after successful fingerprint verification
  Future<void> _showSubmitConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      if (!context.mounted) return;
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.assignment_turned_in, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Text('Confirm POE Submission'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to submit this POE collection?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            const Text('POE Collection Details:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                'Learner: ${widget.learner['FullName'] ?? '${widget.learner['Name']} ${widget.learner['Surname']}'}'),
            Text('ID Number: ${widget.learner['IDNumber'] ?? 'N/A'}'),
            Text('Class: ${widget.className}'),
            Text('Representative: ${representativeController.text.trim()}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Fingerprint Verified',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Signature Provided',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            if (!context.mounted) return;
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'No, Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            if (!context.mounted) return;
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Submit POE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // User confirmed - proceed with submission
      await _autoSubmitPOECollection();
    } else {
      // User cancelled - show cancellation message
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('POE submission cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Geofencing methods - same as clock_in_page.dart
  Future<bool> _checkLocationAndRadius() async {
    try {
      debugPrint('[POE_GEOFENCE] Checking location permissions...');

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Location services are disabled. Please enable GPS.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permissions are permanently denied. Please enable in settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Get current position
      debugPrint('[POE_GEOFENCE] Getting current position...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      debugPrint(
          '[POE_GEOFENCE] Current position: ${position.latitude}, ${position.longitude}');
      debugPrint('[POE_GEOFENCE] Accuracy: ${position.accuracy} meters');

      // Check if within site radius (300 meters)
      return await _isWithinSiteRadius(
        widget.classId,
        position.latitude,
        position.longitude,
        position.accuracy,
      );
    } catch (e) {
      debugPrint('[POE_GEOFENCE] Error checking location: $e');
      if (mounted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _isWithinSiteRadius(String classID, double userLat,
      double userLon, double userAccuracy) async {
    if (userAccuracy > 50) {
      // Accuracy threshold for 300 meter radius
      debugPrint(
          '[POE_GEOFENCE] Geolocation accuracy too low: $userAccuracy meters');
      if (mounted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('GPS accuracy too low. Please wait for better signal.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final classes = await db.query('class');
      final sites = await db.query('sites');
      debugPrint('[POE_GEOFENCE] Class table contents: $classes');
      debugPrint('[POE_GEOFENCE] Sites table contents: $sites');
      debugPrint(
          '[POE_GEOFENCE] Querying coordinates for classID: $classID (type: ${classID.runtimeType})');

      final result = await db.rawQuery(
        'SELECT s.latitude, s.longitude FROM class c JOIN sites s ON c.siteID = s.siteID WHERE c.classID = ?',
        [classID.toString()],
      );

      if (result.isEmpty) {
        if (classes.isEmpty) {
          debugPrint('[POE_GEOFENCE] Class table is empty');
          if (mounted) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No class data available in local database.')),
            );
          }
        } else if (sites.isEmpty) {
          debugPrint('[POE_GEOFENCE] Sites table is empty');
          if (mounted) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No site data available in local database.')),
            );
          }
        } else {
          debugPrint(
              '[POE_GEOFENCE] No matching class or site found for classID: $classID');
          if (mounted) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('No site coordinates found for class $classID.')),
            );
          }
        }
        return false;
      }

      final siteLat = double.tryParse(result.first['latitude'].toString());
      final siteLon = double.tryParse(result.first['longitude'].toString());

      if (siteLat == null || siteLon == null) {
        debugPrint(
            '[POE_GEOFENCE] Invalid site coordinates for classID: $classID, lat: ${result.first['latitude']}, lon: ${result.first['longitude']}');
        if (mounted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Invalid site coordinates in database.')),
          );
        }
        return false;
      }

      final distance = _calculateDistance(userLat, userLon, siteLat, siteLon);

      debugPrint(
          '[POE_GEOFENCE] Distance to site for classID $classID: ${distance.toStringAsFixed(2)} meters');
      debugPrint('[POE_GEOFENCE] Site coordinates: $siteLat, $siteLon');
      debugPrint('[POE_GEOFENCE] User coordinates: $userLat, $userLon');

      if (distance > 50) {
        // 50 meters radius
        if (mounted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'You are ${distance.toStringAsFixed(0)} meters away. Must be within 50 meters to collect POE.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return false;
      }

      debugPrint(
          '[POE_GEOFENCE] ✅ Within 50 meter radius - POE collection allowed');
      return true;
    } catch (e, stackTrace) {
      debugPrint(
          '[POE_GEOFENCE] Error checking site radius for classID $classID: $e\nStack trace: $stackTrace');
      if (mounted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking location: $e')),
        );
      }
      return false;
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371e3; // Earth radius in meters
    final double phi1 = lat1 * math.pi / 180;
    final double phi2 = lat2 * math.pi / 180;
    final double deltaPhi = (lat2 - lat1) * math.pi / 180;
    final double deltaLambda = (lon2 - lon1) * math.pi / 180;

    final double a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c; // Distance in meters
  }

  @override
  void dispose() {
    facilitatorController.dispose();
    representativeController.dispose();
    _representativeSignatureController.dispose();
    _fingerprintService.dispose();
    super.dispose();
  }
}
