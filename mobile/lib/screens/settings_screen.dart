import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../services/alert_service.dart';
import '../services/api_client.dart';
import '../services/sensor_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiUrlController;

  @override
  void initState() {
    super.initState();
    final apiClient = context.read<ApiClient>();
    _apiUrlController = TextEditingController(text: apiClient.baseUrl);
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertService = context.watch<AlertService>();
    final sensorService = context.watch<SensorService>();
    final apiClient = context.watch<ApiClient>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppTheme.surfaceDark,
      ),
      backgroundColor: AppTheme.primaryDark,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Detection Sensitivity
          _SectionHeader(title: 'Detection Sensitivity'),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: SensitivityLevel.values.map((level) {
                final bool selected = sensorService.detectionEngine.sensitivity == level;
                return ListTile(
                  leading: Icon(
                    Icons.tune,
                    color: selected ? AppTheme.accentCyan : Colors.white38,
                  ),
                  title: Text(level.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Vertical threshold: ${level.threshold.toStringAsFixed(1)} m/s²',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: selected ? const Icon(Icons.check_circle, color: AppTheme.accentCyan) : null,
                  onTap: () => sensorService.updateSensitivity(level),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // Alert Settings
          _SectionHeader(title: 'Driver Alerts'),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Voice Alerts (TTS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    alertService.voiceEnabled ? 'Audio warnings active' : 'Silent mode – visual alerts only',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  secondary: Icon(
                    alertService.voiceEnabled ? Icons.volume_up : Icons.volume_off,
                    color: alertService.voiceEnabled ? AppTheme.accentCyan : Colors.grey,
                  ),
                  value: alertService.voiceEnabled,
                  activeColor: AppTheme.accentCyan,
                  onChanged: (v) => alertService.setVoiceEnabled(v),
                ),
                const Divider(color: Colors.white12, height: 1),
                SwitchListTile(
                  title: const Text('Night / Dark Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Auto-enables between 7 PM – 6 AM',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  secondary: Icon(
                    alertService.isNightMode ? Icons.nights_stay : Icons.wb_sunny,
                    color: alertService.isNightMode ? AppTheme.accentCyan : Colors.amber,
                  ),
                  value: alertService.isNightMode,
                  activeColor: AppTheme.accentCyan,
                  onChanged: (v) => alertService.toggleNightMode(v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Alert Distance Info (read-only, dynamically calculated)
          _SectionHeader(title: 'Alert Lookahead (Auto-Scaled)'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Minimum alert distance', value: '${AppConfig.minAlertDistanceMeters.toInt()} m'),
                _InfoRow(label: 'Maximum alert distance', value: '${AppConfig.maxAlertDistanceMeters.toInt()} m'),
                _InfoRow(label: 'Lookahead formula', value: 'Speed × ${AppConfig.lookaheadTimeSeconds.toInt()}s'),
                _InfoRow(label: 'Imminent alert at', value: '≤ ${AppConfig.imminentDistanceMeters.toInt()} m'),
                _InfoRow(label: 'Heading corridor', value: '±${AppConfig.headingCorridorDeg.toInt()}°'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // API Server URL
          _SectionHeader(title: 'Backend Server'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('API Base URL', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _apiUrlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.cardDark,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          hintText: AppConfig.defaultApiBaseUrl,
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        apiClient.setBaseUrl(_apiUrlController.text.trim());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API URL updated'), backgroundColor: AppTheme.accentCyan),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentCyan,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Device ID: ${apiClient.deviceId.isEmpty ? "Loading..." : apiClient.deviceId.substring(0, 18)}…',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    ),
  );
}
