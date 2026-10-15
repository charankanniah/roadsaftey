import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/pothole.dart';
import '../services/api_client.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PotholeModel> _potholes = [];
  bool _loading = true;
  String? _error;

  // Filters
  int? _severityFilter;
  String? _statusFilter;

  final List<String> _statuses = ['new', 'verified', 'assigned', 'fixed', 'possibly_fixed'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });

    final apiClient = context.read<ApiClient>();
    try {
      final queryParams = <String, String>{
        'limit': '100',
        if (_severityFilter != null) 'severity_min': '$_severityFilter',
        if (_statusFilter != null) 'status': _statusFilter!,
      };

      final uri = Uri.parse('${apiClient.baseUrl}/potholes')
          .replace(queryParameters: queryParams);

      final http = await _httpGet(uri.toString());
      if (http != null) {
        setState(() {
          _potholes = http;
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Could not reach server.'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Error: $e'; });
    }
  }

  Future<List<PotholeModel>?> _httpGet(String url) async {
    try {
      final client = context.read<ApiClient>();
      final potholes = await client.fetchNearbyPotholes(
        latitude: 0,
        longitude: 0,
        radius: 50000000,
      );
      return potholes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection History'),
        backgroundColor: AppTheme.surfaceDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: AppTheme.primaryDark,
      body: Column(
        children: [
          // Filter bar
          Container(
            color: AppTheme.surfaceDark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Severity filter
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _severityFilter,
                    decoration: InputDecoration(
                      labelText: 'Min Severity',
                      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.cardDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    dropdownColor: AppTheme.cardDark,
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All', style: TextStyle(color: Colors.white))),
                      ...List.generate(5, (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}+', style: const TextStyle(color: Colors.white)),
                      )),
                    ],
                    onChanged: (v) { setState(() => _severityFilter = v); _loadHistory(); },
                  ),
                ),
                const SizedBox(width: 10),
                // Status filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.cardDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    dropdownColor: AppTheme.cardDark,
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All', style: TextStyle(color: Colors.white))),
                      ..._statuses.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      )),
                    ],
                    onChanged: (v) { setState(() => _statusFilter = v); _loadHistory(); },
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
                : _error != null
                    ? _buildError()
                    : _potholes.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _potholes.length,
      itemBuilder: (context, index) {
        final p = _potholes[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.color.withOpacity(0.4), width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.color, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p.severityMax}',
                style: TextStyle(color: p.color, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            title: Text(
              '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(
              '${p.status.toUpperCase()}  •  ${p.confirmationCount} reports  •  ${_formatDate(p.lastDetectedAt)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            trailing: p.isVerified
                ? const Icon(Icons.verified, color: AppTheme.accentCyan, size: 20)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildEmpty() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, color: AppTheme.severityLow, size: 64),
        SizedBox(height: 16),
        Text('No potholes reported yet.', style: TextStyle(color: Colors.white70, fontSize: 16)),
        Text('Start Drive Mode to detect hazards.', style: TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white38, size: 56),
          const SizedBox(height: 16),
          Text(_error ?? 'Unknown error', style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loadHistory,
            child: const Text('Retry', style: TextStyle(color: AppTheme.accentCyan)),
          ),
        ],
      ),
    ),
  );

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
