import 'dart:io';
import 'package:flutter/material.dart';
import '../services/offline_sync_queue_service.dart';

/// Demonstration of proper offline-first clocking with tap-time queue
class OfflineSyncClockButton extends StatefulWidget {
  final int learnerId;
  final String action; // 'clock_in' or 'clock_out'
  final VoidCallback? onSuccess;
  
  const OfflineSyncClockButton({
    super.key,
    required this.learnerId,
    required this.action,
    this.onSuccess,
  });

  @override
  State<OfflineSyncClockButton> createState() => _OfflineSyncClockButtonState();
}

class _OfflineSyncClockButtonState extends State<OfflineSyncClockButton> {
  final _syncQueue = OfflineSyncQueueService();
  bool _isProcessing = false;
  bool _isPending = false;
  
  @override
  void initState() {
    super.initState();
    _checkPendingStatus();
  }
  
  Future<void> _checkPendingStatus() async {
    final pending = await _syncQueue.isActionPending(widget.action, widget.learnerId);
    if (mounted) {
      setState(() => _isPending = pending);
    }
  }
  
  /// CRITICAL: This method captures all evidence AT TAP TIME
  /// Never do geofence/face verification at sync time!
  /// 
  /// NOTE: This is a demonstration widget with placeholder implementations.
  /// Actual implementation should use proper geofence and camera capture services.
  Future<void> _handleClockAction() async {
    if (_isProcessing || _isPending) return;
    
    setState(() => _isProcessing = true);
    
    try {
      // 1. GEOFENCE CHECK - at tap time
      // TODO: Implement actual geofence verification using SecureLocationService.getSecurePosition()
      // final locationResult = await SecureLocationService.getSecurePosition();
      // if (!locationResult.isTrusted) {
      //   _showError('Location verification failed');
      //   return;
      // }
      
      // 2. FACE VERIFICATION - at tap time
      // TODO: Implement actual face capture using camera service
      // File? faceImage;
      
      // 3. SIGNATURE CAPTURE - at tap time  
      // TODO: Implement signature capture
      // File? signatureImage;
      
      // 4. PREPARE COMPLETE PAYLOAD - everything captured at tap time
      final payload = {
        'user_id': widget.learnerId, // Or current user ID
        'learner_id': widget.learnerId,
        'action': widget.action,
        'clock_date': DateTime.now().toIso8601String().split('T')[0],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
      // 5. ENQUEUE WITH TAP-TIME GENERATED KEY
      final idempotencyKey = await _syncQueue.enqueueAction(
        'consolidated_clocking',
        payload,
        evidence: {}, // Add actual evidence data here
      );
      
      // 6. UPDATE UI IMMEDIATELY
      setState(() {
        _isPending = true;
        _isProcessing = false;
      });
      
      // 7. SHOW CONFIRMATION
      _showSuccess('${widget.action.replaceAll('_', ' ')} queued for sync (Key: ${idempotencyKey.substring(0, 8)}...)');
      
      widget.onSuccess?.call();
      
    } catch (e) {
      _showError('Failed to process ${widget.action}: $e');
      setState(() => _isProcessing = false);
    }
  }
  
  Future<File?> _captureSignature() async {
    // Implement signature capture - placeholder
    // This should capture signature at tap time and save to temp file
    return null;
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: (_isProcessing || _isPending) ? null : _handleClockAction,
          icon: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isPending 
                  ? Icons.schedule 
                  : (widget.action == 'clock_in' ? Icons.login : Icons.logout)
                ),
          label: Text(_getButtonLabel()),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isPending 
                ? Colors.orange 
                : (widget.action == 'clock_in' ? Colors.green : Colors.red),
            foregroundColor: Colors.white,
            minimumSize: const Size(200, 50),
          ),
        ),
        if (_isPending) ...[
          const SizedBox(height: 8),
          Text(
            'Pending sync...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
  
  String _getButtonLabel() {
    if (_isProcessing) return 'Processing...';
    if (_isPending) return 'Pending Sync';
    return widget.action == 'clock_in' ? 'Clock In' : 'Clock Out';
  }
}