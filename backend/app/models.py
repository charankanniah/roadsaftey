import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    Integer,
    Float,
    String,
    Boolean,
    DateTime,
    ForeignKey,
    Text,
    Enum as SQLEnum,
)
from sqlalchemy.orm import relationship
from sqlalchemy.types import TypeDecorator
from geoalchemy2 import Geometry
from app.db import Base


class PointLocation(TypeDecorator):
    """
    Cross-dialect spatial point: maps to PostGIS Geometry(POINT, 4326) on PostgreSQL,
    and falls back to Text (WKT representation) on SQLite for lightweight testing.
    """
    impl = Text
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(Geometry(geometry_type="POINT", srid=4326, spatial_index=True))
        return dialect.type_descriptor(Text())

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if isinstance(value, str):
            return value
        # If passed as (lat, lon) or [lon, lat]
        if isinstance(value, (tuple, list)) and len(value) == 2:
            lon, lat = value[0], value[1]
            return f"SRID=4326;POINT({lon} {lat})"
        return value

    def process_result_value(self, value, dialect):
        return value


class PotholeStatus(str, enum.Enum):
    NEW = "new"
    VERIFIED = "verified"
    ASSIGNED = "assigned"
    FIXED = "fixed"
    POSSIBLY_FIXED = "possibly_fixed"


class Pothole(Base):
    __tablename__ = "potholes"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    latitude = Column(Float, nullable=False, index=True)
    longitude = Column(Float, nullable=False, index=True)
    location = Column(PointLocation, nullable=True)

    severity_avg = Column(Float, default=1.0, nullable=False)
    severity_max = Column(Integer, default=1, nullable=False)
    confirmation_count = Column(Integer, default=1, nullable=False)
    status = Column(SQLEnum(PotholeStatus), default=PotholeStatus.NEW, nullable=False, index=True)

    first_detected_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    last_detected_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    last_verified_at = Column(DateTime(timezone=True), nullable=True)

    consecutive_negative_passes = Column(Integer, default=0, nullable=False)
    notes = Column(Text, nullable=True)

    # Relationship to individual raw reports
    reports = relationship("DetectionReport", back_populates="pothole", cascade="all, delete-orphan")
    outbox_entries = relationship("MunicipalOutbox", back_populates="pothole", cascade="all, delete-orphan")


class DetectionReport(Base):
    __tablename__ = "detection_reports"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    pothole_id = Column(Integer, ForeignKey("potholes.id"), nullable=True, index=True)
    device_id = Column(String(64), nullable=False, index=True)

    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    location = Column(PointLocation, nullable=True)

    speed = Column(Float, nullable=False)  # m/s
    heading = Column(Float, nullable=True)  # degrees 0-360
    accuracy = Column(Float, nullable=False)  # meters
    severity = Column(Integer, nullable=False)  # 1 to 5
    is_manual = Column(Boolean, default=False, nullable=False)

    timestamp = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    pothole = relationship("Pothole", back_populates="reports")


class MunicipalOutbox(Base):
    __tablename__ = "municipal_outbox"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    pothole_id = Column(Integer, ForeignKey("potholes.id"), nullable=False, index=True)
    event_type = Column(String(64), nullable=False)
    payload = Column(Text, nullable=False)
    status = Column(String(32), default="pending", nullable=False)  # pending, sent, failed

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    sent_at = Column(DateTime(timezone=True), nullable=True)

    pothole = relationship("Pothole", back_populates="outbox_entries")
