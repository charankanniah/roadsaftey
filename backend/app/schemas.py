from datetime import datetime
from typing import List, Optional, Dict
from pydantic import BaseModel, Field, field_validator, ConfigDict
from app.models import PotholeStatus


class ReportCreate(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=64, description="Anonymous device UUID")
    latitude: float = Field(..., ge=-90.0, le=90.0, description="Latitude coordinate")
    longitude: float = Field(..., ge=-180.0, le=180.0, description="Longitude coordinate")
    speed: float = Field(..., ge=0.0, description="Speed in m/s")
    heading: Optional[float] = Field(None, ge=0.0, le=360.0, description="Compass bearing (0-360 deg)")
    accuracy: float = Field(..., ge=0.0, le=100.0, description="GPS horizontal accuracy in meters")
    severity: int = Field(..., ge=1, le=5, description="Computed severity score (1-5)")
    timestamp: datetime = Field(..., description="UTC ISO8601 timestamp of sensor detection")
    is_manual: bool = Field(False, description="Whether this report was manually triggered by driver")

    @field_validator("accuracy")
    @classmethod
    def validate_accuracy(cls, v: float) -> float:
        if v > 25.0:
            # We reject poor accuracy fixes (>25m) as per specification
            raise ValueError("GPS accuracy exceeds acceptable threshold of 25 meters.")
        return v


class BatchReportsCreate(BaseModel):
    reports: List[ReportCreate] = Field(..., min_length=1, max_length=100)


class ReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    pothole_id: Optional[int]
    device_id: str
    latitude: float
    longitude: float
    speed: float
    heading: Optional[float]
    accuracy: float
    severity: int
    is_manual: bool
    timestamp: datetime
    created_at: datetime


class PotholeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    latitude: float
    longitude: float
    severity_avg: float
    severity_max: int
    confirmation_count: int
    status: PotholeStatus
    first_detected_at: datetime
    last_detected_at: datetime
    last_verified_at: Optional[datetime] = None
    distance_meters: Optional[float] = None
    bearing: Optional[float] = None
    notes: Optional[str] = None


class PotholeStatusUpdate(BaseModel):
    status: PotholeStatus
    notes: Optional[str] = None


class StatsResponse(BaseModel):
    total_potholes: int
    verified_count: int
    fixed_count: int
    high_severity_count: int
    by_status: Dict[str, int]
    by_severity: Dict[int, int]
    worst_roads: List[Dict[str, str | int | float]] = []


class RouteAlertResponse(BaseModel):
    potholes: List[PotholeResponse]
    total_hazards: int
    buffer_meters: float
