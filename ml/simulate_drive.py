#!/usr/bin/env python3
"""
PotholeGuard Drive Simulator
=============================
Generates a realistic synthetic driving route with injected pothole spikes,
speed bumps, and realistic GPS + IMU noise. Runs the same detection algorithm
as the mobile client (in Python) and POSTs confirmed reports to the backend API.

Usage:
    python ml/simulate_drive.py
    python ml/simulate_drive.py --api-url http://localhost:8000/api --count 20
    python ml/simulate_drive.py --count 40 --noise 0.20

Options:
    --api-url       Backend API base URL (default: http://localhost:8000/api)
    --count         Number of synthetic route waypoints (default: 25)
    --noise         Sensor noise level ratio 0.0–0.5 (default: 0.15)
    --device-id     Override device UUID (default: auto-generated)
    --speed-kmh     Simulated driving speed in km/h (default: 40)
"""

import argparse
import math
import random
import uuid
import time
from datetime import datetime, timezone
from typing import List, Optional, Tuple, Dict, Any
import json

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    print("Warning: 'requests' not installed. Install with: pip install requests")
    REQUESTS_AVAILABLE = False


# ─── Detection Thresholds (mirrors detection_engine.dart) ────────────────────
GRAVITY_ALPHA = 0.92
BASE_VERTICAL_THRESHOLD = 3.5   # m/s²
MIN_VEHICLE_SPEED_MPS = 2.78    # 10 km/h
MIN_REBOUND_MS = 100
MAX_REBOUND_MS = 400
MIN_GYRO_RATE = 0.35            # rad/s
COOLDOWN_MS = 2000
PHONE_DROP_GYRO_THRESH = 4.0
MAX_SPEED_BUMP_DURATION_MS = 450
REF_SPEED_MPS = 12.5
SAMPLE_RATE_HZ = 50


# ─── Severity Computation (mirrors severity.py on backend) ───────────────────
def compute_severity(peak_vertical_acc: float, speed_mps: float) -> int:
    effective_speed = max(speed_mps, 3.0)
    speed_factor = math.pow(REF_SPEED_MPS / effective_speed, 0.35)
    raw_score = (abs(peak_vertical_acc) / BASE_VERTICAL_THRESHOLD) * speed_factor
    return max(1, min(5, round(raw_score)))


