import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../database_helper.dart';
import '../utils/connectivity_utils.dart';
import '../utils/document_scanner_manager.dart';
import '../utils/scanner_pdf_resolver.dart';

/// Document scan + local save + server upload (same flow as [ClockInPage]).
class LearnerDocumentClockInService {
  LearnerDocumentClockInService(this.context);

  final BuildContext context;

  static const int maxFileSize = 5 * 1024 * 1024;
  static const int minFileSize = 10 * 1024;

  String get _uploadUrl => AppConfig.buildUrl('upload_learner_document.php');

  static bool _docNamesMatch(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  Future<bool> documentExistsLocal({
    required String learnerId,
    required String documentName,
  }) async {
    final docs = await DatabaseHelper().fetchLearnerDocuments(learnerId);
    return docs.any(
      (d) => _docNamesMatch(d['documentName']?.toString() ?? '', documentName),
    );
  }

  Future<bool> scanAndSaveDocument(
    String learnerId,
    String documentName, {
    bool replaceExisting = false,
  }) async {
    if (replaceExisting) {
      await _removeLocalDocuments(learnerId, documentName);
    } else {
      final alreadyExists = await documentExistsLocal(
        learnerId: learnerId,
        documentName: documentName,
      );
      if (alreadyExists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$documentName already exists locally. Use re-upload for declined documents.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
    }

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission denied. Enable it in settings.'),
          ),
        );
        await openAppSettings();
      }
      return false;
    }

    try {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Opening document scanner...'),
              ],
            ),
          ),
        );
      }

      final scannerManager = DocumentScannerManager();
      if (scannerManager.isScanning) {
        throw Exception(
            'Scanner is already in use. Please wait and try again.');
      }

      final scanResult = await Future.any([
        scannerManager.scanDocuments(page: 80, maxRetries: 3),
        Future.delayed(const Duration(minutes: 5), () => null),
      ]);

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (scanResult == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Document scanning cancelled or timed out'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      if (scanResult is! Map ||
          !scanResult.containsKey('pdfUri') ||
          scanResult['pdfUri'] == null) {
        throw Exception('Invalid scan result - no PDF generated');
      }

      final file =
          await resolveFlutterDocScannerPdfFile(scanResult['pdfUri'] as String?);
      if (file == null || !await isReadablePdfFile(file)) {
        throw Exception('Invalid or missing PDF file');
      }

      final fileSize = await file.length();
      if (fileSize > maxFileSize) {
        throw Exception('File size exceeds 5MB limit');
      }
      if (fileSize < minFileSize) {
        throw Exception('Scanned file appears too small/unclear');
      }

      await DatabaseHelper().insertLearnerDocument({
        'learner_id': learnerId,
        'documentName': documentName,
        'learner_document': file.path,
        'status': 'Pending',
        'upload_date': DateTime.now().toIso8601String(),
        'synced': 0,
      });

      await syncUnsyncedDocumentsForLearner(learnerId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$documentName scanned and saved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        DocumentScannerManager().forceReset(); // Fire and forget
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to scan document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _removeLocalDocuments(
    String learnerId,
    String documentName,
  ) async {
    final db = await DatabaseHelper().database;
    final docs = await DatabaseHelper().fetchLearnerDocuments(learnerId);
    for (final doc in docs) {
      if (!_docNamesMatch(
          doc['documentName']?.toString() ?? '', documentName)) {
        continue;
      }
      final docId = doc['document_id'];
      await db.delete(
        'learner_document',
        where: 'document_id = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<void> syncUnsyncedDocumentsForLearner(String learnerId) async {
    // ===== DETAILED LOGGING FOR DEBUGGING =====
    debugPrint('[DOC_UPLOAD] ========================================');
    debugPrint('[DOC_UPLOAD] Starting sync for learner: $learnerId');
    debugPrint('[DOC_UPLOAD] Timestamp: ${DateTime.now()}');
    
    if (!await hasNetworkConnectivity()) {
      debugPrint('[DOC_UPLOAD] ❌ NO NETWORK CONNECTIVITY');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No internet - Document saved locally, will sync when online'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    debugPrint('[DOC_UPLOAD] ✓ Network connectivity OK');

    // Get auth token
    final token = await AppConfig.getAuthToken();
    debugPrint('[DOC_UPLOAD] Auth token present: ${token != null ? "YES" : "NO"}');
    if (token == null) {
      debugPrint('[DOC_UPLOAD] ❌ No auth token available');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Auth token missing - Document saved locally only'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final dbHelper = DatabaseHelper();
    final learnerDocs = await dbHelper.fetchLearnerDocuments(learnerId);
    debugPrint('[DOC_UPLOAD] Total documents in DB: ${learnerDocs.length}');
    
    final unsynced = learnerDocs.where((doc) {
      final syncedVal = doc['synced'];
      final syncedInt = syncedVal is int
          ? syncedVal
          : int.tryParse(syncedVal?.toString() ?? '0') ?? 0;
      return syncedInt == 0;
    }).toList();
    
    debugPrint('[DOC_UPLOAD] Unsynced documents: ${unsynced.length}');
    for (var doc in unsynced) {
      debugPrint('[DOC_UPLOAD]   - ${doc['documentName']} (ID: ${doc['document_id']})');
    }

    int successCount = 0;
    int failCount = 0;
    String? lastError;

    for (final doc in unsynced) {
      final filePath = doc['learner_document']?.toString() ?? '';
      final documentName = doc['documentName']?.toString() ?? '';
      
      debugPrint('[DOC_UPLOAD] ----------------------------------------');
      debugPrint('[DOC_UPLOAD] Processing: $documentName');
      debugPrint('[DOC_UPLOAD] File path: $filePath');
      
      if (filePath.isEmpty) {
        debugPrint('[DOC_UPLOAD] ❌ File path is empty');
        lastError = 'File path empty for $documentName';
        failCount++;
        continue;
      }
      
      if (!File(filePath).existsSync()) {
        debugPrint('[DOC_UPLOAD] ❌ File does not exist on disk');
        lastError = 'File not found: $documentName';
        failCount++;
        continue;
      }
      
      final fileSize = await File(filePath).length();
      debugPrint('[DOC_UPLOAD] File exists, size: $fileSize bytes');

      try {
        debugPrint('[DOC_UPLOAD] Building multipart request...');
        debugPrint('[DOC_UPLOAD] Upload URL: $_uploadUrl');
        
        final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
          ..headers['Authorization'] = 'Bearer $token'  // Add auth token
          ..fields['learner_id'] = learnerId
          ..fields['documentName'] = documentName
          ..fields['status'] = doc['status']?.toString() ?? 'Pending'
          ..fields['upload_date'] =
              doc['upload_date']?.toString() ?? DateTime.now().toIso8601String()
          ..fields['synced'] = '1'
          ..fields['rejection_reason'] =
              doc['rejection_reason']?.toString() ?? '';
        
        debugPrint('[DOC_UPLOAD] Request fields: ${request.fields}');
        debugPrint('[DOC_UPLOAD] Adding file to request...');
        
        request.files.add(await http.MultipartFile.fromPath(
          'learner_document',
          filePath,
          filename: filePath.split(Platform.pathSeparator).last,
        ));
        
        debugPrint('[DOC_UPLOAD] File added: ${request.files.first.filename}, ${request.files.first.length} bytes');
        debugPrint('[DOC_UPLOAD] Sending request...');

        final response = await request.send();
        final body = await response.stream.bytesToString();
        
        debugPrint('[DOC_UPLOAD] ========== SERVER RESPONSE ==========');
        debugPrint('[DOC_UPLOAD] Status code: ${response.statusCode}');
        debugPrint('[DOC_UPLOAD] Response headers: ${response.headers}');
        debugPrint('[DOC_UPLOAD] Response body: $body');
        debugPrint('[DOC_UPLOAD] ===================================');
        
        if (response.statusCode != 200) {
          debugPrint('[DOC_UPLOAD] ❌ HTTP ERROR ${response.statusCode}');
          lastError = 'Server error ${response.statusCode} for $documentName';
          failCount++;
          continue;
        }

        final decoded = jsonDecode(body);
        debugPrint('[DOC_UPLOAD] Decoded response: $decoded');
        
        if (decoded is Map && decoded['success'] == true) {
          final docId = doc['document_id'];
          final parsedId = docId is int ? docId : int.tryParse('$docId');
          if (parsedId != null) {
            await dbHelper.updateLearnerDocumentSynced(parsedId, 1);
            debugPrint('[DOC_UPLOAD] ✅ SUCCESS: $documentName uploaded and marked as synced');
            successCount++;
          }
        } else {
          final error = decoded['error'] ?? decoded['message'] ?? 'Unknown error';
          debugPrint('[DOC_UPLOAD] ❌ UPLOAD FAILED: $error');
          lastError = error.toString();
          failCount++;
        }
      } catch (e, stackTrace) {
        debugPrint('[DOC_UPLOAD] ❌ EXCEPTION: $e');
        debugPrint('[DOC_UPLOAD] Stack trace: $stackTrace');
        lastError = e.toString();
        failCount++;
      }
    }

    // ===== SHOW RESULT TO USER =====
    debugPrint('[DOC_UPLOAD] ========================================');
    debugPrint('[DOC_UPLOAD] SYNC COMPLETE');
    debugPrint('[DOC_UPLOAD] Success: $successCount, Failed: $failCount');
    debugPrint('[DOC_UPLOAD] ========================================');

    if (context.mounted) {
      if (successCount > 0 && failCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $successCount document(s) uploaded to server'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Upload failed: $lastError\n'
              'Success: $successCount, Failed: $failCount',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }
}
