import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Security Questions Setup Page for Learners
///
/// Allows learners to register 3-5 security questions and answers.
/// This is a one-time setup required after face enrollment.
/// Questions are used as backup verification when face recognition fails.
class LearnerSecurityQuestionsSetupPage extends StatefulWidget {
  final String learnerId;
  final String learnerName;
  final bool isRequired; // If true, user cannot skip

  const LearnerSecurityQuestionsSetupPage({
    super.key,
    required this.learnerId,
    required this.learnerName,
    this.isRequired = false,
  });

  @override
  _LearnerSecurityQuestionsSetupPageState createState() =>
      _LearnerSecurityQuestionsSetupPageState();
}

class _LearnerSecurityQuestionsSetupPageState
    extends State<LearnerSecurityQuestionsSetupPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _availableQuestions = [];
  final Map<int, String> _selectedAnswers = {}; // question_id -> answer
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAvailableQuestions();
  }

  /// Load all available security questions from server
  Future<void> _loadAvailableQuestions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manage_security_questions.php?action=get_questions'),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['success'] == true && data['questions'] != null) {
        setState(() {
          _availableQuestions =
              List<Map<String, dynamic>>.from(data['questions']);
          _isLoading = false;
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load questions');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading questions: $e';
        _isLoading = false;
      });
    }
  }

  /// Save selected questions and answers to server
  Future<void> _saveSecurityQuestions() async {
    // Validation
    if (_selectedAnswers.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer at least 3 security questions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedAnswers.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 security questions allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check for empty answers
    final hasEmptyAnswers =
        _selectedAnswers.values.any((answer) => answer.trim().isEmpty);
    if (hasEmptyAnswers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide answers for all selected questions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Prepare answers array for API
      final answers = _selectedAnswers.entries.map((entry) {
        return {
          'question_id': entry.key,
          'answer': entry.value.trim(),
        };
      }).toList();

      final response = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manage_security_questions.php?action=save_answers'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'learner_id': widget.learnerId,
          'answers': answers,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Security questions saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Wait a moment for user to see the success message
          await Future.delayed(const Duration(seconds: 1));

          // Return success to caller
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to save questions');
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isRequired,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // If required, don't allow back navigation
        if (!didPop && widget.isRequired) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Setup Required'),
              content: const Text(
                  'Security questions are required for backup verification. Are you sure you want to exit?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Continue Setup'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      const Text('Exit', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (shouldExit == true && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Security Questions Setup'),
          automaticallyImplyLeading: !widget.isRequired,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorView()
                : _buildQuestionsForm(),
        bottomNavigationBar:
            !_isLoading && _errorMessage == null ? _buildBottomBar() : null,
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAvailableQuestions,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Welcome, ${widget.learnerName}!',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Security questions provide a backup way to verify your identity when face recognition fails.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Select 3-5 questions below\n'
                    '• Provide honest answers you will remember\n'
                    '• Answers are case-insensitive',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Questions count indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _selectedAnswers.length >= 3
                  ? Colors.green[100]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Selected: ${_selectedAnswers.length}/5 (minimum 3)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _selectedAnswers.length >= 3
                    ? Colors.green[800]
                    : Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Questions list
          ..._availableQuestions.map((question) {
            final questionId = question['id'] as int;
            final questionText = question['question'] as String;
            final isSelected = _selectedAnswers.containsKey(questionId);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: isSelected ? 4 : 1,
              color: isSelected ? Colors.blue[50] : null,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: _selectedAnswers.length >= 5 && !isSelected
                              ? null
                              : (bool? value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedAnswers[questionId] = '';
                                    } else {
                                      _selectedAnswers.remove(questionId);
                                    }
                                  });
                                },
                        ),
                        Expanded(
                          child: Text(
                            questionText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Your answer',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (value) {
                          _selectedAnswers[questionId] = value;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 80), // Space for bottom bar
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!widget.isRequired)
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isSaving ? null : () => Navigator.pop(context, false),
                  child: const Text('Skip for Now'),
                ),
              ),
            if (!widget.isRequired) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSaving ||
                        _selectedAnswers.length < 3 ||
                        _selectedAnswers.length > 5
                    ? null
                    : _saveSecurityQuestions,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Save ${_selectedAnswers.length} Question${_selectedAnswers.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
