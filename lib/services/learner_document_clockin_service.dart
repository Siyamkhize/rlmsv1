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
        DocumentScannerManager().forceReset();
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
    if (!await hasNetworkConnectivity()) return;

    final dbHelper = DatabaseHelper();
    final learnerDocs = await dbHelper.fetchLearnerDocuments(learnerId);
    final unsynced = learnerDocs.where((doc) {
      final syncedVal = doc['synced'];
      final syncedInt = syncedVal is int
          ? syncedVal
          : int.tryParse(syncedVal?.toString() ?? '0') ?? 0;
      return syncedInt == 0;
    }).toList();

    for (final doc in unsynced) {
      final filePath = doc['learner_document']?.toString() ?? '';
      final documentName = doc['documentName']?.toString() ?? '';
      if (filePath.isEmpty || !File(filePath).existsSync()) continue;

      try {
        final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
          ..fields['learner_id'] = learnerId
          ..fields['documentName'] = documentName
          ..fields['status'] = doc['status']?.toString() ?? 'Pending'
          ..fields['upload_date'] =
              doc['upload_date']?.toString() ?? DateTime.now().toIso8601String()
          ..fields['synced'] = '1'
          ..fields['rejection_reason'] =
              doc['rejection_reason']?.toString() ?? ''
          ..files.add(await http.MultipartFile.fromPath(
            'learner_document',
            filePath,
            filename: filePath.split(Platform.pathSeparator).last,
          ));

        final response = await request.send();
        final body = await response.stream.bytesToString();
        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['success'] == true) {
          final docId = doc['document_id'];
          final parsedId = docId is int ? docId : int.tryParse('$docId');
          if (parsedId != null) {
            await dbHelper.updateLearnerDocumentSynced(parsedId, 1);
          }
        }
      } catch (_) {
        // Keep local copy; will retry later.
      }
    }
  }
}
