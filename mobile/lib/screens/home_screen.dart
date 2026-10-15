import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../services/alert_service.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../services/offline_queue.dart';
import '../services/api_client.dart';
import '../models/pothole.dart';
import '../widgets/alert_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  bool _driveMode = false;
  StreamSubscription? _detectionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServices());
  }

  Future<void> _initServices() async {
    final offlineQueue = context.read<OfflineQueue>();
    await offlineQueue.init();
    final locationService = context.read<LocationService>();
    await locationService.startTracking();
  }

  Future<void> _toggleDriveMode() async {
    final locationService = context.read<LocationService>();
    final sensorService = context.read<SensorService>();
    final alertService = context.read<AlertService>();
    final offlineQueue = context.read<OfflineQueue>();
    final apiClient = context.read<ApiClient>();

    setState(() => _driveMode = !_driveMode);

    if (_driveMode) {
      await sensorService.startListening();
      alertService.start();

      // Subscribe to detections to trigger background queue sync
      _detectionSub = sensorService.onPotholeDetected.listen((_) {
        offlineQueue.syncPendingReports(apiClient);
      });
    } else {
      await sensorService.stopListening();
      alertService.stop();
      await _detectionSub?.cancel();
    }
  }

  @override
  void dispose() {
    _detectionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final alertService = context.watch<AlertService>();
    final sensorService = context.watch<SensorService>();

    final currentPos = locationService.currentPosition;
    final LatLng mapCenter = currentPos != null
        ? LatLng(currentPos.latitude, currentPos.longitude)
        : const LatLng(37.7749, -122.4194); // SF fallback

    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 16.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              // OpenStreetMap tile layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.potholeguard.app',
                tileProvider: NetworkTileProvider(),
              ),
              // Pothole markers
              MarkerLayer(markers: _buildPotholeMarkers(alertService.nearbyHazards)),
              // Current position marker
              if (currentPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(currentPos.latitude, currentPos.longitude),
                      width: 50,
                      height: 50,
                      child: _buildVehicleMarker(locationService.currentHeading),
                    ),
                  ],
                ),
            ],
          ),

          // Top HUD: Speed + Drive Status
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // App title
                      const Text(
                        'PotholeGuard',
                        style: TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Speed display
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${locationService.currentSpeedKmh.round()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text('km/h', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Alert Banner (overlays top if alert is active)
          if (alertService.currentAlert != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AlertBanner(alert: alertService.currentAlert!),
            ),

          // Bottom controls panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drive Mode toggle
                  GestureDetector(
                    onTap: _toggleDriveMode,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _driveMode ? AppTheme.accentCyan : AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _driveMode
                            ? [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.45), blurRadius: 20)]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _driveMode ? Icons.directions_car : Icons.directions_car_outlined,
                            color: _driveMode ? Colors.black : Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _driveMode ? 'DRIVE MODE ON' : 'TAP TO START DRIVING',
                            style: TextStyle(
                              color: _driveMode ? Colors.black : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusChip(
                        label: 'Hazards',
                        value: '${alertService.nearbyHazards.length}',
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.severityMedium,
                      ),
                      _StatusChip(
                        label: 'Accuracy',
                        value: currentPos != null ? '${currentPos.accuracy.round()}m' : '--',
                        icon: Icons.gps_fixed,
                        color: AppTheme.accentCyan,
                      ),
                      _StatusChip(
                        label: 'Detecting',
                        value: sensorService.isListening ? 'ON' : 'OFF',
                        icon: sensorService.isListening ? Icons.sensors : Icons.sensors_off,
                        color: sensorService.isListening ? AppTheme.severityLow : Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildPotholeMarkers(List<PotholeModel> potholes) {
    return potholes.map((p) {
      return Marker(
        point: LatLng(p.latitude, p.longitude),
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: p.color.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(
              color: p.isVerified ? Colors.white : Colors.white54,
              width: p.isVerified ? 2.5 : 1.5,
            ),
            boxShadow: [BoxShadow(color: p.color.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)],
          ),
          alignment: Alignment.center,
          child: Text(
            '${p.severityMax}',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildVehicleMarker(double heading) {
    return Transform.rotate(
      angle: heading * (3.14159265 / 180),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.accentCyan,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.5), blurRadius: 12, spreadRadius: 2)],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.navigation, color: Colors.black, size: 24),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
