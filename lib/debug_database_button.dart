import 'package:flutter/material.dart';
import 'services/manual_clocking_evidence_sync_service.dart';

class DebugDatabaseButton extends StatefulWidget {
  @override
  _DebugDatabaseButtonState createState() => _DebugDatabaseButtonState();
}

class _DebugDatabaseButtonState extends State<DebugDatabaseButton> {
  String _debugOutput = '';
  bool _isLoading = false;

  Future<void> _inspectDatabase() async {
    setState(() {
      _isLoading = true;
      _debugOutput = 'Inspecting database...';
    });

    try {
      // Call the debug inspection method
      final syncService = ManualClockingEvidenceSyncService();
      await syncService.debugInspectDatabase();
      
      setState(() {
        _debugOutput = 'Database inspection complete. Check console logs for details.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _debugOutput = 'Error inspecting database: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isLoading ? null : _inspectDatabase,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isLoading 
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Inspecting...')
                ],
              )
            : Text('🔍 Debug Database'),
        ),
        if (_debugOutput.isNotEmpty)
          Container(
            margin: EdgeInsets.only(top: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              _debugOutput,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}