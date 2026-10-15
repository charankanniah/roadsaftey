import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../core/config.dart';
import '../models/pothole.dart';
import 'api_client.dart';
import 'location_service.dart';
import 'offline_queue.dart';

enum AlertStage { none, earlyWarning, imminent }

class ActiveAlert {
  final PotholeModel pothole;
  final AlertStage stage;
  final double distanceMeters;
  final String message;

  ActiveAlert({
    required this.pothole,
    required this.stage,
    required this.distanceMeters,
    required this.message,
  });
}

class AlertService extends ChangeNotifier {
  final ApiClient apiClient;
  final LocationService locationService;
  final OfflineQueue offlineQueue;

  final FlutterTts _tts = FlutterTts();
  bool _voiceEnabled = true;
  bool get voiceEnabled => _voiceEnabled;

  bool _isNightMode = false;
  bool get isNightMode => _isNightMode;

  ActiveAlert? _currentAlert;
  ActiveAlert? get currentAlert => _currentAlert;

  List<PotholeModel> _nearbyHazards = [];
  List<PotholeModel> get nearbyHazards => _nearbyHazards;

  // Track potholes alerted in current pass to prevent repetitive nag
  final Set<int> _earlyWarnedPotholes = {};
  final Set<int> _imminentWarnedPotholes = {};

  Timer? _pollingTimer;
  Timer? _evaluationTimer;
  bool _isRunning = false;

  AlertService({
    required this.apiClient,
    required this.locationService,
    required this.offlineQueue,
  }) {
    _initTts();
    _checkNightTime();
  }

  void setVoiceEnabled(bool enabled) {
    _voiceEnabled = enabled;
    notifyListeners();
  }

  void toggleNightMode(bool isNight) {
    _isNightMode = isNight;
    notifyListeners();
  }

