# PotholeGuard 🛡️🚗

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![PostGIS](https://img.shields.io/badge/PostGIS-Spatial%20Clustering-green.svg)](https://postgis.net/)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python%203.11-009688.svg)](https://fastapi.tiangolo.com)
[![Flutter](https://img.shields.io/badge/Mobile-Flutter%20%2B%20Dart-02569B.svg)](https://flutter.dev)
[![React](https://img.shields.io/badge/Dashboard-React%20%2B%20Leaflet-61DAFB.svg)](https://react.dev)

PotholeGuard is an autonomous road-safety platform that detects road hazards in real-time using mobile smartphone IMU sensors (accelerometer + gyroscope) and GPS, delivers zero-touch directional audio and haptic alerts to oncoming drivers, and clusters reports on an authority GIS dashboard with municipal work order tracking.

---

## Architecture Diagram

```
+-------------------------------------------------------------------------+
|                              DRIVING CLIENT                             |
|  [ Accelerometer / Gyro (50Hz) ] ---> [ Detection Engine (Dip/Rebound) ]|
|                                                     |                   |
|  [ Geolocator (1Hz GPS Fixes) ]  ---> [ Geo-Tagging & Severity Score ]  |
|                                                     |                   |
|  [ TTS Audio & Haptic Alerts ]   <--- [ Lookahead Alert Engine (<=300m)]|
|                                                     |                   |
|                                       [ Offline SQLite Queue ]          |
+-----------------------------------------------------+-------------------+
                                                      | HTTP POST Sync
                                                      v
+-------------------------------------------------------------------------+
|                        BACKEND & SPATIAL ENGINE                         |
|  FastAPI (Python 3.11) + SQLAlchemy 2 + GeoAlchemy2                     |
|  - Ingestion & Validation (/api/reports)                                |
|  - Spatial Deduplication (PostGIS ST_DWithin 10m Cluster Buffer)        |
|  - Confidence Aggregation, Auto-Verification (>=3 passes)               |
|  - Municipal Notifier (Severity 4-5 Emergency Webhook & Outbox)         |
+-----------------------------------------------------+-------------------+
                                                      |
                          +---------------------------+-------------------+
                          |                                               |
                          v                                               v
+-----------------------------------------+   +------------------------------------+
|       POSTGRESQL + POSTGIS (15)         |   |    AUTHORITY DASHBOARD (REACT)     |
| - GiST Spatial Indexing                 |   | - Real-time Leaflet Map & Clusters |
| - High-Performance BBox & Radius Query |   | - Severity Heatmap & Work Orders   |
+-----------------------------------------+   +------------------------------------+
```

---

## Safety & Privacy Disclaimer

> [!IMPORTANT]
> **Assistive Warning Notice**: PotholeGuard is strictly an assistive road-hazard awareness tool. Drivers must maintain primary attention on the road at all times. PotholeGuard enforces a **zero-touch policy** while the vehicle is in motion ($v > 10\text{ km/h}$); interactive screens and manual buttons are disabled during active driving.

> [!NOTE]
> **Data Privacy**: No Personally Identifiable Information (PII) is ever recorded or transmitted. Telemetry is linked exclusively to a randomly generated ephemeral device UUID stored locally.

---

## Quickstart & Local Setup

### Prerequisites
- Docker & Docker Compose
- Python 3.11+
- Node.js 18+ (for dashboard development)
- Flutter 3.16+ (for mobile compilation)

### 1. Launch Backend, PostGIS & Authority Dashboard
From the repository root:
```bash
# Copy default environment variables
cp .env.example .env

# Start PostGIS, FastAPI Backend, and Vite Dashboard
docker compose up --build
```
- **Backend API Docs**: http://localhost:8000/docs
- **Authority Dashboard**: http://localhost:5173
- **PostGIS Port**: `5432`

### 2. Launch Mobile Client (Flutter)
```bash
cd mobile
flutter pub get
flutter run
```

---

## Autonomous Drive Simulator

You can test and demonstrate the entire detection, ingestion, and spatial clustering pipeline without driving on physical roads:

```bash
# Run synthetic road simulation (generates IMU spikes, GPS trajectory, and posts to API)
python ml/simulate_drive.py --api-url http://localhost:8000/api --count 25
```
Options:
- `--api-url`: Backend endpoint URL (default: `http://localhost:8000/api`).
- `--count`: Number of driving coordinates / hazards to generate.
- `--noise`: Noise level ratio (default: `0.15`).

---

## Tuning Sensitivity

Sensitivity can be calibrated via the mobile settings screen or configured directly in `mobile/lib/core/config.dart`:

| Setting | Threshold Scale ($k$) | Vertical Threshold | Recommended Mount |
| :--- | :--- | :--- | :--- |
| **High Sensitivity** | 0.80 | $2.8\text{ m/s}^2$ | Soft suspension, cushioned luxury vehicles |
| **Medium (Default)** | 1.00 | $3.5\text{ m/s}^2$ | Standard passenger vehicles, vent mounts |
| **Low Sensitivity** | 1.30 | $4.55\text{ m/s}^2$ | Stiff sports suspension, heavy trucks |

---

## API Examples (cURL)

### 1. Ingest Pothole Detection Report
```bash
curl -X POST "http://localhost:8000/api/reports" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
    "latitude": 37.774929,
    "longitude": -122.419416,
    "speed": 12.5,
    "heading": 85.0,
    "accuracy": 4.2,
    "severity": 4,
    "timestamp": "2026-10-15T09:30:00Z"
  }'
```

### 2. Query Nearby Hazards (Driver Lookahead)
```bash
curl "http://localhost:8000/api/potholes/nearby?latitude=37.7749&longitude=-122.4194&radius=1000&heading=85"
```

### 3. Query Hazards Along a Route Polyline
```bash
curl -X GET "http://localhost:8000/api/alerts/route?polyline=37.7749,-122.4194;37.7752,-122.4180;37.7758,-122.4165&buffer_meters=20"
```

### 4. Authority Status Update (Requires API Key)
```bash
curl -X PATCH "http://localhost:8000/api/potholes/1/status" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: potholeguard_admin_key_2026" \
  -d '{
    "status": "assigned",
    "notes": "Dispatched maintenance crew team B"
  }'
```

---

## Known Limitations & Future Work

1. **Vision-Assisted Fusion (TFLite / YOLO)**:
   - IMU detection detects a pothole upon impact. Integrating lightweight front-facing camera inference will permit pre-impact detection (5–15 meters ahead).
2. **Crowd-Sourced IRI Road Quality Index**:
   - Aggregating continuous background acceleration variance ($Z$-axis root-mean-square) to score overall International Roughness Index (IRI) per road segment.
3. **Turn-by-Turn Routing Integration**:
   - Integrating with OSRM or Google Maps SDK to suggest detour paths avoiding heavily cratered arterial routes.
4. **iOS Platform Support**:
   - Expanding background CoreMotion / CoreLocation background task handling for iOS parity.