# ─── Detection Engine ─────────────────────────────────────────────────────────
class PythonDetectionEngine:
    """Pure Python port of detection_engine.dart for simulation and testing."""

    def __init__(self, sensitivity_scale: float = 1.0):
        self.threshold = BASE_VERTICAL_THRESHOLD * sensitivity_scale
        # Gravity low-pass filter state
        self._gx, self._gy, self._gz = 0.0, 0.0, 9.81
        self._initialized = False
        # Rolling sample buffer (60 samples ≈ 1.2 s at 50 Hz)
        self._buffer: List[Dict] = []
        self._last_detection_ms: Optional[float] = None

    def reset(self):
        self._buffer.clear()
        self._initialized = False
        self._last_detection_ms = None

    def feed_sample(self, sample: Dict, speed_mps: float) -> Optional[Dict]:
        """Accepts a sensor sample dict and current speed. Returns detection dict or None."""
        ax, ay, az = sample['ax'], sample['ay'], sample['az']
        gx, gy, gz = sample['gx'], sample['gy'], sample['gz']
        now_ms = sample['ts_ms']

        # 1. Gravity estimation (low-pass)
        if not self._initialized:
            self._gx, self._gy, self._gz = ax, ay, az
            self._initialized = True
        else:
            a = GRAVITY_ALPHA
            self._gx = a * self._gx + (1 - a) * ax
            self._gy = a * self._gy + (1 - a) * ay
            self._gz = a * self._gz + (1 - a) * az

        grav_norm = math.sqrt(self._gx**2 + self._gy**2 + self._gz**2)
        if grav_norm < 1e-4:
            return None
        ugx, ugy, ugz = self._gx / grav_norm, self._gy / grav_norm, self._gz / grav_norm

        # 2. Linear dynamic acceleration
        lin_x, lin_y, lin_z = ax - self._gx, ay - self._gy, az - self._gz
        vertical_acc = lin_x * ugx + lin_y * ugy + lin_z * ugz
        dyn_mag = math.sqrt(lin_x**2 + lin_y**2 + lin_z**2)
        gyro_mag = math.sqrt(gx**2 + gy**2 + gz**2)

        processed = {
            'ts_ms': now_ms,
            'vertical_acc': vertical_acc,
            'dyn_mag': dyn_mag,
            'gyro_mag': gyro_mag,
        }
        self._buffer.append(processed)
        if len(self._buffer) > 60:
            self._buffer.pop(0)

        # 3. Speed gate
        if speed_mps < MIN_VEHICLE_SPEED_MPS:
            return None

        # 4. Cooldown gate
        if self._last_detection_ms is not None:
            if now_ms - self._last_detection_ms < COOLDOWN_MS:
                return None

        # 5. Vertical spike threshold
        if abs(vertical_acc) < self.threshold:
            return None

        # 6. Signature confirmation
        if not self._confirm_signature(self._buffer, self.threshold):
            return None

        # Detection confirmed
        self._last_detection_ms = now_ms
        severity = compute_severity(vertical_acc, speed_mps)
        return {'vertical_acc': vertical_acc, 'severity': severity, 'ts_ms': now_ms}

    @staticmethod
    def _confirm_signature(buffer: List[Dict], threshold: float) -> bool:
        if len(buffer) < 15:
            return False

        latest = buffer[-1]
        # Phone drop rejection
        if latest['gyro_mag'] > PHONE_DROP_GYRO_THRESH:
            return False

        # Gyroscope rate check (wheel-drop evidence)
        gyro_disturbed = any(s['gyro_mag'] >= MIN_GYRO_RATE for s in buffer[-8:])
        if not gyro_disturbed:
            return False

        # Find peak in last 12 samples
        window = buffer[-12:]
        peak = max(window, key=lambda s: abs(s['vertical_acc']))
        if abs(peak['vertical_acc']) < threshold:
            return False

        peak_ts = peak['ts_ms']
        is_dip_first = peak['vertical_acc'] < 0

        # Find opposite-sign rebound within 100–400 ms
        rebound_found = False
        rebound_duration = 0
        for s in buffer:
            dt = s['ts_ms'] - peak_ts
            if dt < MIN_REBOUND_MS:
                continue
            if dt > MAX_REBOUND_MS:
                break
            opposite = (is_dip_first and s['vertical_acc'] > threshold * 0.4) or \
                       (not is_dip_first and s['vertical_acc'] < -threshold * 0.4)
            if opposite:
                rebound_found = True
                rebound_duration = dt
                break

        if not rebound_found:
            return False

        # Speed bump rejection: too-long duration
        if rebound_duration > MAX_SPEED_BUMP_DURATION_MS:
            return False

        # Railway crossing: too many zero crossings
        zero_crossings = sum(
            1 for i in range(1, len(buffer))
            if (buffer[i-1]['vertical_acc'] > 0) != (buffer[i]['vertical_acc'] > 0)
        )
        if zero_crossings >= 6:
            return False

        return True


# ─── Route Generation ─────────────────────────────────────────────────────────
def generate_route(
    start_lat: float,
    start_lon: float,
    n_waypoints: int,
    heading_deg: float = 85.0,
    speed_mps: float = 11.11,  # ~40 km/h
) -> List[Dict]:
    """Generates a sequence of GPS waypoints along a straight road segment."""
    waypoints = []
    lat, lon = start_lat, start_lon
    # Approximately 200 m between waypoints
    step_m = 200.0
    lat_step = (step_m / 111000.0) * math.cos(math.radians(heading_deg))
    lon_step = (step_m / 111000.0) * math.sin(math.radians(heading_deg))

    for i in range(n_waypoints):
        waypoints.append({
            'lat': lat + random.gauss(0, 0.000003),
            'lon': lon + random.gauss(0, 0.000003),
            'speed_mps': speed_mps + random.gauss(0, 0.5),
            'heading': heading_deg + random.gauss(0, 2.0),
            'accuracy': round(random.uniform(2.0, 6.5), 1),
        })
        lat += lat_step
        lon += lon_step

    return waypoints


