import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:signature/signature.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:typed_data';
import 'config.dart';
import 'database_helper.dart';
import 'services/fingerprint_service.dart';

class POECollectionPage extends StatefulWidget {
  final String classID;

  const POECollectionPage({
    super.key,
    required this.classID,
  });

  @override
  _POECollectionPageState createState() => _POECollectionPageState();
}

class _POECollectionPageState extends State<POECollectionPage> {
  List<Map<String, dynamic>> learners = [];
  String selectedItem = 'Select';
  String practitionerFullName = 'Unknown Facilitator';
  String qualificationName = 'No qualification assigned';
  String className = 'N/A';
  String dateAORCreated = DateTime.now().toString().split(' ')[0];
  String selectedDescription = 'POE Submission';
  Uint8List? facilitatorSignature;
  String facilitatorFullName = '';

  TextEditingController studentIdController = TextEditingController();
  TextEditingController studentNameController = TextEditingController();
  TextEditingController classNameController = TextEditingController();
  TextEditingController quantityController = TextEditingController();
  TextEditingController descriptionController = TextEditingController();
  TextEditingController dateReceivedController = TextEditingController();
  TextEditingController practitionerNameController = TextEditingController();
  TextEditingController commentsController = TextEditingController();
  String learnerSignature = '';
  bool received = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _fetchPractitionerAndClassInfo();
    fetchLearners();
    _loadExistingPOESubmissions();
  }

  Future<void> _fetchPractitionerAndClassInfo() async {
    try {
      debugPrint(
          '?? _fetchPractitionerAndClassInfo: Starting with classID = ${widget.classID}');
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // 1. Try to get facilitator info for this class
      final facilitatorQuery = '''
        SELECT 
          f.firstName,
          f.lastName,
          c.className,
          c.qualification_id as class_qual_id,
          s.qualification_id as site_qual_id
        FROM class c
        LEFT JOIN facilitator f ON c.classID = f.classID
        LEFT JOIN sites s ON c.siteID = s.siteID
        WHERE c.classID = ?
      ''';

      final results = await db.rawQuery(facilitatorQuery, [widget.classID]);
      debugPrint('?? _fetchPractitionerAndClassInfo: Raw results = $results');

      if (results.isNotEmpty) {
        final row = results.first;
        debugPrint('?? _fetchPractitionerAndClassInfo: First row = $row');
        setState(() {
          practitionerFullName =
              '${row['firstName'] ?? ''} ${row['lastName'] ?? ''}'.trim();
          if (practitionerFullName.isEmpty) {
            practitionerFullName = 'Unknown Facilitator';
          }
          className = row['className']?.toString() ?? 'Unknown Class';

          // Try to get qualification name
          String? qualId = row['class_qual_id']?.toString() ??
              row['site_qual_id']?.toString();
          if (qualId != null && qualId.isNotEmpty) {
            _fetchQualificationName(qualId);
          }
        });
        debugPrint('? Set practitionerFullName: $practitionerFullName');
        debugPrint('? Set className: $className');
      } else {
        debugPrint('?? _fetchPractitionerAndClassInfo: No results found!');
      }
    } catch (e) {
      debugPrint('? Error fetching practitioner info: $e');
    }
  }

  Future<void> _fetchQualificationName(String qualId) async {
    try {
      debugPrint('?? _fetchQualificationName: Starting with qualId = $qualId');
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final qualQuery =
          'SELECT name FROM qualification WHERE qualification_id = ?';
      final qualResults = await db.rawQuery(qualQuery, [qualId]);
      debugPrint('?? _fetchQualificationName: qualResults = $qualResults');

      if (qualResults.isNotEmpty) {
        setState(() {
          qualificationName = qualResults.first['name']?.toString() ??
              'No qualification assigned';
        });
        debugPrint('? Set qualificationName: $qualificationName');
      }
    } catch (e) {
      debugPrint('? Error fetching qualification name: $e');
    }
  }

  Future<void> _loadExistingPOESubmissions() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // Check if material_receipt_form has POE Collection records
      final results = await db.query(
        'material_receipt_form',
        where: 'class_name = ? AND description = ?',
        whereArgs: [widget.classID, 'POE Collection'],
      );

      for (var result in results) {
        final learnerId = result['student_id_number']?.toString() ?? '';

        final learnerIndex = learners.indexWhere((learner) =>
            learner['learnerID'] == learnerId ||
            learner['IDNumber'] == learnerId);
        if (learnerIndex != -1) {
          learners[learnerIndex]['Received'] = true;
          learners[learnerIndex]['POEStatus'] = 'Collected';
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading existing POE submissions: $e');
    }
  }

  Future<void> fetchLearners() async {
    try {
      debugPrint('? Fetching learners for classID: ${widget.classID}');

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint(
            '? No internet connection. Attempting local database fetch...');
        await fetchLearnerss(widget.classID);
        return;
      }

      debugPrint('?? Internet found. Fetching learners from API...');
      final response = await http.get(Uri.parse(AppConfig.buildUrl(
          'get_poe_collection_status.php?classID=${widget.classID}')));

      if (!context.mounted) return;

      debugPrint('API Response Status: ${response.statusCode}');
      debugPrint('API Response Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
            '? Failed to load learners from API: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      debugPrint('?? Decoded API data: $data');

      final apiData = data['learners'] as List<dynamic>?;

      if (apiData == null || apiData.isEmpty) {
        debugPrint('? No learners found in API response.');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No learners found.')),
        );
        setState(() => learners = []);
        return;
      }

      final processedLearners = <Map<String, dynamic>>[];

      debugPrint('?? Processing ${apiData.length} learners from API...');

      for (var learner in apiData) {
        final idNumber = learner['IDNumber']?.toString() ?? '';
        final poeStatus = learner['POEStatus'] ?? 'Not Submitted';
        final collectionDate = learner['collection_date']?.toString() ?? '';

        debugPrint(
            '?? Learner: ${learner['FullName']} ($idNumber) - POE Status: $poeStatus');

        if (idNumber.isNotEmpty) {
          processedLearners.add({
            'FullName': learner['FullName'] ?? '',
            'IDNumber': idNumber,
            'ClassName': learner['ClassName'] ?? '',
            'Received': poeStatus == 'Collected',
            'Quantity': '1',
            'Date': collectionDate.isNotEmpty
                ? collectionDate.split(' ')[0]
                : DateTime.now().toString().split(' ')[0],
            'Description': 'POE Submission',
            'Signature': null,
            'FacilitatorFullName':
                learner['FacilitatorFullName'] ?? 'Unknown Facilitator',
            'qualification_name':
                learner['qualification_name'] ?? 'No qualification assigned',
            'POEStatus': poeStatus,
            'submission_date': learner['submission_date'],
            'collection_date': learner['collection_date'],
            'learnerID': learner['learnerID'] ?? learner['LearnerID'] ?? '',
          });
        }
      }

      setState(() {
        learners = processedLearners;
      });

      await _loadExistingPOESubmissions();

      debugPrint('? Learners fetched: ${learners.length}');
      debugPrint('Learners: $learners');
    } catch (e) {
      debugPrint('? Error fetching learners: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to fetch learners. Please try again later.')),
      );
    }
  }

  Future<void> fetchLearnerss(String classID) async {
    try {
      final dbHelper = DatabaseHelper();
      final result = await dbHelper.getLearnerss(classID, 'Select');

      debugPrint('Local DB Result: $result');

      if (result.isEmpty) {
        debugPrint('? No learners found in local database.');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No learners found in local database.')),
        );
        setState(() => learners = []);
        return;
      }

      final submittedIds = await getSubmittedLearners('POE Submission');
      debugPrint('Submitted IDs (local): $submittedIds');

      final uniqueLearnersMap = _filterAndFormatLearners(result, submittedIds);

      for (var learner in uniqueLearnersMap.values) {
        final idNumber = learner['IDNumber']?.toString() ?? '';

        if (submittedIds.contains(idNumber)) {
          learner['POEStatus'] = 'Ready for Collection';
          learner['Description'] = 'POE Submission';
        } else {
          learner['POEStatus'] = 'Not Submitted';
          learner['Description'] = 'POE Submission';
        }
      }

      setState(() {
        learners = uniqueLearnersMap.values.toList();
      });

      await _loadExistingPOESubmissions();

      debugPrint('? Local learners fetched: ${learners.length}');
      debugPrint('Local Learners: $learners');
    } catch (e) {
      debugPrint('? Error fetching learners from local database: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error fetching learners from local database.')),
      );
      setState(() => learners = []);
    }
  }

  Future<Set<String>> getSubmittedLearners(String description) async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      final submittedLearners = await db.rawQuery(
        'SELECT student_id_number FROM material_receipt_form WHERE description = ?',
        ['POE Collection'],
      );

      return submittedLearners
          .map((record) => record['student_id_number']?.toString() ?? '')
          .toSet();
    } catch (e) {
      debugPrint('? Error fetching submitted learners: $e');
      return <String>{};
    }
  }

  Map<String, Map<String, dynamic>> _filterAndFormatLearners(
      List<dynamic> apiData, Set<String> submittedIds) {
    final uniqueLearnersMap = <String, Map<String, dynamic>>{};

    for (var learner in apiData) {
      final idNumber = learner['IDNumber']?.toString() ?? '';
      if (idNumber.isNotEmpty) {
        uniqueLearnersMap[idNumber] = {
          'FullName': learner['FullName'] ?? '',
          'IDNumber': idNumber,
          'ClassName': learner['ClassName'] ?? '',
          'Received': false,
          'Quantity': '1',
          'Date': DateTime.now().toString().split(' ')[0],
          'Description': 'POE Submission',
          'Signature': null,
          'FacilitatorFullName': learner['FacilitatorFullName'] ?? '',
          'qualification_name': learner['qualification_name'] ?? '',
          'POEStatus': 'Not Submitted',
          'learnerID': learner['learnerID'] ?? learner['LearnerID'] ?? '',
        };
      }
    }

    return uniqueLearnersMap;
  }

  Future<void> sendData() async {
    final url = AppConfig.buildUrl('save_material_receipt.php');
    debugPrint('?? Sending data to: $url');
    final body = jsonEncode({
      'classID': widget.classID,
      'learners': learners.map((learner) {
        return {
          'Name': learner['FullName'] ?? '',
          'IDNumber': learner['IDNumber'] ?? '',
          'ClassName': learner['ClassName'] ?? '',
          'description': 'POE Submission',
          'subDescription': 'POE Submission',
          'sub_description': 'POE Submission',
          'Received': learner['Received'] ? 'Yes' : 'No',
          'Quantity': learner['Quantity'].toString(),
          'Date': learner['Date'] ?? '',
          'Signature': learner['Signature'] != null
              ? base64Encode(learner['Signature'])
              : '',
          'Description': 'POE Submission',
        };
      }).toList(),
      'facilitator_name': practitionerFullName,
    });

    try {
      debugPrint('?? Request body: $body');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      debugPrint('?? Response Status: ${response.statusCode}');
      debugPrint('?? Response headers: ${response.headers}');
      debugPrint('?? Response Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
            'Server returned status ${response.statusCode}: ${response.body}');
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final dbHelper = DatabaseHelper();
        final db = await dbHelper.database;

        for (var learner in learners) {
          if (learner['Received'] == true && learner['Signature'] != null) {
            String studentId =
                learner['learnerID'] ?? learner['IDNumber'] ?? '';
            String studentName = learner['FullName'] ?? '';
            String className = learner['ClassName'] ?? '';
            String quantityText = learner['Quantity'] ?? '1';
            String description =
                'POE Collection'; // Use POE Collection for local save
            String dateReceived = learner['Date'] ?? '';
            String practitionerName = practitionerFullName;

            final existingRecords = await db.query(
              'material_receipt_form',
              where: 'student_id_number = ? AND description = ?',
              whereArgs: [studentId, description],
            );

            if (existingRecords.isNotEmpty) {
              debugPrint(
                  '?? $studentName already exists locally with description: \'$description\'. Skipping...');
              continue;
            }

            String learnerSignaturePath = await saveSignatureAsPng(
              learner['Signature'],
              'learner_signature_$studentId',
            );

            String receivedText =
                learnerSignaturePath.isNotEmpty ? 'Yes' : 'No';

            Map<String, dynamic> data = {
              'student_id_number': studentId,
              'student_full_name': studentName,
              'class_name': className,
              'received': receivedText,
              'quantity': int.tryParse(quantityText) ?? 1,
              'description': description,
              'date_received': dateReceived,
              'practitioner_full_name': practitionerName,
              'learner_signature': learnerSignaturePath,
              'created_at': DateTime.now().toIso8601String(),
            };

            await db.insert('material_receipt_form', data);
            debugPrint('? Saved $studentName locally after server submission.');
          }
        }

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['message'].contains('already exist')
                ? 'Some learners already exist: ${responseData['message']}'
                : 'POE submissions submitted successfully!'),
          ),
        );

        await fetchLearners();
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to submit data: ${responseData['message']}')),
        );
      }
    } catch (e) {
      debugPrint('? Error submitting form: $e');
      String errorMessage = 'Error submitting form: $e';

      if (e.toString().contains('FormatException')) {
        errorMessage =
            'Server returned invalid response. Please check if the server endpoint exists.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('404')) {
        errorMessage = 'Server endpoint not found. Please contact support.';
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<String> saveSignatureAsPng(
      Uint8List? signatureBytes, String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final signaturesDir = Directory('${appDir.path}/signatures');
      if (!signaturesDir.existsSync()) {
        signaturesDir.createSync(recursive: true);
      }

      final filePath = '${signaturesDir.path}/$fileName.png';
      final file = File(filePath);
      if (signatureBytes != null) {
        await file.writeAsBytes(signatureBytes);
      }
      return filePath;
    } catch (e) {
      debugPrint('Error saving signature: $e');
      return '';
    }
  }

  Future<void> saveMaterialReceiptForm() async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      for (var learner in learners) {
        if (learner['Received'] == true && learner['Signature'] != null) {
          String studentId = learner['learnerID'] ?? learner['IDNumber'] ?? '';
          String studentName = learner['FullName'] ?? '';
          String className = learner['ClassName'] ?? '';
          String quantityText = learner['Quantity'] ?? '1';
          String description =
              'POE Collection'; // Use POE Collection for local save
          String dateReceived = learner['Date'] ?? '';
          String practitionerName = practitionerFullName;

          final existingRecords = await db.query(
            'material_receipt_form',
            where: 'student_id_number = ? AND description = ?',
            whereArgs: [studentId, description],
          );

          if (existingRecords.isNotEmpty) {
            debugPrint(
                '?? $studentName already exists locally with description: \'$description\'. Skipping...');
            continue;
          }

          String learnerSignaturePath = await saveSignatureAsPng(
            learner['Signature'],
            'learner_signature_$studentId',
          );

          String receivedText = learnerSignaturePath.isNotEmpty ? 'Yes' : 'No';

          Map<String, dynamic> data = {
            'student_id_number': studentId,
            'student_full_name': studentName,
            'class_name': className,
            'received': receivedText,
            'quantity': int.tryParse(quantityText) ?? 1,
            'description': description,
            'date_received': dateReceived,
            'practitioner_full_name': practitionerName,
            'learner_signature': learnerSignaturePath,
            'created_at': DateTime.now().toIso8601String(),
          };

          await db.insert('material_receipt_form', data);
          debugPrint('? Saved $studentName locally.');
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POE submissions saved locally!')),
      );

      await fetchLearners();
    } catch (e) {
      debugPrint('? Error saving material receipt form: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving form: $e')),
      );
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return !connectivityResult.contains(ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'Building POE Collection Table with ${learners.length} learners');
    debugPrint('Qualification Name in UI: $qualificationName');
    return Scaffold(
      appBar: AppBar(
        title: const Text('POE Collection'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              itemCount: learners.length,
              itemBuilder: (context, index) {
                final learner = learners[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                learner['FullName'] ?? '',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildStatusIndicator(learner),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ID: ${learner['IDNumber'] ?? ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Class Name',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                controller: TextEditingController(
                                    text: learner['ClassName'] ?? ''),
                                onChanged: (value) =>
                                    learner['ClassName'] = value,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                Checkbox(
                                  value: learner['Received'] ?? false,
                                  onChanged: (value) {
                                    setState(() {
                                      learner['Received'] = value;
                                    });
                                  },
                                ),
                                const Text('Received'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                value:
                                    int.tryParse(learner['Quantity'] ?? '1') ??
                                        1,
                                items: List.generate(
                                    10,
                                    (index) => DropdownMenuItem(
                                          value: index + 1,
                                          child: Text((index + 1).toString()),
                                        )),
                                onChanged: (value) => setState(() {
                                  learner['Quantity'] = value.toString();
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: learner['Date'] != null &&
                                            learner['Date']!.isNotEmpty
                                        ? DateTime.tryParse(
                                                learner['Date'] ?? '') ??
                                            DateTime.now()
                                        : DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (pickedDate != null) {
                                    setState(() {
                                      learner['Date'] = pickedDate
                                          .toIso8601String()
                                          .split('T')[0];
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Date',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 16),
                                  ),
                                  child: Text(
                                    learner['Date'] != null &&
                                            learner['Date']!.isNotEmpty
                                        ? learner['Date']!
                                        : DateTime.now()
                                            .toIso8601String()
                                            .split('T')[0],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          controller: TextEditingController(
                              text: learner['Description'] ?? 'POE Submission'),
                          readOnly: true,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildPOESubmissionButton(learner),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: learners.isEmpty
                  ? null
                  : () async {
                      final isOnline = await _checkConnectivity();
                      if (isOnline) {
                        await sendData();
                      } else {
                        await saveMaterialReceiptForm();
                      }
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Submit All'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(Map<String, dynamic> learner) {
    final poeStatus = learner['POEStatus'] ?? 'Not Submitted';

    debugPrint(
        '?? Building status indicator for ${learner['FullName']} - Status: $poeStatus');

    switch (poeStatus) {
      case 'Collected':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.shade300, width: 1),
          ),
          child: Text(
            'DONE',
            style: TextStyle(
              color: Colors.green.shade700,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 'Ready for Collection':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orange.shade300, width: 1),
          ),
          child: Text(
            'READY',
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 'Not Submitted':
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Text(
            'PENDING',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
    }
  }

  Widget buildCard(String label, String value) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualificationCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Qualification',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8.0),
            Text(
              'Qualification: $qualificationName',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPOEDescriptionCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Description',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Text(
                'POE Submission',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPOESubmissionButton(Map<String, dynamic> learner) {
    final poeStatus = learner['POEStatus'] ?? 'Not Submitted';
    final isReceived = learner['Received'] ?? false;

    debugPrint(
        '?? Building submission button for ${learner['FullName']} - Status: $poeStatus, Received: $isReceived');

    switch (poeStatus) {
      case 'Collected':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'POE Collected',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

      case 'Ready for Collection':
      case 'Not Submitted':
      default:
        return ElevatedButton.icon(
          onPressed: isReceived
              ? () => _showPOESubmissionDialog(context, learner)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isReceived ? Colors.green : Colors.grey,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.fingerprint, size: 20),
          label: Text(
            isReceived ? 'Verify & Collect' : 'Tick "Received" First',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
    }
  }

  Future<void> _showPOESubmissionDialog(
      BuildContext context, Map<String, dynamic> learner) async {
    final FingerprintService fingerprintService = FingerprintService();
    final FutronicService futronicService = FutronicService();

    final facilitatorSignatureController = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    bool isLoading = false;
    bool fingerprintVerified = false;
    bool poeSubmitted = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Add listener to signature controller to update UI when signature changes
          facilitatorSignatureController.addListener(() {
            setDialogState(() {});
          });

          return AlertDialog(
            title: Text('POE Collection - ${learner['FullName']}'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.assignment,
                            color: Colors.green.shade700,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Verify Learner',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Verify the learner\'s fingerprint to collect their POE.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Facilitator Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      enabled: false,
                      controller:
                          TextEditingController(text: practitionerFullName),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Facilitator Digital Signature',
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
                          color: Colors.grey,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Signature(
                        controller: facilitatorSignatureController,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            facilitatorSignatureController.clear();
                          },
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.fingerprint,
                                  color: fingerprintVerified
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Biometric Verification',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                if (fingerprintVerified)
                                  const Icon(Icons.check_circle,
                                      color: Colors.green),
                              ],
                            ),
                            const Divider(),
                            if (!fingerprintVerified) ...[
                              Text(
                                facilitatorSignatureController.isEmpty
                                    ? 'Please provide your signature above, then verify learner fingerprint.'
                                    : 'Now verify the learner\'s fingerprint to complete POE collection.',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: (isLoading ||
                                          facilitatorSignatureController
                                              .isEmpty)
                                      ? null
                                      : () async {
                                          setDialogState(() {
                                            isLoading = true;
                                          });

                                          try {
                                            bool withinRadius =
                                                await _checkLocationAndRadius();

                                            if (!withinRadius) {
                                              setDialogState(() {
                                                isLoading = false;
                                              });
                                              return;
                                            }

                                            final verified =
                                                await _performDirectFingerprintVerification(
                                                    learner,
                                                    fingerprintService,
                                                    futronicService,
                                                    context,
                                                    setDialogState);
                                            if (verified) {
                                              setDialogState(() {
                                                fingerprintVerified = true;
                                                isLoading = false;
                                              });
                                              if (!context.mounted) return false;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      '? Fingerprint verified successfully!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            } else {
                                              setDialogState(() {
                                                isLoading = false;
                                              });
                                              if (!context.mounted) return false;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      '? Fingerprint verification failed'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            setDialogState(() {
                                              isLoading = false;
                                            });
                                            if (!context.mounted) return false;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Error during verification: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.fingerprint),
                                  label:
                                      const Text('Verify Learner Fingerprint'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        facilitatorSignatureController
                                                .isNotEmpty
                                            ? Colors.blue
                                            : Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              if (facilitatorSignatureController.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Provide signature to enable fingerprint verification',
                                    style: TextStyle(
                                        color: Colors.orange, fontSize: 12),
                                  ),
                                )
                            ] else ...[
                              Row(
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Fingerprint verified for ${learner['FullName'] ?? 'Unknown Learner'}',
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
                                  'Processing...',
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
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade700),
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
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              if (fingerprintVerified && !poeSubmitted)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    setDialogState(() {
                      isLoading = true;
                      poeSubmitted = true;
                    });

                    try {
                      Position position = await Geolocator.getCurrentPosition(
                        locationSettings: const LocationSettings(
                          accuracy: LocationAccuracy.high,
                        ),
                      );

                      final facilitatorSignatureBytes =
                          await facilitatorSignatureController.toPngBytes();
                      final facilitatorSignatureBase64 =
                          facilitatorSignatureBytes != null
                              ? base64Encode(facilitatorSignatureBytes)
                              : '';

                      final url =
                          AppConfig.buildUrl('poe_collection_submit.php');

                      if (!context.mounted) return false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                      'Step 1/2: Marking learner as received...')),
                            ],
                          ),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 2),
                        ),
                      );

                      final receiptResponse = await http.post(
                        Uri.parse(url),
                        headers: {
                          'Content-Type': 'application/x-www-form-urlencoded'
                        },
                        body: {
                          'mark_received': '1',
                          'classID': widget.classID.toString(),
                          'received_learners[]':
                              '${learner['IDNumber']?.toString() ?? ''}|${learner['FullName']?.toString() ?? 'Unknown Learner'}|${learner['learnerID']?.toString() ?? learner['LearnerID']?.toString() ?? ''}',
                          'practitioner_full_name':
                              practitionerFullName.toString(),
                          'sub_description': 'POE Submission',
                          'facilitator_signature':
                              facilitatorSignatureBase64.toString(),
                          'date_aor_created':
                              DateTime.now().toIso8601String().split('T')[0],
                        },
                      );

                      if (!context.mounted) return false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                      'Step 2/2: Submitting POE form data...')),
                            ],
                          ),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 2),
                        ),
                      );

                      final formResponse = await http.post(
                        Uri.parse(url),
                        headers: {
                          'Content-Type': 'application/x-www-form-urlencoded'
                        },
                        body: {
                          'save_poe': '1',
                          'classID': widget.classID.toString(),
                          'facilitator_full_name':
                              practitionerFullName.toString(),
                          'representative_full_name': '',
                          'quantity': '1',
                          'facilitator_signature':
                              facilitatorSignatureBase64.toString(),
                          'representative_signature': '',
                          'fingerprint_verified': 'true',
                          'learner_id': (learner['learnerID'] ??
                                  learner['LearnerID'] ??
                                  '')
                              .toString(),
                          'learner_name':
                              (learner['FullName'] ?? 'Unknown Learner')
                                  .toString(),
                          'user_latitude': position.latitude.toString(),
                          'user_longitude': position.longitude.toString(),
                          'user_accuracy': position.accuracy.toString(),
                          'description': 'POE Submission',
                          'subDescription': 'POE Submission',
                          'sub_description': 'POE Submission',
                          'date_aor_created':
                              DateTime.now().toIso8601String().split('T')[0],
                        },
                      );

                      if (receiptResponse.statusCode == 200 &&
                          formResponse.statusCode == 200) {
                        final receiptData = json.decode(receiptResponse.body);
                        final formData = json.decode(formResponse.body);

                        if (receiptData['success'] == true &&
                            formData['success'] == true) {
                          setDialogState(() {
                            isLoading = false;
                          });

                          learner['Signature'] = facilitatorSignatureBytes;
                          learner['Received'] = true;
                          learner['Description'] = 'POE Submission';
                          learner['POEStatus'] = 'Collected';
                          learner['POESubmissionDate'] =
                              DateTime.now().toIso8601String();

                          await _savePOESubmissionLocally(learner);

                          if (!context.mounted) return false;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  '? POE collection completed successfully!'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 3),
                            ),
                          );

                          await Future.delayed(const Duration(seconds: 2));
                          if (mounted) {
                            if (!context.mounted) return false;
                            Navigator.pop(context);
                            setState(() {});
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
                      setDialogState(() {
                        poeSubmitted = false;
                        isLoading = false;
                      });

                      String errorMessage = 'Error submitting POE: ';
                      if (e.toString().contains('SocketException') ||
                          e.toString().contains('NetworkException')) {
                        errorMessage +=
                            'Network connection failed. Please check your internet connection and try again.';
                      } else if (e.toString().contains('TimeoutException')) {
                        errorMessage += 'Request timed out. Please try again.';
                      } else if (e.toString().contains('FormatException')) {
                        errorMessage +=
                            'Invalid server response. Please contact support.';
                      } else {
                        errorMessage += e.toString();
                      }

                      if (!context.mounted) return false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
                  child: const Text('Submit POE Collection'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _checkLocationAndRadius() async {
    // Simplified location check - in real app you would check against site coordinates
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Location services are disabled. Please enable them.')),
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Location permissions are permanently denied. Please enable them in settings.')),
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking location: $e');
      return true; // Allow proceeding even if location check fails
    }
  }

  Future<bool> _performDirectFingerprintVerification(
      Map<String, dynamic> learner,
      FingerprintService fingerprintService,
      FutronicService futronicService,
      BuildContext context,
      void Function(void Function()) setDialogState) async {
    try {
      debugPrint('[POE_COLLECT] Starting direct fingerprint verification...');

      // Get learner ID from learner data
      final learnerId = learner['learnerID'] ?? learner['LearnerID'] ?? 0;
      debugPrint('[POE_COLLECT] Learner ID: $learnerId');

      if (learnerId == 0) {
        debugPrint('[POE_COLLECT] ? Invalid learner ID');
        if (!context.mounted) return false;
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
        debugPrint('[POE_COLLECT] ? Invalid learner ID format');
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Invalid learner ID format. Cannot verify fingerprint.'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      // Get learner templates from database
      debugPrint('[POE_COLLECT] Getting templates from database...');
      final templates = await DatabaseHelper().getAllTemplates(learnerIdInt);
      final scanner = await _detectScanner(fingerprintService, futronicService);
      debugPrint('[POE_COLLECT] Scanner detected: $scanner');

      // Evaluate available templates per scanner
      final hasZkLeft =
          (templates['zkteco_left_template']?.isNotEmpty ?? false);
      final hasZkRight =
          (templates['zkteco_right_template']?.isNotEmpty ?? false);
      final hasFutLeft =
          (templates['futronic_left_template']?.isNotEmpty ?? false);
      final hasFutRight =
          (templates['futronic_right_template']?.isNotEmpty ?? false);

      debugPrint(
          '[POE_COLLECT] Template availability - ZK Left: $hasZkLeft, ZK Right: $hasZkRight, Fut Left: $hasFutLeft, Fut Right: $hasFutRight');

      // If current scanner has no templates but the other scanner does, guide user
      if (scanner == 'futronic' &&
          !(hasFutLeft || hasFutRight) &&
          (hasZkLeft || hasZkRight)) {
        debugPrint(
            '[POE_COLLECT] ? Futronic scanner but only ZKTeco templates');
        if (!context.mounted) return false;
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
        debugPrint(
            '[POE_COLLECT] ? ZKTeco scanner but only Futronic templates');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'This learner\'s fingerprint is enrolled on Futronic. Please use the Futronic scanner or re-enroll on ZKTeco for this learner.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Get template for verification
      String? template;
      if (scanner == 'zkteco') {
        template = templates['zkteco_left_template'] ??
            templates['zkteco_right_template'];
      } else if (scanner == 'futronic') {
        template = templates['futronic_left_template'] ??
            templates['futronic_right_template'];
      }

      if (template == null || template.isEmpty) {
        debugPrint('[POE_COLLECT] ? No templates available');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No fingerprints enrolled for this learner. Please enroll fingerprints first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      // Build guidance message based on available templates for active scanner
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

      debugPrint('[POE_COLLECT] Guidance: $guidance');
      _showProgressDialog(context, guidance);

      // Perform fingerprint verification
      try {
        bool match = false;
        debugPrint(
            '[POE_COLLECT] Starting verification with scanner: $scanner');

        if (scanner == 'zkteco') {
          debugPrint(
              '[POE_COLLECT] ZKTeco verification - Template length: ${template.length}');
          match = await fingerprintService.verify('left', template) ||
              await fingerprintService.verify('right', template);
          debugPrint('[POE_COLLECT] ZKTeco verification result: $match');
        } else if (scanner == 'futronic') {
          try {
            debugPrint('[POE_COLLECT] Attempting Futronic verification');
            final leftTemplate = templates['futronic_left_template'];
            final rightTemplate = templates['futronic_right_template'];
            final hint = (leftTemplate != null && leftTemplate.isNotEmpty)
                ? 'left'
                : 'right';

            debugPrint(
                '[POE_COLLECT] Futronic verification - Left template length: ${leftTemplate?.length ?? 0}, Right template length: ${rightTemplate?.length ?? 0}, Hint: $hint');

            match = await futronicService.verifyBoth(
              hintFinger: hint,
              leftTemplate: leftTemplate,
              rightTemplate: rightTemplate,
            );
            debugPrint('[POE_COLLECT] Futronic verification result: $match');
          } catch (futronicError) {
            debugPrint(
                '[POE_COLLECT] Futronic verification error: $futronicError');
            _hideProgressDialog(context);

            // Provide specific error messages for common Futronic issues
            String errorMessage = 'Fingerprint verification failed';
            if (futronicError.toString().contains('USB_OPEN_FAILED') ||
                futronicError.toString().contains('DEVICE_OPEN_FAILED')) {
              errorMessage =
                  'Scanner connection failed. Please check USB connection and try again.';
            } else if (futronicError.toString().contains('CAPTURE_FAILED')) {
              errorMessage =
                  'Could not capture fingerprint. Please place finger firmly on scanner and try again.';
            } else if (futronicError.toString().contains('Timeout') ||
                futronicError.toString().contains('Timeout')) {
              errorMessage =
                  'Timeout waiting for fingerprint. Please try again.';
            }

            if (!context.mounted) return false;
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
          // No scanner detected
          _hideProgressDialog(context);
          debugPrint('[POE_COLLECT] ? No scanner detected');
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No fingerprint scanner detected. Please connect a scanner.'),
              backgroundColor: Colors.orange,
            ),
          );
          return false;
        }

        _hideProgressDialog(context);
        debugPrint('[POE_COLLECT] Final verification result: $match');

        return match;
      } catch (e) {
        debugPrint('[POE_COLLECT] Verification error: $e');
        _hideProgressDialog(context);
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } catch (e) {
      debugPrint('[POE_COLLECT] Fingerprint verification error: $e');
      _hideProgressDialog(context);
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<String> _detectScanner(FingerprintService fingerprintService,
      FutronicService futronicService) async {
    debugPrint('[POE_COLLECT] Starting scanner detection...');

    // Try ZKTeco first
    try {
      debugPrint('[POE_COLLECT] Trying ZKTeco scanner...');
      final isZkConnected = await fingerprintService.isSensorConnected();
      debugPrint('[POE_COLLECT] ZKTeco result: $isZkConnected');
      if (isZkConnected) {
        debugPrint('[POE_COLLECT] ? ZKTeco scanner detected!');
        return 'zkteco';
      }
    } catch (e) {
      debugPrint('[POE_COLLECT] ZKTeco detection failed: $e');
    }

    // Enhanced Futronic detection with retry
    debugPrint('[POE_COLLECT] ZKTeco not found, trying Futronic...');
    return await _detectFutronicWithRetry(futronicService);
  }

  Future<String> _detectFutronicWithRetry(
      FutronicService futronicService) async {
    const maxAttempts = 3;
    const delays = [500, 1000, 2000]; // Progressive delays

    debugPrint('[POE_COLLECT] Starting Futronic detection with retry...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[POE_COLLECT] Futronic attempt $attempt/$maxAttempts...');
        final isFutronicConnected = await futronicService.isFutronicConnected();
        debugPrint(
            '[POE_COLLECT] Futronic attempt $attempt result: $isFutronicConnected');

        if (isFutronicConnected) {
          debugPrint('[POE_COLLECT] ? Futronic detected on attempt $attempt!');
          return 'futronic';
        }

        // Wait before next attempt (except on last)
        if (attempt < maxAttempts) {
          debugPrint('[POE_COLLECT] Waiting before next attempt...');
          await Future.delayed(Duration(milliseconds: delays[attempt - 1]));
        }
      } catch (e) {
        debugPrint('[POE_COLLECT] Futronic attempt $attempt failed: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }

    debugPrint(
        '[POE_COLLECT] ? No Futronic scanner detected after all attempts');
    return 'none';
  }

  void _showProgressDialog(BuildContext context, String message) {
    if (!context.mounted) return false;
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

  void _hideProgressDialog(BuildContext context) {
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) {
      if (!context.mounted) return false;
      Navigator.of(context).pop();
    }
  }

  Future<void> _savePOESubmissionLocally(Map<String, dynamic> learner) async {
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // Get facilitator signature from learner or use empty
      String? facilitatorSignatureBase64;
      if (learner['Signature'] != null) {
        facilitatorSignatureBase64 = base64Encode(learner['Signature']);
      }

      await db.insert('material_receipt_form', {
        'learnerID': learner['learnerID'] ?? learner['LearnerID'] ?? '',
        'student_id_number': learner['IDNumber'],
        'student_full_name': learner['FullName'],
        'class_name': learner['ClassName'] ?? '',
        'received': 'Yes',
        'quantity': 1,
        'description': 'POE Submission',
        'sub_description': 'POE Submission',
        'date_received': DateTime.now().toIso8601String().split('T')[0],
        'date_aor_created': DateTime.now().toIso8601String().split('T')[0],
        'practitioner_full_name': practitionerFullName,
        'facilitator_signature': facilitatorSignatureBase64 ?? '',
        'learner_signature': '',
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint(
          '? POE submission saved to material_receipt_form for ${learner['FullName']}');
    } catch (e) {
      debugPrint('?? Error saving POE submission locally: $e');
    }
  }
}
