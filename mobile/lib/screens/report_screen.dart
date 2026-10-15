import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/offline_queue.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _selectedSeverity = 3;
  bool _isSubmitting = false;
  String? _statusMessage;

  final List<String> _severityLabels = [
    '',
    'Minor surface dip',
    'Shallow pothole',
    'Notable hazard',
    'Severe – rim risk',
    'CRITICAL – immediate danger',
  ];

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final double speed = locationService.currentSpeedKmh;

    // Safety lock: when speed >10 km/h, manual report is locked
    final bool isDriving = speed > 10.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Hazard'),
        backgroundColor: AppTheme.surfaceDark,
      ),
      backgroundColor: AppTheme.primaryDark,
      body: isDriving
          // Safety lockout screen while driving
          ? _buildDrivingLockout(speed)
          : _buildReportForm(context, locationService),
    );
  }

  Widget _buildDrivingLockout(double speed) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: AppTheme.severityHigh, size: 72),
            const SizedBox(height: 24),
            const Text(
              'Manual reporting is disabled while driving.',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your speed: ${speed.round()} km/h\nStop the vehicle to file a manual report.',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '⚡ Potholes are detected and reported automatically while you drive.',
                style: TextStyle(color: AppTheme.accentCyan, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportForm(BuildContext context, LocationService locationService) {
    final pos = locationService.currentPosition;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_pin, color: AppTheme.accentCyan, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current Location', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        pos != null
                            ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
                            : 'Acquiring GPS fix...',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Severity of Hazard',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Severity picker
          ...List.generate(5, (i) {
            final int sev = i + 1;
            final bool selected = _selectedSeverity == sev;
            return GestureDetector(
              onTap: () => setState(() => _selectedSeverity = sev),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.getSeverityColor(sev).withOpacity(0.3) : AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppTheme.getSeverityColor(sev) : Colors.white12,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.getSeverityColor(sev),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text('$sev', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _severityLabels[sev],
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white60,
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 28),

          // Status message
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _statusMessage!.contains('✅') ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_statusMessage!, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: pos == null || _isSubmitting ? null : () => _submitReport(context, pos),
              icon: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.send_rounded, color: Colors.black),
              label: Text(
                _isSubmitting ? 'Submitting...' : 'Submit Manual Report',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReport(BuildContext context, dynamic pos) async {
    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
    });

    final apiClient = context.read<ApiClient>();
    final offlineQueue = context.read<OfflineQueue>();

    final payload = {
      'device_id': apiClient.deviceId,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'speed': 0.0,
      'heading': pos.heading ?? 0.0,
      'accuracy': pos.accuracy,
      'severity': _selectedSeverity,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'is_manual': true,
    };

    final success = await apiClient.submitReport(payload);
    if (!success) {
      await offlineQueue.enqueueReport(payload);
    }

    setState(() {
      _isSubmitting = false;
      _statusMessage = success
          ? '✅ Report submitted successfully!'
          : '📲 No connection — saved to upload queue (${offlineQueue.pendingCount} pending)';
    });
  }
}
