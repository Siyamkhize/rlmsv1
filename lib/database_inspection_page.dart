import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database_helper.dart';

class DatabaseInspectionPage extends StatefulWidget {
  @override
  _DatabaseInspectionPageState createState() => _DatabaseInspectionPageState();
}

class _DatabaseInspectionPageState extends State<DatabaseInspectionPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _results = [];
  final TextEditingController _queryController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default query to show manual_clocking_evidence table
    _queryController.text =
        'SELECT * FROM manual_clocking_evidence ORDER BY evidence_id DESC LIMIT 10';
  }

  Future<void> _executeQuery() async {
    if (_queryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Please enter a SQL query')));
      return;
    }

    setState(() {
      _isLoading = true;
      _results = [];
    });

    try {
      final db = await _dbHelper.database;
      final results = await db.rawQuery(_queryController.text.trim());

      setState(() {
        _results = results;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Query executed successfully. ${results.length} rows returned.')));
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Widget _buildResultsTable() {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No data to display. Execute a query to see results.',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      );
    }

    final columns = _results[0].keys.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: columns
              .map((column) => DataColumn(
                    label: Text(
                      column,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
          rows: _results
              .map((row) => DataRow(
                    cells: columns
                        .map((column) => DataCell(
                              GestureDetector(
                                onTap: () {
                                  // Copy cell content to clipboard
                                  Clipboard.setData(ClipboardData(
                                      text: row[column]?.toString() ?? ''));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text('Copied to clipboard')));
                                },
                                child: Container(
                                  constraints: BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    row[column]?.toString() ?? 'NULL',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 3,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Database Inspector'),
        backgroundColor: Colors.blue[800],
      ),
      body: Column(
        children: [
          // Query Input Section
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SQL Query:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _queryController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter SQL query here...',
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isLoading ? null : _executeQuery,
                      child: _isLoading
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Executing...'),
                              ],
                            )
                          : Text('Execute Query'),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _queryController.text =
                              'SELECT * FROM manual_clocking_evidence ORDER BY evidence_id DESC LIMIT 10';
                        });
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey),
                      child: Text('Manual Evidence'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _queryController.text =
                              'SELECT name FROM sqlite_master WHERE type=\'table\' ORDER BY name';
                        });
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange),
                      child: Text('Show Tables'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results Section
          Expanded(
            child: Container(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Results: (${_results.length} rows)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Expanded(child: _buildResultsTable()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }
}
