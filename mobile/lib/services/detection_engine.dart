import 'dart:math' as math;
import '../core/config.dart';

class SensorSample {
  final DateTime timestamp;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;

  SensorSample({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  double get accelerationMagnitude => math.sqrt(ax * ax + ay * ay + az * az);
  double get gyroMagnitude => math.sqrt(gx * gx + gy * gy + gz * gz);
}

class ProcessedSample {
  final DateTime timestamp;
  final double verticalAcc; // Orientation-independent projection
  final double dynamicMagnitude;
  final double gyroMagnitude;

  ProcessedSample({
    required this.timestamp,
    required this.verticalAcc,
    required this.dynamicMagnitude,
    required this.gyroMagnitude,
  });
}

class PotholeDetectionEvent {
  final DateTime timestamp;
  final double peakVerticalAcc;
  final int severity;
  final double vehicleSpeedMps;

  PotholeDetectionEvent({
    required this.timestamp,
    required this.peakVerticalAcc,
    required this.severity,
    required this.vehicleSpeedMps,
  });
}

class DetectionEngine {
  SensitivityLevel sensitivity;

  // Low-pass filter state for dynamic gravity tracking (alpha ~ 0.92)
  double _gx = 0.0;
  double _gy = 0.0;
  double _gz = 9.81;
  bool _gravityInitialized = false;

  // Circular rolling buffer of processed samples (up to 60 samples ~ 1.2s)
  final List<ProcessedSample> _buffer = [];
  static const int _maxBufferSize = 60;

  DateTime? _lastDetectionTime;

  DetectionEngine({this.sensitivity = SensitivityLevel.medium});

  void reset() {
    _buffer.clear();
    _gravityInitialized = false;
    _lastDetectionTime = null;
  }

  /// Ingests a new IMU sample and current GPS speed; returns a confirmed event if all criteria met.
  PotholeDetectionEvent? feedSample(SensorSample sample, double currentSpeedMps) {
    // 1. Orientation-Independent Gravity Estimation
    if (!_gravityInitialized) {
      _gx = sample.ax;
      _gy = sample.ay;
      _gz = sample.az;
      _gravityInitialized = true;
    } else {
      const alpha = AppConfig.gravityFilterAlpha;
      _gx = alpha * _gx + (1.0 - alpha) * sample.ax;
      _gy = alpha * _gy + (1.0 - alpha) * sample.ay;
      _gz = alpha * _gz + (1.0 - alpha) * sample.az;
    }

    final double gravNorm = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gravNorm < 1e-4) return null;

    final double uGx = _gx / gravNorm;
    final double uGy = _gy / gravNorm;
    final double uGz = _gz / gravNorm;

    // Linear dynamic acceleration (raw minus gravity)
    final double linX = sample.ax - _gx;
    final double linY = sample.ay - _gy;
    final double linZ = sample.az - _gz;

    // Project onto gravity unit vector to isolate pure vertical road shock
    final double verticalAcc = linX * uGx + linY * uGy + linZ * uGz;
    final double dynMag = math.sqrt(linX * linX + linY * linY + linZ * linZ);

    final processed = ProcessedSample(
      timestamp: sample.timestamp,
      verticalAcc: verticalAcc,
      dynamicMagnitude: dynMag,
      gyroMagnitude: sample.gyroMagnitude,
    );

    _buffer.add(processed);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    // 2. Gate: Speed threshold (> 10 km/h)
    if (currentSpeedMps < AppConfig.minVehicleSpeedMps) {
      return null;
    }

    // 3. Gate: Cooldown period (2 seconds)
    if (_lastDetectionTime != null) {
      final elapsed = sample.timestamp.difference(_lastDetectionTime!).inMilliseconds;
      if (elapsed < AppConfig.cooldownDurationMs) {
        return null;
      }
    }

    // 4. Condition A: Peak vertical acceleration exceeds sensitivity threshold
    final double threshold = sensitivity.threshold;
    if (verticalAcc.abs() < threshold) {
      return null;
    }

    // 5. Condition B & False-Positive Rejection
    if (!_confirmPotholeSignature(_buffer, threshold)) {
      return null;
    }

    // 6. Confirmed Pothole Event -> Calculate Speed-Normalized Severity
    _lastDetectionTime = sample.timestamp;
    final int sev = computeSeverity(verticalAcc, currentSpeedMps);

    return PotholeDetectionEvent(
      timestamp: sample.timestamp,
      peakVerticalAcc: verticalAcc,
      severity: sev,
      vehicleSpeedMps: currentSpeedMps,
    );
  }

  /// Verifies dip-rebound oscillation shape and rejects false positives
  static bool _confirmPotholeSignature(List<ProcessedSample> buffer, double threshold) {
    if (buffer.length < 15) return false;

    // Check for phone drop (extreme rotational impulse without road profile)
    final latest = buffer.last;
    if (latest.gyroMagnitude > AppConfig.phoneDropGyroThreshold) {
      return false;
    }

    // Must have minimum gyro pitch/roll disturbance supporting wheel drop
    bool gyroDisturbed = false;
    for (int i = buffer.length - 8; i < buffer.length; i++) {
      if (i >= 0 && buffer[i].gyroMagnitude >= AppConfig.minGyroAngularRate) {
        gyroDisturbed = true;
        break;
      }
    }
    if (!gyroDisturbed) return false;

    // Detect dip-rebound: an initial depression (negative vertical acc)
    // followed by an upward rebound (positive vertical acc) or vice versa within 100-400 ms
    int peakIndex = -1;
    double maxAmp = 0.0;
    for (int i = buffer.length - 12; i < buffer.length; i++) {
      if (i >= 0 && buffer[i].verticalAcc.abs() > maxAmp) {
        maxAmp = buffer[i].verticalAcc.abs();
        peakIndex = i;
      }
    }

    if (peakIndex == -1 || maxAmp < threshold) return false;
    final peakSample = buffer[peakIndex];
    final bool isDipFirst = peakSample.verticalAcc < 0;

    // Look for opposite-sign rebound within 100 - 400 ms window
    bool reboundFound = false;
    int reboundDurationMs = 0;

    for (int j = peakIndex + 1; j < buffer.length; j++) {
      final dt = buffer[j].timestamp.difference(peakSample.timestamp).inMilliseconds;
      if (dt > AppConfig.maxReboundWindowMs) break;

      if (dt >= AppConfig.minReboundWindowMs) {
        final bool oppositeSign = isDipFirst
            ? (buffer[j].verticalAcc > (threshold * 0.4))
            : (buffer[j].verticalAcc < -(threshold * 0.4));

        if (oppositeSign) {
          reboundFound = true;
          reboundDurationMs = dt;
          break;
        }
      }
    }

    if (!reboundFound) return false;

    // False Positive 1: Speed bump rejection (longer duration > 450 ms and smooth shape)
    if (reboundDurationMs > AppConfig.maxSpeedBumpDurationMs) {
      return false;
    }

    // False Positive 2: Railway crossing rejection (periodic oscillation with >= 4 zero-crossings in 1 sec)
    int zeroCrossings = 0;
    for (int k = 1; k < buffer.length; k++) {
      if ((buffer[k - 1].verticalAcc > 0 && buffer[k].verticalAcc < 0) ||
          (buffer[k - 1].verticalAcc < 0 && buffer[k].verticalAcc > 0)) {
        zeroCrossings++;
      }
    }
    if (zeroCrossings >= 6) {
      // Periodic track chatter, not a isolated pothole impact
      return false;
    }

    return true;
  }

  /// Pure Dart speed-normalized severity calculation (1-5 scale)
  /// Matches severity.py on the backend
  static int computeSeverity(
    double peakVerticalAcc,
    double speedMps, {
    double baseThreshold = AppConfig.baseVerticalThreshold,
    double refSpeedMps = AppConfig.referenceSpeedMps,
  }) {
    final double effectiveSpeed = math.max(speedMps, 3.0);
    final double speedFactor = math.pow(refSpeedMps / effectiveSpeed, 0.35).toDouble();
    final double rawScore = (peakVerticalAcc.abs() / baseThreshold) * speedFactor;
    final int rounded = rawScore.round();
    return math.max(1, math.min(5, rounded));
  }
}
