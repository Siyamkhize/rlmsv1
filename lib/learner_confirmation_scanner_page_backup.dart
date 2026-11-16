import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'config.dart';

/// Learner Confirmation Upload Page
/// Only allows upload for TODAY's date - no past or future dates
class LearnerConfirmationUploadPage extends StatefulWidget {
  final int facilitatorId;
  final int classId;
  final String className;

  const LearnerConfirmationUploadPage({
    super.key,
    required this.facilitatorId,
    required this.classId,
    required this.className,
  });

  @override
  State<LearnerConfirmationUploadPage> createState() =>
      _LearnerConfirmationUploadPageState();
}

class _LearnerConfirmationUploadPageState
    extends State<LearnerConfirmationUploadPage> {
  // Current date (read-only, auto-set)
  final String _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final String _todayDisplay =
      DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

  // Form state
  File? _selectedPdf;
  List<Map<String, dynamic>> _learners = [];
  Set<int> _selectedLearnerIds = {};
  bool _isLoading = false;
  bool _isUploading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadLearners();
  }

  /// Load learners for this class
  Future<void> _loadLearners() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get authentication token
      final token = await AppConfig.getAuthToken();

      final response = await http.get(
        Uri.parse(
          '${AppConfig.buildUrl('get_learners.php')}?classID=${widget.classId}',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Backend returns 'data' not 'learners'
          final learnersList = data['data'];

          setState(() {
            _learners = List<Map<String, dynamic>>.from(learnersList ?? []);
            _isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load learners');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load learners: $e';
        _isLoading = false;
      });
    }
  }

  /// Pick PDF file - REMOVED (using document scanner instead)
  // This functionality is not used in this version

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

  /// Select all learners
  void _selectAll() {
    setState(() {
      _selectedLearnerIds = _learners.map((l) => l['LearnerID'] as int).toSet();
    });
  }

  /// Clear all selections
  void _clearAll() {
    setState(() {
      _selectedLearnerIds.clear();
    });
  }

  /// Upload confirmation
  Future<void> _uploadConfirmation() async {
    // Validation
    if (_selectedPdf == null) {
      setState(() {
        _errorMessage = 'Please select a PDF file';
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
      _isUploading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final uri = Uri.parse(
        'YOUR_BASE_URL/mobile/upload_learner_confirmation.php',
      );

      final request = http.MultipartRequest('POST', uri);

      // Add form fields
      request.fields['facilitator_id'] = widget.facilitatorId.toString();
      request.fields['class_id'] = widget.classId.toString();
      request.fields['submission_date'] = _todayDate; // Today's date
      request.fields['learner_ids'] = jsonEncode(_selectedLearnerIds.toList());

      // Add PDF file
      request.files.add(
        await http.MultipartFile.fromPath(
          'pdf_file',
          _selectedPdf!.path,
          filename: 'attendance_register.pdf',
        ),
      );

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final result = jsonDecode(responseBody);

      if (result['success'] == true) {
        setState(() {
          _successMessage = result['message'] ?? 'Upload successful!';
          _isUploading = false;

          // Reset form
          _selectedPdf = null;
          _selectedLearnerIds.clear();
        });

        // Show success dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Success'),
                ],
              ),
              content: Text(result['message'] ?? 'Upload successful!'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception(result['message'] ?? 'Upload failed');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Upload failed: $e';
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload Attendance - ${widget.className}'),
        backgroundColor: Colors.blue[800],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ═══════════════════════════════════════════════════════
                  // CURRENT DATE DISPLAY (Read-Only)
                  // ═══════════════════════════════════════════════════════
                  Card(
                    elevation: 4,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[700]!, Colors.blue[500]!],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ATTENDANCE DATE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _todayDisplay,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'TODAY ONLY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // PDF FILE PICKER
                  // ═══════════════════════════════════════════════════════
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Attendance Register PDF *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_selectedPdf != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                border: Border.all(color: Colors.green),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf,
                                      color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedPdf!.path.split('/').last,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        FutureBuilder<int>(
                                          future: _selectedPdf!.length(),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasData) {
                                              final kb = (snapshot.data! / 1024)
                                                  .toStringAsFixed(2);
                                              return Text(
                                                '$kb KB',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _selectedPdf = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                          else
                            // PDF picker removed - using scanner instead
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Please use the Scanner page instead',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              border: Border.all(color: Colors.orange),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info,
                                    color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Use Learner Confirmation Scanner for uploads',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // LEARNER COUNT DISPLAY
                  // ═══════════════════════════════════════════════════════
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            '${_selectedLearnerIds.length}',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          Text(
                            'LEARNERS SELECTED',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // LEARNER LIST
                  // ═══════════════════════════════════════════════════════
                  Card(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.blue[700],
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Select Learners',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _selectAll,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Select All'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _clearAll,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _learners.length,
                            itemBuilder: (context, index) {
                              final learner = _learners[index];
                              final learnerId = learner['LearnerID'] as int;
                              final isSelected =
                                  _selectedLearnerIds.contains(learnerId);

                              return Container(
                                color: index % 2 == 0
                                    ? Colors.grey[50]
                                    : Colors.white,
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (val) => _toggleLearner(learnerId),
                                  title: Text(
                                    '${learner['Surname']}, ${learner['Name']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    learner['IDNumber']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  activeColor: Colors.green,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // ERROR/SUCCESS MESSAGES
                  // ═══════════════════════════════════════════════════════
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_successMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════
                  // SUBMIT BUTTON
                  // ═══════════════════════════════════════════════════════
                  ElevatedButton(
                    onPressed: _isUploading ? null : _uploadConfirmation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isUploading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Uploading...'),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.upload),
                              SizedBox(width: 8),
                              Text(
                                'SUBMIT CONFIRMATION',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
