import time
from collections import defaultdict
from typing import Union, List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db import get_db
from app.config import settings
from app.schemas import ReportCreate, BatchReportsCreate, ReportResponse
from app.services.clustering import process_detection_report

router = APIRouter(prefix="/reports", tags=["Reports"])

# Simple in-memory sliding-window rate limiter per device ID
# device_id -> list of unix timestamps
_device_request_timestamps = defaultdict(list)


def check_rate_limit(device_id: str):
    """Enforces per-device rate limiting (default 120 req/min)."""
    now = time.time()
    window_start = now - 60.0
    timestamps = _device_request_timestamps[device_id]

    # Clean old timestamps
    _device_request_timestamps[device_id] = [t for t in timestamps if t >= window_start]

    if len(_device_request_timestamps[device_id]) >= settings.RATE_LIMIT_PER_MINUTE:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit exceeded for device {device_id}. Max {settings.RATE_LIMIT_PER_MINUTE} reports/minute.",
        )

    _device_request_timestamps[device_id].append(now)


@router.post("", response_model=Union[ReportResponse, List[ReportResponse]], status_code=status.HTTP_201_CREATED)
def submit_report(
    payload: Union[BatchReportsCreate, ReportCreate],
    db: Session = Depends(get_db),
):
    """
    Ingests road irregularity telemetry reports from driving clients.
    Supports single report submissions or batched uploads from offline synchronization.
    """
    if isinstance(payload, BatchReportsCreate):
        reports_in = payload.reports
        is_batch = True
    elif isinstance(payload, ReportCreate):
        reports_in = [payload]
        is_batch = False
    else:
        raise HTTPException(status_code=400, detail="Invalid payload structure.")

    responses: List[ReportResponse] = []

    for report in reports_in:
        # Enforce rate limiting
        check_rate_limit(report.device_id)

        # Ingest and spatially cluster
        report_record, _ = process_detection_report(report, db)
        responses.append(ReportResponse.model_validate(report_record))

    return responses if is_batch else responses[0]
