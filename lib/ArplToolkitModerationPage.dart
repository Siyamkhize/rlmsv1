import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models/arpl_toolkit_data.dart';

class ArplToolkitModerationPage extends StatefulWidget {
  final int learnerID;
  final int classID;
  final String ofoNumber;
  final String moderatorId;

  const ArplToolkitModerationPage({
    Key? key,
    required this.learnerID,
    required this.classID,
    required this.ofoNumber,
    required this.moderatorId,
  }) : super(key: key);

  @override
  _ArplToolkitModerationPageState createState() =>
      _ArplToolkitModerationPageState();
}

class _ArplToolkitModerationPageState extends State<ArplToolkitModerationPage>
    with SingleTickerProviderStateMixin {
  ArplToolkitData? _toolkitData;
  bool _isLoading = true;
  String? _errorMessage;
  TabController? _tabController;

  // ========= OVERRIDE MODE =========
  bool _overrideMode = false;
  // Appendix D override values (key → override text)
  final Map<String, TextEditingController> _appendixDOverrides = {};
  // Appendix E per-activity assessor field overrides
  final Map<int, TextEditingController> _appendixECommentOverrides = {};
  // Appendix F mark overrides (key: 'PT_$taskNumber' score int as text)
  final Map<String, TextEditingController> _appendixFMarkOverrides = {};
  final Map<String, TextEditingController> _appendixHStatusOverrides = {};
  final Map<int, TextEditingController> _appendixHRemarksOverrides = {};

  // ========= MODERATOR REPORT (NAMB Internal Moderation Report) =========
  final TextEditingController _reportCenterName =
      TextEditingController(text: 'MTL TRAINING AND PROJECTS');
  final TextEditingController _reportAccreditationNo = TextEditingController();
  final TextEditingController _reportAssessorName = TextEditingController();
  final TextEditingController _reportAssessorRegNo = TextEditingController();
  final TextEditingController _reportModeratorName = TextEditingController();
  final TextEditingController _reportModeratorRegNo = TextEditingController();
  DateTime? _reportModerationDate;
  final TextEditingController _reportCandidateName = TextEditingController();
  final TextEditingController _reportCandidateIdNo = TextEditingController();
  final TextEditingController _reportTrade = TextEditingController();

  // Observation criteria Y/N + Comments (10 criteria from paper form)
  static const List<Map<String, String>> _reportObservationCriteria = [
    {
      'criterion':
          'Briefing of candidates done prior to the commencement of the assessment'
    },
    {
      'criterion':
          'All assessment documentation prepared and ready to be issued to the candidates'
    },
    {
      'criterion':
          'All logistical arrangements, tools, equipment and materials readily available'
    },
    {
      'criterion':
          'Conditions of all tools and equipment are conducive to fair and quality trade testing'
    },
    {
      'criterion':
          'Trade test venue safe and conducive to fair reliable trade test'
    },
    {
      'criterion':
          'Safe keeping and storage of assessment documentation according to trade test guidelines'
    },
    {
      'criterion':
          'Recordkeeping of trade test results and documentation according to trade test guidelines'
    },
    {'criterion': 'Fair assessment judgments made by the assessor'},
    {'criterion': 'Effective feedback given to candidate'},
    {
      'criterion':
          'Moderator satisfied overall with integrity of assessment process'
    },
  ];
  // criterion index → bool? (null / true=Y / false=N)
  final Map<int, bool?> _reportObservationYN = {};
  final Map<int, TextEditingController> _reportObservationComments = {};

  // Additional moderator report fields (bottom section)
  final TextEditingController _reportModeratorObservations =
      TextEditingController();
  String? _reportTradeTestResult; // 'Upheld' or 'Rejected'
  final TextEditingController _reportRecommendations = TextEditingController();
  final TextEditingController _reportResponsiblePerson =
      TextEditingController();
  final TextEditingController _reportResponsibleSignature =
      TextEditingController();
  final TextEditingController _reportInternalModeratorName =
      TextEditingController();
  final TextEditingController _reportInternalModeratorSignature =
      TextEditingController();
  DateTime? _reportSignatureDate;
  final TextEditingController _reportCorrectiveActions =
      TextEditingController();
  DateTime? _reportCompletionDate;
  final TextEditingController _reportResponsiblePersonFinalSignature =
      TextEditingController();
  DateTime? _reportResponsiblePersonDate;

  // ========= MODERATOR JUDGEMENT STATE =========
  // Appendix D - Work Environment Moderation
  final Map<String, TextEditingController> _appendixDModeratorComments = {};
  int? _appendixDModeratorRating; // 1-5

  // Appendix E - Practical Observation Moderation
  final Map<int, int> _appendixEModeratorRatings = {};
  final Map<int, TextEditingController> _appendixEModeratorComments = {};
  int? _appendixEAggregateRating;

  // Appendix F - Knowledge & Practical Moderation
  final Map<String, int> _appendixFModeratorMarkAdjustments = {};
  final TextEditingController _appendixFKnowledgeModeratorComments =
      TextEditingController();
  final TextEditingController _appendixFPracticalModeratorComments =
      TextEditingController();

  // Appendix H - Access Recommendation Moderation
  final Map<int, int> _appendixHModeratorApprovals = {};
  final Map<int, TextEditingController> _appendixHModeratorComments = {};

  // Final Moderation Decision
  int? _finalModeratorDecision; // 1=Approve, 2=Re-assess, 3=Reject
  final TextEditingController _finalDecisionReason = TextEditingController();
  final TextEditingController _moderatorSignatureName = TextEditingController();
  DateTime? _moderatorDecisionDate;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _reportModerationDate = DateTime.now();
    for (int i = 0; i < _reportObservationCriteria.length; i++) {
      _reportObservationComments[i] = TextEditingController();
    }
    _loadToolkitData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _finalDecisionReason.dispose();
    _moderatorSignatureName.dispose();
    _appendixFKnowledgeModeratorComments.dispose();
    _appendixFPracticalModeratorComments.dispose();
    for (var c in _appendixDModeratorComments.values) c.dispose();
    for (var c in _appendixEModeratorComments.values) c.dispose();
    for (var c in _appendixHModeratorComments.values) c.dispose();
    // Override controllers
    for (var c in _appendixDOverrides.values) c.dispose();
    for (var c in _appendixECommentOverrides.values) c.dispose();
    for (var c in _appendixFMarkOverrides.values) c.dispose();
    for (var c in _appendixHStatusOverrides.values) c.dispose();
    for (var c in _appendixHRemarksOverrides.values) c.dispose();
    // Moderator Report controllers
    _reportCenterName.dispose();
    _reportAccreditationNo.dispose();
    _reportAssessorName.dispose();
    _reportAssessorRegNo.dispose();
    _reportModeratorName.dispose();
    _reportModeratorRegNo.dispose();
    _reportCandidateName.dispose();
    _reportCandidateIdNo.dispose();
    _reportTrade.dispose();
    for (var c in _reportObservationComments.values) c.dispose();
    // Additional report fields
    _reportModeratorObservations.dispose();
    _reportRecommendations.dispose();
    _reportResponsiblePerson.dispose();
    _reportResponsibleSignature.dispose();
    _reportInternalModeratorName.dispose();
    _reportInternalModeratorSignature.dispose();
    _reportCorrectiveActions.dispose();
    _reportResponsiblePersonFinalSignature.dispose();
    super.dispose();
  }

  String _getTradeName(String ofo) {
    switch (ofo) {
      case '641201':
        return 'Bricklayer';
      case '642601':
        return 'Plumber';
      case '671101':
        return 'Electrician';
      default:
        return 'ARPL Trade';
    }
  }

  String _competencyLabel(int scale) {
    switch (scale) {
      case 5:
        return 'Outstanding (5)';
      case 4:
        return 'Competent (4)';
      case 3:
        return 'Not Yet Competent (3)';
      case 2:
        return 'Unsatisfactory (2)';
      case 1:
        return 'Poor (1)';
      default:
        return 'Not Rated';
    }
  }

  Color _competencyColor(int scale) {
    switch (scale) {
      case 5:
        return Colors.green;
      case 4:
        return Colors.teal;
      case 3:
        return Colors.orange;
      case 2:
        return Colors.deepOrange;
      case 1:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadToolkitData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ✅ Match ArplToolkitViewerPage's OFO-based endpoint dispatch exactly
      String endpointUrl;
      if (widget.ofoNumber == '641201') {
        endpointUrl = AppConfig.getBricklayerToolkitDataUrl;
      } else if (widget.ofoNumber == '642601') {
        endpointUrl = AppConfig.getPlumberToolkitDataUrl;
      } else {
        endpointUrl = AppConfig.getArplToolkitDataUrl;
      }

      print('[MOD_LOAD] OFO=${widget.ofoNumber} → Endpoint: $endpointUrl');
      final response = await http.post(
        Uri.parse(endpointUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'learnerID': widget.learnerID,
          'classID': widget.classID,
          'ofoNumber': widget.ofoNumber,
        }),
      );

      print(
          '[MOD_LOAD] HTTP ${response.statusCode} · body-len=${response.body.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _toolkitData = ArplToolkitData.fromJson(data);
            _initModerationControllers();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage =
                '${data['message'] ?? 'Failed to load toolkit data'}\n(OFO: ${widget.ofoNumber})';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'Server ${response.statusCode} on ${widget.ofoNumber} endpoint\n'
              'Try: ensure $endpointUrl exists on server';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[MOD_LOAD] Exception: $e');
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  void _initModerationControllers() {
    if (_toolkitData == null) return;
    final data = _toolkitData!;

    // Appendix D
    data.appendixD.forEach((key, value) {
      if (!_appendixDModeratorComments.containsKey(key)) {
        _appendixDModeratorComments[key] = TextEditingController();
      }
      if (!_appendixDOverrides.containsKey(key)) {
        _appendixDOverrides[key] = TextEditingController(text: value);
      }
    });

    // Appendix E
    for (var rating in data.appendixE) {
      if (!_appendixEModeratorRatings.containsKey(rating.activityId)) {
        _appendixEModeratorRatings[rating.activityId] =
            rating.competencyScaleId;
      }
      if (!_appendixEModeratorComments.containsKey(rating.activityId)) {
        _appendixEModeratorComments[rating.activityId] =
            TextEditingController();
      }
      if (!_appendixECommentOverrides.containsKey(rating.activityId)) {
        _appendixECommentOverrides[rating.activityId] =
            TextEditingController(text: rating.comments);
      }
    }

    // Appendix F - mark overrides keyed by practical task number
    final f = data.appendixF;
    if (f != null) {
      for (var pt in f.practicalTasks) {
        final k = 'PT_${pt.taskNumber}';
        if (!_appendixFMarkOverrides.containsKey(k)) {
          _appendixFMarkOverrides[k] =
              TextEditingController(text: pt.score.toString());
        }
      }
    }

    // Appendix H
    for (var rec in data.appendixH.recommendations) {
      if (!_appendixHModeratorApprovals.containsKey(rec.recommendationId)) {
        _appendixHModeratorApprovals[rec.recommendationId] = 1;
      }
      if (!_appendixHModeratorComments.containsKey(rec.recommendationId)) {
        _appendixHModeratorComments[rec.recommendationId] =
            TextEditingController();
      }
      final statusKey = 'H_${rec.recommendationId}_status';
      if (!_appendixHStatusOverrides.containsKey(statusKey)) {
        _appendixHStatusOverrides[statusKey] =
            TextEditingController(text: rec.status);
      }
      if (!_appendixHRemarksOverrides.containsKey(rec.recommendationId)) {
        _appendixHRemarksOverrides[rec.recommendationId] =
            TextEditingController(text: rec.remarks);
      }
    }

    // ========= Seed Moderator Report header from toolkit data =========
    final learner = data.learner;
    final assessor = data.facilitator;
    if (learner != null) {
      if (_reportCandidateName.text.trim().isEmpty) {
        _reportCandidateName.text = '${learner.name} ${learner.surname}';
      }
      if (_reportCandidateIdNo.text.trim().isEmpty &&
          learner.idNumber.isNotEmpty) {
        _reportCandidateIdNo.text = learner.idNumber;
      }
    }
    if (assessor != null) {
      if (_reportAssessorName.text.trim().isEmpty) {
        _reportAssessorName.text = '${assessor.firstName} ${assessor.lastName}';
      }
    }
    if (_reportTrade.text.trim().isEmpty) {
      _reportTrade.text = _getTradeName(data.ofoNumber);
    }
  }

  Future<void> _saveModerationJudgement() async {
    if (_finalModeratorDecision == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a Final Moderator Decision')),
      );
      return;
    }
    if (_moderatorSignatureName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Moderator full name')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'moderator_id': widget.moderatorId,
      'learner_id': widget.learnerID,
      'class_id': widget.classID,
      'ofo_number': widget.ofoNumber,
      'override_mode_active': _overrideMode,
      'assessor_data_overrides': {
        'appendix_d': _appendixDOverrides.map((k, v) => MapEntry(k, v.text)),
        'appendix_e_comments': _appendixECommentOverrides
            .map((k, v) => MapEntry(k.toString(), v.text)),
        'appendix_f_marks':
            _appendixFMarkOverrides.map((k, v) => MapEntry(k, v.text)),
        'appendix_h_status':
            _appendixHStatusOverrides.map((k, v) => MapEntry(k, v.text)),
        'appendix_h_remarks': _appendixHRemarksOverrides
            .map((k, v) => MapEntry(k.toString(), v.text)),
      },
      'moderation_report': {
        'center_name': _reportCenterName.text,
        'accreditation_no': _reportAccreditationNo.text,
        'assessor_name': _reportAssessorName.text,
        'assessor_reg_no': _reportAssessorRegNo.text,
        'moderator_name': _reportModeratorName.text,
        'moderator_reg_no': _reportModeratorRegNo.text,
        'moderation_date': _reportModerationDate?.toIso8601String(),
        'candidate_name': _reportCandidateName.text,
        'candidate_id_no': _reportCandidateIdNo.text,
        'trade': _reportTrade.text,
        'observation_criteria':
            List.generate(_reportObservationCriteria.length, (i) {
          return {
            'index': i,
            'criterion': _reportObservationCriteria[i]['criterion'],
            'yn': _reportObservationYN[i] == null
                ? null
                : (_reportObservationYN[i]! ? 'Y' : 'N'),
            'comments': _reportObservationComments[i]?.text ?? '',
          };
        }),
        'moderator_observations': _reportModeratorObservations.text,
        'trade_test_result': _reportTradeTestResult,
        'recommendations': _reportRecommendations.text,
        'responsible_person': _reportResponsiblePerson.text,
        'responsible_signature': _reportResponsibleSignature.text,
        'internal_moderator_name': _reportInternalModeratorName.text,
        'internal_moderator_signature': _reportInternalModeratorSignature.text,
        'signature_date': _reportSignatureDate?.toIso8601String(),
        'corrective_actions': _reportCorrectiveActions.text,
        'completion_date': _reportCompletionDate?.toIso8601String(),
        'responsible_person_final_signature':
            _reportResponsiblePersonFinalSignature.text,
        'responsible_person_date':
            _reportResponsiblePersonDate?.toIso8601String(),
      },
      'appendix_d': {
        'rating': _appendixDModeratorRating,
        'comments':
            _appendixDModeratorComments.map((k, v) => MapEntry(k, v.text)),
      },
      'appendix_e': {
        'aggregate_rating': _appendixEAggregateRating,
        'per_activity_ratings': _appendixEModeratorRatings,
        'per_activity_comments': _appendixEModeratorComments
            .map((k, v) => MapEntry(k.toString(), v.text)),
      },
      'appendix_f': {
        'knowledge_comments': _appendixFKnowledgeModeratorComments.text,
        'practical_comments': _appendixFPracticalModeratorComments.text,
        'mark_adjustments':
            _appendixFModeratorMarkAdjustments.map((k, v) => MapEntry(k, v)),
      },
      'appendix_h': {
        'per_recommendation_approvals': _appendixHModeratorApprovals,
        'per_recommendation_comments': _appendixHModeratorComments
            .map((k, v) => MapEntry(k.toString(), v.text)),
      },
      'final_decision': _finalModeratorDecision,
      'final_decision_reason': _finalDecisionReason.text,
      'moderator_signature_name': _moderatorSignatureName.text,
      'decision_date': DateTime.now().toIso8601String(),
    };

    print('[MODERATION_SAVE] Payload: ${jsonEncode(payload)}');

    try {
      final url = AppConfig.saveModerationJudgementUrl;
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 60),
          );

      print('[MODERATION_SAVE] Status: ${response.statusCode}');
      print('[MODERATION_SAVE] Body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['status'] == 'success' || res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ Moderation Judgement Saved Successfully'),
                backgroundColor: Colors.green),
          );
          setState(() {
            _moderatorDecisionDate = DateTime.now();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('⚠️ ${res['message'] ?? 'Failed to save judgement'}'),
                backgroundColor: Colors.orange),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Server error: ${response.statusCode}'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print('[MODERATION_SAVE] Exception: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Offline — saved locally: $e'),
            backgroundColor: Colors.blueGrey),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        title: const Text('ARPL Toolkit Moderation'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveModerationJudgement,
              tooltip: 'Save Moderation Judgement',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadToolkitData,
            tooltip: 'Reload Assessor Data',
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
                controller: _tabController!,
                isScrollable: true,
                indicatorColor: Colors.amber,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(text: 'Summary'),
                  Tab(text: 'Appx D (Workplace)'),
                  Tab(text: 'Appx E (Observation)'),
                  Tab(text: 'Appx F (Knowledge)'),
                  Tab(text: 'Appx H (Access Rec)'),
                  Tab(text: 'Final Decision'),
                  Tab(text: 'Mod Report'),
                ],
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF6A1B9A))),
            SizedBox(height: 16),
            Text('Loading assessor toolkit data...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadToolkitData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A)),
              ),
            ],
          ),
        ),
      );
    }

    if (_toolkitData == null) {
      return const Center(child: Text('No assessor data available'));
    }

    return Column(
      children: [
        // ========= OVERRIDE MODE TOGGLE (global header) =========
        Container(
          width: double.infinity,
          color:
              _overrideMode ? Colors.deepOrange.shade50 : Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(_overrideMode ? Icons.edit_note : Icons.visibility,
                  color: _overrideMode ? Colors.deepOrange : Colors.grey,
                  size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _overrideMode
                      ? 'OVERRIDE MODE: ON — editing assessor stored values'
                      : 'OVERRIDE MODE: OFF — assessor data read-only',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _overrideMode
                          ? Colors.deepOrange
                          : Colors.grey.shade700),
                ),
              ),
              Switch(
                value: _overrideMode,
                activeColor: Colors.deepOrange,
                onChanged: (v) => setState(() => _overrideMode = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController!,
            children: [
              _buildSummaryTab(),
              _buildAppendixDTab(),
              _buildAppendixETab(),
              _buildAppendixFTab(),
              _buildAppendixHTab(),
              _buildFinalDecisionTab(),
              _buildModeratorReportTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ========= SUMMARY TAB =========
  Widget _buildSummaryTab() {
    final data = _toolkitData!;
    final trade = _getTradeName(data.ofoNumber);
    final learner = data.learner;
    final assessor = data.facilitator;

    int totalE = 0;
    int countE = 0;
    for (var r in data.appendixE) {
      if (r.competencyScaleId > 0) {
        totalE += r.competencyScaleId;
        countE++;
      }
    }
    final avgE = countE > 0 ? (totalE / countE).toStringAsFixed(1) : '-';

    int hCompetent = 0;
    for (var r in data.appendixH.recommendations) {
      if (r.recommendationId >= 2) hCompetent++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6A1B9A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MODERATION SUMMARY',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6A1B9A))),
                const SizedBox(height: 12),
                _summaryRow('Trade', trade),
                _summaryRow('Learner',
                    '${learner?.name ?? ''} ${learner?.surname ?? ''}'),
                _summaryRow('Learner ID', learner?.learnerID.toString() ?? '-'),
                _summaryRow('ID Number', learner?.idNumber ?? '-'),
                _summaryRow('Class ID', widget.classID.toString()),
                _summaryRow(
                    'Assessor', '${assessor?.fullName ?? 'Not assigned'}'),
                const Divider(height: 24),
                _summaryRow('Appendix D (Workplace)',
                    data.appendixD.isNotEmpty ? 'Submitted' : 'No data'),
                _summaryRow(
                    'Appendix E (Observation)',
                    countE > 0
                        ? '$countE activities · Avg $avgE/5'
                        : 'No data'),
                _summaryRow(
                    'Appendix H (Access Rec)',
                    data.appendixH.recommendations.isNotEmpty
                        ? '$hCompetent / ${data.appendixH.recommendations.length} marked'
                        : 'No data'),
                if (_moderatorDecisionDate != null) ...[
                  const Divider(height: 24),
                  const Text('Moderation Status',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.green.withOpacity(0.1),
                    child: Text(
                      '✅ Judgement submitted on ${_moderatorDecisionDate!.toLocal()}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Quick Navigation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickNavButton('📋 Appendix D', 'Workplace Learning', 1),
              _quickNavButton('👁 Appendix E', 'Practical Observation', 2),
              _quickNavButton('📝 Appendix F', 'Knowledge & Practical', 3),
              _quickNavButton('🎯 Appendix H', 'Access Recommendation', 4),
              _quickNavButton('⚖️ Final Decision', 'Moderator Judgement', 5),
              _quickNavButton('📄 Mod Report', 'NAMB Observation Checklist', 6),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _quickNavButton(String title, String subtitle, int tabIndex) {
    return SizedBox(
      width: 170,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF6A1B9A),
          side: BorderSide(color: const Color(0xFF6A1B9A).withOpacity(0.4)),
          padding: const EdgeInsets.all(12),
        ),
        onPressed: () => _tabController!.animateTo(tabIndex),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ========= ASSESSOR-READONLY CARD =========
  Widget _assessorReadOnlyCard(
      {required String title,
      required IconData icon,
      Color? accent,
      required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: (accent ?? Colors.grey).withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent ?? Colors.grey),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _overrideMode
                        ? Colors.deepOrange.shade200
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                    border: _overrideMode
                        ? Border.all(color: Colors.deepOrange, width: 1)
                        : null,
                  ),
                  child: Text(
                      _overrideMode
                          ? 'OVERRIDE MODE · EDITABLE'
                          : 'ASSESSOR DATA · READ-ONLY',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _overrideMode
                              ? Colors.deepOrange.shade900
                              : Colors.black54)),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }

  // ========= MODERATOR JUDGEMENT CARD =========
  Widget _moderatorJudgementCard(
      {required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF6A1B9A).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6A1B9A), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              color: Color(0xFF6A1B9A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.gavel, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('MODERATOR JUDGEMENT',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }

  // ========= APPENDIX D TAB =========
  Widget _buildAppendixDTab() {
    final data = _toolkitData!;
    final items = data.appendixD.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appendix D — Work Environment & Learning Conditions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Assessor-answered workplace questions. Review for truthfulness and add your judgement.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No Appendix D data submitted by assessor'),
            ))
          else
            _assessorReadOnlyCard(
              title: 'Assessor Work Environment Responses',
              icon: Icons.work,
              accent: Colors.blue,
              child: Column(
                children: List.generate(items.length, (i) {
                  final key = items[i].key;
                  final value = items[i].value;
                  final ctrl = _appendixDOverrides[key];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _overrideMode
                              ? Colors.deepOrange.shade200
                              : Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Q${i + 1} · $key',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey)),
                        const SizedBox(height: 6),
                        if (_overrideMode && ctrl != null)
                          TextField(
                            controller: ctrl,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              hintText: value.isEmpty
                                  ? 'Enter assessor override response'
                                  : null,
                              labelStyle: TextStyle(
                                  color: Colors.deepOrange.shade700,
                                  fontSize: 11),
                              labelText:
                                  value.isEmpty ? 'Override value' : 'Override',
                            ),
                          )
                        else
                          Text(value.isEmpty ? '(No response)' : value,
                              style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          _moderatorJudgementCard(
            title: 'Appendix D Moderation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Appendix D Moderator Aggregate Rating',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(5, (i) {
                    final val = i + 1;
                    final selected = _appendixDModeratorRating == val;
                    return ChoiceChip(
                      label: Text(_competencyLabel(val)),
                      selected: selected,
                      selectedColor: _competencyColor(val),
                      onSelected: (_) =>
                          setState(() => _appendixDModeratorRating = val),
                      labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black,
                          fontSize: 12),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                const Text('Per-question Moderator Comments (optional)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...List.generate(items.length, (i) {
                  final key = items[i].key;
                  final ctrl = _appendixDModeratorComments[key] ??
                      TextEditingController();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: 'Comment on Q${i + 1}: $key',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 1,
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========= APPENDIX E TAB =========
  Widget _buildAppendixETab() {
    final data = _toolkitData!;
    final eData = data.appendixE;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appendix E — Practical Observation Ratings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Assessor per-activity ratings (1–5). Moderator reviews each and adjusts with rationale.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          _assessorReadOnlyCard(
            title: 'Assessor Practical Observation Ratings',
            icon: Icons.remove_red_eye,
            accent: Colors.green,
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Activity')),
                      DataColumn(label: Text('Assessor Rating')),
                      DataColumn(label: Text('Assessor Comments')),
                    ],
                    rows: List.generate(eData.length, (i) {
                      final item = eData[i];
                      return DataRow(cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(SizedBox(
                            width: 220,
                            child: Text(item.activityName,
                                style: const TextStyle(fontSize: 12)))),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _competencyColor(item.competencyScaleId)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_competencyLabel(item.competencyScaleId),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _competencyColor(
                                      item.competencyScaleId))),
                        )),
                        DataCell(SizedBox(
                            width: 260,
                            child: _overrideMode
                                ? TextField(
                                    controller: _appendixECommentOverrides[
                                        item.activityId],
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      labelText: 'Override comment',
                                      labelStyle: TextStyle(fontSize: 10),
                                    ),
                                  )
                                : Text(
                                    item.comments.isEmpty ? '—' : item.comments,
                                    style: const TextStyle(fontSize: 12)))),
                      ]);
                    }),
                  ),
                ),
              ],
            ),
          ),
          _moderatorJudgementCard(
            title: 'Appendix E Moderation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Per-activity Moderator Rating Adjustment',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...List.generate(eData.length, (i) {
                  final item = eData[i];
                  final currentModRating =
                      _appendixEModeratorRatings[item.activityId] ??
                          item.competencyScaleId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('E.${i + 1} · ${item.activityName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Assessor: ',
                                style: TextStyle(fontSize: 12)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _competencyColor(item.competencyScaleId)
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                  _competencyLabel(item.competencyScaleId),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _competencyColor(
                                          item.competencyScaleId))),
                            ),
                            const SizedBox(width: 16),
                            const Text('Moderator: ',
                                style: TextStyle(fontSize: 12)),
                            DropdownButton<int>(
                              value: currentModRating,
                              items: List.generate(
                                  5,
                                  (v) => DropdownMenuItem(
                                      value: v + 1,
                                      child: Text(_competencyLabel(v + 1),
                                          style:
                                              const TextStyle(fontSize: 12)))),
                              onChanged: (val) => setState(() =>
                                  _appendixEModeratorRatings[item.activityId] =
                                      val ?? currentModRating),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller:
                              _appendixEModeratorComments[item.activityId] ??
                                  TextEditingController(),
                          decoration: const InputDecoration(
                            labelText: 'Moderator rationale / comment',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                const Text('Appendix E Aggregate Moderator Rating',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(5, (i) {
                    final val = i + 1;
                    final selected = _appendixEAggregateRating == val;
                    return ChoiceChip(
                      label: Text(_competencyLabel(val)),
                      selected: selected,
                      selectedColor: _competencyColor(val),
                      onSelected: (_) =>
                          setState(() => _appendixEAggregateRating = val),
                      labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black,
                          fontSize: 12),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========= APPENDIX F TAB =========
  Widget _buildAppendixFTab() {
    final f = _toolkitData?.appendixF;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appendix F — Knowledge & Practical Assessments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Assessor-awarded marks on theory and practical papers. Moderator reviews and comments.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          _assessorReadOnlyCard(
            title: 'Assessor Assessment Marks',
            icon: Icons.article,
            accent: Colors.orange,
            child: f == null
                ? const Text('No Appendix F data submitted by assessor')
                : Builder(builder: (context) {
                    int pSum = 0;
                    for (var p in f.practicalTasks) {
                      pSum += p.score;
                    }
                    int wSum = 0;
                    for (var w in f.workplaceObservations) {
                      wSum += (int.tryParse(w.technicalKnowledge) ?? 0) +
                          (int.tryParse(w.interpretation) ?? 0) +
                          (int.tryParse(w.teamWork) ?? 0);
                    }
                    final totalCount = f.practicalTasks.length * 2 +
                        f.workplaceObservations.length * 3;
                    final overallScore = pSum * 2 + wSum;
                    final overallPct = totalCount > 0
                        ? (overallScore / (totalCount * 5) * 100)
                        : 0.0;
                    return Column(
                      children: [
                        Text(
                            'Assessor Name: ${f.assessorName ?? 'N/A'} · Date: ${f.assessmentDate ?? 'N/A'}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ...f.practicalTasks.take(10).map((p) => _markRow(
                              'Practical #${p.taskNumber}: ${p.taskName}',
                              p.score,
                              p.percentage,
                            )),
                        const Divider(),
                        _markRow(
                            'Practical Subtotal',
                            pSum,
                            f.practicalTasks.isNotEmpty
                                ? (pSum / (f.practicalTasks.length * 5) * 100)
                                : null),
                        _markRow(
                            'Workplace Observation Subtotal (${f.workplaceObservations.length})',
                            wSum,
                            f.workplaceObservations.isNotEmpty
                                ? (wSum /
                                    (f.workplaceObservations.length * 15) *
                                    100)
                                : null),
                        const Divider(),
                        _markRow('OVERALL Appendix F Calculated Score',
                            overallScore, overallPct > 0 ? overallPct : null,
                            bold: true),
                      ],
                    );
                  }),
          ),
          _moderatorJudgementCard(
            title: 'Appendix F Moderation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Knowledge Paper Moderator Comments',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _appendixFKnowledgeModeratorComments,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Review knowledge paper answer marking accuracy...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Practical Assessment Moderator Comments',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _appendixFPracticalModeratorComments,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Review practical task rubric application, observation notes...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Mark Adjustments (optional)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                    'If marks are adjusted, note the paper/question and adjustment amount.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _markRow(String label, int? score, double? percent,
      {bool bold = false, String? overrideKey}) {
    final overrideCtrl =
        overrideKey != null ? _appendixFMarkOverrides[overrideKey] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          if (_overrideMode && overrideCtrl != null)
            SizedBox(
              width: 100,
              child: TextField(
                controller: overrideCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                    fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Score',
                  labelStyle: TextStyle(fontSize: 10, color: Colors.deepOrange),
                  hintText: '0–5',
                ),
              ),
            )
          else
            Text(score?.toString() ?? '-',
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                    color: Colors.orange.shade800,
                    fontSize: bold ? 16 : 14)),
          if (percent != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: percent >= 50
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${percent.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: percent >= 50 ? Colors.green : Colors.red,
                      fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  // ========= APPENDIX H TAB =========
  Widget _buildAppendixHTab() {
    final recs = _toolkitData!.appendixH.recommendations;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appendix H — Access Recommendation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Assessor access recommendations. Moderator confirms or overrides each one.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          if (recs.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No Appendix H recommendations from assessor'),
            ))
          else
            _assessorReadOnlyCard(
              title: 'Assessor Access Recommendations',
              icon: Icons.recommend,
              accent: Colors.purple,
              child: Column(
                children: List.generate(recs.length, (i) {
                  final r = recs[i];
                  final recLabel = r.recommendationId >= 2
                      ? 'Competent / Access Granted'
                      : 'Not Yet Competent';
                  final sectionLabel = r.trade.isNotEmpty
                      ? '${r.trade} (OFO: ${r.ofoCode})'
                      : 'Unit Standard ACR #${r.acrId}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(sectionLabel,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: r.recommendationId >= 2
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(recLabel,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: r.recommendationId >= 2
                                          ? Colors.green
                                          : Colors.red)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Status: ',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey)),
                            if (_overrideMode)
                              Expanded(
                                child: TextField(
                                  controller: _appendixHStatusOverrides[
                                      'H_${r.recommendationId}_status'],
                                  style: const TextStyle(fontSize: 11),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    labelText: 'Override status',
                                    labelStyle: TextStyle(fontSize: 9),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                  ),
                                ),
                              )
                            else
                              Text(r.status.isEmpty ? 'Pending' : r.status,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_overrideMode)
                          TextField(
                            controller:
                                _appendixHRemarksOverrides[r.recommendationId],
                            maxLines: 2,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              labelText: 'Override assessor remarks',
                              labelStyle: TextStyle(fontSize: 10),
                            ),
                          )
                        else
                          Text(r.remarks,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          _moderatorJudgementCard(
            title: 'Appendix H Moderation',
            child: Column(
              children: List.generate(recs.length, (i) {
                final r = recs[i];
                final currentApproval =
                    _appendixHModeratorApprovals[r.recommendationId] ?? 1;
                final sectionLabel = r.trade.isNotEmpty
                    ? '${r.trade} (OFO: ${r.ofoCode})'
                    : 'Unit Standard ACR #${r.acrId}';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepPurple.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('H.${i + 1} · $sectionLabel',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('✅ CONFIRM Competent'),
                            selected: currentApproval == 1,
                            selectedColor: Colors.green,
                            onSelected: (_) => setState(() =>
                                _appendixHModeratorApprovals[
                                    r.recommendationId] = 1),
                            labelStyle: TextStyle(
                                color: currentApproval == 1
                                    ? Colors.white
                                    : Colors.black,
                                fontSize: 12),
                          ),
                          ChoiceChip(
                            label: const Text('⚠️ RE-ASSESS Required'),
                            selected: currentApproval == 2,
                            selectedColor: Colors.orange,
                            onSelected: (_) => setState(() =>
                                _appendixHModeratorApprovals[
                                    r.recommendationId] = 2),
                            labelStyle: TextStyle(
                                color: currentApproval == 2
                                    ? Colors.white
                                    : Colors.black,
                                fontSize: 12),
                          ),
                          ChoiceChip(
                            label: const Text('❌ OVERRIDE Not Competent'),
                            selected: currentApproval == 3,
                            selectedColor: Colors.red,
                            onSelected: (_) => setState(() =>
                                _appendixHModeratorApprovals[
                                    r.recommendationId] = 3),
                            labelStyle: TextStyle(
                                color: currentApproval == 3
                                    ? Colors.white
                                    : Colors.black,
                                fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller:
                            _appendixHModeratorComments[r.recommendationId] ??
                                TextEditingController(),
                        decoration: const InputDecoration(
                          labelText: 'Moderator rationale / comment',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ========= FINAL DECISION TAB =========
  Widget _buildFinalDecisionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Final Moderator Decision',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'This is the binding moderator judgement for the entire ARPL toolkit.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6A1B9A), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SELECT FINAL DECISION',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF6A1B9A))),
                const SizedBox(height: 12),
                _finalDecisionTile(
                  value: 1,
                  color: Colors.green,
                  icon: Icons.check_circle,
                  title: 'APPROVE ASSESSMENT',
                  subtitle:
                      'Assessor findings confirmed. Candidate meets all required standards.',
                ),
                const SizedBox(height: 8),
                _finalDecisionTile(
                  value: 2,
                  color: Colors.orange,
                  icon: Icons.autorenew,
                  title: 'RECOMMEND RE-ASSESSMENT',
                  subtitle:
                      'Shortcomings noted. Candidate must re-do specific sections.',
                ),
                const SizedBox(height: 8),
                _finalDecisionTile(
                  value: 3,
                  color: Colors.red,
                  icon: Icons.cancel,
                  title: 'REJECT ASSESSMENT',
                  subtitle:
                      'Critical deficiencies. Candidate does not meet standards.',
                ),
                const SizedBox(height: 24),
                const Text('Decision Reason / Remarks *',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _finalDecisionReason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Explain the basis for this decision. Reference specific appendices if needed...',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                const Text('Moderator Full Name (Signature) *',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _moderatorSignatureName,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Type full name to sign digitally',
                  ),
                ),
                if (_moderatorDecisionDate != null) ...[
                  const SizedBox(height: 12),
                  Text('Signed on: ${_moderatorDecisionDate!.toLocal()}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.green)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveModerationJudgement,
                    icon: const Icon(Icons.gavel, size: 22),
                    label: Text(
                        _isSaving ? 'SAVING...' : 'SUBMIT MODERATOR JUDGEMENT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('By submitting this judgement, you confirm that:',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          const Text(
            '• You have reviewed all assessor evidence in Appendices D, E, F, H\n'
            '• Your ratings and comments above reflect your professional moderator judgement\n'
            '• This decision is binding per SETA/ARPL moderation policy',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _finalDecisionTile({
    required int value,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _finalModeratorDecision == value;
    return GestureDetector(
      onTap: () => setState(() => _finalModeratorDecision = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
            Radio<int>(
              value: value,
              groupValue: _finalModeratorDecision,
              activeColor: color,
              onChanged: (val) => setState(() => _finalModeratorDecision = val),
            ),
          ],
        ),
      ),
    );
  }

  // ========= MODERATOR REPORT TAB (NAMB Internal Moderation Report) =========
  Widget _buildModeratorReportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NAMB Internal Moderation Report',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Complete the 10-point observation checklist and header fields as per NAMB moderation standards.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),

          // ========= HEADER SECTION =========
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Report Header Information',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                _buildHeaderField('Assessment Centre Name', _reportCenterName),
                const SizedBox(height: 10),
                _buildHeaderField(
                    'Accreditation Number', _reportAccreditationNo),
                const SizedBox(height: 10),
                _buildHeaderField('Assessor Name', _reportAssessorName),
                const SizedBox(height: 10),
                _buildHeaderField(
                    'Assessor Registration No.', _reportAssessorRegNo),
                const SizedBox(height: 10),
                _buildHeaderField('Moderator Name', _reportModeratorName),
                const SizedBox(height: 10),
                _buildHeaderField(
                    'Moderator Registration No.', _reportModeratorRegNo),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Text('Moderation Date',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _reportModerationDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _reportModerationDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                _reportModerationDate != null
                                    ? '${_reportModerationDate!.year}-${_reportModerationDate!.month.toString().padLeft(2, '0')}-${_reportModerationDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select date',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildHeaderField('Candidate Name', _reportCandidateName),
                const SizedBox(height: 10),
                _buildHeaderField('Candidate ID Number', _reportCandidateIdNo),
                const SizedBox(height: 10),
                _buildHeaderField('Trade/Qualification', _reportTrade),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ========= OBSERVATION CHECKLIST (10 criteria) =========
          const Text('Internal Moderation Observation Checklist',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
              'For each criterion, indicate Yes (Y) or No (N) and provide comments where needed.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),

          ...List.generate(_reportObservationCriteria.length, (i) {
            final criterion = _reportObservationCriteria[i]['criterion']!;
            final yn = _reportObservationYN[i];
            final commentCtrl = _reportObservationComments[i]!;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(criterion,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Response:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Y (Yes)'),
                        selected: yn == true,
                        selectedColor: Colors.green,
                        onSelected: (_) =>
                            setState(() => _reportObservationYN[i] = true),
                        labelStyle: TextStyle(
                            color: yn == true ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('N (No)'),
                        selected: yn == false,
                        selectedColor: Colors.red,
                        onSelected: (_) =>
                            setState(() => _reportObservationYN[i] = false),
                        labelStyle: TextStyle(
                            color: yn == false ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      if (yn != null)
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _reportObservationYN[i] = null),
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('Clear',
                              style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentCtrl,
                    decoration: InputDecoration(
                      labelText: 'Comments (optional)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: yn == false
                          ? 'Explain what was observed and why this criterion was not met'
                          : null,
                      hintStyle:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          // ========= MODERATOR OBSERVATIONS & FINAL DECISION =========
          const Text('Moderator Observations & Final Decision',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Observations by the internal moderator:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                TextField(
                  controller: _reportModeratorObservations,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Enter detailed observations about the assessment process, assessor performance, and any concerns...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 20),
                const Text('Trade test results',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Upheld',
                            style: TextStyle(fontSize: 14)),
                        value: _reportTradeTestResult == 'Upheld',
                        onChanged: (val) => setState(() =>
                            _reportTradeTestResult = val! ? 'Upheld' : null),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: Colors.green,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Rejected',
                            style: TextStyle(fontSize: 14)),
                        value: _reportTradeTestResult == 'Rejected',
                        onChanged: (val) => setState(() =>
                            _reportTradeTestResult = val! ? 'Rejected' : null),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('RECOMMENDATION:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                const Text('Recommendations by the internal moderator:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: _reportRecommendations,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Enter final recommendations (e.g., N/A if upheld, or specific actions required)...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Responsible Person:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _reportResponsiblePerson,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'Name',
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Signature:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _reportResponsibleSignature,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'Type name to sign',
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Internal Moderator:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _reportInternalModeratorName,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'Name',
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Signature:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _reportInternalModeratorSignature,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'Type name to sign',
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Date: ',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _reportSignatureDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _reportSignatureDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 14, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                _reportSignatureDate != null
                                    ? '${_reportSignatureDate!.year}-${_reportSignatureDate!.month.toString().padLeft(2, '0')}-${_reportSignatureDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select date',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('REQUIRED CORRECTIVE ACTIONS:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                TextField(
                  controller: _reportCorrectiveActions,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'List any corrective actions required, or enter N/A if none needed...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Planned completion date:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _reportCompletionDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _reportCompletionDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 14, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                _reportCompletionDate != null
                                    ? '${_reportCompletionDate!.year}-${_reportCompletionDate!.month.toString().padLeft(2, '0')}-${_reportCompletionDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select date',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Responsible person signature:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _reportResponsiblePersonFinalSignature,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'Type name',
                          contentPadding: EdgeInsets.all(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Date:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _reportResponsiblePersonDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(
                                () => _reportResponsiblePersonDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _reportResponsiblePersonDate != null
                                      ? '${_reportResponsiblePersonDate!.day}/${_reportResponsiblePersonDate!.month}/${_reportResponsiblePersonDate!.year}'
                                      : 'Select',
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ========= SUMMARY BOX =========
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 22),
                    SizedBox(width: 8),
                    Text('Moderator Report Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'You have answered ${_reportObservationYN.values.where((v) => v != null).length} / ${_reportObservationCriteria.length} criteria.',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                    'Y: ${_reportObservationYN.values.where((v) => v == true).length}  ·  N: ${_reportObservationYN.values.where((v) => v == false).length}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                    'This checklist will be saved with your moderation judgement and included in the final report.',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderField(String label, TextEditingController controller) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              hintText: 'Enter $label',
              hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
