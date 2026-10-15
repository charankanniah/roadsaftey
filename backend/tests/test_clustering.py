import pytest
from datetime import datetime, timezone
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db import Base
from app.models import Pothole, PotholeStatus, DetectionReport
from app.schemas import ReportCreate
from app.services.clustering import (
    haversine_distance,
    calculate_bearing,
    is_heading_aligned,
    process_detection_report,
    compute_confidence_decay,
)
from app.services.severity import calculate_severity, update_rolling_average


@pytest.fixture
def db_session():
    """In-memory SQLite session for isolated spatial clustering tests."""
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSession()
    try:
        yield session
    finally:
        session.close()


def test_haversine_distance():
    # San Francisco City Hall to Civic Center BART (~350m)
    lat1, lon1 = 37.77928, -122.41924
    lat2, lon2 = 37.77976, -122.41400
    dist = haversine_distance(lat1, lon1, lat2, lon2)
    assert 300 < dist < 500


def test_calculate_bearing_and_alignment():
    # Moving due North
    bearing = calculate_bearing(37.77, -122.41, 37.78, -122.41)
    assert abs(bearing - 0.0) < 1.0 or abs(bearing - 360.0) < 1.0

    # Moving heading 0 (North), pothole is bearing 15 -> aligned
    assert is_heading_aligned(0.0, 15.0, threshold_deg=45.0) is True
    # Moving heading 0 (North), pothole is bearing 180 (behind) -> not aligned
    assert is_heading_aligned(0.0, 180.0, threshold_deg=45.0) is False


def test_severity_calculation():
    # 5.0 m/s^2 at 12.5 m/s (45 km/h) -> ~ round(5/3.5 * 1.0) = 1
    # Very sharp spike 14.0 m/s^2 at 12.5 m/s -> round(14/3.5) = 4
    sev_low = calculate_severity(peak_vertical_acceleration=4.0, speed_mps=12.5)
    sev_high = calculate_severity(peak_vertical_acceleration=14.0, speed_mps=12.5)
    assert 1 <= sev_low <= 2
    assert sev_high >= 4

    # Rolling average helper
    new_avg = update_rolling_average(current_avg=2.0, current_count=1, new_value=4.0)
    assert new_avg == 3.0


def test_clustering_deduplication_within_10_meters(db_session):
    # Report 1
    r1 = ReportCreate(
        device_id="dev-001",
        latitude=37.774929,
        longitude=-122.419416,
        speed=12.0,
        heading=90.0,
        accuracy=3.0,
        severity=3,
        timestamp=datetime.now(timezone.utc),
    )
    rep1, pot1 = process_detection_report(r1, db_session)
    assert pot1.confirmation_count == 1
    assert pot1.status == PotholeStatus.NEW

    # Report 2 from another device roughly 4 meters away (same cluster)
    r2 = ReportCreate(
        device_id="dev-002",
        latitude=37.774950,
        longitude=-122.419420,
        speed=11.5,
        heading=90.0,
        accuracy=2.5,
        severity=5,
        timestamp=datetime.now(timezone.utc),
    )
    rep2, pot2 = process_detection_report(r2, db_session)

    # Must deduplicate into same pothole
    assert pot1.id == pot2.id
    assert pot2.confirmation_count == 2
    assert pot2.severity_max == 5
    assert db_session.query(Pothole).count() == 1


def test_clustering_creates_separate_potholes_beyond_10_meters(db_session):
    # Hazard 1
    r1 = ReportCreate(
        device_id="dev-001",
        latitude=37.774929,
        longitude=-122.419416,
        speed=12.0,
        accuracy=3.0,
        severity=2,
        timestamp=datetime.now(timezone.utc),
    )
    _, pot1 = process_detection_report(r1, db_session)

    # Hazard 2 roughly 200 meters away
    r2 = ReportCreate(
        device_id="dev-002",
        latitude=37.776500,
        longitude=-122.419416,
        speed=12.0,
        accuracy=3.0,
        severity=4,
        timestamp=datetime.now(timezone.utc),
    )
    _, pot2 = process_detection_report(r2, db_session)

    assert pot1.id != pot2.id
    assert db_session.query(Pothole).count() == 2


def test_auto_verification_escalation_at_three_passes(db_session):
    lat, lon = 37.774929, -122.419416

    for i in range(1, 4):
        report = ReportCreate(
            device_id=f"device-uuid-{i}",
            latitude=lat,
            longitude=lon,
            speed=10.0,
            accuracy=3.0,
            severity=4,
            timestamp=datetime.now(timezone.utc),
        )
        _, pothole = process_detection_report(report, db_session)

    assert pothole.confirmation_count == 3
    assert pothole.status == PotholeStatus.VERIFIED
    assert pothole.last_verified_at is not None
