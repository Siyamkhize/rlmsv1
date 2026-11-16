import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'config.dart';
import 'database_helper.dart';

/// Learner Confirmation Scanner Page
/// NEW WORKFLOW: 1. Scan register FIRST → 2. Select learners → 3. Confirm and upload
class LearnerConfirmationScannerPage extends StatefulWidget {
  final int facilitatorId;
  final int classId;
  final String className;

  const LearnerConfirmationScannerPage({
    super.key,
    required this.facilitatorId,
    required this.classId,
    required this.className,
  });

  @override
  State<LearnerConfirmationScannerPage> createState() =>
      _LearnerConfirmationScannerPageState();
}

class _LearnerConfirmationScannerPageState
    extends State<LearnerConfirmationScannerPage> {
  // Current date (read-only, auto-set)
  final String _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final String _todayDisplay =
      DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

  // Form state
  File? _scannedDocument;
  List<Map<String, dynamic>> _learners = [];
  Set<int> _selectedLearnerIds = {};
  Set<int> _learnersWithRecords = {}; // Learners who already uploaded today
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isUploading = false;
  bool _isCheckingStatus = false;
  String? _errorMessage;
  String? _successMessage;
  int _pageCount = 0;
  String? _actualClassName; // Fetched class name
  String _searchQuery = ''; // Search filter text
  final TextEditingController _searchController = TextEditingController();

  // Workflow step (1=scan register, 2=select learners, 3=confirm/upload)
  int _currentStep = 1;

  @override
  void initState() {
    super.initState();
    // DON'T load learners on init - wait until after scanning
    // Fetch the actual class name from classID
    _fetchClassName();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Get filtered learners based on search query
  List<Map<String, dynamic>> get _filteredLearners {
    if (_searchQuery.isEmpty) {
      return _learners;
    }

    final query = _searchQuery.toLowerCase();
    return _learners.where((learner) {
      final surname = (learner['Surname'] ?? '').toString().toLowerCase();
      final name = (learner['Name'] ?? '').toString().toLowerCase();
      final idNumber = (learner['IDNumber'] ?? '').toString().toLowerCase();
      final learnerId = (learner['LearnerID'] ?? '').toString().toLowerCase();

      return surname.contains(query) ||
          name.contains(query) ||
          idNumber.contains(query) ||
          learnerId.contains(query);
    }).toList();
  }

  /// Fetch the class name from classID using database
  Future<void> _fetchClassName() async {
    try {
      // Get class name from local database
      final db = await DatabaseHelper().database;
      final classData = await db.query(
        'class',
        where: 'classID = ?',
        whereArgs: [widget.classId.toString()],
      );

      if (classData.isNotEmpty) {
        setState(() {
          _actualClassName =
              classData.first['className']?.toString() ?? widget.className;
        });
      } else {
        setState(() {
          _actualClassName = widget.className;
        });
      }
    } catch (e) {
      // Silently fail - keep using widget.className
      setState(() {
        _actualClassName = widget.className;
      });
    }
  }

  /// Load learners for this class (ONLY called after scanning register)
  Future<void> _loadLearners() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get learners from local database using the same method as clock_in_page
      final dbHelper = DatabaseHelper();
      final learnersData =
          await dbHelper.getLearnersWithClockingData(widget.classId.toString());

      // Convert to List<Map<String, dynamic>>
      List<Map<String, dynamic>> parsedLearners = [];
      for (var learner in learnersData) {
        parsedLearners.add(Map<String, dynamic>.from(learner));
      }

      // Get facilitator_id for status check
      final db = await DatabaseHelper().database;
      final facilitatorResult = await db.query(
        'facilitator',
        columns: ['facilitator_id'],
        where: 'classID = ?',
        whereArgs: [widget.classId.toString()],
        limit: 1,
      );

      if (facilitatorResult.isNotEmpty) {
        final facilitatorId =
            facilitatorResult.first['facilitator_id']?.toString() ?? '';

        // Check status with server to get learners who already uploaded
        final statusData = await _checkSubmissionStatus(facilitatorId);

        if (statusData != null) {
          // Extract learners_with_records
          final learnersWithRecordsData =
              statusData['learners_with_records'] as List<dynamic>?;
          if (learnersWithRecordsData != null) {
            setState(() {
              _learnersWithRecords = learnersWithRecordsData
                  .map((e) => int.parse(e.toString()))
                  .toSet();
            });
            debugPrint(
                '[LOAD_LEARNERS] Learners with records: $_learnersWithRecords');
          }
        }
      }

      setState(() {
        _learners = parsedLearners;
        // Sort by Surname A-Z, then Name A-Z
        _learners.sort((a, b) {
          final surnameA = (a['Surname'] ?? '').toString().toLowerCase();
          final surnameB = (b['Surname'] ?? '').toString().toLowerCase();
          final surnameCompare = surnameA.compareTo(surnameB);

          if (surnameCompare != 0) {
            return surnameCompare;
          }

          // If surnames are equal, sort by Name
          final nameA = (a['Name'] ?? '').toString().toLowerCase();
          final nameB = (b['Name'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load learners: $e';
        _isLoading = false;
      });
    }
  }

  /// Toggle learner selection
  void _toggleLearner(int learnerId) {
    setState(() {
      if (_selectedLearnerIds.contains(learnerId)) {
        _selectedLearnerIds.remove(learnerId);
      } else {
        _selectedLearnerIds.add(learnerId);
      }
    });
  }

  /// Select all learners (excluding those with existing records)
  void _selectAll() {
    setState(() {
      _selectedLearnerIds = _learners
          .map((l) => int.parse(l['LearnerID'].toString()))
          .where((id) => !_learnersWithRecords.contains(id))
          .toSet();
    });
  }

  /// Clear all selections
  void _clearAll() {
    setState(() {
      _selectedLearnerIds.clear();
    });
  }

  /// Scan document using camera scanner (STEP 1 - FIRST ACTION)
  Future<void> _scanDocument() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      // Open document scanner - returns dynamic (can be Map or List)
      final FlutterDocScanner scanner = FlutterDocScanner();
      final dynamic scanResult = await scanner.getScanDocuments(page: 80);

      // DEFENSIVE HANDLING: Scanner can return Map OR List
      List<String> scannedPaths = [];

      if (scanResult is Map) {
        // Map response - extract all String values as file paths
        for (var value in scanResult.values) {
          if (value is String && value.isNotEmpty) {
            scannedPaths.add(value);
          }
        }
      } else if (scanResult is List) {
        // List response - extract all String items as file paths
        for (var item in scanResult) {
          if (item is String && item.isNotEmpty) {
            scannedPaths.add(item);
          }
        }
      }

      // Validate we have at least one path
      if (scannedPaths.isEmpty) {
        setState(() {
          _errorMessage = 'No document was scanned. Please try again.';
          _isScanning = false;
        });
        return;
      }

      // Use the first scanned path
      final String pdfUri = scannedPaths.first;

      // Convert the URI to a File
      final File scannedFile = File(pdfUri);

      // Check if file exists - if not, try to find it in cache
      if (!await scannedFile.exists()) {
        // Scanner might have cleaned up the file - try cache directory
        final cacheDir = Directory(
            '/data/user/0/com.example.rlmss/cache/mlkit_docscan_ui_client/');
        if (await cacheDir.exists()) {
          final files = await cacheDir.list().toList();
          if (files.isNotEmpty) {
            // Find first PDF file
            File? pdfFile;
            for (var f in files) {
              if (f is File && f.path.toLowerCase().endsWith('.pdf')) {
                pdfFile = f;
                break;
              }
            }

            if (pdfFile == null && files.first is File) {
              pdfFile = files.first as File;
            }

            if (pdfFile != null) {
              // Copy to app documents directory for persistence
              final appDocDir = Directory(
                  '/storage/emulated/0/Android/data/com.example.rlmss/files/scanned_registers');
              if (!await appDocDir.exists()) {
                await appDocDir.create(recursive: true);
              }

              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final persistentFile =
                  File('${appDocDir.path}/register_$timestamp.pdf');
              await pdfFile.copy(persistentFile.path);

              setState(() {
                _scannedDocument = persistentFile;
                _pageCount = scannedPaths.length;
                _isScanning = false;
                _successMessage =
                    'Document scanned successfully (${scannedPaths.length} page${scannedPaths.length == 1 ? "" : "s"})';
              });

              // NOW load learners after successful scan
              await _loadLearners();

              // Move to learner selection step
              setState(() {
                _currentStep = 2;
              });
              return;
            }
          }
        }

        setState(() {
          _errorMessage = 'Scanned file not found. Please scan again.';
          _isScanning = false;
        });
        return;
      }

      // File exists - copy it to persistent location
      final appDocDir = Directory(
          '/storage/emulated/0/Android/data/com.example.rlmss/files/scanned_registers');
      if (!await appDocDir.exists()) {
        await appDocDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final persistentFile = File('${appDocDir.path}/register_$timestamp.pdf');
      await scannedFile.copy(persistentFile.path);

      setState(() {
        _scannedDocument = persistentFile;
        _pageCount = scannedPaths.length; // Number of pages/files scanned
        _isScanning = false;
        _successMessage =
            'Document scanned successfully (${scannedPaths.length} page${scannedPaths.length == 1 ? "" : "s"})';
      });

      // NOW load learners after successful scan
      await _loadLearners();

      // Move to learner selection step
      setState(() {
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _errorMessage = 'Scanner error: $e';
      });
    }
  }

  /// Check submission status with server
  Future<Map<String, dynamic>?> _checkSubmissionStatus(
      String facilitatorId) async {
    try {
      final token = await AppConfig.getAuthToken();
      final url = '${AppConfig.buildUrl('check_learner_confirmation_status.php')}?facilitator_id=$facilitatorId&class_id=${widget.classId}&date=$_todayDate';

      debugPrint('[STATUS_CHECK] Calling: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      debugPrint('[STATUS_CHECK] Response: ${response.statusCode}');
      debugPrint('[STATUS_CHECK] Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        debugPrint(
            '[STATUS_CHECK] Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[STATUS_CHECK] Exception: $e');
      return null;
    }
  }

  /// Proceed to confirmation (after selecting learners)
  void _proceedToConfirm() {
    if (_selectedLearnerIds.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one learner';
      });
      return;
    }

    setState(() {
      _currentStep = 3;
      _errorMessage = null;
    });
  }

  /// Upload confirmation
  Future<void> _uploadConfirmation() async {
    // Final validation
    if (_scannedDocument == null) {
      setState(() {
        _errorMessage = 'Please scan the attendance register first';
      });
      return;
    }

    if (_selectedLearnerIds.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one learner';
      });
      return;
    }

    setState(() {
      _isCheckingStatus = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // === STEP 1: CHECK STATUS BEFORE UPLOAD ===
      debugPrint('[UPLOAD] ========== CHECKING STATUS FIRST ==========');

      // Get facilitator_id
      final db = await DatabaseHelper().database;
      final facilitatorResult = await db.query(
        'facilitator',
        columns: ['facilitator_id'],
        where: 'classID = ?',
        whereArgs: [widget.classId.toString()],
        limit: 1,
      );

      if (facilitatorResult.isEmpty) {
        throw Exception(
            'Facilitator not found for this class. Please sync data.');
      }

      final actualFacilitatorId =
          facilitatorResult.first['facilitator_id']?.toString() ??
              widget.facilitatorId.toString();

      debugPrint(
          '[UPLOAD] Checking status for facilitator: $actualFacilitatorId');

      // Check submission status (only for per-learner check now)
      final statusData = await _checkSubmissionStatus(actualFacilitatorId);

      if (statusData == null) {
        throw Exception(
            'Could not check submission status. Please check your connection.');
      }

      // NOTE: We no longer block based on already_submitted
      // Multiple submissions per day are allowed - only per-learner duplicates are prevented

      debugPrint('[UPLOAD] Status check passed - proceeding with upload');

      // === STEP 2: PROCEED WITH UPLOAD ===
      setState(() {
        _isCheckingStatus = false;
        _isUploading = true;
      });

      debugPrint('[UPLOAD] ========== STARTING UPLOAD ==========');
      debugPrint('[UPLOAD] Class ID: ${widget.classId}');
      debugPrint('[UPLOAD] Learners selected: ${_selectedLearnerIds.length}');
      debugPrint('[UPLOAD] Document path: ${_scannedDocument!.path}');

      debugPrint('[UPLOAD] Using facilitator_id: $actualFacilitatorId');

      // Get authentication token
      final token = await AppConfig.getAuthToken();
      debugPrint(
          '[UPLOAD] Token retrieved: ${token != null ? "YES (${token.length} chars)" : "NO"}');

      final url = AppConfig.buildUrl('upload_learner_confirmation.php');
      debugPrint('[UPLOAD] Target URL: $url');

      var request = http.MultipartRequest('POST', Uri.parse(url));
      debugPrint('[UPLOAD] HTTP MultipartRequest created');

      // Add authentication header
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
        debugPrint('[UPLOAD] Authorization header added');
      }

      // Add fields
      request.fields['facilitator_id'] = actualFacilitatorId;
      request.fields['class_id'] = widget.classId.toString();
      request.fields['submission_date'] = _todayDate;
      request.fields['learners_counted'] =
          _selectedLearnerIds.length.toString();
      request.fields['learner_ids'] =
          jsonEncode(_selectedLearnerIds.toList()); // JSON array

      debugPrint('[UPLOAD] Request fields set');
      debugPrint('[UPLOAD]   - facilitator_id: $actualFacilitatorId');
      debugPrint('[UPLOAD]   - class_id: ${widget.classId}');
      debugPrint('[UPLOAD]   - submission_date: $_todayDate');
      debugPrint(
          '[UPLOAD]   - learners_counted: ${_selectedLearnerIds.length}');
      debugPrint(
          '[UPLOAD]   - learner_ids (JSON): ${jsonEncode(_selectedLearnerIds.toList())}');

      // Add scanned document
      debugPrint('[UPLOAD] Adding file from path: ${_scannedDocument!.path}');
      request.files.add(
        await http.MultipartFile.fromPath(
          'pdf_file', // Match PHP expectation
          _scannedDocument!.path,
        ),
      );
      debugPrint('[UPLOAD] File added to request');

      debugPrint('[UPLOAD] Sending request...');
      final streamedResponse = await request.send();
      debugPrint(
          '[UPLOAD] Response received with status: ${streamedResponse.statusCode}');

      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('[UPLOAD] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _successMessage =
                'Successfully uploaded confirmation for ${_selectedLearnerIds.length} learner(s)';
            _isUploading = false;
          });

          // Show success dialog
          _showSuccessDialog();
        } else {
          throw Exception(data['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('[UPLOAD] ========== ERROR OCCURRED ==========');
      debugPrint('[UPLOAD] Error: $e');
      debugPrint('[UPLOAD] Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Upload failed: $e';
        _isCheckingStatus = false;
        _isUploading = false;
      });
    }
  }

  /// Show success dialog
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('Upload Successful'),
          ],
        ),
        content: Text(_successMessage ?? 'Confirmation uploaded successfully'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to previous screen
            },
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Reset for another upload
              setState(() {
                _scannedDocument = null;
                _selectedLearnerIds.clear();
                _successMessage = null;
                _errorMessage = null;
                _currentStep = 1;
                _pageCount = 0;
              });
            },
            child: const Text('Upload Another'),
          ),
        ],
      ),
    );
  }

  /// Build instruction step indicator
  Widget _buildInstructionStep(int stepNum, String text, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isActive
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                      stepNum.toString(),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isActive ? Colors.green.shade900 : Colors.grey.shade700,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learner Confirmation'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Class info card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _actualClassName ?? widget.className,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Text(_todayDisplay),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Instructions
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Instructions',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInstructionStep(
                              1,
                              'Scan the attendance register',
                              _currentStep >= 1),
                          _buildInstructionStep(
                              2,
                              'Select learners who signed the register',
                              _currentStep >= 2),
                          _buildInstructionStep(
                              3, 'Upload confirmation', _currentStep >= 3),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Error message
                  if (_errorMessage != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Success message
                  if (_successMessage != null && _scannedDocument == null)
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: TextStyle(color: Colors.green.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // STEP 1: SCAN REGISTER FIRST
                  if (_currentStep == 1) ...[
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.document_scanner,
                                color: Colors.blue, size: 64),
                            const SizedBox(height: 16),
                            Text(
                              'Scan Register First',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Start by scanning the signed attendance register. After scanning, you will select the learners.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Scan button
                    ElevatedButton.icon(
                      onPressed: _isScanning ? null : _scanDocument,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.document_scanner, size: 36),
                      label: Text(
                        _isScanning
                            ? 'Scanning Register...'
                            : 'Scan Attendance Register',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding:
                            const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  // STEP 2: Learner selection (AFTER SCANNING)
                  if (_currentStep == 2) ...[
                    // Success message - scanned
                    if (_scannedDocument != null)
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Register Scanned!',
                                      style: TextStyle(
                                        color: Colors.green.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '$_pageCount page(s) captured',
                                      style: TextStyle(
                                          color: Colors.green.shade700),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Select Learners Present',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _selectedLearnerIds.isEmpty
                                        ? Colors.grey
                                        : Colors.blue,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_selectedLearnerIds.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _selectAll,
                                    icon: const Icon(Icons.check_box, size: 20),
                                    label: const Text('Select All'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _clearAll,
                                    icon: const Icon(Icons.clear, size: 20),
                                    label: const Text('Clear'),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // ═══════════════════════════════════════════════════════
                            // SEARCH BOX
                            // ═══════════════════════════════════════════════════════
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search by name, surname, or ID...',
                                  prefixIcon: Icon(Icons.search,
                                      color: Colors.blue[700]),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            setState(() {
                                              _searchController.clear();
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.blue[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.blue[200]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: Colors.blue[700]!, width: 2),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                            ),

                            if (_isLoading)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              ..._filteredLearners.map((learner) {
                                final learnerId =
                                    int.parse(learner['LearnerID'].toString());
                                final hasRecord =
                                    _learnersWithRecords.contains(learnerId);
                                final isSelected =
                                    _selectedLearnerIds.contains(learnerId);
                                final firstName = learner['Name'] ??
                                    learner['firstName'] ??
                                    '';
                                final surname = learner['Surname'] ??
                                    learner['surname'] ??
                                    '';
                                final idNumber = learner['IDNumber'] ?? 'N/A';

                                return CheckboxListTile(
                                  value: hasRecord ? false : isSelected,
                                  onChanged: hasRecord
                                      ? null
                                      : (_) => _toggleLearner(learnerId),
                                  title: Text(
                                    '$surname $firstName', // Surname FIRST, then Name
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: hasRecord
                                          ? Colors.grey
                                          : Colors.black,
                                      decoration: hasRecord
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ID: $idNumber',
                                        style: TextStyle(
                                          color: hasRecord
                                              ? Colors.grey
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (hasRecord)
                                        Text(
                                          '(Already recorded for today)',
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                    ],
                                  ),
                                  dense: false,
                                  activeColor: Colors.green,
                                  checkColor: Colors.white,
                                  tileColor: hasRecord
                                      ? Colors.grey.shade100
                                      : (isSelected
                                          ? Colors.green.shade50
                                          : null),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: hasRecord
                                        ? BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1)
                                        : BorderSide.none,
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Proceed button with count
                    ElevatedButton.icon(
                      onPressed: _selectedLearnerIds.isEmpty
                          ? null
                          : _proceedToConfirm,
                      icon: const Icon(Icons.check_circle, size: 24),
                      label: Text(
                        _selectedLearnerIds.isEmpty
                            ? 'Select at least one learner'
                            : 'Confirm ${_selectedLearnerIds.length} Learner${_selectedLearnerIds.length == 1 ? "" : "s"}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedLearnerIds.isEmpty
                            ? Colors.grey
                            : Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  // STEP 3: Confirmation and upload
                  if (_currentStep == 3) ...[
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Ready to Upload',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            _buildSummaryRow(
                                'Class', _actualClassName ?? widget.className),
                            _buildSummaryRow('Date', _todayDisplay),
                            _buildSummaryRow('Register Pages', '$_pageCount'),
                            _buildSummaryRow('Learners Confirmed',
                                '${_selectedLearnerIds.length}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _currentStep = 2),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: (_isUploading || _isCheckingStatus)
                                ? null
                                : _uploadConfirmation,
                            icon: (_isUploading || _isCheckingStatus)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload, size: 24),
                            label: Text(
                              _isCheckingStatus
                                  ? 'Checking Status...'
                                  : (_isUploading
                                      ? 'Uploading...'
                                      : 'Submit Confirmation'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// Build summary row for confirmation step
  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
