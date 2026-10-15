from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Dict
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import func, text
from app.db import init_db, get_db
from app.config import settings
from app.models import Pothole, PotholeStatus, DetectionReport
from app.schemas import StatsResponse
from app.routers import potholes, alerts, reports


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize database tables & PostGIS extension
    init_db()
    yield


app = FastAPI(
    title=settings.APP_NAME,
    description="PotholeGuard backend: high-performance road hazard ingestion, spatial clustering, and driver safety alerts.",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# Enable permissive CORS for mobile app & dashboard web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register modular sub-routers under /api
app.include_router(reports.router, prefix="/api")
app.include_router(potholes.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")


@app.get("/api/health", tags=["Health"])
def health_check(db: Session = Depends(get_db)):
    """System health check endpoint verifying database connectivity."""
    db_ok = False
    try:
        db.execute(text("SELECT 1"))
        db_ok = True
    except Exception:
        db_ok = False

    return {
        "status": "healthy" if db_ok else "degraded",
        "database": "connected" if db_ok else "unreachable",
        "app_env": settings.APP_ENV,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "1.0.0",
    }


@app.get("/api/stats", response_model=StatsResponse, tags=["Potholes"])
def get_system_stats(db: Session = Depends(get_db)):
    """
    Computes aggregate metrics across all hazards for the municipal dashboard.
    """
    total = db.query(Pothole).count()
    verified = db.query(Pothole).filter(Pothole.status == PotholeStatus.VERIFIED).count()
    fixed = db.query(Pothole).filter(Pothole.status == PotholeStatus.FIXED).count()
    high_sev = db.query(Pothole).filter(Pothole.severity_max >= 4).count()

    # Status distribution
    status_counts = (
        db.query(Pothole.status, func.count(Pothole.id))
        .group_by(Pothole.status)
        .all()
    )
    by_status: Dict[str, int] = {s.value: 0 for s in PotholeStatus}
    for st, count in status_counts:
        key = st.value if hasattr(st, "value") else str(st)
        by_status[key] = count

    # Severity distribution (1-5)
    sev_counts = (
        db.query(Pothole.severity_max, func.count(Pothole.id))
        .group_by(Pothole.severity_max)
        .all()
    )
    by_severity: Dict[int, int] = {i: 0 for i in range(1, 6)}
    for sev, count in sev_counts:
        if sev in by_severity:
            by_severity[sev] = count

    return StatsResponse(
        total_potholes=total,
        verified_count=verified,
        fixed_count=fixed,
        high_severity_count=high_sev,
        by_status=by_status,
        by_severity=by_severity,
        worst_roads=[],
    )
