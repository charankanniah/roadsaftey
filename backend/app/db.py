import os
import logging
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from app.config import settings

logger = logging.getLogger("potholeguard.db")

from sqlalchemy.pool import StaticPool

connect_args = {}
db_url = settings.DATABASE_URL
engine_kwargs = {"pool_pre_ping": True}

# Render, Heroku, and Supabase often provide postgres:// or postgresql:// URLs.
# SQLAlchemy 2+ requires the explicit dialect prefix postgresql+psycopg2://
if db_url.startswith("postgres://"):
    db_url = db_url.replace("postgres://", "postgresql+psycopg2://", 1)
elif db_url.startswith("postgresql://") and not db_url.startswith("postgresql+"):
    db_url = db_url.replace("postgresql://", "postgresql+psycopg2://", 1)

if "postgres" in db_url:
    try:
        import psycopg2  # noqa: F401
    except ImportError:
        logger.warning("psycopg2 not available in current environment; falling back to SQLite in-memory.")
        db_url = "sqlite:///:memory:"

if db_url.startswith("sqlite"):
    connect_args["check_same_thread"] = False
    engine_kwargs["poolclass"] = StaticPool

engine = create_engine(
    db_url,
    connect_args=connect_args,
    **engine_kwargs,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """FastAPI dependency for yielding database sessions."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Initialize database tables and spatial extensions if running on PostgreSQL."""
    import app.models  # noqa: F401 - ensure all ORM tables are registered on Base.metadata

    if "postgres" in db_url:
        try:
            with engine.connect() as conn:
                conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
                conn.commit()
            logger.info("PostGIS extension verified.")
        except Exception as e:
            logger.warning(f"Could not initialize PostGIS extension (might already exist or non-superuser): {e}")

    Base.metadata.create_all(bind=engine)
    logger.info("Database schemas initialized.")

    # Seed demo hazards on startup if table is empty
    try:
        from datetime import datetime, timezone
        from app.models import Pothole, PotholeStatus
        db = SessionLocal()
        if db.query(Pothole).count() == 0:
            now = datetime.now(timezone.utc)
            demo_potholes = [
                Pothole(
                    latitude=37.7749, longitude=-122.4194,
                    location="SRID=4326;POINT(-122.4194 37.7749)",
                    severity_max=4, severity_avg=3.8, confirmation_count=6,
                    status=PotholeStatus.VERIFIED, notes="Market St near 8th - Deep asphalt depression",
                    first_detected_at=now, last_detected_at=now, last_verified_at=now
                ),
                Pothole(
                    latitude=37.7680, longitude=-122.4200,
                    location="SRID=4326;POINT(-122.4200 37.7680)",
                    severity_max=5, severity_avg=4.7, confirmation_count=9,
                    status=PotholeStatus.VERIFIED, notes="Mission St & 20th - Severe road hazard",
                    first_detected_at=now, last_detected_at=now, last_verified_at=now
                ),
                Pothole(
                    latitude=37.7810, longitude=-122.4215,
                    location="SRID=4326;POINT(-122.4215 37.7810)",
                    severity_max=3, severity_avg=2.9, confirmation_count=4,
                    status=PotholeStatus.ASSIGNED, notes="Van Ness Ave - Work order #402 dispatched",
                    first_detected_at=now, last_detected_at=now
                ),
                Pothole(
                    latitude=37.7850, longitude=-122.4300,
                    location="SRID=4326;POINT(-122.4300 37.7850)",
                    severity_max=2, severity_avg=2.0, confirmation_count=2,
                    status=PotholeStatus.NEW, notes="Geary Blvd - Moderate surface crack",
                    first_detected_at=now, last_detected_at=now
                ),
                Pothole(
                    latitude=37.8020, longitude=-122.4260,
                    location="SRID=4326;POINT(-122.4260 37.8020)",
                    severity_max=4, severity_avg=3.9, confirmation_count=5,
                    status=PotholeStatus.VERIFIED, notes="Lombard approach - Significant dip",
                    first_detected_at=now, last_detected_at=now, last_verified_at=now
                ),
                Pothole(
                    latitude=37.7950, longitude=-122.3940,
                    location="SRID=4326;POINT(-122.3940 37.7950)",
                    severity_max=1, severity_avg=1.2, confirmation_count=3,
                    status=PotholeStatus.FIXED, notes="Embarcadero north - Cold patch complete",
                    first_detected_at=now, last_detected_at=now
                ),
                Pothole(
                    latitude=37.7980, longitude=-122.4080,
                    location="SRID=4326;POINT(-122.4080 37.7980)",
                    severity_max=3, severity_avg=3.0, confirmation_count=4,
                    status=PotholeStatus.ASSIGNED, notes="Columbus Ave & Broadway - Scheduled",
                    first_detected_at=now, last_detected_at=now
                ),
            ]
            db.add_all(demo_potholes)
            db.commit()
            logger.info("Demo potholes seeded successfully.")
        db.close()
    except Exception as e:
        logger.warning(f"Could not seed initial demo potholes: {e}")
