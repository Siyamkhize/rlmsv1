import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'ArplToolkitModerationPage.dart';
import 'ModeratorPage.dart';
import 'ArplPracticalImageCapturePage.dart';

class ArplModeratorPage extends StatefulWidget {
  final String facilitator_id;

  const ArplModeratorPage({super.key, required this.facilitator_id});

  @override
  _ArplModeratorPageState createState() => _ArplModeratorPageState();
}

class _ArplModeratorPageState extends State<ArplModeratorPage> {
  late Future<List<dynamic>> _classes;
  int _selectedIndex = 0;
  String? _pathwayType;
  String? _ofoNumber;

  @override
  void initState() {
    super.initState();
    print('[ArplModeratorPage] ===== INITIALIZATION =====');
    print('[ArplModeratorPage] Facilitator ID: ${widget.facilitator_id}');
    print('[ArplModeratorPage] Starting fetchClasses...');
    _classes = fetchClasses(widget.facilitator_id);
  }

  Future<List<dynamic>> fetchClasses(String facilitatorId) async {
    try {
      final url = AppConfig.buildUrl('get_classes.php', queryParams: {
        'facilitator_id': facilitatorId,
      });

      print('[ArplModeratorPage] Fetching classes from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['status'] == 'error') {
          throw Exception('Server error: ${data['message']}');
        }

        if (data is List) {
          if (data.isNotEmpty) {
            setState(() {
              String pathway =
                  (data[0]['Project_pathway'] ?? data[0]['learning_pathway'])
                          ?.toString()
                          .toUpperCase() ??
                      '';

              print(
                  '[ArplModeratorPage] DEBUG: Raw pathway from data: "${data[0]['Project_pathway']}"');
              print(
                  '[ArplModeratorPage] DEBUG: Uppercased pathway: "$pathway"');

              try {
                String rawPathway =
                    data[0]['Project_pathway']?.toString() ?? '';
                if (rawPathway.isNotEmpty && rawPathway.startsWith('[')) {
                  List<dynamic> pathwayList = jsonDecode(rawPathway);
                  if (pathwayList.isNotEmpty &&
                      pathwayList[0]['ofo_code'] != null) {
                    _ofoNumber = pathwayList[0]['ofo_code'].toString();
                    print(
                        '[ArplModeratorPage] Extracted OFO Code: $_ofoNumber');
                  }
                }
              } catch (e) {
                print('[ArplModeratorPage] Could not parse OFO code: $e');
              }

              bool isARPL = pathway.contains('ARPL') ||
                  pathway.contains('ELECTRICIAN') ||
                  pathway.contains('BRICKLAYING') ||
                  pathway.contains('BRICKLAYER') ||
                  pathway.contains('PLUMBING') ||
                  pathway.contains('PLUMBER') ||
                  pathway.contains('ELECTRICITY');

              print('[ArplModeratorPage] DEBUG: isARPL check result: $isARPL');

              if (isARPL) {
                _pathwayType = 'ARPL';
              } else {
                _pathwayType = pathway;
              }

              print(
                  '[ArplModeratorPage] Detected Pathway: $_pathwayType (from data: $pathway, isARPL: $isARPL)');
            });
          }
          return data;
        } else {
          throw Exception('Unexpected response format');
        }
      } else {
        throw Exception(
            'Failed to load classes. Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('[ArplModeratorPage] Error fetching classes: $e');
      throw Exception('Failed to load classes. Error: $e');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildContent() {
    if (_pathwayType == 'ARPL') {
      switch (_selectedIndex) {
        case 0:
          return _buildClassesContent();
        case 10:
          return _buildARPLDashboard();
        case 11:
          return ModerationFeedbackPage(facilitatorId: widget.facilitator_id);
        case 12:
          return ModerationReportPage(facilitatorId: widget.facilitator_id);
        case 13:
          return ModerationSamplingPage(facilitatorId: widget.facilitator_id);
        case 14:
          return ModeratorPracticalImagesSelectionPage(
              facilitatorId: widget.facilitator_id);
        case 20:
          return _buildAppealManagementContent();
        case 21:
          return _buildToolkitReviewContent();
        case 22:
          return _buildAppendixReviewContent();
        default:
          return _buildARPLDashboard();
      }
    }

    switch (_selectedIndex) {
      case 0:
        return _buildClassesContent();
      case 1:
        return ModerationFeedbackPage(facilitatorId: widget.facilitator_id);
      case 2:
        return ModerationReportPage(facilitatorId: widget.facilitator_id);
      case 3:
        return ModeratorPracticalImagesSelectionPage(
            facilitatorId: widget.facilitator_id);
      case 4:
        return ModerationSamplingPage(facilitatorId: widget.facilitator_id);
      default:
        return _buildClassesContent();
    }
  }

  Widget _buildARPLDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ARPL Moderator Dashboard',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A)),
          ),
          const SizedBox(height: 8),
          const Text('Recognition of Prior Learning — Moderation Workflow'),
          const SizedBox(height: 24),
          _buildDashboardCard(
            title: 'Assigned Classes',
            icon: Icons.class_,
            color: Colors.blue,
            onTap: () => _onItemTapped(0),
          ),
          _buildDashboardCard(
            title: 'Portfolio Moderation',
            icon: Icons.folder_shared,
            color: const Color(0xFF6A1B9A),
            onTap: () => _onItemTapped(21),
          ),
          _buildDashboardCard(
            title: 'Appendix Review (D,E,F)',
            icon: Icons.fact_check,
            color: Colors.indigo,
            onTap: () => _onItemTapped(22),
          ),
          _buildDashboardCard(
            title: 'Appeal Management',
            icon: Icons.assignment_late,
            color: Colors.orange,
            onTap: () => _onItemTapped(20),
          ),
          _buildDashboardCard(
            title: 'Moderation Feedback',
            icon: Icons.feedback,
            color: Colors.teal,
            onTap: () => _onItemTapped(11),
          ),
          _buildDashboardCard(
            title: 'Moderation Sampling',
            icon: Icons.pie_chart_outline,
            color: Colors.green,
            onTap: () => _onItemTapped(13),
          ),
          _buildDashboardCard(
            title: 'Moderation Report',
            icon: Icons.picture_as_pdf,
            color: Colors.redAccent,
            onTap: () => _onItemTapped(12),
          ),
          _buildDashboardCard(
            title: 'Practical Evidence Images',
            icon: Icons.photo_camera,
            color: Colors.amber,
            onTap: () => _onItemTapped(14),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildClassesContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Moderator ID: ${widget.facilitator_id}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _classes,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No classes found.'));
              } else {
                List<dynamic> classes = snapshot.data!;

                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Project ID')),
                        DataColumn(label: Text('Class ID')),
                        DataColumn(label: Text('Class Name')),
                        DataColumn(label: Text('Learners')),
                        DataColumn(label: Text('Site ID')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: classes.map<DataRow>((classData) {
                        String projectId = classData['project_id'].toString();
                        String classId = classData['classID'].toString();
                        String className = classData['className'] ?? 'Unknown';
                        String numberOfLearners =
                            classData['numberOfLearners'].toString();
                        String siteId = classData['siteID'].toString();

                        return DataRow(cells: [
                          DataCell(Text(projectId)),
                          DataCell(Text(classId)),
                          DataCell(Text(className)),
                          DataCell(Text(numberOfLearners)),
                          DataCell(Text(siteId)),
                          DataCell(
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ArplModeratorClassDetailsPage(
                                      classId: classId,
                                      moderatorId: widget.facilitator_id,
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6A1B9A),
                              ),
                              child: const Text('Moderate'),
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAppealManagementContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appeal Management',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review and manage learner appeals within 1 week of receipt.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            title: 'Appeal Process',
            icon: Icons.info_outline,
            color: Colors.indigo,
            children: const [
              Text(
                  '• Candidate states reason for appeal and forwards to moderator'),
              SizedBox(height: 8),
              Text(
                  '• Moderator calls a meeting within 1 week of receiving appeal'),
              SizedBox(height: 8),
              Text('• Review assessor evidence and decision'),
              SizedBox(height: 8),
              Text('• Record decision and feedback in the toolkit'),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            title: 'Review Assigned Classes for Appeals',
            subtitle: 'Navigate to class list and open learner toolkits',
            icon: Icons.open_in_new,
            color: Colors.blue,
            onTap: () => _onItemTapped(0),
          ),
        ],
      ),
    );
  }

  Widget _buildToolkitReviewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Portfolio Moderation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review assessor Portfolios of Evidence (PoE) for compliance and consistency.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            title: 'Moderation Checklist',
            icon: Icons.verified_user,
            color: Colors.teal,
            children: const [
              Text('• Verify assessment decisions are evidence-based'),
              SizedBox(height: 8),
              Text('• Check Appendix D: Work Environment & Learning'),
              SizedBox(height: 8),
              Text('• Check Appendix E: Practical Observation Ratings'),
              SizedBox(height: 8),
              Text('• Check Appendix F: Knowledge & Practical Assessments'),
              SizedBox(height: 8),
              Text('• Validate Appendix H: Access Recommendation'),
              SizedBox(height: 8),
              Text(
                  '• Confirm Appendix C curriculum coverage matches trade/OFO'),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            title: 'Open Assigned Classes',
            subtitle: 'Browse classes and access individual learner toolkits',
            icon: Icons.class_,
            color: const Color(0xFF6A1B9A),
            onTap: () => _onItemTapped(0),
          ),
        ],
      ),
    );
  }

