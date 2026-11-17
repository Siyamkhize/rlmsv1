import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:geolocator/geolocator.dart';  // Temporarily commented out
import 'database_helper.dart';
import 'config.dart';
import 'dart:io'; // For File
import 'package:http_parser/http_parser.dart'; // For MediaType
import 'package:sqflite/sqflite.dart'; // For ConflictAlgorithm
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'utils/clocking_logger.dart';
import 'services/http_client_service.dart';
import 'config/network_config.dart';

Future<bool> syncSingleClockIn(Map<String, dynamic> attendance) async {
  debugPrint('=== CLOCK-IN SYNC START ===');
  debugPrint('Input attendance: $attendance');

  final connectivityResult = await Connectivity().checkConnectivity();
  debugPrint('Connectivity result: $connectivityResult');

  final isOffline = connectivityResult.contains(ConnectivityResult.none);

  if (isOffline) {
    debugPrint('No internet connection - returning false');
    return false;
  }

  debugPrint('✅ Internet connection available - proceeding with sync');

  // Retry logic with exponential backoff
  const int maxRetries = 2; // Reduced retries for faster response
  const Duration baseTimeout =
      Duration(seconds: 8); // Reduced timeout for faster response

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final url = Uri.parse(AppConfig.clockinUrl);
      debugPrint('Target URL: $url (attempt $attempt/$maxRetries)');

      // Prepare payload exactly like LearnerListPage.dart
      final payload = {
        'learnerId': attendance['learnerId'],
        'clock_in': '1',
        'signature': '', // Empty signature for now
        'user_latitude': attendance['user_latitude'] ?? '0.0',
        'user_longitude': attendance['user_longitude'] ?? '0.0',
        'user_accuracy':
            attendance['user_accuracy'] ?? '10.0', // Server expects this field
        'synced': '0',
        'classID': attendance['classID'] ?? '',
        'fingerprint_verified':
            'true', // CRITICAL: Indicate fingerprint was verified
        'request_source': 'mobile_app', // CRITICAL: Indicate request source
        'sync_request': 'true', // CRITICAL: Indicate this is a sync request
      };

      debugPrint('Sending clock-in sync request: $payload');

      // Convert payload to URL-encoded format
      final body = payload.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
          .join('&');

      debugPrint('Encoded body: $body');

      // Use exponential backoff for timeout
      final timeout = Duration(seconds: baseTimeout.inSeconds * attempt);

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);

      debugPrint(
          'Clock-in sync response (status ${response.statusCode}): "${response.body}"');
      ClockingLogger.instance.logHttpRequest(
          'POST', url.toString(), payload, response.statusCode, response.body);

      if (response.statusCode == 200) {
        try {
          final responseJson = json.decode(response.body);
          debugPrint('Parsed response JSON: $responseJson');

          // Check for different possible success indicators
          bool success = false;
          if (responseJson is Map<String, dynamic>) {
            success = responseJson['success'] == true ||
                responseJson['status'] == 'success' ||
                responseJson['success'] == 'true';
          }

          debugPrint('Sync success: $success');
          return success;
        } catch (e) {
          debugPrint('Error parsing response JSON: $e');
          debugPrint('Raw response body: "${response.body}"');
          if (attempt == maxRetries) return false;
          // Continue to next attempt
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        debugPrint('Response body: "${response.body}"');
        if (attempt == maxRetries) return false;
        // Continue to next attempt
      }
    } catch (e) {
      debugPrint('Error syncing clock-in (attempt $attempt): $e');
      if (attempt == maxRetries) return false;

      // Wait before retry with exponential backoff
      final delay = Duration(seconds: attempt * 2); // 2s, 4s, 6s
      debugPrint('Waiting ${delay.inSeconds} seconds before retry...');
      await Future.delayed(delay);
    }
  }

  return false;
}

Future<bool> syncSingleClockOut(Map<String, dynamic> attendance) async {
  debugPrint('=== CLOCK-OUT SYNC START ===');
  debugPrint('Input attendance: $attendance');

  final connectivityResult = await Connectivity().checkConnectivity();
  debugPrint('Connectivity result: $connectivityResult');

  final isOffline = connectivityResult.contains(ConnectivityResult.none);

  if (isOffline) {
    debugPrint('No internet connection - returning false');
    return false;
  }

  debugPrint('✅ Internet connection available - proceeding with sync');

  // Retry logic with exponential backoff
  const int maxRetries = 2; // Reduced retries for faster response
  const Duration baseTimeout =
      Duration(seconds: 8); // Reduced timeout for faster response

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final url = Uri.parse(AppConfig.clockoutUrl);
      debugPrint('Target URL: $url (attempt $attempt/$maxRetries)');

      // Prepare payload exactly like LearnerListPage.dart
      final payload = {
        'learnerId': attendance['learnerId'],
        'clock_out': '1',
        'signature': '', // Empty signature for now
        'user_latitude': attendance['user_latitude'] ?? '0.0',
        'user_longitude': attendance['user_longitude'] ?? '0.0',
        'user_accuracy':
            attendance['user_accuracy'] ?? '10.0', // Server expects this field
        'synced': '0',
        'classID': attendance['classID'] ?? '',
        'fingerprint_verified':
            'true', // CRITICAL: Indicate fingerprint was verified
        'request_source': 'mobile_app', // CRITICAL: Indicate request source
        'sync_request': 'true', // CRITICAL: Indicate this is a sync request
      };

      debugPrint('Sending clock-out sync request: $payload');

      // Convert payload to URL-encoded format
      final body = payload.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
          .join('&');

      debugPrint('Encoded body: $body');

      // Use exponential backoff for timeout
      final timeout = Duration(seconds: baseTimeout.inSeconds * attempt);

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(timeout);

      debugPrint(
          'Clock-out sync response (status ${response.statusCode}): "${response.body}"');
      ClockingLogger.instance.logHttpRequest(
          'POST', url.toString(), payload, response.statusCode, response.body);

      if (response.statusCode == 200) {
        try {
          final responseJson = json.decode(response.body);
          debugPrint('Parsed response JSON: $responseJson');

          // Check for different possible success indicators
          bool success = false;
          if (responseJson is Map<String, dynamic>) {
            success = responseJson['success'] == true ||
                responseJson['status'] == 'success' ||
                responseJson['success'] == 'true';
          }

          debugPrint('Sync success: $success');
          return success;
        } catch (e) {
          debugPrint('Error parsing response JSON: $e');
          debugPrint('Raw response body: "${response.body}"');
          if (attempt == maxRetries) return false;
          // Continue to next attempt
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        debugPrint('Response body: "${response.body}"');
        if (attempt == maxRetries) return false;
        // Continue to next attempt
      }
    } catch (e) {
      debugPrint('Error syncing clock-out (attempt $attempt): $e');
      if (attempt == maxRetries) return false;

      // Wait before retry with exponential backoff
      final delay = Duration(seconds: attempt * 2); // 2s, 4s, 6s
      debugPrint('Waiting ${delay.inSeconds} seconds before retry...');
      await Future.delayed(delay);
    }
  }

  return false;
}