  void _checkNightTime() {
    final hour = DateTime.now().hour;
    // Auto dark theme between 7 PM and 6 AM
    _isNightMode = (hour >= 19 || hour < 6);
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS initialization warning: $e');
    }
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // Periodic hazard sync from server
    _pollingTimer = Timer.periodic(AppConfig.nearbyPotholesPollInterval, (_) => _refreshHazards());
    // High-frequency proximity & heading evaluation (every 500ms)
    _evaluationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _evaluateProximity());

    _refreshHazards();
    notifyListeners();
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _pollingTimer?.cancel();
    _evaluationTimer?.cancel();
    _currentAlert = null;
    _earlyWarnedPotholes.clear();
    _imminentWarnedPotholes.clear();
    notifyListeners();
  }

  Future<void> _refreshHazards() async {
    final pos = locationService.currentPosition;
    if (pos == null) return;

    // Fetch from API; if offline or empty, fallback to cached SQLite records
    final online = await apiClient.fetchNearbyPotholes(
      latitude: pos.latitude,
      longitude: pos.longitude,
      radius: 1200.0,
    );

    if (online.isNotEmpty) {
      _nearbyHazards = online;
      await offlineQueue.cachePotholes(online);
    } else {
      _nearbyHazards = await offlineQueue.getCachedPotholes();
    }

    notifyListeners();
  }

  void _evaluateProximity() {
    final pos = locationService.currentPosition;
    if (pos == null || _nearbyHazards.isEmpty) {
      if (_currentAlert != null) {
        _currentAlert = null;
        notifyListeners();
      }
      return;
    }

    final double speed = locationService.currentSpeedMps;
    final double heading = locationService.currentHeading;

    // Dynamic Lookahead Distance = clamp(40m, speed * 6s, 300m)
    final double lookaheadDistance = math.max(
      AppConfig.minAlertDistanceMeters,
      math.min(AppConfig.maxAlertDistanceMeters, speed * AppConfig.lookaheadTimeSeconds),
    );

    ActiveAlert? candidateAlert;
    double closestDistance = double.infinity;

    for (final hazard in _nearbyHazards) {
      if (hazard.isFixed) continue;

      final dist = _calculateDistance(pos.latitude, pos.longitude, hazard.latitude, hazard.longitude);
      if (dist > lookaheadDistance) {
        // Driver has moved away from previously alerted pothole; clear debounce
        _earlyWarnedPotholes.remove(hazard.id);
        _imminentWarnedPotholes.remove(hazard.id);
        continue;
      }

      // Check bearing alignment: only alert if hazard is positioned ahead within +/- 45 deg
      // If stationary (speed < 1.0 m/s), allow omni-directional proximity
      if (speed >= 1.0) {
        final bearing = _calculateBearing(pos.latitude, pos.longitude, hazard.latitude, hazard.longitude);
        if (!_isAligned(heading, bearing, AppConfig.headingCorridorDeg)) {
          continue;
        }
      }

      if (dist < closestDistance) {
        closestDistance = dist;

        if (dist <= AppConfig.imminentDistanceMeters) {
          candidateAlert = ActiveAlert(
            pothole: hazard,
            stage: AlertStage.imminent,
            distanceMeters: dist,
            message: 'POTHOLE NOW! SLOW DOWN',
          );
        } else {
          final int roundedMeters = ((dist / 10).round() * 10);
          candidateAlert = ActiveAlert(
            pothole: hazard,
            stage: AlertStage.earlyWarning,
            distanceMeters: dist,
            message: 'Pothole ahead in ${roundedMeters}m',
          );
        }
      }
    }

    if (candidateAlert != null) {
      _triggerAlertIfNew(candidateAlert);
    } else if (_currentAlert != null) {
      _currentAlert = null;
      notifyListeners();
    }
  }

  Future<void> _triggerAlertIfNew(ActiveAlert alert) async {
    final hazardId = alert.pothole.id;

    if (alert.stage == AlertStage.imminent) {
      if (!_imminentWarnedPotholes.contains(hazardId)) {
        _imminentWarnedPotholes.add(hazardId);
        _currentAlert = alert;
        notifyListeners();
        _dispatchAudioFeedback('Caution! Pothole imminent.');
        _dispatchHaptic(isImminent: true, severity: alert.pothole.severityMax);
      } else {
        // Update distance reading on existing active banner
        _currentAlert = alert;
        notifyListeners();
      }
    } else if (alert.stage == AlertStage.earlyWarning) {
      if (!_earlyWarnedPotholes.contains(hazardId)) {
        _earlyWarnedPotholes.add(hazardId);
        _currentAlert = alert;
        notifyListeners();
        _dispatchAudioFeedback('Pothole ahead, ${alert.distanceMeters.round()} meters.');
        _dispatchHaptic(isImminent: false, severity: alert.pothole.severityMax);
      } else {
        _currentAlert = alert;
        notifyListeners();
      }
    }
  }

  void _dispatchAudioFeedback(String speech) {
    if (!_voiceEnabled) return;
    try {
      _tts.speak(speech);
    } catch (_) {}
  }

  void _dispatchHaptic({required bool isImminent, required int severity}) async {
    try {
      final bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      if (isImminent) {
        // Urgent double shock
        Vibration.vibrate(pattern: [0, 350, 150, 350], intensities: [0, 255, 0, 255]);
      } else {
        // Single distinct pulse
        Vibration.vibrate(duration: 250, amplitude: severity >= 4 ? 255 : 180);
      }
    } catch (_) {}
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final y = math.sin((lon2 - lon1) * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0));
    final x = math.cos(lat1 * (math.pi / 180.0)) * math.sin(lat2 * (math.pi / 180.0)) -
        math.sin(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) * math.cos((lon2 - lon1) * (math.pi / 180.0));
    final b = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
    return b;
  }

  static bool _isAligned(double heading, double bearing, double tolerance) {
    double diff = (heading - bearing).abs() % 360.0;
    if (diff > 180.0) diff = 360.0 - diff;
    return diff <= tolerance;
  }

  @override
  void dispose() {
    stop();
    _tts.stop();
    super.dispose();
  }
}