  Widget _buildAppendixReviewContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appendix Review (D, E, F)',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Deep-dive review of assessor-completed appendices.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            title: 'Appendix D — Work Environment & Learning',
            icon: Icons.work,
            color: Colors.blue,
            children: const [
              Text('• Confirms learner has access to required workplace tools'),
              SizedBox(height: 8),
              Text('• Verifies supervision arrangements and mentorship'),
              SizedBox(height: 8),
              Text('• Checks all YES/NO responses are justified'),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            title: 'Appendix E — Practical Observation',
            icon: Icons.remove_red_eye,
            color: Colors.green,
            children: const [
              Text('• Validates 1-5 rating scale applied consistently'),
              SizedBox(height: 8),
              Text('• Cross-checks remarks with evidence'),
              SizedBox(height: 8),
              Text('• Verifies witness signatures where required'),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            title: 'Appendix F — Knowledge & Practical',
            icon: Icons.article,
            color: Colors.orange,
            children: const [
              Text('• Confirms knowledge question marks align with answer key'),
              SizedBox(height: 8),
              Text('• Validates practical assessment rubric application'),
              SizedBox(height: 8),
              Text('• Verifies total calculations and pass/fail decisions'),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            title: 'Browse Classes to Review Appendices',
            subtitle:
                'Select a class and learner to launch the ARPL Toolkit Viewer',
            icon: Icons.description,
            color: Colors.indigo,
            onTap: () => _onItemTapped(0),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('[ArplModeratorPage] ===== BUILD METHOD =====');
    print('[ArplModeratorPage] _pathwayType: "$_pathwayType"');
    print(
        '[ArplModeratorPage] Will show ${_pathwayType == 'ARPL' ? 'ARPL' : 'DEFAULT'} dashboard');
    print('[ArplModeratorPage] ===========================');

    return Scaffold(
      appBar: AppBar(
          backgroundColor:
              _pathwayType == 'ARPL' ? const Color(0xFF6A1B9A) : Colors.blue,
          title: Text(_pathwayType == 'ARPL'
              ? 'ARPL Moderator Dashboard'
              : 'Moderator Dashboard')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: _pathwayType == 'ARPL'
              ? _buildARPLDrawerItems(context)
              : _buildDefaultDrawerItems(context),
        ),
      ),
      body: _buildContent(),
    );
  }

  List<Widget> _buildARPLDrawerItems(BuildContext context) {
    return [
      const DrawerHeader(
        decoration: BoxDecoration(color: Color(0xFF6A1B9A)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ARPL Moderator',
                style: TextStyle(color: Colors.white, fontSize: 24)),
            SizedBox(height: 6),
            Text('Recognition of Prior Learning',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
      ListTile(
        title: const Text('ARPL Dashboard'),
        selected: _selectedIndex == 10,
        leading: const Icon(Icons.dashboard),
        onTap: () {
          _onItemTapped(10);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Assigned Classes'),
        selected: _selectedIndex == 0,
        leading: const Icon(Icons.class_),
        onTap: () {
          _onItemTapped(0);
          Navigator.pop(context);
        },
      ),
      const Divider(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('ARPL MODERATION',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
      ),
      ListTile(
        title: const Text('Portfolio Moderation'),
        selected: _selectedIndex == 21,
        leading: const Icon(Icons.folder_shared),
        onTap: () {
          _onItemTapped(21);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Appendix Review (D,E,F)'),
        selected: _selectedIndex == 22,
        leading: const Icon(Icons.fact_check),
        onTap: () {
          _onItemTapped(22);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Appeal Management'),
        selected: _selectedIndex == 20,
        leading: const Icon(Icons.assignment_late),
        onTap: () {
          _onItemTapped(20);
          Navigator.pop(context);
        },
      ),
      const Divider(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('MODERATION TOOLS',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
      ),
      ListTile(
        title: const Text('Moderation Feedback'),
        selected: _selectedIndex == 11,
        leading: const Icon(Icons.feedback),
        onTap: () {
          _onItemTapped(11);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Moderation Sampling'),
        selected: _selectedIndex == 13,
        leading: const Icon(Icons.pie_chart_outline),
        onTap: () {
          _onItemTapped(13);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Moderation Report'),
        selected: _selectedIndex == 12,
        leading: const Icon(Icons.picture_as_pdf),
        onTap: () {
          _onItemTapped(12);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Practical Evidence Images'),
        selected: _selectedIndex == 14,
        leading: const Icon(Icons.photo_camera),
        onTap: () {
          _onItemTapped(14);
          Navigator.pop(context);
        },
      ),
    ];
  }

  List<Widget> _buildDefaultDrawerItems(BuildContext context) {
    return [
      const DrawerHeader(
        decoration: BoxDecoration(color: Colors.blue),
        child: Text('Moderator Menu',
            style: TextStyle(color: Colors.white, fontSize: 24)),
      ),
      ListTile(
        title: const Text('Classes'),
        selected: _selectedIndex == 0,
        onTap: () {
          _onItemTapped(0);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Moderation Feedback'),
        selected: _selectedIndex == 1,
        onTap: () {
          _onItemTapped(1);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Moderation Report'),
        selected: _selectedIndex == 2,
        onTap: () {
          _onItemTapped(2);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Practical Evidence Images'),
        selected: _selectedIndex == 3,
        onTap: () {
          _onItemTapped(3);
          Navigator.pop(context);
        },
      ),
      ListTile(
        title: const Text('Moderation Sampling'),
        selected: _selectedIndex == 4,
        onTap: () {
          _onItemTapped(4);
          Navigator.pop(context);
        },
      ),
    ];
  }
}

class ArplModeratorClassDetailsPage extends StatefulWidget {
  final String classId;
  final String moderatorId;

  const ArplModeratorClassDetailsPage({
    super.key,
    required this.classId,
    required this.moderatorId,
  });

  @override
  _ArplModeratorClassDetailsPageState createState() =>
      _ArplModeratorClassDetailsPageState();
}

class _ArplModeratorClassDetailsPageState
    extends State<ArplModeratorClassDetailsPage> {
  late Future<List<dynamic>> _learners;

  @override
  void initState() {
    super.initState();
    _learners = _fetchLearners(widget.classId);
  }

  Future<List<dynamic>> _fetchLearners(String classId) async {
    try {
      final url = AppConfig.buildUrl('get_learners.php', queryParams: {
        'classID': classId,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      print('[ArplModClassDetails] Fetching learners from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        if (response.body.isEmpty ||
            !response.body.trim().startsWith(RegExp(r'[\[\{]'))) {
          throw Exception('Invalid server response');
        }
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('[ArplModClassDetails] Error: $e');
      throw Exception('Failed to load learners: $e');
    }
  }

  Future<String> _resolveOfoForClass() async {
    try {
      final url = AppConfig.buildUrl('get_class_trade_info.php', queryParams: {
        'classID': widget.classId,
      });
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final tradeName = (data['trade_name'] ?? '').toString().toLowerCase();
          if (tradeName.contains('brick') || tradeName.contains('641201'))
            return '641201';
          if (tradeName.contains('plumb') || tradeName.contains('642601'))
            return '642601';
          if (tradeName.contains('electr') || tradeName.contains('671101'))
            return '671101';
        }
      }
    } catch (_) {}
    return '671101';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        title: Text('Moderate Class · ${widget.classId}'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: const Color(0xFF6A1B9A).withOpacity(0.06),
            child: const Row(
              children: [
                Icon(Icons.gavel, color: Color(0xFF6A1B9A)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review each learner\'s ARPL toolkit — tap MODERATE to open toolkit',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _learners,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No learners found'));
                }
                final learners = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: learners.length,
                  itemBuilder: (context, i) {
                    final l = learners[i];
                    final id = l['LearnerID']?.toString() ?? '';
                    final name = l['Name'] ?? '';
                    final surname = l['Surname'] ?? '';
                    final idNo = l['IDNumber'] ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF6A1B9A),
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('$name $surname',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text('ID: $id · IDNo: $idNo',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final ofo = await _resolveOfoForClass();
                                      if (!mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ArplToolkitModerationPage(
                                            learnerID: int.tryParse(id) ?? 0,
                                            classID:
                                                int.tryParse(widget.classId) ??
                                                    0,
                                            ofoNumber: ofo,
                                            moderatorId: widget.moderatorId,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.gavel),
                                    label: const Text('MODERATE TOOLKIT'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6A1B9A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final ofo = await _resolveOfoForClass();
                                      if (!mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ArplToolkitModerationPage(
                                            learnerID: int.tryParse(id) ?? 0,
                                            classID:
                                                int.tryParse(widget.classId) ??
                                                    0,
                                            ofoNumber: ofo,
                                            moderatorId: widget.moderatorId,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.description),
                                    label: const Text('VIEW DATA'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF6A1B9A),
                                      side: const BorderSide(
                                          color: Color(0xFF6A1B9A)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Moderator Practical Images Selection Page (ARPL Only)
class ModeratorPracticalImagesSelectionPage extends StatefulWidget {
  final String facilitatorId;

  const ModeratorPracticalImagesSelectionPage({
    super.key,
    required this.facilitatorId,
  });

  @override
  _ModeratorPracticalImagesSelectionPageState createState() =>
      _ModeratorPracticalImagesSelectionPageState();
}

class _ModeratorPracticalImagesSelectionPageState
    extends State<ModeratorPracticalImagesSelectionPage> {
  late Future<List<dynamic>> _classes;
  String? _selectedClassId;
  Future<List<dynamic>>? _learners;
  String? _selectedOfoNumber;

  @override
  void initState() {
    super.initState();
    _classes = _fetchClasses();
  }

  Future<List<dynamic>> _fetchClasses() async {
    try {
      final url = AppConfig.buildUrl('get_classes.php', queryParams: {
        'facilitator_id': widget.facilitatorId,
      });
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data['status'] == 'error') {
          throw Exception('Server error: ${data['message']}');
        }
      }
      throw Exception('Failed to load classes');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  Future<List<dynamic>> _fetchLearners(String classId) async {
    try {
      final url = AppConfig.buildUrl('get_learners.php', queryParams: {
        'classID': classId,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        if (response.body.isEmpty ||
            !response.body.trim().startsWith(RegExp(r'[\[\{]'))) {
          throw Exception('Invalid server response');
        }
        return jsonDecode(response.body) as List<dynamic>;
      }
      throw Exception('Failed to load learners');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  Future<String> _resolveOfoForClass(String classId) async {
    try {
      final url = AppConfig.buildUrl('get_class_trade_info.php', queryParams: {
        'classID': classId,
      });
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final tradeName = (data['trade_name'] ?? '').toString().toLowerCase();
          if (tradeName.contains('brick') || tradeName.contains('641201'))
            return '641201';
          if (tradeName.contains('plumb') || tradeName.contains('642601'))
            return '642601';
          if (tradeName.contains('electr') || tradeName.contains('671101'))
            return '671101';
        }
      }
    } catch (_) {}
    return '671101'; // default fallback
  }

  void _selectClass(String classId, String? ofoNumber) {
    setState(() {
      _selectedClassId = classId;
      _selectedOfoNumber = ofoNumber;
      _learners = _fetchLearners(classId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        title: const Text('Practical Evidence Images'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Instructions banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF6A1B9A).withOpacity(0.1),
            child: const Row(
              children: [
                Icon(Icons.photo_camera, color: Color(0xFF6A1B9A)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select a class, then select a learner to capture or view practical task evidence images',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Class selection section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<List<dynamic>>(
              future: _classes,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Text('No classes found');
                }

                final classes = snapshot.data!;
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Class',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_),
                  ),
                  value: _selectedClassId,
                  items: classes.map<DropdownMenuItem<String>>((classData) {
                    final classId = classData['classID'].toString();
                    final className = classData['className'] ?? 'Unknown';
                    return DropdownMenuItem(
                      value: classId,
                      child: Text('$classId - $className'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) async {
                    if (newValue != null) {
                      final selectedClass = classes.firstWhere(
                          (c) => c['classID'].toString() == newValue);

                      // Try to extract OFO from Project_pathway
                      String? ofoNumber;
                      try {
                        String rawPathway =
                            selectedClass['Project_pathway']?.toString() ?? '';
                        if (rawPathway.isNotEmpty &&
                            rawPathway.startsWith('[')) {
                          List<dynamic> pathwayList = jsonDecode(rawPathway);
                          if (pathwayList.isNotEmpty &&
                              pathwayList[0]['ofo_code'] != null) {
                            ofoNumber = pathwayList[0]['ofo_code'].toString();
                          }
                        }
                      } catch (e) {
                        print('Could not parse OFO: $e');
                      }

                      // Fallback to API lookup if needed
                      ofoNumber ??= await _resolveOfoForClass(newValue);

                      _selectClass(newValue, ofoNumber);
                    }
                  },
                );
              },
            ),
          ),

          // Learner list section
          if (_learners != null)
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _learners,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No learners found'));
                  }

                  final learners = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: learners.length,
                    itemBuilder: (context, index) {
                      final learner = learners[index];
                      final learnerId = learner['LearnerID']?.toString() ?? '';
                      final name = learner['Name'] ?? '';
                      final surname = learner['Surname'] ?? '';
                      final idNumber = learner['IDNumber'] ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 3,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF6A1B9A),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'L',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            '$name $surname',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('ID: $idNumber'),
                          trailing: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ArplPracticalImageCapturePage(
                                    learnerID: int.tryParse(learnerId) ?? 0,
                                    classID:
                                        int.tryParse(_selectedClassId!) ?? 0,
                                    ofoNumber: _selectedOfoNumber ?? '671101',
                                    role: 'moderator',
                                    userId: widget.facilitatorId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.photo_camera, size: 18),
                            label: const Text('Images'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6A1B9A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          if (_learners == null)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_upward, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Select a class to view learners',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
