# PotholeGuard System Architecture

## 1. High-Level Overview

PotholeGuard is an intelligent, low-latency, privacy-first road safety platform designed to detect hazardous road irregularities in real-time, alert drivers before impact, and autonomously dispatch road-condition intelligence to municipal engineering teams.

```
+-------------------------------------------------------------------------+
|                              DRIVING CLIENT                             |
|  +--------------------+     +-------------------+     +--------------+  |
|  | Accelerometer / Gyro| --> | Detection Engine  | --> | Event Filter |  |
|  | (50Hz Stream)      |     | (Gravity & Rebound|     | (Spd/Cool-   |  |
|  +--------------------+     +-------------------+     |  down/Bumps) |  |
|                                                       +-------+------+  |
|                                                               |         |
|  +--------------------+     +-------------------+             v         |
|  |  Geolocator (GPS)  | --> | Geo-Tag & Queue   | <-----------+         |
|  | (1Hz Best Accuracy)|     | (SQLite Offline)  |                       |
|  +---------+----------+     +---------+---------+                       |
|            |                          |                                 |
|            v                          v HTTP POST (Sync / Batch)        |
|  +--------------------+     +----------------------------------------+  |
|  | Real-Time Alert    | <-- | REST API (FastAPI)                     |  |
|  | Engine (Lookahead, |     | - Ingestion & Auth Validation          |  |
|  | Bearing & TTS)     |     +-------------------+--------------------+  |
|  +--------------------+                         |                       |
+-------------------------------------------------|-----------------------+
                                                  v
                               +-------------------------------------+
                               | PostgreSQL 15 + PostGIS Spatial DB  |
                               | - GiST Spatial Indexing             |
                               | - ST_DWithin 10m Cluster Aggregation|
                               | - Confirmation Count & Decay        |
                               +------------------+------------------+
                                                  |
                          +-----------------------+-----------------------+
                          |                                               |
                          v                                               v
        +-----------------------------------+           +----------------------------------+
        | Municipal Notifier Service        |           | React + Vite Authority Dashboard |
        | - Severity 4-5 Emergency Webhook  |           | - Real-time Leaflet Map & Clusters|
        | - Municipal Outbox & Email Hook   |           | - Work Order Status Transitions  |
        +-----------------------------------+           +----------------------------------+
```

---

## 2. Core Components

### A. Mobile Client (Flutter / Dart)
1. **Sensor Acquisition (`sensor_service.dart`)**:
   - Subscribes to accelerometer and gyroscope streams at approximately 50 Hz.
   - Operates in a foreground execution service accompanied by a partial wake-lock (`wakelock_plus`) to prevent OS throttling when the screen dims or locks.
2. **On-Device Detection (`detection_engine.dart`)**:
   - Applies continuous gravity separation (low-pass smoothing subtracted from raw vector) to maintain orientation independence regardless of vehicle mount tilt.
   - Evaluates vertical spikes against dynamic sensitivity thresholds.
   - Confirms true pothole signatures using dip-rebound oscillation temporal windows (100–400 ms) and angular pitch/roll rates while discarding speed bumps, railway tracks, and phone handling shocks.
3. **Geo-Correlation & Offline Ingestion (`location_service.dart`, `offline_queue.dart`)**:
   - Correlates valid pothole events with current GPS position, heading, velocity, and horizontal dilution of precision (< 25 m).
   - Enqueues detected events into an encrypted SQLite local store.
   - Continuously drains local queues via exponential backoff HTTP requests to the ingestion endpoint (`/api/reports`).
4. **Driver Lookahead Alert Service (`alert_service.dart`)**:
   - Caches road hazards within a 1 km radius.
   - Computes driver vector geometry: vector angle from current coordinate to hazard must align within $\pm 45^\circ$ of driving heading.
   - Dynamic lookahead distance:
     $$D_{\text{alert}} = \text{clamp}(40\text{ m},\, v \times 6\text{ s},\, 300\text{ m})$$
   - Dispatches tiered alerts (Early Warning vs. Imminent Danger) through multi-frequency haptics, Android Text-to-Speech (TTS), and ultra-high-contrast UI banners.

---

### B. Backend API & Services (FastAPI + SQLAlchemy 2 + GeoAlchemy2)
1. **REST Interface (`backend/app/main.py`)**:
   - Fast, asynchronous Python 3.11 service exposed under `/api`.
   - Automated OpenAPI documentation with Pydantic v2 validation.
   - API key verification for authority administrative actions (`PATCH /potholes/{id}/status`).
2. **Spatial Clustering Engine (`backend/app/services/clustering.py`)**:
   - Evaluates incoming raw reports against established hazards using PostGIS `ST_DWithin` with an ellipsoidal spatial tolerance of 10 metres (`geography(Point, 4326)`).
   - If an existing pothole is matched:
     - Updates cumulative moving average of severity:
       $$\bar{S}_{k+1} = \frac{k \cdot \bar{S}_k + S_{\text{new}}}{k + 1}$$
     - Increments `confirmation_count`.
     - Automatically escalates status from `new` to `verified` when distinct device/pass count reaches $\ge 3$.
     - Refreshes centroid coordinates using weighted spatial average.
   - If no hazard is found within 10 m, generates a new pothole record.
3. **Confidence Decay & Fix Detection**:
   - Periodic or query-time decay calculation: hazards unconfirmed for >30 days experience linear confidence decay.
   - Negative reporting: if consecutive vehicles pass within 5 m at operating speed without reporting a bump, the backend tracks pass counters to mark potential road repairs (`possibly_fixed`).
4. **Municipal Notifier (`backend/app/services/notifier.py`)**:
   - Pluggable interface triggered when a pothole reaches `verified` status with high severity ($\ge 4$).
   - Commits records to a durable database outbox and dispatches asynchronous HTTP webhooks to municipal civic work systems.

---

### C. Authority Dashboard (React + Leaflet)
1. **Interactive Cartography (`MapView.jsx`)**:
   - OpenStreetMap base layer with Leaflet and `react-leaflet`.
   - Cluster markers to visualize city-wide hazard concentrations without browser lag.
   - High-visibility color palette according to severity:
     - Level 1-2: Green / Yellow (Low hazard)
     - Level 3: Orange (Moderate suspension risk)
     - Level 4-5: Crimson Red (Severe tyre / rim failure risk)
2. **Work Order Management & Audit (`ReportTable.jsx`)**:
   - Real-time tabular registry with sorting, searching, and CSV export for municipal road crews.
   - Lifecycle workflow controls: `new` $\rightarrow$ `verified` $\rightarrow$ `assigned` $\rightarrow$ `fixed`.

---

### D. Simulation Engine (`ml/simulate_drive.py`)
- Python harness capable of generating synthetic road itineraries, injecting noise, simulating speed bumps, and outputting realistic telemetry streams to exercise the entire pipeline without road travel.

---

## 3. Data Privacy & Zero-Touch Safety Contract

1. **Anonymous Telemetry**:
   - No user identity, names, phone numbers, or vehicle licenses are ever gathered or transmitted.
   - A randomly generated client UUID is created upon first application initialization.
   - GPS readings are only queried and retained during an active Drive Mode session.
2. **Zero-Touch Operation**:
   - Driver safety is paramount. When driving speed exceeds 10 km/h, all interactive inputs are locked.
   - Manual reporting is restricted to single-phrase voice commands or when stationary.
   - Visual warnings utilize massive 24pt+ bold text, high contrast amber/red warnings, and spoken audio cues.
