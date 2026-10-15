import math
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Tuple
from sqlalchemy import func, text, cast
from sqlalchemy.orm import Session
from geoalchemy2 import Geography
from app.config import settings
from app.models import Pothole, DetectionReport, PotholeStatus
from app.schemas import ReportCreate
from app.services.severity import update_rolling_average
from app.services.notifier import dispatch_emergency_notification


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate great-circle distance between two coordinates in meters.
    """
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c


def calculate_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate initial compass bearing from coordinate 1 to coordinate 2 (0-360 degrees).
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_lambda = math.radians(lon2 - lon1)

    y = math.sin(delta_lambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(delta_lambda)
    initial_bearing = math.degrees(math.atan2(y, x))
    return (initial_bearing + 360.0) % 360.0


def is_heading_aligned(vehicle_heading: float, bearing_to_target: float, threshold_deg: float = 45.0) -> bool:
    """
    Check if target bearing is within +/- threshold degrees of vehicle heading.
    """
    diff = abs(vehicle_heading - bearing_to_target) % 360.0
    if diff > 180.0:
        diff = 360.0 - diff
    return diff <= threshold_deg


def find_nearby_existing_pothole(
    db: Session,
    lat: float,
    lon: float,
    max_distance_meters: float = 10.0,
) -> Optional[Tuple[Pothole, float]]:
    """
    Locates an existing pothole within max_distance_meters using PostGIS ST_DWithin
    or Haversine fallback on SQLite.
    """
    bind = db.get_bind()
    dialect = bind.dialect.name if bind else "sqlite"

    if dialect == "postgresql":
        try:
            # PostGIS ST_DWithin on geography(Point, 4326)
            stmt = text("""
                SELECT id, ST_Distance(
                    location::geography,
                    ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography
                ) as dist
                FROM potholes
                WHERE ST_DWithin(
                    location::geography,
                    ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography,
                    :dist_m
                )
                ORDER BY dist ASC
                LIMIT 1
            """)
            result = db.execute(stmt, {"lon": lon, "lat": lat, "dist_m": max_distance_meters}).first()
            if result:
                pothole_id, dist = result[0], float(result[1])
                pothole = db.query(Pothole).filter(Pothole.id == pothole_id).first()
                if pothole:
                    return pothole, dist
        except Exception:
            # Fallback to query
            pass

    # Universal bounding-box prefilter + haversine (exact for SQLite or when PostGIS fallback needed)
    # 1 deg lat ~= 111,000 m. 10m is approx 0.0001 deg
    lat_delta = (max_distance_meters * 1.5) / 111000.0
    lon_delta = (max_distance_meters * 1.5) / (111000.0 * max(0.1, math.cos(math.radians(lat))))

    candidates = db.query(Pothole).filter(
        Pothole.latitude.between(lat - lat_delta, lat + lat_delta),
        Pothole.longitude.between(lon - lon_delta, lon + lon_delta),
        Pothole.status != PotholeStatus.FIXED,
    ).all()

    closest: Optional[Tuple[Pothole, float]] = None
    min_dist = max_distance_meters + 1.0

    for candidate in candidates:
        d = haversine_distance(lat, lon, candidate.latitude, candidate.longitude)
        if d <= max_distance_meters and d < min_dist:
            min_dist = d
            closest = (candidate, d)

    return closest


def process_detection_report(report_in: ReportCreate, db: Session) -> Tuple[DetectionReport, Pothole]:
    """
    Ingests a raw detection report: clusters it into an existing pothole within 10m
    or generates a new pothole record. Updates verification counters, severity averages,
    and triggers automated notifications when appropriate.
    """
    cluster_match = find_nearby_existing_pothole(
        db,
        report_in.latitude,
        report_in.longitude,
        max_distance_meters=settings.CLUSTER_DISTANCE_METERS,
    )

    now_utc = datetime.now(timezone.utc)
    wkt_location = f"SRID=4326;POINT({report_in.longitude} {report_in.latitude})"

    if cluster_match:
        pothole, dist = cluster_match

        # Check if this device reported this pothole very recently (within 5 minutes)
        five_mins_ago = now_utc - timedelta(minutes=5)
        recent_device_report = db.query(DetectionReport).filter(
            DetectionReport.pothole_id == pothole.id,
            DetectionReport.device_id == report_in.device_id,
            DetectionReport.created_at >= five_mins_ago,
        ).first()

        # Update severity rolling average
        pothole.severity_avg = update_rolling_average(
            pothole.severity_avg,
            pothole.confirmation_count,
            float(report_in.severity),
        )
        pothole.severity_max = max(pothole.severity_max, report_in.severity)
        pothole.last_detected_at = now_utc
        pothole.consecutive_negative_passes = 0

        # Increment confirmation count if distinct device or distinct pass (>5 mins)
        if not recent_device_report:
            pothole.confirmation_count += 1

            # Update centroid coordinates via weighted average
            k = pothole.confirmation_count
            pothole.latitude = round(((pothole.latitude * (k - 1)) + report_in.latitude) / k, 7)
            pothole.longitude = round(((pothole.longitude * (k - 1)) + report_in.longitude) / k, 7)
            pothole.location = f"SRID=4326;POINT({pothole.longitude} {pothole.latitude})"

        # Verification escalation: 3 or more passes escalates 'new' -> 'verified'
        if pothole.confirmation_count >= settings.VERIFICATION_THRESHOLD and pothole.status == PotholeStatus.NEW:
            pothole.status = PotholeStatus.VERIFIED
            pothole.last_verified_at = now_utc

            # If severity is 4-5, fire municipal notification
            if pothole.severity_avg >= 4.0 or pothole.severity_max >= 4:
                dispatch_emergency_notification(pothole, db)

    else:
        # Create brand-new pothole entity
        pothole = Pothole(
            latitude=round(report_in.latitude, 7),
            longitude=round(report_in.longitude, 7),
            location=wkt_location,
            severity_avg=float(report_in.severity),
            severity_max=report_in.severity,
            confirmation_count=1,
            status=PotholeStatus.NEW,
            first_detected_at=now_utc,
            last_detected_at=now_utc,
            consecutive_negative_passes=0,
        )
        db.add(pothole)
        db.flush()

    # Save raw detection record
    report_record = DetectionReport(
        pothole_id=pothole.id,
        device_id=report_in.device_id,
        latitude=report_in.latitude,
        longitude=report_in.longitude,
        location=wkt_location,
        speed=report_in.speed,
        heading=report_in.heading,
        accuracy=report_in.accuracy,
        severity=report_in.severity,
        is_manual=report_in.is_manual,
        timestamp=report_in.timestamp,
        created_at=now_utc,
    )
    db.add(report_record)
    db.commit()
    db.refresh(report_record)
    db.refresh(pothole)

    return report_record, pothole


def record_negative_pass(db: Session, lat: float, lon: float, speed: float) -> Optional[Pothole]:
    """
    If a vehicle passes within 5m of a recorded pothole without detecting any irregularity,
    increment consecutive_negative_passes. If threshold reached, mark possibly_fixed.
    """
    if speed < 3.0:  # Must be driving speed (> 10 km/h)
        return None

    match = find_nearby_existing_pothole(db, lat, lon, max_distance_meters=5.0)
    if not match:
        return None

    pothole, _ = match
    if pothole.status in (PotholeStatus.FIXED, PotholeStatus.POSSIBLY_FIXED):
        return pothole

    pothole.consecutive_negative_passes += 1
    if pothole.consecutive_negative_passes >= settings.NEGATIVE_PASSES_FIXED_THRESHOLD:
        pothole.status = PotholeStatus.POSSIBLY_FIXED

    db.commit()
    db.refresh(pothole)
    return pothole


def compute_confidence_decay(pothole: Pothole) -> float:
    """
    Computes a normalized confidence factor (0.0 to 1.0) taking into account
    confirmation count and inactivity decay over 30 days.
    """
    base_confidence = min(1.0, pothole.confirmation_count / float(settings.VERIFICATION_THRESHOLD))
    if pothole.last_detected_at:
        now_utc = datetime.now(timezone.utc)
        days_inactive = (now_utc - pothole.last_detected_at).total_seconds() / 86400.0
        if days_inactive > settings.DECAY_DAYS:
            decay_rate = 0.02 * (days_inactive - settings.DECAY_DAYS)
            return max(0.1, round(base_confidence - decay_rate, 2))
    return round(base_confidence, 2)
