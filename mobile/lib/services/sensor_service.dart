import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/config.dart';
import 'detection_engine.dart';
import 'location_service.dart';
import 'offline_queue.dart';
import 'api_client.dart';

class SensorService extends ChangeNotifier {
  final LocationService locationService;
  final OfflineQueue offlineQueue;
  final ApiClient apiClient;

  late final DetectionEngine detectionEngine;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Cached sensor coordinates to synchronize accelerometer & gyroscope streams
  double _lastAx = 0.0;
  double _lastAy = 0.0;
  double _lastAz = 9.81;

  double _lastGx = 0.0;
  double _lastGy = 0.0;
  double _lastGz = 0.0;

  bool _isListening = false;
  bool get isListening => _isListening;

  // Stream for UI notifications & sound triggers
  final _detectionController = StreamController<PotholeDetectionEvent>.broadcast();
  Stream<PotholeDetectionEvent> get onPotholeDetected => _detectionController.stream;

  SensorService({
    required this.locationService,
    required this.offlineQueue,
    required this.apiClient,
    SensitivityLevel sensitivity = SensitivityLevel.medium,
  }) {
    detectionEngine = DetectionEngine(sensitivity: sensitivity);
  }

  void updateSensitivity(SensitivityLevel level) {
    detectionEngine.sensitivity = level;
    notifyListeners();
  }

  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;
    detectionEngine.reset();

    // Prevent phone CPU & screen from sleeping during active drive
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock not available: $e');
    }

    // Subscribe to gyroscope stream (~50Hz sampling)
    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      (GyroscopeEvent event) {
        _lastGx = event.x;
        _lastGy = event.y;
        _lastGz = event.z;
      },
      onError: (err) => debugPrint('Gyroscope error: $err'),
    );

    // Subscribe to accelerometer stream (~50Hz sampling)
    _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      (AccelerometerEvent event) {
        _lastAx = event.x;
        _lastAy = event.y;
        _lastAz = event.z;

        final sample = SensorSample(
          timestamp: DateTime.now(),
          ax: _lastAx,
          ay: _lastAy,
          az: _lastAz,
          gx: _lastGx,
          gy: _lastGy,
          gz: _lastGz,
        );

        final double currentSpeed = locationService.currentSpeedMps;
        final detection = detectionEngine.feedSample(sample, currentSpeed);

        if (detection != null) {
          _handlePotholeDetected(detection);
        }
      },
      onError: (err) => debugPrint('Accelerometer error: $err'),
    );

    notifyListeners();
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;

    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;

    try {
      await WakelockPlus.disable();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _handlePotholeDetected(PotholeDetectionEvent event) async {
    _detectionController.add(event);

    final position = locationService.currentPosition;
    if (position == null) {
      debugPrint('Hazard detected but GPS fix not yet available.');
      return;
    }

    // Discard inaccurate GPS fixes (>25m)
    if (position.accuracy > 25.0) {
      debugPrint('Hazard discarded due to poor GPS accuracy: ${position.accuracy}m');
      return;
    }

    final reportPayload = {
      'device_id': apiClient.deviceId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speed': locationService.currentSpeedMps,
      'heading': position.heading,
      'accuracy': position.accuracy,
      'severity': event.severity,
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      'is_manual': false,
    };

    // Attempt direct submission; on failure or if offline, enqueue in SQLite
    final success = await apiClient.submitReport(reportPayload);
    if (!success) {
      await offlineQueue.enqueueReport(reportPayload);
    }
  }

  @override
  void dispose() {
    stopListening();
    _detectionController.close();
    super.dispose();
  }
}
