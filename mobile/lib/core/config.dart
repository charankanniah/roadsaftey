class AppConfig {
  // Network Endpoints
  // Default to 10.0.2.2 for Android Emulator, overrideable in Settings
  static const String defaultApiBaseUrl = 'http://10.0.2.2:8000/api';

  // Sensor Ingestion & Filtering
  static const double sensorSamplingRateHz = 50.0;
  static const double gravityFilterAlpha = 0.92; // Low-pass filter constant

  // Detection Algorithm Thresholds (docs/DETECTION_ALGORITHM.md)
  static const double baseVerticalThreshold = 3.5; // m/s^2 above baseline
  static const double minVehicleSpeedMps = 2.78; // 10.0 km/h minimum speed
  static const int minReboundWindowMs = 100;
  static const int maxReboundWindowMs = 400;
  static const double minGyroAngularRate = 0.35; // rad/s
  static const int cooldownDurationMs = 2000; // 2 seconds between detections

  // False Positive Suppression
  static const int maxSpeedBumpDurationMs = 450;
  static const double phoneDropGyroThreshold = 4.0; // rad/s (pure handling)

  // Severity Calibration
  static const double referenceSpeedMps = 12.5; // 45.0 km/h

  // Alert Lookahead & Proximity Engine
  static const double lookaheadTimeSeconds = 6.0;
  static const double minAlertDistanceMeters = 40.0;
  static const double maxAlertDistanceMeters = 300.0;
  static const double imminentDistanceMeters = 50.0;
  static const double headingCorridorDeg = 45.0; // +/- 45 degrees ahead

  // Periodic Refresh
  static const Duration nearbyPotholesPollInterval = Duration(seconds: 4);
}

enum SensitivityLevel {
  low(1.30, 'Low (Stiff Suspension)'),
  medium(1.00, 'Medium (Standard)'),
  high(0.80, 'High (Soft / Luxury)');

  final double scaleFactor;
  final String label;
  const SensitivityLevel(this.scaleFactor, this.label);

  double get threshold => AppConfig.baseVerticalThreshold * scaleFactor;
}