class SyncService extends ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Initialize the app and download data if online
  Future<void> initSync() async {
    await syncData();
  }

  // Sync all tables from the server to the local database
  Future<void> syncData() async {
    debugPrint('[SYNC] ===== STARTING FULL SYNC =====');

    try {
      await _syncUsers();
      debugPrint('[SYNC] ✅ Users sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Users sync failed: $e');
    }

    try {
      await _syncLearnerDetails();
      debugPrint('[SYNC] ✅ Learner details sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Learner details sync failed: $e');
    }

    // Only sync current day's clocking data to avoid loading old records
    try {
      await _syncLearnerClocking(currentDayOnly: true);
      debugPrint('[SYNC] ✅ Learner clocking sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Learner clocking sync failed: $e');
    }

    try {
      await _syncFacilitator();
      debugPrint('[SYNC] ✅ Facilitator sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Facilitator sync failed: $e');
    }

    try {
      await _syncSdp();
      debugPrint('[SYNC] ✅ SDP sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ SDP sync failed: $e');
    }

    try {
      await syncSites();
      debugPrint('[SYNC] ✅ Sites sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Sites sync failed: $e');
    }

    try {
      await _syncClass();
      debugPrint('[SYNC] ✅ Class sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Class sync failed: $e');
    }

    try {
      await DatabaseHelper().syncLocationTables();
      debugPrint('[SYNC] ✅ Location tables sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Location tables sync failed: $e');
    }

    try {
      await _syncLearningpathway();
      debugPrint('[SYNC] ✅ Learning pathway sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Learning pathway sync failed: $e');
    }

    try {
      await _syncPathwaySelection();
      debugPrint('[SYNC] ✅ Pathway selection sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Pathway selection sync failed: $e');
    }

    try {
      await _syncQualification();
      debugPrint('[SYNC] ✅ Qualification sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Qualification sync failed: $e');
    }

    try {
      await _syncQualificationSelection();
      debugPrint('[SYNC] ✅ Qualification selection sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Qualification selection sync failed: $e');
    }

    try {
      await _syncQualificationPathway();
      debugPrint('[SYNC] ✅ Qualification pathway sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Qualification pathway sync failed: $e');
    }

    try {
      await _syncQualificationunitstandard();
      debugPrint('[SYNC] ✅ Qualification unit standard sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Qualification unit standard sync failed: $e');
    }

    try {
      await _syncUnitstandard();
      debugPrint('[SYNC] ✅ Unit standard sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Unit standard sync failed: $e');
    }

    try {
      await _syncUnitStandardSelection();
      debugPrint('[SYNC] ✅ Unit standard selection sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Unit standard selection sync failed: $e');
    }

    try {
      await _syncAssessment();
      debugPrint('[SYNC] ✅ Assessment sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Assessment sync failed: $e');
    }

    // Sync learner documents
    try {
      await _syncLearnerDocuments();
      debugPrint('[SYNC] ✅ Learner documents sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Learner documents sync failed: $e');
    }

    try {
      await _syncPoe();
      debugPrint('[SYNC] ✅ POE sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ POE sync failed: $e');
    }

    try {
      await syncAcknowledgmentOfReceiptToServer();
      debugPrint('[SYNC] ✅ Acknowledgment of receipt sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Acknowledgment of receipt sync failed: $e');
    }

    try {
      await syncDataFromServer();
      debugPrint('[SYNC] ✅ Sync data from server complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Sync data from server failed: $e');
    }

    try {
      await syncMaterialReceiptFormData();
      debugPrint('[SYNC] ✅ Material receipt form data sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Material receipt form data sync failed: $e');
    }

    try {
      await syncMaterialsReceivedData();
      debugPrint('[SYNC] ✅ Materials received data sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Materials received data sync failed: $e');
    }

    try {
      await syncProjectData();
      debugPrint('[SYNC] ✅ Project data sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Project data sync failed: $e');
    }

    try {
      await syncSickNotesToServer();
      debugPrint('[SYNC] ✅ Sick notes sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Sick notes sync failed: $e');
    }

    try {
      await _syncBankDetails();
      debugPrint('[SYNC] ✅ Bank details sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Bank details sync failed: $e');
    }

    try {
      await _syncInductionClocking();
      debugPrint('[SYNC] ✅ Induction clocking sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Induction clocking sync failed: $e');
    }

    try {
      await syncInductionClocking();
      debugPrint('[SYNC] ✅ Sync induction clocking complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Sync induction clocking failed: $e');
    }

    try {
      await syncMonitoringRecords();
      debugPrint('[SYNC] ✅ Monitoring records sync complete');
    } catch (e) {
      debugPrint('[SYNC] ❌ Monitoring records sync failed: $e');
    }

    debugPrint('[SYNC] ===== FULL SYNC COMPLETED =====');
  }

  // Sync users table
  Future<void> _syncUsers() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncUsersUrl));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        debugPrint('Users data from server: $data'); // Debug the response

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint('Syncing ${data.length} users using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        // Insert each user into the SQLite database
        for (var user in data) {
          await db.insert(
            'users',
            user,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          debugPrint('Synced user: $user'); // Debug insertion
        }
        debugPrint(
            "Users table synchronized and data inserted into local database successfully.");
      } else {
        debugPrint('Failed to sync users. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error during users sync: $e');
    }
  }

  // Fetch and print local data to confirm insertion
  Future<void> printLocalUsers() async {
    final db = await _dbHelper.database;
    final users = await db.query('users');
    debugPrint("Users in local database: $users");
  }

  // Sync learnerdetails table
  Future<void> _syncLearnerDetails() async {
    try {
      // Verify connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.wifi) &&
          !connectivityResult.contains(ConnectivityResult.mobile)) {
        debugPrint("No network available, skipping learner details sync");
        return;
      }

      // Make GET request to fetch learner details
      final response = await http.get(
        Uri.parse(AppConfig.syncLearnerDetailsUrl),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint("Server response status: ${response.statusCode}");
      debugPrint("Server response body: ${response.body}");

      if (response.statusCode == 200) {
        final List<dynamic> learners = json.decode(response.body);
        if (learners.isEmpty) {
          debugPrint("Warning: No learner data received from API");
          return;
        }

        final db = await _dbHelper.database;

        // Create a mapping of IDNumber to server learnerId for existing records
        Map<String, int> idNumberToServerId = {};
        for (var learner in learners) {
          if (learner['IDNumber'] != null && learner['learnerId'] != null) {
            idNumberToServerId[learner['IDNumber'].toString()] =
                learner['learnerId'] as int;
          }
        }

        // Get existing local learners to create ID mapping
        final existingLearners = await db.query('learnerdetails');
        Map<int, int> localToServerIdMapping = {};

        for (var existingLearner in existingLearners) {
          String idNumber = existingLearner['IDNumber']?.toString() ?? '';
          int localId = existingLearner['learnerId'] as int;

          if (idNumberToServerId.containsKey(idNumber)) {
            int serverId = idNumberToServerId[idNumber]!;
            localToServerIdMapping[localId] = serverId;
            debugPrint(
                "Mapping local ID $localId to server ID $serverId for IDNumber $idNumber");
          }
        }

        // Update related tables with new IDs before syncing learnerdetails
        if (localToServerIdMapping.isNotEmpty) {
          await _updateRelatedTablesWithNewIds(db, localToServerIdMapping);
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${learners.length} learner details using UPDATE/INSERT pattern');

        // Insert records one by one
        for (var learner in learners) {
          // Validate required fields
          if (learner['IDNumber'] == null || learner['classID'] == null) {
            debugPrint("Skipping invalid learner record: $learner");
            continue;
          }

          // Log data quality issues when server returns incomplete data
          if (learner['Title'] == null ||
              learner['DateOfBirth'] == null ||
              learner['Name'] == null ||
              learner['Surname'] == null) {
            debugPrint("WARNING: Server returned incomplete data for learner ${learner['IDNumber']}: " "Title=${learner['Title']}, Name=${learner['Name']}, " "Surname=${learner['Surname']}, DateOfBirth=${learner['DateOfBirth']}");
          }

          // Extract bank details before inserting learner
          Map<String, dynamic>? bankDetails;
          if (learner['BankName'] != null || learner['BankAccount'] != null) {
            bankDetails = {
              'learnerId': learner['learnerId'],
              'BankName': learner['BankName'] ?? '',
              'bankType': learner['bankType'] ?? '',
              'BankAccount': learner['BankAccount'] ?? '',
              'BankCode': learner['BankCode'] ?? '',
              'synced': 0,
            };
          }

          // Create learner data WITHOUT bank fields
          Map<String, dynamic> learnerData = Map<String, dynamic>.from(learner);
          learnerData.remove('BankName');
          learnerData.remove('bankType');
          learnerData.remove('BankAccount');
          learnerData.remove('BankCode');

          try {
            // Insert/update learner details using sanitized upsert
            await _dbHelper.upsertLearner(learnerData);

            // Insert/update bank details if they exist
            if (bankDetails != null) {
              await db.insert(
                'bankdetails',
                bankDetails,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }

            debugPrint(
                "Successfully synced learner with IDNumber: ${learner['IDNumber']}, Server ID: ${learner['learnerId']}");
          } catch (e) {
            if (e.toString().contains('NOT NULL constraint failed')) {
              debugPrint(
                  "NOT NULL constraint failed for learner with IDNumber ${learner['IDNumber']}: $e");
              debugPrint("Raw learner data: $learner");
              // Continue with other learners even if one fails due to constraint issues
            } else {
              debugPrint(
                  "Error syncing learner with IDNumber ${learner['IDNumber']}: $e");
            }
            // Continue with other learners even if one fails
          }
        }

        debugPrint("Successfully synchronized ${learners.length} learner records");
      } else {
        throw Exception(
            "Failed to sync learner details. Status code: ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      debugPrint("Error syncing learner details: $e");
      debugPrint("Stack trace: $stackTrace");
      rethrow;
    }
  }

  // Helper method to update related tables with new LearnerIDs
  Future<void> _updateRelatedTablesWithNewIds(
      Database db, Map<int, int> idMapping) async {
    try {
      // Update learner_clocking table
      for (var entry in idMapping.entries) {
        int oldId = entry.key;
        int newId = entry.value;

        await db.update(
          'learner_clocking',
          {'learnerId': newId},
          where: 'learnerId = ?',
          whereArgs: [oldId],
        );
        debugPrint("Updated learner_clocking: $oldId -> $newId");
      }

      // Update bankdetails table
      for (var entry in idMapping.entries) {
        int oldId = entry.key;
        int newId = entry.value;

        await db.update(
          'bankdetails',
          {'learnerId': newId},
          where: 'learnerId = ?',
          whereArgs: [oldId],
        );
        debugPrint("Updated bankdetails: $oldId -> $newId");
      }

      // Update poe table
      for (var entry in idMapping.entries) {
        int oldId = entry.key;
        int newId = entry.value;

        await db.update(
          'poe',
          {'learnerId': newId},
          where: 'learnerId = ?',
          whereArgs: [oldId],
        );
        debugPrint("Updated poe: $oldId -> $newId");
      }

      // Update learner_document table
      for (var entry in idMapping.entries) {
        int oldId = entry.key;
        int newId = entry.value;

        await db.update(
          'learner_document',
          {'learner_id': newId},
          where: 'learner_id = ?',
          whereArgs: [oldId],
        );
        debugPrint("Updated learner_document: $oldId -> $newId");
      }

      debugPrint("Successfully updated all related tables with new LearnerIDs");
    } catch (e) {
      debugPrint("Error updating related tables: $e");
      rethrow;
    }
  }

  // Sync bank details table
  Future<void> _syncBankDetails() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncBankLocalUrl));

      if (response.statusCode == 200) {
        List details = json.decode(response.body);

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${details.length} bank details using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var detail in details) {
          await db.insert(
            'bankdetails',
            detail,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        debugPrint("bankdetails table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync bankdetails. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing bankdetails: $e");
    }
  }

  //facilitator
  // Public method to sync facilitator data (including fingerprints)
  Future<void> syncFacilitatorData() async {
    await _syncFacilitator();
  }

  Future<void> _syncFacilitator() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncFacilitatorUrl));

      if (response.statusCode == 200) {
        List facilitatorData = json.decode(response.body);
        debugPrint(
            "[FAC_SYNC] Received ${facilitatorData.length} facilitators from server");

        final db = await _dbHelper.database;

        // Clear table
        await db.delete('facilitator');
        debugPrint("[FAC_SYNC] Cleared facilitator table");

        // Insert using direct SQL to avoid any data transformation issues
        int successCount = 0;
        for (var facilitator in facilitatorData) {
          try {
            // Direct SQL insert - no helpers, no transformations
            await db.rawInsert('''
              INSERT INTO facilitator (
                facilitator_id, firstName, lastName, role, email, classID,
                password, assessorNo, f_signature, phoneNumber, workNumber,
                f_profile, f_IDNumber, serial_number,
                zkteco_left_template, zkteco_right_template,
                futronic_left_template, futronic_right_template
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', [
              facilitator['facilitator_id'],
              facilitator['firstName'],
              facilitator['lastName'],
              facilitator['role'],
              facilitator['email'],
              facilitator['classID'],
              facilitator['password'],
              facilitator['assessorNo'],
              facilitator['f_signature'],
              facilitator['phoneNumber'],
              facilitator['workNumber'],
              facilitator['f_profile'],
              facilitator['f_IDNumber'],
              facilitator['serial_number'],
              facilitator['zkteco_left_template'],
              facilitator['zkteco_right_template'],
              facilitator['futronic_left_template'],
              facilitator['futronic_right_template'],
            ]);

            successCount++;
            debugPrint(
                "[FAC_SYNC] ✓ Synced facilitator ID ${facilitator['facilitator_id']}: ${facilitator['firstName']} ${facilitator['lastName']}");
          } catch (e) {
            debugPrint(
                "[FAC_SYNC] ✗ Error inserting facilitator ${facilitator['facilitator_id']}: $e");
          }
        }

        debugPrint(
            "[FAC_SYNC] Sync complete: $successCount/${facilitatorData.length} facilitators synced");
      } else {
        debugPrint("[FAC_SYNC] Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("[FAC_SYNC] Sync error: $e");
    }
  }

  // Sync learner_clocking table (ALL records, optionally filtered by classID)
  Future<void> _syncLearnerClocking(
      {String? classID, bool currentDayOnly = false}) async {
    try {
      String url = AppConfig.syncLearnerClockingUrl;
      String? today; // Declare today variable outside the if block

      // Use South African time (SAST - UTC+2)
      final saTime = DateTime.now().toUtc().add(const Duration(hours: 2));
      final todayDate = DateFormat('yyyy-MM-dd').format(saTime);

      // Add date filter only if currentDayOnly is true
      if (currentDayOnly) {
        today = todayDate;
        url += '?clock_date=$today';
      }

      // Add classID filter if provided
      if (classID != null && classID.isNotEmpty) {
        if (currentDayOnly) {
          url += '&classID=$classID';
          debugPrint(
              "[SYNC] Fetching learner_clocking for date: $today (SAST), classID: $classID");
        } else {
          url += '?classID=$classID';
          debugPrint(
              "[SYNC] Fetching ALL learner_clocking records for classID: $classID");
        }
      } else if (!currentDayOnly) {
        debugPrint("[SYNC] Fetching ALL learner_clocking records (all classes)");
      } else {
        debugPrint(
            "[SYNC] Fetching learner_clocking for date: $today (SAST), all classes");
      }

      final response = await http.get(Uri.parse(url));

      debugPrint("[SYNC] Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        var decodedData = json.decode(response.body);
        if (decodedData is List) {
          List clockingData = decodedData;
          debugPrint(
              "[SYNC] Fetched ${clockingData.length} records for $todayDate (SAST)");
          int insertedCount = 0;
          int skippedCount = 0;

          debugPrint(
              "[SYNC] Merging ${clockingData.length} server records (currentDayOnly: $currentDayOnly)");

          // Insert or update each record
          for (var clocking in clockingData) {
            // Map JSON keys to match table schema - include ALL columns for full sync
            final raw = clocking as Map<String, dynamic>;
            var mappedClocking = <String, dynamic>{
              'clocking_id': raw['clocking_id'],
              'learnerId': raw['learnerId'] ?? raw['learner_id'],
              'clock_date': raw['clock_date'],
              'clock_in_time': raw['clock_in_time'],
              'clock_out_time': raw['clock_out_time'],
              'contact_time': raw['contact_time'],
              'signature': raw['signature'],
              'synced': raw['synced'] ?? 1,
              'user_latitude': raw['user_latitude'],
              'user_longitude': raw['user_longitude'],
              'user_accuracy': raw['user_accuracy'],
            };

            // Validate required fields
            if (mappedClocking['clocking_id'] == null ||
                mappedClocking['learnerId'] == null ||
                mappedClocking['clock_date'] == null ||
                mappedClocking['clock_in_time'] == null) {
              debugPrint("Skipping invalid record: $mappedClocking");
              skippedCount++;
              continue;
            }

            // CRITICAL: If currentDayOnly is true, ONLY insert today's records
            if (currentDayOnly && mappedClocking['clock_date'] != todayDate) {
              debugPrint(
                  "⏩ Skipping non-current day record: ${mappedClocking['clock_date']} (not today: $todayDate)");
              skippedCount++;
              continue;
            }

            debugPrint("Merging server record: $mappedClocking");
            try {
              final db = await _dbHelper.database;
              // Check for existing record with same learner and date ONLY.
              // This guarantees max ONE local record per learner per date.
              final existingRecords = await db.query(
                'learner_clocking',
                where: 'learnerId = ? AND clock_date = ?',
                whereArgs: [
                  mappedClocking['learnerId'],
                  mappedClocking['clock_date'],
                ],
              );

              if (existingRecords.isNotEmpty) {
                // NEVER overwrite local records - local is source of truth.
                // Also, do NOT create a second record for the same learner/date.
                debugPrint(
                    "⏭️ PRESERVING local record for ${mappedClocking['learnerId']} (clock_date=${mappedClocking['clock_date']}) - not inserting duplicate for day");
                skippedCount++;
              } else {
                // Insert new record from server (no existing record for that learner/date)
                await db.insert(
                  'learner_clocking',
                  mappedClocking,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                debugPrint(
                    "✅ Inserted new server record for ${mappedClocking['learnerId']}");
                insertedCount++;
              }
            } catch (e) {
              debugPrint("Error merging record $mappedClocking: $e");
            }
          }
          debugPrint(
              "✅ Sync complete: $insertedCount inserted/updated, $skippedCount skipped (currentDayOnly: $currentDayOnly)");
        } else {
          debugPrint(
              "Error: Expected List, got ${decodedData.runtimeType}: $decodedData");
        }
      } else {
        debugPrint(
            "Failed to sync. Status: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error syncing learner_clocking: $e");
    }
  }

  bool isSyncing = false;
  String syncMessage = '';

  // Public method to sync clocking data for a specific class (current day only)
  Future<void> syncClassClockingFromServer(String classID) async {
    try {
      debugPrint(
          "[SYNC] Syncing clocking data for classID: $classID (current day only)");
      await _syncLearnerClocking(classID: classID, currentDayOnly: true);
      debugPrint("[SYNC] Class clocking sync completed for classID: $classID");
    } catch (e) {
      debugPrint("[SYNC] Error syncing class clocking: $e");
    }
  }

  // Public method to sync ALL clocking data for a specific class (all dates)
  Future<void> syncAllClassClockingFromServer(String classID) async {
    try {
      debugPrint("[SYNC] Syncing ALL clocking data for classID: $classID");
      await _syncLearnerClocking(classID: classID, currentDayOnly: false);
      debugPrint("[SYNC] All class clocking sync completed for classID: $classID");
    } catch (e) {
      debugPrint("[SYNC] Error syncing all class clocking: $e");
    }
  }

  Future<void> syncClockingDataToServer() async {
    final db = await _dbHelper.database;

    isSyncing = true;
    syncMessage = 'Syncing data to the server...';
    notifyListeners();

    try {
      // Sync ALL unsynced records for the last 10 days (including clock-in only)
      // This allows devices to be offline for a few days but avoids sending very old data.
      final now = DateTime.now();
      final cutoffDate = DateFormat('yyyy-MM-dd')
          .format(now.subtract(const Duration(days: 10)));

      final List<Map<String, dynamic>> clockingDataList = await db.query(
        'learner_clocking',
        where: 'synced = ? AND clock_date >= ?',
        whereArgs: [0, cutoffDate],
      );

      if (clockingDataList.isEmpty) {
        syncMessage = 'No data to sync!';
        notifyListeners();
        return;
      }

      const maxRetries = 3;
      for (var clockingData in clockingDataList) {
        final clockingId = clockingData['clocking_id'];
        final learnerId = clockingData['learnerId'];
        final clockInTime = clockingData['clock_in_time'];
        final clockOutTime = clockingData['clock_out_time'];
        final contactTime = clockingData['contact_time'];
        // We no longer send signature for clocking sync; always null on server
        final userLatitude = clockingData['user_latitude'];
        final userLongitude = clockingData['user_longitude'];
        final userAccuracy = clockingData['user_accuracy'];
        final clockDate = clockingData['clock_date'] ??
            DateTime.now().toIso8601String().split('T')[0];

        bool synced = false;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            // Prepare multipart request
            var request = http.MultipartRequest(
              'POST',
              Uri.parse(AppConfig.syncClockingUrl),
            );

            // Add fields
            request.fields['clocking_id'] = clockingId.toString();
            request.fields['learnerId'] = learnerId.toString();
            request.fields['clock_in_time'] = clockInTime ?? '';
            request.fields['clock_out_time'] = clockOutTime ?? '';
            request.fields['contact_time'] = contactTime ?? '';
            request.fields['clock_date'] = clockDate;
            request.fields['user_latitude'] = userLatitude?.toString() ?? '';
            request.fields['user_longitude'] = userLongitude?.toString() ?? '';
            request.fields['user_accuracy'] = userAccuracy?.toString() ?? '';

            // Log request details
            debugPrint('Attempt $attempt: Request fields: ${request.fields}');
            debugPrint(
                'Attempt $attempt: Request files: ${request.files.map((f) => f.filename).toList()}');

            // Send request
            final response =
                await request.send().timeout(const Duration(seconds: 30));
            final responseString = await response.stream.bytesToString();

            debugPrint(
                'Attempt $attempt: Server response for clocking_id $clockingId: $responseString (Status: ${response.statusCode})');

            if (response.statusCode == 200) {
              if (responseString.isEmpty) {
                debugPrint(
                    'Attempt $attempt: Empty response received for clocking_id $clockingId');
                syncMessage =
                    'Empty response from server for record $clockingId';
                if (attempt == maxRetries) {
                  syncMessage =
                      'Max retries reached for record $clockingId: Empty response';
                }
                await Future.delayed(const Duration(seconds: 1));
                continue;
              }

              try {
                final responseData = json.decode(responseString);
                if (responseData['status'] == 'success') {
                  await db.update(
                    'learner_clocking',
                    {'synced': true},
                    where: 'clocking_id = ?',
                    whereArgs: [clockingId],
                  );
                  syncMessage = 'Record $clockingId synced successfully!';
                  synced = true;
                  break;
                } else {
                  syncMessage =
                      'Server error for record $clockingId: ${responseData['message']}';
                  if (attempt == maxRetries) {
                    syncMessage =
                        'Max retries reached for record $clockingId: ${responseData['message']}';
                  }
                  await Future.delayed(const Duration(seconds: 1));
                  continue;
                }
              } catch (e) {
                debugPrint(
                    'Attempt $attempt: JSON parse error for clocking_id $clockingId: $e');
                syncMessage =
                    'Invalid response format for record $clockingId: $e';
                if (attempt == maxRetries) {
                  syncMessage =
                      'Max retries reached for record $clockingId: Invalid response';
                }
                await Future.delayed(const Duration(seconds: 1));
                continue;
              }
            } else {
              debugPrint(
                  'Attempt $attempt: Failed for clocking_id $clockingId: Status ${response.statusCode}, Response: $responseString');
              syncMessage =
                  'Failed to sync record $clockingId. Status: ${response.statusCode}, Response: $responseString';
              if (attempt == maxRetries) {
                syncMessage =
                    'Max retries reached for record $clockingId: Status ${response.statusCode}';
              }
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }
          } catch (e) {
            debugPrint('Attempt $attempt: Error for clocking_id $clockingId: $e');
            syncMessage = 'Error syncing record $clockingId: $e';
            if (attempt == maxRetries) {
              syncMessage = 'Max retries reached for record $clockingId: $e';
            }
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }

        if (!synced) {
          syncMessage =
              'Failed to sync record $clockingId after $maxRetries attempts';
          notifyListeners();
        }
      }

      if (syncMessage.contains('Failed') || syncMessage.contains('Error')) {
        // Keep syncMessage as is to reflect the last error
      } else {
        syncMessage = 'All data synced successfully!';
      }
    } catch (e) {
      syncMessage = 'Sync failed: $e';
      debugPrint('Error syncing data: $e');
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  // Method to synchronize unsynced data to the server
  Future<void> syncUnsyncedData() async {
    try {
      List<Map<String, dynamic>> unsyncedData =
          await _dbHelper.fetchData('unsynced_data');

      for (var data in unsyncedData) {
        final response = await http.post(
          Uri.parse(AppConfig.syncUnsyncedDataUrl),
          body: json.encode(data),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          await _dbHelper.deleteData('unsynced_data', data['id']);
          debugPrint("Unsynced data synced successfully.");
        } else {
          debugPrint(
              "Failed to sync unsynced data. Status code: ${response.statusCode}");
        }
      }
    } catch (e) {
      debugPrint("Error syncing unsynced data: $e");
    }
  }

  // Upload a local SDP to the server
  Future<void> _syncSdp() async {
    try {
      // Sending GET request to the PHP server to sync sdp data
      final response = await http.get(Uri.parse(AppConfig.getSdpUrl));

      if (response.statusCode == 200) {
        // Parse the response body as a map
        Map<String, dynamic> data = json.decode(response.body);

        // Ensure that 'data' is a list before proceeding
        if (data['status'] == 'success' && data['data'] is List) {
          List sdpData = data['data']; // Extract the 'data' list

          debugPrint("sdp data received from server: $sdpData");

          // SMART SYNC: Update existing, insert new (no delete)
          final db = await _dbHelper.database;

          for (var sdp in sdpData) {
            debugPrint("Syncing sdp: $sdp"); // Debug log

            // Check if record exists
            final existing = await db.query(
              'sdp',
              where: 'sdp_id = ?',
              whereArgs: [sdp['sdp_id']],
              limit: 1,
            );

            final sdpRecord = {
              'sdp_id': sdp['sdp_id'],
              'sdp_name': sdp['sdp_name'],
              'Reg_number': sdp['Reg_number'],
              'b_description': sdp['b_description'],
              'accreditation_n': sdp['accreditation_n'],
              'p_address': sdp['p_address'],
              'province': sdp['province'],
              'district': sdp['district'],
              'municipality': sdp['municipality'],
              'email': sdp['email'],
              'sdp_logo': sdp['sdp_logo'],
              'password': sdp['password'],
              'role': sdp['role'],
              'client_name': sdp['client_name'],
              'signature_image': sdp['signature_image'],
            };

            if (existing.isNotEmpty) {
              // Update existing record
              await db.update(
                'sdp',
                sdpRecord,
                where: 'sdp_id = ?',
                whereArgs: [sdp['sdp_id']],
              );
              debugPrint("Updated sdp: ${sdp['sdp_id']}");
            } else {
              // Insert new record
              await _dbHelper.insertData('sdp', sdpRecord);
              debugPrint("Inserted new sdp: ${sdp['sdp_id']}");
            }
          }

          // Query the local sdp table to check if data is synced
          final sdp = await db.query('sdp');
          debugPrint("sdp in local database: ${sdp.length} records");

          debugPrint("sdp table synchronized successfully.");
        } else {
          debugPrint("Failed to sync sdp. Unexpected response format.");
        }
      } else {
        debugPrint("Failed to sync sdp. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing sdp: $e");
    }
  }

  Future<void> syncSites() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncSitesUrl));

      if (response.statusCode == 200) {
        // Parse the response body
        var data = json.decode(response.body);
        if (data['status'] == 'success') {
          List sitesData = data['data'];
          debugPrint('Sites data received: ${sitesData.length} sites');

          // Process the data and insert it into the local database (SQLite)
          for (var sites in sitesData) {
            // Insert each site into the local database with ALL fields
            await _dbHelper.insertSite({
              'siteID': sites['siteID'],
              'siteName': sites['siteName'],
              'beneficiaries': sites['beneficiaries'],
              'latitude': sites['latitude'],
              'longitude': sites['longitude'],
              'sdp_id': sites['sdp_id'],
              'Province': sites['Province'],
              'District': sites['District'],
              'Municipality': sites['Municipality'],
              'Category': sites['Category'],
              'project_id': sites['project_id'],
              'Project_pathway': sites['Project_pathway'],
              'qualification_id': sites['qualification_id'],
              'first_name': sites['first_name'],
              'last_name': sites['last_name'],
              'cell_phone': sites['cell_phone'],
              'email': sites['email'],
            });
          }

          // Ensure that the database is opened before querying
          final db = await _dbHelper.database;

          // Query the local sites table to check if data is inserted
          final localSites = await db.query('sites');
          debugPrint("Sites in local database: ${localSites.length} records");

          debugPrint("Sites table synchronized successfully.");
        } else {
          debugPrint("Failed to sync sites. Unexpected response format.");
        }
      } else {
        debugPrint("Failed to sync sites. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing sites: $e");
    }
  }

  Future<void> _syncClass() async {
    try {
      // Sending GET request to the PHP server to sync class data
      final response = await http.get(Uri.parse(AppConfig.syncClassUrl));

      if (response.statusCode == 200) {
        // Parse the response body as a Map first
        Map<String, dynamic> responseBody = json.decode(response.body);

        // Check the status of the response
        if (responseBody['status'] == 'success') {
          // Extract the list of classes from the 'data' key
          List classData = responseBody['data'] ?? [];

          debugPrint("Class data received from server: $classData");

          // SMART SYNC: Update existing, insert new (no delete)
          debugPrint(
              'Syncing ${classData.length} classes using UPDATE/INSERT pattern');

          final db = await _dbHelper.database;

          // Insert each class record into the local database
          for (var classEntry in classData) {
            debugPrint("Syncing class: $classEntry"); // Debug log
            await db.insert(
              'class',
              {
                'classID': classEntry['classID'],
                'className': classEntry['className'],
                'numberOfLearners': classEntry['numberOfLearners'],
                'siteID': classEntry['siteID'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          // Query the local class table to check if data is inserted
          final localClassData = await db.query('class');
          debugPrint("Class in local database: ${localClassData.length} records");

          debugPrint("Class table synchronized successfully.");
        } else {
          debugPrint("Failed to sync class. Server responded with error.");
        }
      } else {
        debugPrint("Failed to sync class. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing class: $e");
    }
  }

  //sync to online server for learner_clocking
  Future<List<Map<String, dynamic>>> fetchDataFromLocalDatabase() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> results = await db.query(
        'learner_clocking',
        where: 'synced = ?',
        whereArgs: [0],
      );
      if (results.isNotEmpty) {
        debugPrint(
            "Fetched ${results.length} unsynced record(s) from local database.");
        return results;
      } else {
        debugPrint("No unsynced data found in local database.");
        return [];
      }
    } catch (e) {
      debugPrint("Error fetching data from local database: $e");
      rethrow;
    }
  }

  Future<void> markIsSynced(int clockingId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'learner_clocking',
        {'synced': 1},
        where: 'clocking_id = ?',
        whereArgs: [clockingId],
      );
      debugPrint("Marked clocking_id $clockingId as synced.");
    } catch (e) {
      debugPrint("Error marking entry as synced: $e");
      throw Exception("Failed to update sync status.");
    }
  }

  Future<void> syncDataToServer({int maxRetries = 3}) async {
    try {
      if (!await isConnected()) {
        debugPrint("No internet connection. Sync aborted.");
        showSyncError("No internet connection.");
        return;
      }

      // Sync monitoring records first
      await syncMonitoringRecords();

      final unsyncedRecords = await fetchDataFromLocalDatabase();
      if (unsyncedRecords.isEmpty) {
        debugPrint("No data to sync.");
        return;
      }

      for (final localData in unsyncedRecords) {
        int attempts = 0;
        bool synced = false;
        while (attempts < maxRetries && !synced) {
          try {
            // Validate required fields
            if (!localData.containsKey('learnerId') ||
                localData['learnerId'] == null ||
                !localData.containsKey('clock_in_time') ||
                localData['clock_in_time'] == null ||
                !localData.containsKey('clocking_id') ||
                localData['clocking_id'] == null) {
              debugPrint(
                  "Skipping record ${localData['clocking_id']}: Missing required fields");
              break;
            }

            final url = Uri.parse(AppConfig.syncClockingUrl);
            var request = http.MultipartRequest('POST', url)
              ..headers['Content-Type'] = 'multipart/form-data';

            // Add fields, ensuring non-null values
            localData.forEach((key, value) {
              if (value != null && key != 'signature') {
                request.fields[key] = value.toString();
              }
            });
            debugPrint("Request fields: ${request.fields}");

            // Handle signature file
            if (localData['signature'] != null) {
              final signaturePath = localData['signature'].toString();
              final signatureFile = File(signaturePath);
              if (await signatureFile.exists()) {
                var multipartFile = await http.MultipartFile.fromPath(
                    'signature', signaturePath);
                request.files.add(multipartFile);
                debugPrint("Signature file added: $signaturePath");
              } else {
                debugPrint("Signature file not found: $signaturePath");
              }
            }

            final response = await request.send();
            final responseBody = await response.stream.bytesToString();
            debugPrint("Server response: $responseBody");

            if (response.statusCode == 200) {
              final responseJson =
                  json.decode(responseBody) as Map<String, dynamic>;
              if (responseJson['status'] == 'success') {
                await markIsSynced(localData['clocking_id']);
                debugPrint("Record ${localData['clocking_id']} synced.");
                synced = true;
              } else {
                throw Exception("Sync failed: ${responseJson['message']}");
              }
            } else {
              throw Exception(
                  "Status code: ${response.statusCode}, response: $responseBody");
            }
          } catch (e) {
            attempts++;
            debugPrint(
                "Attempt $attempts failed for clocking_id ${localData['clocking_id']}: $e");
            if (attempts == maxRetries) {
              debugPrint(
                  "Max retries reached for clocking_id ${localData['clocking_id']}");
              showSyncError(
                  "Failed to sync record ${localData['clocking_id']}");
            }
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    } catch (e) {
      debugPrint("Error during data sync: $e");
      showSyncError("Sync error: $e");
      rethrow;
    }
  }

  Future<bool> isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  void showSyncError(String message) {
    debugPrint("Sync error: $message");
    // Add SnackBar or other UI feedback if needed
  }

  /// Sync unsynced monitoring records to the server
  Future<void> syncMonitoringRecords() async {
    try {
      debugPrint('[SYNC-MONITORING] Starting monitoring sync...');

      final unsyncedRecords = await _dbHelper.getUnsyncedMonitoringRecords();
      if (unsyncedRecords.isEmpty) {
        debugPrint('[SYNC-MONITORING] No unsynced monitoring records found');
        return;
      }

      debugPrint(
          '[SYNC-MONITORING] Found ${unsyncedRecords.length} records to sync');

      for (var record in unsyncedRecords) {
        try {
          final response = await http
              .post(
                Uri.parse(AppConfig.saveMonitoringRecordsUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(record),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final result = json.decode(response.body);
            if (result['success'] == true || result['status'] == 'success') {
              await _dbHelper.markMonitoringRecordAsSynced(record['id']);
              debugPrint(
                  '[SYNC-MONITORING] ✅ Successfully synced record ID: ${record['id']}');
            } else {
              debugPrint(
                  '[SYNC-MONITORING] ❌ Server returned error for record ${record['id']}: ${result['message']}');
            }
          } else {
            debugPrint(
                '[SYNC-MONITORING] ❌ Server error (${response.statusCode}) for record ${record['id']}');
          }
        } catch (e) {
          debugPrint(
              '[SYNC-MONITORING] ⚠️ Failed to sync record ${record['id']}: $e');
        }
      }
    } catch (e) {
      debugPrint('[SYNC-MONITORING] ❌ ERROR during monitoring sync: $e');
    }
  }

  // Sync learnerdetails table
  Future<void> _syncLearningpathway() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncLearningPathwayUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List insertLearningpathway;

        // If the response is a Map with a key pointing to the actual list, access it properly
        if (decodedResponse is Map) {
          // Assuming the data is nested inside a key, like 'data'
          insertLearningpathway = decodedResponse['data'] ??
              []; // Modify based on your actual structure
        } else if (decodedResponse is List) {
          // If the response is already a list
          insertLearningpathway = decodedResponse;
        } else {
          insertLearningpathway = [];
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${insertLearningpathway.length} learning pathways using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var pathwayData in insertLearningpathway) {
          await db.insert(
            'learningpathway',
            pathwayData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        debugPrint("Pathway selection table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync pathway selection. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing pathway selection: $e");
    }
  }

  Future<void> _syncPathwaySelection() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncPathwaySelectionUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List pathwaySelectionlist = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          pathwaySelectionlist = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          pathwaySelectionlist = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${pathwaySelectionlist.length} pathway selections using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var pathwaySelectionData in pathwaySelectionlist) {
          await db.insert(
            'pathway_selection',
            pathwaySelectionData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Pathway selection table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync pathway selection. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing pathway selection: $e");
    }
  }

  Future<void> _syncQualification() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncQualificationUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List qualificationList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          qualificationList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          qualificationList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${qualificationList.length} qualifications using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var qualificationData in qualificationList) {
          await db.insert(
            'qualification',
            qualificationData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Qualification table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync qualification. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing qualification data: $e");
    }
  }

  Future<void> _syncQualificationSelection() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncQualificationSelectionUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List qualificationSelectionlist = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          qualificationSelectionlist = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          qualificationSelectionlist = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${qualificationSelectionlist.length} qualification selections using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var qualificationSelectionData in qualificationSelectionlist) {
          await db.insert(
            'qualification_selection',
            qualificationSelectionData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Qualification selection table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync qualification selection. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing qualification data: $e");
    }
  }

  Future<void> _syncQualificationPathway() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncQualificationPathwayUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List qualificationPathwaylist = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          qualificationPathwaylist = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          qualificationPathwaylist = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${qualificationPathwaylist.length} qualification pathways using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var qualificationPathwayData in qualificationPathwaylist) {
          await db.insert(
            'qualification_pathway',
            qualificationPathwayData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Qualification pathway table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync qualification pathway. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing qualification data: $e");
    }
  }

  Future<void> _syncQualificationunitstandard() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncQualificationUnitStandardUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List qualificationunitstandardList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          qualificationunitstandardList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          qualificationunitstandardList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${qualificationunitstandardList.length} qualification unit standards using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var qualificationunitstandardData
            in qualificationunitstandardList) {
          await db.insert(
            'qualificationunitstandard',
            qualificationunitstandardData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Qualification unitstandard table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync qualification unitstandard. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing qualification data: $e");
    }
  }

  Future<void> _syncUnitstandard() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncUnitStandardUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List unitstandardList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          unitstandardList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          unitstandardList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${unitstandardList.length} unit standards using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var unitstandardData in unitstandardList) {
          await db.insert(
            'unitstandard',
            unitstandardData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Unitstandard table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync unitstandard. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing unitstandard data: $e");
    }
  }

  Future<void> _syncUnitStandardSelection() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncUnitStandardSelectionUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List unitstandardSelectionList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          unitstandardSelectionList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          unitstandardSelectionList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${unitstandardSelectionList.length} unit standard selections using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var unitstandardSelectionData in unitstandardSelectionList) {
          await db.insert(
            'unit_standard_selection',
            unitstandardSelectionData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Unit standard selection table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync unit standard selection. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing unit standard selection: $e");
    }
  }

  Future<void> _syncAssessment() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncAssessmentUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List assessmentsList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          assessmentsList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          assessmentsList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${assessmentsList.length} assessments using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var assessmentsData in assessmentsList) {
          await db.insert(
            'assessments',
            assessmentsData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        debugPrint("Assessments table synchronized successfully.");
      } else {
        debugPrint(
            "Failed to sync assessments. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing assessments: $e");
    }
  }

  Future<void> _syncPoe() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.syncPoeUrl));

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List poeList = [];

        // If the response is a Map with a key pointing to the actual list
        if (decodedResponse is Map) {
          // Assuming the data is inside a key like 'data', modify based on your actual structure
          poeList = decodedResponse['data'] ??
              []; // Replace 'data' with the correct key if necessary
        } else if (decodedResponse is List) {
          // If the response is already a list
          poeList = decodedResponse;
        }

        // SMART SYNC: Update existing, insert new (no delete)
        debugPrint(
            'Syncing ${poeList.length} POE records using UPDATE/INSERT pattern');

        final db = await _dbHelper.database;

        for (var poe in poeList) {
          try {
            await db.insert(
              'poe',
              poe,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            debugPrint("Error syncing POE with ID ${poe['poe_id']}: $e");
            // Continue with other POE records even if one fails
          }
        }

        debugPrint("Successfully synchronized ${poeList.length} POE records");
      } else {
        throw Exception(
            "Failed to sync POE. Status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error syncing POE: $e");
    }
  }

  // Sync learner documents from server
  Future<void> _syncLearnerDocuments() async {
    try {
      debugPrint('[SYNC] Starting learner documents sync...');
      await _dbHelper.syncLearnerDocuments();
      debugPrint('[SYNC] Learner documents sync completed');
    } catch (e) {
      debugPrint('[SYNC] Error syncing learner documents: $e');
    }
  }

  //Aknowledgement
  // Fetch unsynced records from the local database
  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await DatabaseHelper().database;
    final unsyncedRecords = await db
        .query('material_receipt_form', where: 'synced = ?', whereArgs: [0]);

    // Log the result
    debugPrint("Unsynced records fetched: $unsyncedRecords");

    return unsyncedRecords;
  }

  Future<Map<String, dynamic>> _getMultipartFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return {};
    final file = File(filePath);
    return await file.exists()
        ? {'name': file.path.split('/').last, 'tmp_name': file.path}
        : {};
  }

  Future<void> syncAcknowledgmentOfReceiptToServer() async {
    debugPrint("Syncing Acknowledgment of Receipt...");
    final unsyncedRecords = await getUnsyncedRecords();
    if (unsyncedRecords.isEmpty) {
      debugPrint("No records to sync.");
      return;
    }

    debugPrint("Found ${unsyncedRecords.length} unsynced records.");
    final Uri url = Uri.parse(AppConfig.syncAcknowledgmentDataUrl);
    List<Map<String, dynamic>> validRecords = [];
    var request = http.MultipartRequest('POST', url);

    for (int i = 0; i < unsyncedRecords.length; i++) {
      var record = unsyncedRecords[i];
      debugPrint("Processing record ${record['student_id_number']}");

      if ([
        'student_id_number',
        'student_full_name',
        'class_name',
        'description',
        'date_received',
        'learner_signature'
      ].any((key) => record[key] == null || record[key].toString().isEmpty)) {
        debugPrint(
            "Skipping record ${record['student_id_number']} due to missing required fields.");
        continue;
      }

      List<String> signaturePaths = [];
      if (record['learner_signature'] is String) {
        signaturePaths = [record['learner_signature']];
      } else if (record['learner_signature'] is List) {
        signaturePaths = List<String>.from(record['learner_signature']);
      }

      debugPrint(
          "Signature paths for record ${record['student_id_number']}: $signaturePaths");
      if (signaturePaths.isEmpty || !await _allFilesExist(signaturePaths)) {
        debugPrint(
            "Skipping record ${record['student_id_number']} - Missing or invalid signature files.");
        continue;
      }

      validRecords.add(record);
      for (int j = 0; j < signaturePaths.length; j++) {
        debugPrint("Adding signature file for record $i: ${signaturePaths[j]}");
        request.files.add(await http.MultipartFile.fromPath(
          'signature[]', // Simplified field name
          signaturePaths[j],
          contentType: MediaType('image', 'png'),
        ));
      }
    }

    if (validRecords.isEmpty) {
      debugPrint("No valid records to sync in form.");
      return;
    }

    debugPrint("Sending data to server: ${json.encode(validRecords)}");
    request.fields['data'] = json.encode(validRecords);

    try {
      var response = await request.send();
      String responseBody = await response.stream.bytesToString();
      debugPrint("Server response status: ${response.statusCode}");
      debugPrint("Server response body: $responseBody");

      if (response.statusCode == 200) {
        debugPrint("Batch sync successful for ${validRecords.length} records.");
        await _updateSyncedStatus(validRecords);
      } else {
        debugPrint(
            "Batch sync failed. Response: ${response.statusCode}, Body: $responseBody");
      }
    } catch (e) {
      debugPrint("Error syncing batch: $e");
    }
  }

  Future<bool> _allFilesExist(List<String> paths) async {
    for (String path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint("File does not exist: $path");
        return false;
      }
    }
    return true;
  }

  Future<void> _updateSyncedStatus(List<Map<String, dynamic>> records) async {
    final db = await DatabaseHelper().database;

    for (var record in records) {
      try {
        // Ensure the record has the 'id' field
        if (record['id'] == null) {
          debugPrint("Skipping record due to missing 'id' field: $record");
          continue;
        }

        debugPrint("Marking record ${record['id']} as synced.");

        // Update the 'synced' status to 1 for the record with the given 'id'
        await db.update(
          'material_receipt_form', // Ensure this is the correct table name
          {'synced': 1}, // Set the 'synced' column to 1
          where: 'id = ?', // Use 'id' as the primary key
          whereArgs: [
            record['id'].toString()
          ], // Pass the 'id' from the record as the argument
        );
      } catch (e) {
        // Log any error encountered while updating the record
        debugPrint("Error updating record ${record['id']}: $e");
      }
    }
  }

  // from sever to offline
  Future<void> syncDataFromServer() async {
    final serverUrl = AppConfig.syncMaterialFormsUrl; // Server endpoint

    try {
      // Fetch material forms from the server
      final response = await http.get(Uri.parse(serverUrl));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Check if the response is successful
        if (responseData['success'] == true) {
          List<dynamic> materialForms = responseData['data'];
          debugPrint(
              'Fetched ${materialForms.length} material forms from the server.');

          DatabaseHelper dbHelper = DatabaseHelper();

          // Insert each material form into the local SQLite database
          for (var form in materialForms) {
            debugPrint('Processing form: ${form['id']}');

            Map<String, dynamic> materialForm = {
              'id': form['id'],
              'classID': form['classID'],
              'facilitator_full_name': form['facilitator_full_name'],
              'representative_full_name': form['representative_full_name'],
              'qualification_name': form['qualification_name'],
              'facilitator_signature': form['facilitator_signature'],
              'representative_signature': form['representative_signature'],
              'description': form['description'],
              'quantity': form['quantity'],
              'is_synced': form['is_synced'],
              'created_at': form['created_at'],
              'updated_at': form['updated_at'],
            };

            // Print data before insertion
            debugPrint('Inserting form data: $materialForm');

            // Insert the material form data into the local database
            int result = await dbHelper.insertMaterialForm(materialForm);
            if (result > 0) {
              debugPrint('Successfully inserted form with ID: ${form['id']}');
            } else {
              debugPrint('Failed to insert form with ID: ${form['id']}');
            }
          }

          debugPrint(
              'Data successfully synced from the server to the local database');
        } else {
          debugPrint('Failed to fetch data from the server');
        }
      } else {
        debugPrint('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error syncing data from server: $e');
    }
  }

  //Sync Function to Upload Data to Server
  Future<String> convertFileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      return base64Encode(bytes); // Convert the file bytes to Base64
    } catch (e) {
      debugPrint('Error converting file to Base64: $e');
      return ''; // Return an empty string if there is an error
    }
  }

  // sync to online
  Future<void> syncMaterialFormsWithServer() async {
    final serverUrl = AppConfig.uploadSaveMaterialFormUrl; // Server endpoint

    try {
      // Fetch unsynced material forms from local SQLite database
      DatabaseHelper dbHelper = DatabaseHelper();
      List<Map<String, dynamic>> unsyncedForms =
          await dbHelper.fetchUnsyncedMaterialForms();
      debugPrint('Unsynced records fetched: $unsyncedForms');

      // Loop through the unsynced material forms
      for (var form in unsyncedForms) {
        String classID = form['classID'].toString();
        String facilitatorFullName = form['facilitator_full_name'];
        String representativeFullName = form['representative_full_name'];
        String qualificationName = form['qualification_name'];
        String description = form['description'];
        int quantity = form['quantity'];
        bool isSynced = form['is_synced'] == 1;

        // Get the file paths for the signatures
        String facilitatorSignaturePath = form['facilitator_signature'];
        String representativeSignaturePath = form['representative_signature'];

        // Debug print to check values
        debugPrint('classID: $classID');
        debugPrint('facilitatorFullName: $facilitatorFullName');
        debugPrint('representativeFullName: $representativeFullName');
        debugPrint('qualificationName: $qualificationName');
        debugPrint('description: $description');
        debugPrint('facilitatorSignaturePath: $facilitatorSignaturePath');
        debugPrint('representativeSignaturePath: $representativeSignaturePath');

        // Get the created_at and updated_at values
        String createdAt = form['created_at'];
        String updatedAt = form['updated_at'];

        // Prepare the multipart request
        final request = http.MultipartRequest('POST', Uri.parse(serverUrl))
          ..fields['classID'] = classID
          ..fields['facilitatorFullName'] = facilitatorFullName
          ..fields['representativeFullName'] = representativeFullName
          ..fields['qualificationName'] = qualificationName
          ..fields['description'] = description
          ..fields['quantity'] = quantity.toString()
          ..fields['createdAt'] = createdAt
          ..fields['isSynced'] = isSynced.toString()
          ..fields['updatedAt'] = updatedAt;

        // Add the facilitator's signature image file
        var facilitatorSignatureFile = await http.MultipartFile.fromPath(
            'facilitatorSignature', facilitatorSignaturePath);
        request.files.add(facilitatorSignatureFile);

        // Add the representative's signature image file
        var representativeSignatureFile = await http.MultipartFile.fromPath(
            'representativeSignature', representativeSignaturePath);
        request.files.add(representativeSignatureFile);

        debugPrint('Uploading material form data for class ID: $classID');

        // Send the request
        final response = await request.send();

        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final responseJson = json.decode(responseData);

          if (responseJson['success'] == true) {
            debugPrint('Material form synced successfully with server');
            // Update sync status in local database
            await dbHelper.updateSyncStatus(form['id']);
          } else {
            debugPrint('Failed to sync material form: ${responseJson['message']}');
          }
        } else {
          debugPrint('Server error: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error syncing material forms with server: $e');
    }
  }

  //for acknowlagment form
  Future<void> syncMaterialReceiptFormData() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.saveReceiptFormUrl));

      if (response.statusCode == 200) {
        debugPrint('Response body: ${response.body}');

        final decodedResponse = jsonDecode(response.body);

        if (decodedResponse['status'] == 'success') {
          List<dynamic> receiptForms = decodedResponse['data'];

          if (receiptForms.isEmpty) {
            debugPrint('No material receipt forms found to sync.');
            return;
          }

          final db = await _dbHelper.database;

          await db.transaction((txn) async {
            await txn.delete('material_receipt_form');

            for (var receiptForm in receiptForms) {
              try {
                // Check for missing fields and log the specific ones
                if (receiptForm['student_id_number'] == null) {
                  debugPrint('Skipping record due to missing student_id_number');
                  continue;
                }
                if (receiptForm['class_name'] == null) {
                  debugPrint('Skipping record due to missing class_name');
                  continue;
                }

                // Handle missing fields with defaults
                String studentFullName =
                    receiptForm['student_full_name'] ?? 'Unknown';
                String received =
                    (receiptForm['received'] == 'Yes') ? 'Yes' : 'No';
                int quantity = receiptForm['quantity'] ?? 1;
                String description =
                    receiptForm['description'] ?? 'No description';
                String dateReceived = receiptForm['date_received'] ?? '';
                String practitionerName =
                    receiptForm['practitioner_full_name'] ?? 'Unknown';
                String learnerSignature =
                    receiptForm['learner_signature'] ?? '';
                int synced = receiptForm['synced'] ?? 0;

                await txn.insert(
                  'material_receipt_form',
                  {
                    'student_id_number': receiptForm['student_id_number'],
                    'student_full_name': studentFullName,
                    'class_name': receiptForm['class_name'],
                    'received': received,
                    'quantity': quantity,
                    'description': description,
                    'date_received': dateReceived,
                    'practitioner_full_name': practitionerName,
                    'learner_signature': learnerSignature,
                    'created_at':
                        receiptForm['created_at'] ?? DateTime.now().toString(),
                    'synced': synced,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );

                debugPrint(
                    'Successfully inserted: ${receiptForm['student_id_number']}');
              } catch (e) {
                debugPrint('Error inserting material receipt form: $e');
              }
            }

            debugPrint('Material receipt form data synced successfully.');
          });
        } else {
          debugPrint(
              'Error syncing material receipt form data: ${decodedResponse['message']}');
        }
      } else {
        debugPrint(
            'Error: Failed to fetch material receipt form data. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error syncing material receipt form data: $e');
    }
  }

  Future<void> syncMaterialsReceivedData() async {
    try {
      // Define the PHP API URL for materials received data
      final apiUrl = AppConfig.saveMaterialsReceivedUrl;

      // Make the API call using HttpClientService with proper retry and timeout
      final response = await HttpClientService.makeRequest(
        () => http.get(Uri.parse(apiUrl)),
        endpoint: 'materials_received_sync',
        maxRetries: NetworkConfig.syncOperationsMaxRetries,
        timeout: const Duration(seconds: NetworkConfig.lightweightTimeout),
      );

      // Check if the response is successful
      if (response.statusCode == 200) {
        debugPrint(
            'Response body: ${response.body}'); // Print the response for debugging

        try {
          // Decode the JSON response into a Map
          final Map<String, dynamic> data = jsonDecode(response.body);

          // Check if the response contains 'status' as 'success'
          if (data['status'] == 'success') {
            // Access the 'data' field which contains the list of materials received
            List<dynamic> materialsReceived = data['data'];

            if (materialsReceived.isEmpty) {
              debugPrint('No materials received data to sync.');
              return;
            }

            // Get an instance of the database
            final db = await _dbHelper.database;

            // Start a database transaction to insert the materials received data
            await db.transaction((txn) async {
              // Clear existing data in the 'materials_received' table before inserting new data
              await txn.delete('materials_received');

              // Insert each material into the table
              for (var material in materialsReceived) {
                try {
                  await txn.insert(
                    'materials_received',
                    {
                      'quantity':
                          material['quantity'] ?? 0, // Default value if missing
                      'received': material['received'] ??
                          'Unknown', // Default value if missing
                      'learnerId': material['learnerId'] ??
                          'Unknown', // Default value if missing
                      'Description': material['Description'] ??
                          'Unknown', // Default value if missing
                      'date_received': material['date_received'] ??
                          'Unknown', // Default value if missing
                      'facilitator_name': material['facilitator_name'] ??
                          'Unknown', // Default value if missing
                      'representative_name': material['representative_name'] ??
                          'Unknown', // Default value if missing
                      'signature': material['signature'] ??
                          'Unknown', // Default value if missing
                      'synced': 0, // Mark as unsynced
                    },
                    conflictAlgorithm: ConflictAlgorithm
                        .replace, // Or ConflictAlgorithm.ignore
                  );
                  debugPrint(
                      'Inserted material: ${material['learnerId']}'); // Log inserted material
                } catch (e) {
                  debugPrint('Error inserting material: $e');
                }
              }
            });

            debugPrint('Materials received data synced successfully.');
          } else {
            debugPrint('Error syncing materials received data: ${data['message']}');
          }
        } catch (e) {
          debugPrint('Error decoding JSON response: $e');
        }
      } else {
        debugPrint(
            'Error: Failed to fetch materials received data. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error syncing materials received data: $e');
    }
  }

  // Method to sync project data
  Future<void> syncProjectData() async {
    debugPrint('[PROJECT_SYNC] ===== STARTING PROJECT SYNC =====');
    try {
      // Define your PHP API URL
      final apiUrl = AppConfig.syncProjectUrl;
      debugPrint('[PROJECT_SYNC] API URL: $apiUrl');

      // Make the API call
      debugPrint('[PROJECT_SYNC] Making HTTP GET request...');
      final response = await http.get(Uri.parse(apiUrl));
      debugPrint('[PROJECT_SYNC] Response status: ${response.statusCode}');

      // Check if the response is successful
      if (response.statusCode == 200) {
        debugPrint('[PROJECT_SYNC] ✅ HTTP request successful');
        debugPrint(
            '[PROJECT_SYNC] Response body length: ${response.body.length} characters');
        debugPrint(
            '[PROJECT_SYNC] Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

        try {
          // Decode the JSON response into a Map
          debugPrint('[PROJECT_SYNC] Attempting to decode JSON...');
          final Map<String, dynamic> data = jsonDecode(response.body);
          debugPrint('[PROJECT_SYNC] ✅ JSON decoded successfully');
          debugPrint('[PROJECT_SYNC] Response status: ${data['status']}');

          // Check if the response contains 'status' as 'success'
          if (data['status'] == 'success') {
            // Access the 'data' field which contains the list of projects
            List<dynamic> projects = data['data'];
            debugPrint(
                '[PROJECT_SYNC] ✅ Found ${projects.length} projects in response');

            // Get an instance of the database
            final db = await _dbHelper.database;
            debugPrint('[PROJECT_SYNC] ✅ Database connection obtained');

            // SMART SYNC: Update existing, insert new (no delete)
            debugPrint(
                '[PROJECT_SYNC] Syncing ${projects.length} projects using UPDATE/INSERT pattern');

            int successCount = 0;
            int errorCount = 0;

            for (var project in projects) {
              try {
                debugPrint(
                    '[PROJECT_SYNC] Processing project ID: ${project['project_id']}, Name: ${project['Project_name']}');
                // Check if required fields are missing and provide default values if necessary
                String projectName = project['Project_name'] ??
                    'Unknown Project'; // Default value
                String contractNo =
                    project['Contract_no'] ?? 'N/A'; // Default value
                String financialYear =
                    project['Financial_year'] ?? 'Unknown'; // Default value
                String startDate =
                    project['Start_date'] ?? 'Unknown'; // Default value
                String endDate =
                    project['End_date'] ?? 'Unknown'; // Default value
                String projectPathway =
                    project['Project_pathway'] ?? 'N/A'; // Default value
                String projectFunder =
                    project['Project_funder'] ?? 'N/A'; // Default value
                String province =
                    project['Province'] ?? 'Unknown'; // Default value
                String district =
                    project['District'] ?? 'Unknown'; // Default value
                String municipality =
                    project['Municipality'] ?? 'Unknown'; // Default value
                String ppe = project['PPE'] ?? 'Unknown'; // Default value
                String learningMaterial =
                    project['Learning_material'] ?? 'Unknown'; // Default value
                String toolkit =
                    project['Toolkit'] ?? 'Unknown'; // Default value
                String consumables =
                    project['Consumables'] ?? 'Unknown'; // Default value
                String budget = project['Budget'] ?? 'Unknown'; // Default value
                String nBeneficiaries =
                    project['n_beneficiaries'] ?? '0'; // Default value

                await db.insert(
                  'project',
                  {
                    'project_id': project['project_id'],
                    'sdp_name': project['sdp_name'],
                    'client_name': project['client_name'],
                    'Project_name': projectName, // Ensure this is not NULL
                    'Contract_no': contractNo, // Ensure this is not NULL
                    'Financial_year': financialYear, // Ensure this is not NULL
                    'Start_date': startDate, // Ensure this is not NULL
                    'End_date': endDate, // Ensure this is not NULL
                    'Project_pathway':
                        projectPathway, // Ensure this is not NULL
                    'Project_funder': projectFunder, // Ensure this is not NULL
                    'n_beneficiaries':
                        nBeneficiaries, // Ensure this is not NULL
                    'Province': province, // Ensure this is not NULL
                    'District': district, // Ensure this is not NULL
                    'Municipality': municipality, // Ensure this is not NULL
                    'PPE': ppe, // Ensure this is not NULL
                    'Learning_material':
                        learningMaterial, // Ensure this is not NULL
                    'Toolkit': toolkit, // Ensure this is not NULL
                    'Consumables': consumables, // Ensure this is not NULL
                    'Budget': budget, // Ensure this is not NULL
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                debugPrint(
                    '[PROJECT_SYNC] ✅ Successfully inserted project ID: ${project['project_id']}');
                successCount++;
              } catch (insertError) {
                debugPrint(
                    '[PROJECT_SYNC] ❌ Error inserting project ID ${project['project_id']}: $insertError');
                errorCount++;
              }
            }

            debugPrint(
                '[PROJECT_SYNC] ✅ Project sync completed: $successCount successful, $errorCount errors');

            // Verify data was inserted
            final projectCount =
                await db.rawQuery('SELECT COUNT(*) as count FROM project');
            final count = projectCount.first['count'] as int? ?? 0;
            debugPrint('[PROJECT_SYNC] 📊 Total projects in local database: $count');
          } else {
            debugPrint(
                '[PROJECT_SYNC] ❌ Server response status not success: ${data['status']}');
            debugPrint(
                '[PROJECT_SYNC] Server message: ${data['message'] ?? 'No message provided'}');
          }
        } catch (e) {
          debugPrint('[PROJECT_SYNC] ❌ Error decoding JSON response: $e');
          debugPrint('[PROJECT_SYNC] Raw response body: ${response.body}');
        }
      } else {
        debugPrint(
            '[PROJECT_SYNC] ❌ HTTP request failed with status: ${response.statusCode}');
        debugPrint('[PROJECT_SYNC] Response body: ${response.body}');
      }
    } catch (e) {
      debugPrint('[PROJECT_SYNC] ❌ Error syncing project data: $e');
    }
    debugPrint('[PROJECT_SYNC] ===== PROJECT SYNC COMPLETED =====');
  }

  // Public method to manually sync project data for testing
  Future<void> manualSyncProjectData() async {
    debugPrint('[MANUAL_SYNC] Manually triggering project sync...');
    await syncProjectData();
  }

  Future<void> syncToServerPOE(Map<String, dynamic> poe) async {
    try {
      final url = Uri.parse(AppConfig.syncPoeOnlineUrl);
      var request = http.MultipartRequest('POST', url);

      // Validate required fields
      String? learnerId = poe['learnerId']?.toString();
      if (learnerId == null ||
          learnerId.isEmpty ||
          poe['exercise'] == null ||
          poe['exercise'].toString().isEmpty ||
          poe['type'] == null ||
          poe['type'].toString().isEmpty ||
          poe['submitted_at'] == null ||
          poe['submitted_at'].toString().isEmpty) {
        debugPrint("Error: Missing required fields!");
        return;
      }

      // Get file path from poe record
      String? filePath = poe['filePath'];
      if (filePath == null || !await File(filePath).exists()) {
        debugPrint("No POE PDF found for $learnerId at $filePath");
        return;
      }

      // Add fields
      request.fields['learnerId'] = learnerId;
      request.fields['exercise'] = poe['exercise'].toString();
      request.fields['type'] = poe['type'].toString();
      request.fields['submitted_at'] = poe['submitted_at'].toString();

      // Attach PDF file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType('application', 'pdf'),
      ));

      debugPrint("Uploading POE PDF for learnerId: $learnerId...");

      // Retry logic
      int maxRetries = 3;
      int retryCount = 0;
      while (retryCount < maxRetries) {
        try {
          final response =
              await request.send().timeout(const Duration(seconds: 30));
          final responseBody = await http.Response.fromStream(response);

          debugPrint("Server Response: ${responseBody.body}");

          if (responseBody.statusCode == 200) {
            var jsonResponse = jsonDecode(responseBody.body);
            if (jsonResponse['success'] == true) {
              await markAsSyncedPOE(poe['poe_id']);
              debugPrint("POE PDF for $learnerId synced successfully.");
              break;
            } else {
              debugPrint("Sync failed: ${jsonResponse['message']}");
            }
          } else {
            debugPrint("Sync failed: HTTP ${responseBody.statusCode}");
          }
        } catch (e) {
          retryCount++;
          debugPrint(
              "Retry $retryCount/$maxRetries for learnerId: $learnerId, Error: $e");
          if (retryCount == maxRetries) {
            debugPrint("Max retries reached for learnerId: $learnerId");
          }
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    } catch (e) {
      debugPrint("Error syncing POE PDF: $e");
    }
  }

// Load unsynced POE data from local SQLite database
  Future<List<Map<String, dynamic>>> loadFromLocalPOE(Database db) async {
    try {
      List<Map<String, dynamic>> unsyncedData = await db.query(
        'poe',
        where: 'synced = 0', // Load only unsynced records
      );
      debugPrint("Loaded ${unsyncedData.length} unsynced POE records.");
      return unsyncedData;
    } catch (e) {
      debugPrint("Error loading POE data from local database: $e");
      return [];
    }
  }

// Mark POE record as synced in local database
  Future<void> markAsSyncedPOE(int poeId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'poe',
        {'synced': 1},
        where: 'poe_id = ?',
        whereArgs: [poeId],
      );
      debugPrint("POE ID $poeId marked as synced.");
    } catch (e) {
      debugPrint("Error marking POE ID $poeId as synced: $e");
    }
  }

// Function to sync all unsynced POE records
  Future<void> syncAllPOERecords() async {
    final db = await _dbHelper.database;
    List<Map<String, dynamic>> unsyncedRecords = await loadFromLocalPOE(db);

    for (var poe in unsyncedRecords) {
      await syncToServerPOE(poe);
    }
  }

  // Helper to get unsynced learners
  Future<List<Map<String, dynamic>>> _getUnsyncedLearners() async {
    if (kDebugMode) {
      debugPrint('DEBUG: Starting _getUnsyncedLearners');
    }
    final db = await _dbHelper.database;
    if (kDebugMode) {
      debugPrint('DEBUG: Database path: ${db.path}');
    }
    try {
      final result = await db.query(
        'learnerdetails',
        where: 'synced = ?',
        whereArgs: [0],
      );
      if (kDebugMode) {
        debugPrint('DEBUG: Retrieved ${result.length} unsynced learners: $result');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DEBUG: Error querying unsynced learners: $e');
      }
      return [];
    }
  }

  Future<void> _markAsSynced(String learnerId) async {
    if (kDebugMode) {
      debugPrint('DEBUG: Marking learner $learnerId as synced');
    }
    final db = await _dbHelper.database;
    final updatedRows = await db.update(
      'learnerdetails',
      {'synced': 1},
      where: 'learnerId = ?',
      whereArgs: [learnerId],
    );
    if (kDebugMode) {
      debugPrint('DEBUG: Updated $updatedRows rows for learnerId $learnerId');
    }
  }

  Future<Map<String, dynamic>> syncLearnerDetails() async {
    if (kDebugMode) {
      debugPrint('DEBUG: Starting syncLearnerDetails');
    }
    try {
      List<Map<String, dynamic>> unsyncedLearners =
          await _getUnsyncedLearners();
      debugPrint(
          'DEBUG: Found ${unsyncedLearners.length} unsynced learners to process');

      if (unsyncedLearners.isEmpty) {
        return {
          'success': true,
          'message': 'No unsynced learner records to sync.',
          'syncedCount': 0,
        };
      }

      int syncedCount = 0;
      List<String> errors = [];

      for (var learner in unsyncedLearners) {
        try {
          String? learnerId = learner['learnerId']?.toString();
          if (learnerId == null || learnerId.isEmpty) {
            errors.add(
                'Skipping learner due to missing learnerId: ${learner['Name'] ?? 'Unknown'}');
            if (kDebugMode) {
              debugPrint('DEBUG: ${errors.last}');
            }
            continue;
          }

          String? idNumber = learner['IDNumber']?.toString();
          if (idNumber == null || idNumber.isEmpty) {
            errors.add(
                'Skipping learner due to missing IDNumber: ${learner['Name'] ?? 'Unknown'}');
            if (kDebugMode) {
              debugPrint('DEBUG: ${errors.last}');
            }
            continue;
          }

          if (kDebugMode) {
            debugPrint('DEBUG: Sending request for learner $learnerId');
          }

          var request = http.MultipartRequest(
            'POST',
            Uri.parse(AppConfig.syncOnlineDetailsUrl),
          );

          // Helper function to check if a value should be excluded
          bool shouldExcludeValue(String? value) {
            if (value == null) return true;
            final trimmed = value.trim();
            if (trimmed.isEmpty) return true;
            // Exclude common default/placeholder values
            final excludeValues = [
              'N/A',
              'n/a',
              '1900-01-01',
              '0.0',
              'false',
              'null',
              'NULL',
              'undefined'
            ];
            // Don't exclude '0' as it's a valid value for Age (newborns) and other numeric fields
            return excludeValues.contains(trimmed);
          }

          // Always include required fields
          request.fields['learnerId'] = learnerId;
          request.fields['IDNumber'] = idNumber;
          request.fields['synced'] = '1';

          // Add a special flag to indicate this is a partial update
          request.fields['partial_update'] = 'true';

          // Add optional fields only if they have meaningful values
          final optionalFields = [
            'Title',
            'Name',
            'Surname',
            'DateOfBirth',
            'PhoneNumber',
            'Email',
            'Age',
            'Gender',
            'Race',
            'Language',
            'Disability',
            'AddressLine1',
            'AddressLine2',
            'AddressLine3',
            'PostalCode',
            'KinName',
            'KinRelation',
            'KinContact',
            'SchoolName',
            'SchoolCompletion',
            'SchoolLocation',
            'SchoolGrade',
            'activity_statu',
            'witness_initials',
            'learner_initials',
            'witness_signature',
            'zkteco_left_template',
            'zkteco_right_template',
            'futronic_left_template',
            'futronic_right_template',
            'imagePath'
          ];

          for (final key in optionalFields) {
            final value = learner[key]?.toString();
            if (!shouldExcludeValue(value)) {
              request.fields[key] = value!;
              if (kDebugMode) {
                debugPrint('DEBUG: Including field $key = $value');
              }
            } else {
              if (kDebugMode) {
                debugPrint('DEBUG: Excluding field $key = $value (empty/default value)');
              }
            }
          }

          debugPrint(
              'DEBUG: Final request fields for learner $learnerId (${request.fields.length} fields): ${request.fields}');

          // Add file uploads if they exist
          if (learner['profile_image'] != null &&
              File(learner['profile_image'].toString()).existsSync()) {
            debugPrint(
                'DEBUG: Adding profile_image for $learnerId: ${learner['profile_image']}');
            request.files.add(await http.MultipartFile.fromPath(
              'profile_image',
              learner['profile_image'].toString(),
            ));
          }

          if (learner['signature'] != null &&
              File(learner['signature'].toString()).existsSync()) {
            debugPrint(
                'DEBUG: Adding signature for $learnerId: ${learner['signature']}');
            request.files.add(await http.MultipartFile.fromPath(
              'signature',
              learner['signature'].toString(),
            ));
          }

          if (learner['witness_signature'] != null &&
              File(learner['witness_signature'].toString()).existsSync()) {
            debugPrint(
                'DEBUG: Adding witness_signature for $learnerId: ${learner['witness_signature']}');
            request.files.add(await http.MultipartFile.fromPath(
              'witness_signature',
              learner['witness_signature'].toString(),
            ));
          }

          var response = await request.send().timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              errors.add('Request timed out for learnerId $learnerId');
              if (kDebugMode) {
                debugPrint('DEBUG: ${errors.last}');
              }
              return http.StreamedResponse(const Stream.empty(), 408);
            },
          );

          if (kDebugMode) {
            debugPrint('DEBUG: Response status for $learnerId: ${response.statusCode}');
            debugPrint('DEBUG: Response headers: ${response.headers}');
          }

          String responseBody = await response.stream.bytesToString();
          
          if (kDebugMode) {
            debugPrint('DEBUG: Raw response body for $learnerId: "$responseBody"');
          }

          if (response.statusCode != 200) {
            errors.add(
                'Server error for learnerId $learnerId: Status ${response.statusCode}, Response: $responseBody');
            if (kDebugMode) {
              debugPrint('DEBUG: ${errors.last}');
            }
            continue;
          }

          if (responseBody.isEmpty) {
            errors.add('Empty server response for learnerId $learnerId');
            if (kDebugMode) {
              debugPrint('DEBUG: ${errors.last}');
            }
            continue;
          }

          try {
            Map<String, dynamic> jsonResponse = jsonDecode(responseBody);
            if (jsonResponse['success'] == true) {
              await _markAsSynced(learnerId);
              syncedCount++;
              if (kDebugMode) {
                debugPrint('DEBUG: Successfully synced learner $learnerId');
              }
            } else {
              errors.add(
                  'Server error for learnerId $learnerId: ${jsonResponse['error'] ?? 'Unknown server error'}');
              if (kDebugMode) {
                debugPrint('DEBUG: ${errors.last}');
              }
            }
          } catch (e) {
            errors.add(
                'Failed to parse server response for learnerId $learnerId: $e. Response: $responseBody');
            if (kDebugMode) {
              debugPrint('DEBUG: ${errors.last}');
            }
          }
        } catch (e) {
          errors.add(
              'Error syncing learnerId ${learner['learnerId'] ?? 'unknown'}: $e - Data: $learner');
          if (kDebugMode) {
            debugPrint('DEBUG: ${errors.last}');
          }
        }
      }

      final result = {
        'success': errors.isEmpty,
        'message': errors.isEmpty
            ? 'Synced $syncedCount records successfully'
            : 'Synced $syncedCount records with ${errors.length} errors',
        'syncedCount': syncedCount,
        'errors': errors.isEmpty ? null : errors,
      };
      if (kDebugMode) {
        debugPrint('DEBUG: Sync result: $result');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DEBUG: Sync process failed: $e');
      }
      return {
        'success': false,
        'message': 'Sync failed: $e',
        'syncedCount': 0,
      };
    }
  }

  Future<void> syncSickNotesToServer() async {
    debugPrint("Syncing Sick Notes to server...");
    final serverUrl = AppConfig.syncSickNotesUrl;

    try {
      // Fetch unsynced sick note records from local database
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> unsyncedRecords = await db.query(
        'sick_note',
        where: 'synced = ?',
        whereArgs: [0],
      );

      if (unsyncedRecords.isEmpty) {
        debugPrint("No unsynced sick notes to sync.");
        return;
      }

      debugPrint("Found ${unsyncedRecords.length} unsynced sick note records.");

      // Prepare multipart request for batch sync
      final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      List<Map<String, dynamic>> validRecords = [];
      List<String> localFilePaths = [];

      for (int i = 0; i < unsyncedRecords.length; i++) {
        var record = unsyncedRecords[i];
        debugPrint("Processing sick note record: $record");

        // Check for required fields with null safety
        String? learnerId = record['learner_id']?.toString();
        String? documentPath = record['document_path']?.toString();
        String? practiceName = record['practice_name']?.toString();
        String? medicalPractitioner =
            record['medical_practitioner']?.toString();
        String? practitionerName = record['practitioner_name']?.toString();
        String? dateFrom = record['date_from']?.toString();
        String? dateTo = record['date_to']?.toString();
        String? uploadDate = record['upload_date']?.toString();
        String? status = record['status']?.toString();
        String? rejectionReason = record['rejection_reason']?.toString();

        // Validate required fields (all except rejection_reason)
        if (learnerId == null ||
            documentPath == null ||
            practiceName == null ||
            medicalPractitioner == null ||
            practitionerName == null ||
            dateFrom == null ||
            dateTo == null ||
            uploadDate == null ||
            status == null) {
          debugPrint(
              "Skipping record ${record['note_id']} due to null required fields.");
          continue;
        }

        // Validate document file existence
        try {
          final file = File(documentPath);
          if (!await file.exists()) {
            debugPrint(
                "Document file not found for record ${record['note_id']}: $documentPath");
            continue;
          }

          // Extract filename from document_path
          String fileName = path.basename(documentPath);

          // Add fields to validRecords, excluding 'note_id' and 'synced', using filename for document_path
          validRecords.add({
            'learner_id': learnerId,
            'document_path': fileName,
            'practice_name': practiceName,
            'medical_practitioner': medicalPractitioner,
            'practitioner_name': practitionerName,
            'date_from': dateFrom,
            'date_to': dateTo,
            'upload_date': uploadDate,
            'status': status,
            'rejection_reason': rejectionReason ?? '',
          });

          // Add document file to multipart request using a consistent field name
          request.files.add(await http.MultipartFile.fromPath(
            'document_file[]', // Use 'document_file[]' to group files
            documentPath,
            contentType: MediaType('application', 'pdf'),
            filename: fileName,
          ));
          debugPrint(
              "Added document file for record ${record['note_id']}: $documentPath (filename: $fileName)");

          // Track local file path for potential deletion
          localFilePaths.add(documentPath);
        } catch (e) {
          debugPrint(
              "Error adding document file for record ${record['note_id']}: $e");
          continue;
        }
      }

      if (validRecords.isEmpty) {
        debugPrint("No valid sick note records to sync.");
        return;
      }

      // Add valid records as JSON to the request
      debugPrint("Sending sick note data to server: ${json.encode(validRecords)}");
      request.fields['data'] = json.encode(validRecords);

      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint("Server response status: ${response.statusCode}");
      debugPrint("Server response body: $responseBody");

      if (response.statusCode == 200) {
        try {
          final responseJson = json.decode(responseBody);
          if (responseJson['success'] == true) {
            debugPrint(
                "Batch sync successful for ${validRecords.length} sick note records.");
            // Update sync status for valid records
            await _updateSickNoteSyncedStatus(unsyncedRecords, validRecords);
          } else {
            debugPrint("Batch sync failed: ${responseJson['message']}");
          }
        } catch (e) {
          debugPrint("Error parsing server response: $e");
        }
      } else {
        debugPrint(
            "Batch sync failed. Response: ${response.statusCode}, Body: $responseBody");
      }
    } catch (e) {
      debugPrint("Error syncing sick notes to server: $e");
      rethrow;
    }
  }

// Helper method to update sync status for sick note records
  Future<void> _updateSickNoteSyncedStatus(
    List<Map<String, dynamic>> unsyncedRecords,
    List<Map<String, dynamic>> validRecords,
  ) async {
    final db = await _dbHelper.database;

    // Map valid records to their local IDs for updating
    for (int i = 0; i < validRecords.length; i++) {
      try {
        final localId = unsyncedRecords[i]['note_id'];
        if (localId == null) {
          debugPrint(
              "Skipping record due to missing 'note_id' field: ${unsyncedRecords[i]}");
          continue;
        }

        debugPrint("Marking sick note record $localId as synced.");
        await db.update(
          'sick_note',
          {'synced': 1},
          where: 'note_id = ?',
          whereArgs: [localId],
        );
      } catch (e) {
        debugPrint(
            "Error updating sick note record ${unsyncedRecords[i]['note_id']}: $e");
      }
    }
  }

  Future<void> syncInductionClocking() async {
    final db = await _dbHelper.database;

    isSyncing = true;
    syncMessage = 'Syncing data to the server...';
    notifyListeners();

    try {
      // Only sync current day's records
      final today = DateTime.now().toIso8601String().split('T')[0];
      final List<Map<String, dynamic>> clockingDataList = await db.query(
        'induction_clocking',
        where: 'synced = ? AND clock_date = ?',
        whereArgs: [false, today],
      );

      if (clockingDataList.isEmpty) {
        syncMessage = 'No data to sync!';
        notifyListeners();
        return;
      }

      const maxRetries = 3;
      for (var clockingData in clockingDataList) {
        final clockingId = clockingData['clocking_id'];
        final learnerId = clockingData['learnerId'];
        final clockInTime = clockingData['clock_in_time'];
        final clockOutTime = clockingData['clock_out_time'];
        final contactTime = clockingData['contact_time'];
        final signaturePath =
            clockingData['signature_path'] ?? clockingData['signature'];
        final userLatitude = clockingData['user_latitude'];
        final userLongitude = clockingData['user_longitude'];
        final userAccuracy = clockingData['user_accuracy'];
        final clockDate = clockingData['clock_date'] ??
            DateTime.now().toIso8601String().split('T')[0];

        bool synced = false;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            // Prepare multipart request
            var request = http.MultipartRequest(
              'POST',
              Uri.parse(AppConfig.syncInductionUrl),
            );

            // Add fields
            request.fields['clocking_id'] = clockingId.toString();
            request.fields['learnerId'] = learnerId.toString();
            request.fields['clock_in_time'] = clockInTime ?? '';
            request.fields['clock_out_time'] = clockOutTime ?? '';
            request.fields['contact_time'] = contactTime ?? '';
            request.fields['clock_date'] = clockDate;
            request.fields['user_latitude'] = userLatitude?.toString() ?? '';
            request.fields['user_longitude'] = userLongitude?.toString() ?? '';
            request.fields['user_accuracy'] = userAccuracy?.toString() ?? '';

            // Add signature file if it exists
            if (signaturePath != null && File(signaturePath).existsSync()) {
              var signatureFile = File(signaturePath);
              var signatureStream = http.ByteStream(signatureFile.openRead());
              var signatureLength = await signatureFile.length();
              var extension = path
                  .extension(signaturePath)
                  .toLowerCase()
                  .replaceFirst('.', '');
              var mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';

              var signatureMultipart = http.MultipartFile(
                'signature',
                signatureStream,
                signatureLength,
                filename: path.basename(signaturePath),
                contentType: MediaType.parse(mimeType),
              );
              request.files.add(signatureMultipart);
              debugPrint(
                  'Attempt $attempt: Signature file added: $signaturePath, MIME type: $mimeType');
            } else if (signaturePath != null) {
              debugPrint(
                  'Attempt $attempt: Signature file not found: $signaturePath');
            }

            // Log request details
            debugPrint('Attempt $attempt: Request fields: ${request.fields}');
            debugPrint(
                'Attempt $attempt: Request files: ${request.files.map((f) => f.filename).toList()}');

            // Send request
            final response =
                await request.send().timeout(const Duration(seconds: 30));
            final responseString = await response.stream.bytesToString();

            debugPrint(
                'Attempt $attempt: Server response for clocking_id $clockingId: $responseString (Status: ${response.statusCode})');

            if (response.statusCode == 200) {
              if (responseString.isEmpty) {
                debugPrint(
                    'Attempt $attempt: Empty response received for clocking_id $clockingId');
                syncMessage =
                    'Empty response from server for record $clockingId';
                if (attempt == maxRetries) {
                  syncMessage =
                      'Max retries reached for record $clockingId: Empty response';
                }
                await Future.delayed(const Duration(seconds: 1));
                continue;
              }

              try {
                final responseData = json.decode(responseString);
                if (responseData['status'] == 'success') {
                  await db.update(
                    'induction_clocking',
                    {'synced': true},
                    where: 'clocking_id = ?',
                    whereArgs: [clockingId],
                  );
                  syncMessage = 'Record $clockingId synced successfully!';
                  synced = true;
                  break;
                } else {
                  syncMessage =
                      'Server error for record $clockingId: ${responseData['message']}';
                  if (attempt == maxRetries) {
                    syncMessage =
                        'Max retries reached for record $clockingId: ${responseData['message']}';
                  }
                  await Future.delayed(const Duration(seconds: 1));
                  continue;
                }
              } catch (e) {
                debugPrint(
                    'Attempt $attempt: JSON parse error for clocking_id $clockingId: $e');
                syncMessage =
                    'Invalid response format for record $clockingId: $e';
                if (attempt == maxRetries) {
                  syncMessage =
                      'Max retries reached for record $clockingId: Invalid response';
                }
                await Future.delayed(const Duration(seconds: 1));
                continue;
              }
            } else {
              debugPrint(
                  'Attempt $attempt: Failed for clocking_id $clockingId: Status ${response.statusCode}, Response: $responseString');
              syncMessage =
                  'Failed to sync record $clockingId. Status: ${response.statusCode}, Response: $responseString';
              if (attempt == maxRetries) {
                syncMessage =
                    'Max retries reached for record $clockingId: Status ${response.statusCode}';
              }
              await Future.delayed(const Duration(seconds: 1));
              continue;
            }
          } catch (e) {
            debugPrint('Attempt $attempt: Error for clocking_id $clockingId: $e');
            syncMessage = 'Error syncing record $clockingId: $e';
            if (attempt == maxRetries) {
              syncMessage = 'Max retries reached for record $clockingId: $e';
            }
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }

        if (!synced) {
          syncMessage =
              'Failed to sync record $clockingId after $maxRetries attempts';
          notifyListeners();
        }
      }

      if (syncMessage.contains('Failed') || syncMessage.contains('Error')) {
        // Keep syncMessage as is to reflect the last error
      } else {
        syncMessage = 'All data synced successfully!';
      }
    } catch (e) {
      syncMessage = 'Sync failed: $e';
      debugPrint('Error syncing data: $e');
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncInductionClocking() async {
    try {
      final response =
          await http.get(Uri.parse(AppConfig.syncInductionClockingUrl));

      debugPrint("Response status: ${response.statusCode}");
      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        var decodedData = json.decode(response.body);
        if (decodedData is List) {
          List clockingData = decodedData;
          debugPrint("Fetched ${clockingData.length} records");

          // DON'T clear the local table - preserve local clock-in states
          // await _dbHelper.clearTable('induction_clocking');
          debugPrint(
              "Syncing induction_clocking data without clearing local records");

          // Insert each record
          for (var clocking in clockingData) {
            // Map JSON keys to match table schema if needed
            var mappedClocking = {
              'clocking_id': clocking['clocking_id'],
              'learnerId': clocking['learnerId'] ??
                  clocking['learner_id'], // Handle key mismatch
              'clock_date': clocking['clock_date'],
              'clock_in_time': clocking['clock_in_time'],
              'clock_out_time': clocking['clock_out_time'],
              'contact_time': clocking['contact_time'],
              'signature': clocking['signature'],
              'synced': clocking['synced'] ?? 0, // Default to 0 if missing
              'user_latitude': clocking['user_latitude'],
              'user_longitude': clocking['user_longitude'],
              'user_accuracy': clocking['user_accuracy'],
            };

            // Validate required fields
            if (mappedClocking['clocking_id'] == null ||
                mappedClocking['learnerId'] == null ||
                mappedClocking['clock_date'] == null ||
                mappedClocking['clock_in_time'] == null) {
              debugPrint("Skipping invalid record: $mappedClocking");
              continue;
            }

            debugPrint("Merging record: $mappedClocking");
            try {
              // Check if record exists locally
              final db = await _dbHelper.database;
              final existingRecords = await db.query(
                'induction_clocking',
                where: 'learnerId = ? AND clock_date = ?',
                whereArgs: [
                  mappedClocking['learnerId'],
                  mappedClocking['clock_date']
                ],
              );

              if (existingRecords.isNotEmpty) {
                final existingRecord = existingRecords.first;

                // PRESERVE local clock-in state if learner is currently clocked in
                // Only update if server has more recent complete data
                if (existingRecord['clock_in_time'] != null &&
                    existingRecord['clock_out_time'] == null &&
                    mappedClocking['clock_out_time'] != null) {
                  // Server has clock-out but we have local clock-in without clock-out
                  // This might be auto-generated - DON'T overwrite
                  debugPrint(
                      "PRESERVING local clock-in state for ${mappedClocking['learnerId']} - server has auto clock-out");
                  continue;
                }

                // Update existing record with server data
                await db.update(
                  'induction_clocking',
                  mappedClocking,
                  where: 'learnerId = ? AND clock_date = ?',
                  whereArgs: [
                    mappedClocking['learnerId'],
                    mappedClocking['clock_date']
                  ],
                );
                debugPrint(
                    "Updated existing record for ${mappedClocking['learnerId']}");
              } else {
                // Insert new record
                await _dbHelper.insertData(
                    'induction_clocking', mappedClocking);
                debugPrint("Inserted new record for ${mappedClocking['learnerId']}");
              }
            } catch (e) {
              debugPrint("Error merging record $mappedClocking: $e");
            }
          }
          debugPrint("Synchronized ${clockingData.length} records");
        } else {
          debugPrint(
              "Error: Expected List, got ${decodedData.runtimeType}: $decodedData");
        }
      } else {
        debugPrint(
            "Failed to sync. Status: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error syncing induction_clocking: $e");
    }
  }
}
