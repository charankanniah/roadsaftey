import pytest
from datetime import datetime, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.main import app
from app.db import Base, get_db
from app.config import settings

# Test in-memory database with StaticPool so all connections share tables
test_engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_database():
    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)
    yield


def test_health_endpoint():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"


def test_submit_single_report_and_retrieve_pothole():
    payload = {
        "device_id": "test-device-uuid-1",
        "latitude": 37.774929,
        "longitude": -122.419416,
        "speed": 12.5,
        "heading": 90.0,
        "accuracy": 4.5,
        "severity": 4,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "is_manual": False,
    }
    res = client.post("/api/reports", json=payload)
    assert res.status_code == 201
    report_data = res.json()
    assert report_data["device_id"] == "test-device-uuid-1"
    assert report_data["pothole_id"] is not None

    # Verify retrieval
    pothole_res = client.get(f"/api/potholes/{report_data['pothole_id']}")
    assert pothole_res.status_code == 200
    pothole_data = pothole_res.json()
    assert pothole_data["severity_max"] == 4
    assert pothole_data["status"] == "new"


def test_submit_report_rejects_poor_accuracy():
    payload = {
        "device_id": "test-device-uuid-1",
        "latitude": 37.774929,
        "longitude": -122.419416,
        "speed": 12.5,
        "accuracy": 35.0,  # Exceeds 25m limit
        "severity": 3,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    res = client.post("/api/reports", json=payload)
    assert res.status_code == 422  # Unprocessable Entity validation error


def test_batch_reports_submission():
    batch_payload = {
        "reports": [
            {
                "device_id": "dev-sync-1",
                "latitude": 37.7750,
                "longitude": -122.4190,
                "speed": 10.0,
                "accuracy": 5.0,
                "severity": 2,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
            {
                "device_id": "dev-sync-1",
                "latitude": 37.7800,
                "longitude": -122.4100,
                "speed": 11.0,
                "accuracy": 4.0,
                "severity": 5,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        ]
    }
    res = client.post("/api/reports", json=batch_payload)
    assert res.status_code == 201
    assert len(res.json()) == 2


def test_nearby_potholes_with_heading_filter():
    # Insert pothole to the North (37.7800, -122.4194)
    client.post("/api/reports", json={
        "device_id": "dev-1",
        "latitude": 37.7800,
        "longitude": -122.4194,
        "speed": 12.0,
        "accuracy": 3.0,
        "severity": 3,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })

    # Query from South (37.7750, -122.4194) facing North (heading = 0)
    res_ahead = client.get("/api/potholes/nearby?latitude=37.7750&longitude=-122.4194&radius=1000&heading=0")
    assert res_ahead.status_code == 200
    items = res_ahead.json()
    assert len(items) == 1
    assert items[0]["distance_meters"] > 0

    # Query facing South (heading = 180), pothole is behind -> should be empty
    res_behind = client.get("/api/potholes/nearby?latitude=37.7750&longitude=-122.4194&radius=1000&heading=180")
    assert res_behind.status_code == 200
    assert len(res_behind.json()) == 0


def test_alerts_along_route():
    # Insert a hazard on Market St (SF)
    client.post("/api/reports", json={
        "device_id": "dev-1",
        "latitude": 37.7780,
        "longitude": -122.4150,
        "speed": 12.0,
        "accuracy": 3.0,
        "severity": 4,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })

    # Query with a polyline passing through that coordinate
    polyline = "37.7770,-122.4160;37.7790,-122.4140"
    res = client.get(f"/api/alerts/route?polyline={polyline}&buffer_meters=50")
    assert res.status_code == 200
    data = res.json()
    assert data["total_hazards"] == 1


def test_authority_status_update_auth():
    # Create hazard
    rep_res = client.post("/api/reports", json={
        "device_id": "dev-1",
        "latitude": 37.7780,
        "longitude": -122.4150,
        "speed": 12.0,
        "accuracy": 3.0,
        "severity": 4,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
    pothole_id = rep_res.json()["pothole_id"]

    # Attempt status update without key -> 401
    res_unauth = client.patch(f"/api/potholes/{pothole_id}/status", json={"status": "assigned"})
    assert res_unauth.status_code == 401

    # Attempt with valid key -> 200
    res_auth = client.patch(
        f"/api/potholes/{pothole_id}/status",
        headers={"X-API-Key": settings.AUTHORITY_API_KEY},
        json={"status": "assigned", "notes": "Dispatched maintenance crew"},
    )
    assert res_auth.status_code == 200
    assert res_auth.json()["status"] == "assigned"


def test_stats_endpoint():
    res = client.get("/api/stats")
    assert res.status_code == 200
    stats = res.json()
    assert "total_potholes" in stats
    assert "by_status" in stats
    assert "by_severity" in stats
