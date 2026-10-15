import math
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Header, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.db import get_db
from app.config import settings
from app.models import Pothole, PotholeStatus
from app.schemas import PotholeResponse, PotholeStatusUpdate, StatsResponse
from app.services.clustering import haversine_distance, calculate_bearing, is_heading_aligned

router = APIRouter(prefix="/potholes", tags=["Potholes"])


def verify_authority_key(x_api_key: Optional[str] = Header(None, alias="X-API-Key")):
    """Validates authority administrative API key."""
    if not x_api_key or x_api_key != settings.AUTHORITY_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing authority administrative API key (X-API-Key).",
        )
    return x_api_key


@router.get("", response_model=List[PotholeResponse])
def get_potholes(
    bbox: Optional[str] = Query(None, description="Bounding box: min_lat,min_lng,max_lat,max_lng"),
    severity_min: Optional[int] = Query(None, ge=1, le=5),
    status_filter: Optional[PotholeStatus] = Query(None, alias="status"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """
    Retrieve list of potholes with optional bounding box, severity, and status filtering.
    """
    query = db.query(Pothole)

    if bbox:
        try:
            parts = [float(p.strip()) for p in bbox.split(",")]
            if len(parts) == 4:
                min_lat, min_lng, max_lat, max_lng = parts
                query = query.filter(
                    Pothole.latitude.between(min_lat, max_lat),
                    Pothole.longitude.between(min_lng, max_lng),
                )
        except ValueError:
            raise HTTPException(status_code=400, detail="Malformed bbox parameter. Format: min_lat,min_lng,max_lat,max_lng")

    if severity_min:
        query = query.filter(Pothole.severity_max >= severity_min)

    if status_filter:
        query = query.filter(Pothole.status == status_filter)

    potholes = query.order_by(Pothole.last_detected_at.desc()).offset(offset).limit(limit).all()
    return potholes


@router.get("/nearby", response_model=List[PotholeResponse])
def get_nearby_potholes(
    latitude: float = Query(..., ge=-90.0, le=90.0),
    longitude: float = Query(..., ge=-180.0, le=180.0),
    radius: float = Query(1000.0, ge=10.0, le=10000.0, description="Search radius in meters"),
    heading: Optional[float] = Query(None, ge=0.0, le=360.0, description="Current heading (0-360) to filter hazards ahead"),
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """
    Locates hazards near the given coordinate, optionally filtering to only those directly
    ahead in the driver's heading direction (+/- 45 degrees).
    """
    # Approximate degree delta for bounding box prefilter
    lat_delta = radius / 111000.0
    lon_delta = radius / (111000.0 * max(0.1, math.cos(math.radians(latitude))))

    candidates = db.query(Pothole).filter(
        Pothole.latitude.between(latitude - lat_delta, latitude + lat_delta),
        Pothole.longitude.between(longitude - lon_delta, longitude + lon_delta),
        Pothole.status != PotholeStatus.FIXED,
    ).all()

    results: List[PotholeResponse] = []

    for pothole in candidates:
        dist = haversine_distance(latitude, longitude, pothole.latitude, pothole.longitude)
        if dist > radius:
            continue

        bearing = calculate_bearing(latitude, longitude, pothole.latitude, pothole.longitude)

        # If heading supplied, filter to only hazards positioned ahead of the driver (+/- 45 deg)
        if heading is not None:
            if not is_heading_aligned(heading, bearing, threshold_deg=45.0):
                continue

        resp_obj = PotholeResponse.model_validate(pothole)
        resp_obj.distance_meters = round(dist, 1)
        resp_obj.bearing = round(bearing, 1)
        results.append(resp_obj)

    # Sort nearest first
    results.sort(key=lambda x: x.distance_meters or 0.0)
    return results[:limit]


@router.get("/{id}", response_model=PotholeResponse)
def get_pothole_by_id(id: int, db: Session = Depends(get_db)):
    """Retrieve detailed state of a single pothole."""
    pothole = db.query(Pothole).filter(Pothole.id == id).first()
    if not pothole:
        raise HTTPException(status_code=404, detail=f"Pothole #{id} not found.")
    return pothole


@router.patch("/{id}/status", response_model=PotholeResponse)
def update_pothole_status(
    id: int,
    status_update: PotholeStatusUpdate,
    db: Session = Depends(get_db),
    _key: str = Depends(verify_authority_key),
):
    """
    Authority endpoint to update hazard lifecycle status (new -> verified -> assigned -> fixed).
    Secured with X-API-Key.
    """
    pothole = db.query(Pothole).filter(Pothole.id == id).first()
    if not pothole:
        raise HTTPException(status_code=404, detail=f"Pothole #{id} not found.")

    pothole.status = status_update.status
    if status_update.notes:
        pothole.notes = status_update.notes

    db.commit()
    db.refresh(pothole)
    return pothole
