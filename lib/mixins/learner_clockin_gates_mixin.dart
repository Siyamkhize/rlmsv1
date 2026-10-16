import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../LearnerDetailsPage.dart';
import '../config.dart';
import '../services/learner_document_clockin_service.dart';
import '../utils/connectivity_utils.dart';
import '../utils/learner_profile_validation.dart';

/// Profile + mandatory document gates shared by clock-in, backup, and signature pages.
mixin LearnerClockInGatesMixin<T extends StatefulWidget> on State<T> {
  Future<bool> ensureLearnerProfileCompleteForClockIn(String learnerId) async {
    final learner = await fetchLearnerForClockInValidation(learnerId);
    if (learner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load learner profile. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    final missingFieldLabels = learnerProfileMissingFieldLabels(learner);
    final missingFieldKeys = learnerProfileMissingFieldKeys(learner);
    if (missingFieldLabels.isEmpty) {
      return true;
    }

    if (int.tryParse(learnerId) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid learner ID for profile completion.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    final shouldOpenProfile = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Complete Learner Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This learner profile is incomplete. Please fill in missing fields and press Update Data before clock-in.',
              ),
              if (missingFieldLabels.any((l) =>
                  l == 'Province' ||
                  l == 'District' ||
                  l == 'Municipality')) ...[
                const SizedBox(height: 8),
                const Text(
                  'Province, District and Municipality must all be selected together.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Missing fields:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...missingFieldLabels.map((field) => Text('- $field')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open Profile'),
            ),
          ],
        );
      },
    );

    if (shouldOpenProfile != true) {
      return false;
    }

    // CRITICAL FIX: Use pushReplacement to avoid navigation stack issues
    // This ensures we return to the CALLING page (signature_geofence_clock_in_page)
    // instead of going back through the navigation history
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LearnerDetailsPage(
          learnerID: learnerId,
          missingProfileOnlyMode: true,
          missingProfileFields: missingFieldKeys,
        ),
      ),
    );

    if (!mounted) return false;
    
    // If user explicitly cancelled from LearnerDetailsPage
    if (result == false) {
      return false;
    }

    final refreshedLearner = await fetchLearnerForClockInValidation(learnerId);
    final refreshedMissing = learnerProfileMissingFieldLabels(
      refreshedLearner ?? {},
    );

    if (refreshedMissing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile still incomplete: ${refreshedMissing.join(', ')}. Please update before clock-in.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    return true;
  }

  bool _isDocStatus(Map<String, dynamic> doc, String status) {
    return doc['status']?.toString().toLowerCase() == status.toLowerCase();
  }

  /// Order: (1) upload missing → (2) re-upload declined → (3) wait on pending only.
  Future<bool> ensureLearnerDocumentsCompleteForClockIn(String learnerId) async {
    final docService = LearnerDocumentClockInService(context);

    while (true) {
      if (!mounted) return false;

      final docStatuses = await getDetailedDocumentStatusesForClockIn(learnerId);

      if (docStatuses['allApproved'] == true) {
        return true;
      }

      final List<Map<String, dynamic>> problemDocs =
          List<Map<String, dynamic>>.from(docStatuses['documents'] ?? []);

      final missingDocs =
          problemDocs.where((d) => _isDocStatus(d, 'Not Uploaded')).toList();
      final declinedDocs =
          problemDocs.where((d) => _isDocStatus(d, 'Declined')).toList();
      final pendingDocs = problemDocs
          .where((d) => _isDocStatus(d, 'Pending'))
          .toList();

      Map<String, dynamic>? action;

      // Step 1 — always clear missing documents before anything else.
      if (missingDocs.isNotEmpty) {
        action = await _showMissingDocumentsDialogForClockIn(
          problemDocs: missingDocs,
          approvedCount: 3 - problemDocs.length,
        );
        if (action == null || action['action'] == 'cancel') {
          return false;
        }
        if (action['action'] == 'upload') {
          final docName = action['document']?.toString() ?? '';
          if (docName.isNotEmpty) {
            await docService.scanAndSaveDocument(learnerId, docName);
          }
          continue;
        }
        return false;
      }

      // Step 2 — replace declined documents (after missing are done).
      if (declinedDocs.isNotEmpty) {
        action = await _showDeclinedDocumentsDialogForClockIn(
          problemDocs: declinedDocs,
          pendingDocs: pendingDocs,
        );
        if (action == null || action['action'] == 'cancel') {
          return false;
        }
        if (action['action'] == 'reupload') {
          final docName = action['document']?.toString() ?? '';
          if (docName.isNotEmpty) {
            await docService.scanAndSaveDocument(
              learnerId,
              docName,
              replaceExisting: true,
            );
          }
          continue;
        }
        return false;
      }

      // Step 3 — only Pending (and/or already Approved on server); cannot clock in yet.
      if (pendingDocs.isNotEmpty) {
        action = await _showPendingOnlyDocumentsDialogForClockIn(
          pendingDocs: pendingDocs,
        );
        return false;
      }

      return false;
    }
  }

  Future<Map<String, dynamic>> getDetailedDocumentStatusesForClockIn(
    String learnerId,
  ) async {
    try {
      debugPrint('[CLOCKIN_GATES] ===== Starting document check for learner: $learnerId =====');
      
      if (!await hasNetworkConnectivity()) {
        debugPrint('[CLOCKIN_GATES] No network connectivity - allowing clock-in');
        return {'allApproved': true, 'documents': []};
      }

      // Get auth token
      final token = await AppConfig.getAuthToken();
      debugPrint('[CLOCKIN_GATES] Auth token present: ${token != null}');
      
      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      };
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
        debugPrint('[CLOCKIN_GATES] Auth header added (token hidden for security)');
      }

      final url = AppConfig.buildUrl('get_document_statuses.php');
      debugPrint('[CLOCKIN_GATES] Request URL: $url');
      debugPrint('[CLOCKIN_GATES] Request body: learner_id=$learnerId');

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: {'learner_id': learnerId},
          )
          .timeout(const Duration(seconds: 6));

      debugPrint('[CLOCKIN_GATES] Response status: ${response.statusCode}');
      debugPrint('[CLOCKIN_GATES] Response body length: ${response.body.length}');
      debugPrint('[CLOCKIN_GATES] Response body: ${response.body}');

      if (response.statusCode != 200) {
        debugPrint('[CLOCKIN_GATES] ❌ HTTP error - status ${response.statusCode}');
        return {'allApproved': false, 'documents': []};
      }

      final decoded = json.decode(response.body);
      debugPrint('[CLOCKIN_GATES] Decoded JSON type: ${decoded.runtimeType}');
      debugPrint('[CLOCKIN_GATES] Decoded success field: ${decoded['success']}');
      
      if (decoded['success'] != true) {
        debugPrint('[CLOCKIN_GATES] ❌ API returned success=false');
        if (decoded['message'] != null) {
          debugPrint('[CLOCKIN_GATES] Error message: ${decoded['message']}');
        }
        return {'allApproved': false, 'documents': []};
      }

      final docsMap = decoded['documents'] as Map<String, dynamic>?;
      if (docsMap == null) {
        debugPrint('[CLOCKIN_GATES] ❌ Documents map is null');
        return {'allApproved': false, 'documents': []};
      }

      debugPrint('[CLOCKIN_GATES] Documents map keys: ${docsMap.keys.toList()}');
      debugPrint('[CLOCKIN_GATES] Required documents: $learnerClockInRequiredDocuments');

      final List<Map<String, dynamic>> problemDocs = [];

      for (final requiredDoc in learnerClockInRequiredDocuments) {
        final normalizedName = requiredDoc.trim().toLowerCase();
        debugPrint('[CLOCKIN_GATES] Checking required doc: "$requiredDoc" (normalized: "$normalizedName")');

        Map<String, dynamic>? docInfo;
        for (final entry in docsMap.entries) {
          if (entry.key.trim().toLowerCase() == normalizedName) {
            docInfo = entry.value as Map<String, dynamic>?;
            debugPrint('[CLOCKIN_GATES]   ✓ Found match: ${entry.key} -> $docInfo');
            break;
          }
        }

        if (docInfo == null) {
          debugPrint('[CLOCKIN_GATES]   ❌ Not found - marking as "Not Uploaded"');
          problemDocs.add({
            'name': requiredDoc,
            'status': 'Not Uploaded',
            'reason': null,
          });
        } else {
          final status = docInfo['status']?.toString() ?? 'Pending';
          debugPrint('[CLOCKIN_GATES]   Status: $status');
          
          if (status.toLowerCase() != 'approved') {
            debugPrint('[CLOCKIN_GATES]   ⚠️ Not approved - adding to problem docs');
            problemDocs.add({
              'name': requiredDoc,
              'status': status,
              'reason': docInfo['rejection_reason'],
            });
          } else {
            debugPrint('[CLOCKIN_GATES]   ✓ Approved');
          }
        }
      }

      final allApproved = problemDocs.isEmpty;
      debugPrint('[CLOCKIN_GATES] Problem docs count: ${problemDocs.length}');
      debugPrint('[CLOCKIN_GATES] All approved: $allApproved');
      debugPrint('[CLOCKIN_GATES] ===== Document check complete =====');

      return {
        'allApproved': allApproved,
        'documents': problemDocs,
      };
    } catch (e, stackTrace) {
      debugPrint('[CLOCKIN_GATES] ❌ EXCEPTION in document check: $e');
      debugPrint('[CLOCKIN_GATES] Stack trace: $stackTrace');
      return {'allApproved': false, 'documents': []};
    }
  }

  Future<Map<String, dynamic>?> _showMissingDocumentsDialogForClockIn({
    required List<Map<String, dynamic>> problemDocs,
    int approvedCount = 0,
  }) {
    final missingDocs = problemDocs;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Missing Required Documents')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approvedCount > 0
                    ? '$approvedCount of 3 documents already approved. Upload missing document(s) first.'
                    : 'Upload missing document(s) first (built-in scanner).',
              ),
              const SizedBox(height: 12),
              ...missingDocs.map(
                (doc) => Text('- ${doc['name']} (missing)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop({'action': 'cancel'}),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (missingDocs.isEmpty) {
                  Navigator.of(dialogContext).pop({'action': 'cancel'});
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'action': 'upload',
                  'document': missingDocs.first['name'],
                });
              },
              icon: const Icon(Icons.document_scanner),
              label: const Text('Scan Next Document'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showDeclinedDocumentsDialogForClockIn({
    required List<Map<String, dynamic>> problemDocs,
    List<Map<String, dynamic>> pendingDocs = const [],
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final firstDeclined = problemDocs.first;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Declined — Re-upload Required')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missing documents are done. Re-scan declined document(s) to replace them on the server.',
                ),
                if (pendingDocs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${pendingDocs.length} document(s) still pending admin approval — clock-in stays blocked until all 3 are approved.',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ],
                const SizedBox(height: 12),
                ...problemDocs.map((doc) {
                  final docName = doc['name']?.toString() ?? '';
                  final reason = doc['reason'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(docName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (reason != null && reason.toString().isNotEmpty)
                          Text('Reason: $reason',
                              style: TextStyle(color: Colors.red.shade900)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop({'action': 'cancel'}),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop({
                'action': 'reupload',
                'document': firstDeclined['name'],
              }),
              icon: const Icon(Icons.document_scanner),
              label: Text('Re-upload ${firstDeclined['name']}'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showPendingOnlyDocumentsDialogForClockIn({
    required List<Map<String, dynamic>> pendingDocs,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.hourglass_top, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Awaiting Approval')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'All required documents are uploaded. Clock-in is blocked until an administrator approves every document.',
              ),
              const SizedBox(height: 12),
              ...pendingDocs.map(
                (doc) => Text('- ${doc['name']}: Pending'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop({'action': 'ok'}),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
