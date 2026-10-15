import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  StreamSubscription<Position>? _positionSub;
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  double get currentSpeedMps => _currentPosition?.speed ?? 0.0;
  double get currentSpeedKmh => currentSpeedMps * 3.6;
  double get currentHeading => _currentPosition?.heading ?? 0.0;
  double get currentAccuracy => _currentPosition?.accuracy ?? 999.0;

  Future<bool> checkAndRequestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) {
      debugPrint('Location permission not granted.');
      return;
    }

    _isTracking = true;

    // High accuracy, 1Hz updates, 2m distance filter
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        // Discard low-accuracy fixes (>25m)
        if (position.accuracy <= 25.0) {
          _currentPosition = position;
          notifyListeners();
        }
      },
      onError: (err) => debugPrint('Geolocator stream error: $err'),
    );

    // Initial fix
    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (initial.accuracy <= 25.0) {
        _currentPosition = initial;
        notifyListeners();
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
