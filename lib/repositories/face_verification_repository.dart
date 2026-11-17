import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Face Verification Repository
///
/// HTTP wrapper for face recognition endpoints (enrollment and verification).
/// Only the embedding vector is transmitted, never the raw photo.
class FaceVerificationRepository {
  Map<String, dynamic> _parseJsonBody(String body, String operation) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return {
        'success': false,
        'message': 'Empty server response ($operation)'
      };
    }

    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {
        'success': false,
        'message': 'Invalid response format ($operation)',
      };
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final decoded = json.decode(trimmed.substring(start, end + 1));
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }

      final preview =
          trimmed.length > 120 ? '${trimmed.substring(0, 120)}...' : trimmed;
      return {
        'success': false,
        'message': 'Server returned non-JSON ($operation): $preview',
      };
    }
  }

  /// Check if a learner has an active face enrollment
  ///
  /// Parameters:
  /// - learnerId: Learner's ID
  ///
  /// Returns:
  /// - success: Whether API call succeeded
  /// - enrolled: Whether learner has active face enrollment
  /// - face_id: Database ID of the enrollment (if enrolled)
  /// - quality_score: Quality score from enrollment (if enrolled)
  /// - enrolled_at: Enrollment timestamp (if enrolled)
  Future<Map<String, dynamic>> checkFaceEnrolled(int learnerId) async {
    try {
      debugPrint(
          '🔷 FaceVerificationRepository: Checking enrollment for learner $learnerId');

      final url = AppConfig.buildUrl('check_face_enrollment.php');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'learner_id': learnerId}),
      );

      debugPrint('🔷 Check enrollment response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = _parseJsonBody(response.body, 'check enrollment');
        debugPrint('🔷 Enrollment status: ${data['enrolled']}');
        return data;
      } else {
        return {
          'success': false,
          'enrolled': false,
          'message': 'Server error: HTTP ${response.statusCode}',
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error checking face enrollment: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'enrolled': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Enroll a learner's face embedding
  ///
  /// Parameters:
  /// - learnerId: Learner's ID from learnerdetails table
  /// - embedding: 192-float embedding vector from MobileFaceNet
  /// - qualityScore: Quality score from face detection (0.0 to 1.0)
  /// - consentGiven: Whether learner gave explicit consent
  ///
  /// Returns:
  /// - success: Whether enrollment succeeded
  /// - enrollmentId: Database ID of the enrollment record
  /// - action: 'created' or 'updated' (for re-enrollment)
  /// - message: Success or error message
  Future<Map<String, dynamic>> enrollFace({
    required int learnerId,
    required List<double> embedding,
    required double qualityScore,
    required bool consentGiven,
  }) async {
    try {
      debugPrint(
          '🔷 FaceVerificationRepository: Enrolling face for learner $learnerId');

      final url = AppConfig.buildUrl('enrol_learner_face.php');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'learner_id': learnerId,
          'embedding': embedding,
          'quality_score': qualityScore,
          'consent_given': consentGiven,
        }),
      );

      debugPrint('🔷 Enrollment response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 400) {
        final data = _parseJsonBody(response.body, 'enrollment');
        debugPrint('🔷 Enrollment response: $data');
        return data;
      } else {
        return {
          'success': false,
          'message': 'Server error: HTTP ${response.statusCode}',
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error enrolling face: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Verify a learner's face against their enrolled embedding
  ///
  /// Parameters:
  /// - learnerId: Learner's ID
  /// - embedding: Live embedding from current camera capture
  /// - qualityScore: Quality of the live capture
  /// - livenessPassed: Whether liveness check passed
  /// - verificationType: 'clock_in' or 'clock_out'
  /// - deviceInfo: Device model, OS, app version for logging
  ///
  /// Returns:
  /// - success: Whether API call succeeded
  /// - verified: Whether face matched (score >= threshold)
  /// - similarityScore: Cosine similarity score (0.0 to 1.0)
  /// - threshold: Threshold used for matching
  /// - logId: Reference to learner_face_verification_log entry
  /// - message: Success or error message
  Future<Map<String, dynamic>> verifyFace({
    required int learnerId,
    required List<double> embedding,
    required double qualityScore,
    required bool livenessPassed,
    String verificationType = 'clock_in',
    String? deviceInfo,
  }) async {
    try {
      debugPrint(
          '🔷 FaceVerificationRepository: Verifying face for learner $learnerId');

      final url = AppConfig.buildUrl('verify_learner_face.php');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'learner_id': learnerId,
          'embedding': embedding,
          'quality_score': qualityScore,
          'liveness_passed': livenessPassed,
          'verification_type': verificationType,
          'device_info': deviceInfo,
        }),
      );

      debugPrint('🔷 Verification response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 400) {
        final data = _parseJsonBody(response.body, 'verification');
        debugPrint('🔷 Verification response: $data');
        return data;
      } else {
        return {
          'success': false,
          'verified': false,
          'message': 'Server error: HTTP ${response.statusCode}',
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error verifying face: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'verified': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Get device info string for logging
  static Future<String> getDeviceInfo() async {
    try {
      // Import device_info_plus if available
      // For now, return a placeholder
      return 'Flutter App v1.0.7'; // TODO: Get actual device info from device_info_plus
    } catch (e) {
      return 'Unknown device';
    }
  }

  /// Delete a learner's face enrollment (for re-enrollment)
  ///
  /// Parameters:
  /// - learnerId: Learner's ID
  ///
  /// Returns:
  /// - success: Whether deletion succeeded
  /// - message: Success or error message
  Future<Map<String, dynamic>> deleteFaceEnrollment(int learnerId) async {
    try {
      debugPrint(
          '🔷 FaceVerificationRepository: Deleting face enrollment for learner $learnerId');

      final url = AppConfig.buildUrl('delete_face_enrollment.php');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'learner_id': learnerId}),
      );

      debugPrint(
          '🔷 Delete enrollment response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = _parseJsonBody(response.body, 'delete enrollment');
        debugPrint('🔷 Delete enrollment response: $data');
        return data;
      } else {
        return {
          'success': false,
          'message': 'Server error: HTTP ${response.statusCode}',
        };
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error deleting face enrollment: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }
}