def generate_imu_samples_between(
    waypoint_a: Dict,
    waypoint_b: Dict,
    n_samples: int,
    noise_level: float = 0.15,
    inject_pothole: bool = False,
    inject_speed_bump: bool = False,
) -> List[Dict]:
    """
    Generates synthetic IMU sensor samples for the road segment between two waypoints.
    Optionally injects a pothole event (sharp dip-rebound) or a speed bump (wide parabola).
    """
    samples = []
    dt_ms = 1000.0 / SAMPLE_RATE_HZ  # ~20ms per sample

    # Steady-state normal road vibration (gravity + noise)
    base_ax = random.gauss(0.0, 0.3 * noise_level)
    base_ay = random.gauss(0.0, 0.3 * noise_level)
    base_az = 9.81 + random.gauss(0.0, 0.15 * noise_level)

    for i in range(n_samples):
        ax = base_ax + random.gauss(0, noise_level * 0.5)
        ay = base_ay + random.gauss(0, noise_level * 0.5)
        az = base_az + random.gauss(0, noise_level * 0.3)
        gx = random.gauss(0, 0.08)
        gy = random.gauss(0, 0.08)
        gz = random.gauss(0, 0.05)

        if inject_pothole:
            t_center = int(n_samples * 0.55)   # event at 55% of segment
            # Dip phase: -spike
            if abs(i - t_center) < 3:
                az += random.gauss(-5.5, 0.4)   # large downward jolt
                gy += random.gauss(0.55, 0.12)  # pitch disturbance
            # Rebound phase: +spike (100–250 ms after dip)
            rebound_center = t_center + int(0.18 * SAMPLE_RATE_HZ)  # ~180 ms later
            if abs(i - rebound_center) < 4:
                az += random.gauss(4.5, 0.3)    # upward rebound

        elif inject_speed_bump:
            # Speed bump: smooth wide parabola, no sharp rebound
            t_center = int(n_samples * 0.5)
            dist = abs(i - t_center)
            if dist < 15:
                bump_force = 2.5 * math.exp(-0.02 * dist**2)
                az += bump_force

        samples.append({
            'ts_ms': i * dt_ms,
            'ax': ax, 'ay': ay, 'az': az,
            'gx': gx, 'gy': gy, 'gz': gz,
        })

    return samples


# ─── API Submission ───────────────────────────────────────────────────────────
def post_report(api_url: str, report: Dict[str, Any], timeout: int = 8) -> bool:
    if not REQUESTS_AVAILABLE:
        print(f"  [DRY-RUN] Would POST: severity={report['severity']} @ ({report['latitude']:.5f},{report['longitude']:.5f})")
        return True
    try:
        resp = requests.post(f'{api_url}/reports', json=report, timeout=timeout)
        if resp.status_code == 201:
            return True
        print(f"  [WARN] POST /reports returned {resp.status_code}: {resp.text[:80]}")
        return False
    except requests.RequestException as e:
        print(f"  [ERROR] Could not reach backend: {e}")
        return False


def check_health(api_url: str) -> bool:
    if not REQUESTS_AVAILABLE:
        return False
    try:
        resp = requests.get(f'{api_url}/health', timeout=4)
        return resp.status_code == 200
    except Exception:
        return False


