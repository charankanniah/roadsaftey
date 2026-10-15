import math
from typing import List, Tuple
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from app.db import get_db
from app.models import Pothole, PotholeStatus
from app.schemas import RouteAlertResponse, PotholeResponse
from app.services.clustering import haversine_distance

router = APIRouter(prefix="/alerts", tags=["Alerts"])


def point_to_segment_distance(
    p_lat: float, p_lon: float,
    a_lat: float, a_lon: float,
    b_lat: float, b_lon: float,
) -> float:
    """
    Computes shortest distance in meters from a point (P) to a line segment (A-B)
    using flat-Earth local projection approximation for fast route queries.
    """
    # Convert lat/lon to approximate local metric plane coordinates (meters)
    # Origin at A
    m_per_deg_lat = 111132.954
    m_per_deg_lon = 111132.954 * math.cos(math.radians(a_lat))

    px = (p_lon - a_lon) * m_per_deg_lon
    py = (p_lat - a_lat) * m_per_deg_lat
    bx = (b_lon - a_lon) * m_per_deg_lon
    by = (b_lat - a_lat) * m_per_deg_lat

    seg_len_sq = bx * bx + by * by
    if seg_len_sq < 1e-6:
        return math.hypot(px, py)

    # Project point onto segment: t = (P . B) / |B|^2
    t = max(0.0, min(1.0, (px * bx + py * by) / seg_len_sq))
    proj_x = t * bx
    proj_y = t * by

    dx = px - proj_x
    dy = py - proj_y
    return math.hypot(dx, dy)


@router.get("/route", response_model=RouteAlertResponse)
def get_alerts_along_route(
    polyline: str = Query(..., description="Route polyline: lat1,lon1;lat2,lon2;..."),
    buffer_meters: float = Query(25.0, ge=5.0, le=200.0, description="Buffer corridor width in meters"),
    db: Session = Depends(get_db),
):
    """
    Analyzes a route polyline and retrieves all active hazards situated within
    the road corridor (buffer_meters) of the travel path.
    """
    coords: List[Tuple[float, float]] = []
    try:
        segments = polyline.strip().split(";")
        for seg in segments:
            if not seg.strip():
                continue
            lat_str, lon_str = seg.split(",")
            coords.append((float(lat_str.strip()), float(lon_str.strip())))
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Invalid polyline format. Expected: 'lat1,lon1;lat2,lon2;lat3,lon3'",
        )

    if len(coords) < 2:
        raise HTTPException(status_code=400, detail="Polyline must contain at least 2 vertices.")

    # Calculate bounding box of entire route with buffer
    min_lat = min(c[0] for c in coords)
    max_lat = max(c[0] for c in coords)
    min_lon = min(c[1] for c in coords)
    max_lon = max(c[1] for c in coords)

    deg_buf_lat = buffer_meters / 111000.0
    deg_buf_lon = buffer_meters / (111000.0 * max(0.1, math.cos(math.radians(min_lat))))

    candidates = db.query(Pothole).filter(
        Pothole.latitude.between(min_lat - deg_buf_lat, max_lat + deg_buf_lat),
        Pothole.longitude.between(min_lon - deg_buf_lon, max_lon + deg_buf_lon),
        Pothole.status != PotholeStatus.FIXED,
    ).all()

    matched_potholes: List[PotholeResponse] = []
    seen_ids = set()

    for pothole in candidates:
        min_distance_to_route = float("inf")
        for i in range(len(coords) - 1):
            a_lat, a_lon = coords[i]
            b_lat, b_lon = coords[i + 1]
            dist = point_to_segment_distance(
                pothole.latitude, pothole.longitude,
                a_lat, a_lon,
                b_lat, b_lon,
            )
            if dist < min_distance_to_route:
                min_distance_to_route = dist

        if min_distance_to_route <= buffer_meters and pothole.id not in seen_ids:
            seen_ids.add(pothole.id)
            resp = PotholeResponse.model_validate(pothole)
            resp.distance_meters = round(min_distance_to_route, 1)
            matched_potholes.append(resp)

    return RouteAlertResponse(
        potholes=matched_potholes,
        total_hazards=len(matched_potholes),
        buffer_meters=buffer_meters,
    )