# ─── Main Simulation ──────────────────────────────────────────────────────────
def run_simulation(
    api_url: str,
    n_waypoints: int,
    noise_level: float,
    device_id: str,
    speed_kmh: float,
):
    speed_mps = speed_kmh / 3.6
    print(f"\n{'='*60}")
    print(f" PotholeGuard Drive Simulator")
    print(f"{'='*60}")
    print(f" API URL     : {api_url}")
    print(f" Waypoints   : {n_waypoints}")
    print(f" Speed       : {speed_kmh:.1f} km/h ({speed_mps:.2f} m/s)")
    print(f" Noise Level : {noise_level}")
    print(f" Device ID   : {device_id[:18]}...")
    print(f"{'='*60}\n")

    # Check backend health before running
    if REQUESTS_AVAILABLE:
        healthy = check_health(api_url)
        if not healthy:
            print("[WARN] Backend is not reachable. Running in DRY-RUN mode (no actual POST).\n")

    # Generate route starting from San Francisco civic center
    route = generate_route(
        start_lat=37.7749,
        start_lon=-122.4194,
        n_waypoints=n_waypoints,
        speed_mps=speed_mps,
    )

    # Randomly assign hazard events along the route (20–35% of waypoint segments)
    n_segments = len(route) - 1
    hazard_indices = set(random.sample(
        range(1, n_segments - 1),
        min(int(n_segments * 0.28), n_segments - 2)
    ))
    speed_bump_indices = set(random.sample(
        [i for i in range(1, n_segments - 1) if i not in hazard_indices],
        min(int(n_segments * 0.10), 3)
    ))

    engine = PythonDetectionEngine(sensitivity_scale=1.0)
    engine.reset()

    total_detections = 0
    total_submitted = 0
    total_speed_bumps_rejected = 0

    print(f" Starting simulation across {n_segments} road segments...\n")

    for seg_idx in range(n_segments):
        wp_a = route[seg_idx]
        wp_b = route[seg_idx + 1]

        inject_pothole = seg_idx in hazard_indices
        inject_speed_bump = seg_idx in speed_bump_indices

        event_type = '🕳 POTHOLE' if inject_pothole else ('〰 BUMP' if inject_speed_bump else '  road')
        print(f" Segment {seg_idx+1:3d}/{n_segments}: {event_type}  ({wp_a['lat']:.5f}, {wp_a['lon']:.5f})", end='')

        samples = generate_imu_samples_between(
            wp_a, wp_b,
            n_samples=50,
            noise_level=noise_level,
            inject_pothole=inject_pothole,
            inject_speed_bump=inject_speed_bump,
        )

        segment_detected = False
        for sample in samples:
            result = engine.feed_sample(sample, wp_a['speed_mps'])
            if result is not None:
                total_detections += 1
                segment_detected = True

                # Interpolate GPS position partway through segment
                frac = 0.5 + random.uniform(-0.1, 0.1)
                det_lat = wp_a['lat'] + frac * (wp_b['lat'] - wp_a['lat'])
                det_lon = wp_a['lon'] + frac * (wp_b['lon'] - wp_a['lon'])

                report = {
                    'device_id': device_id,
                    'latitude': round(det_lat, 6),
                    'longitude': round(det_lon, 6),
                    'speed': round(wp_a['speed_mps'], 2),
                    'heading': round(wp_a['heading'], 1),
                    'accuracy': round(wp_a['accuracy'], 1),
                    'severity': result['severity'],
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'is_manual': False,
                }

                ok = post_report(api_url, report)
                if ok:
                    total_submitted += 1
                    print(f" → DETECTED (sev={result['severity']}, posted ✓)", end='')
                else:
                    print(f" → DETECTED (sev={result['severity']}, POST failed)", end='')

                break  # One event per segment

        if inject_speed_bump and not segment_detected:
            total_speed_bumps_rejected += 1

        print()  # Newline for segment
        time.sleep(0.05)  # Brief pause to avoid hammering API

    print(f"\n{'='*60}")
    print(f" Simulation Complete")
    print(f"{'='*60}")
    print(f" Segments driven     : {n_segments}")
    print(f" Pothole events      : {len(hazard_indices)}")
    print(f" Speed bumps         : {len(speed_bump_indices)} ({total_speed_bumps_rejected} correctly rejected)")
    print(f" Detections fired    : {total_detections}")
    print(f" Reports submitted   : {total_submitted}")
    print(f"{'='*60}\n")

    if total_detections > 0:
        print(f" ✅ Dashboard should now show {total_submitted} pothole report(s) at:")
        print(f"    http://localhost:5173\n")

    return {
        'segments': n_segments,
        'injected_potholes': len(hazard_indices),
        'detections': total_detections,
        'submitted': total_submitted,
        'speed_bumps_rejected': total_speed_bumps_rejected,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='PotholeGuard Drive Simulator')
    parser.add_argument('--api-url', default='http://localhost:8000/api', help='Backend API base URL')
    parser.add_argument('--count', type=int, default=25, help='Number of route waypoints')
    parser.add_argument('--noise', type=float, default=0.15, help='Sensor noise level (0.0–0.5)')
    parser.add_argument('--device-id', default=None, help='Override simulator device UUID')
    parser.add_argument('--speed-kmh', type=float, default=40.0, help='Simulated driving speed km/h')
    args = parser.parse_args()

    sim_device_id = args.device_id or f'sim-{str(uuid.uuid4())[:8]}-simulator'

    run_simulation(
        api_url=args.api_url,
        n_waypoints=args.count,
        noise_level=args.noise,
        device_id=sim_device_id,
        speed_kmh=args.speed_kmh,
    )
