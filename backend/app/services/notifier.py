import json
import logging
import smtplib
from datetime import datetime, timezone
from email.mime.text import MIMEText
from typing import Dict, Any, Optional
import requests
from sqlalchemy.orm import Session
from app.config import settings
from app.models import Pothole, MunicipalOutbox

logger = logging.getLogger("potholeguard.notifier")


def municipal_erp_hook(pothole_data: Dict[str, Any]) -> bool:
    """
    Pluggable integration hook for municipal 311 or road maintenance work-order systems
    (e.g., CityWorks, Cartegraph, Maximo, Salesforce Service Cloud).
    Override or extend this function to interface with proprietary municipal APIs.
    """
    logger.info(f"[MUNICIPAL_ERP_HOOK] Forwarding critical hazard #{pothole_data.get('id')} to municipal backlog.")
    # Return True on successful integration handshake
    return True


def dispatch_emergency_notification(pothole: Pothole, db: Session) -> Optional[MunicipalOutbox]:
    """
    Dispatches automated high-severity alert when a pothole is verified and severity is >= 4.
    Writes to MunicipalOutbox, triggers webhook and email (if configured), and executes municipal ERP hook.
    """
    if pothole.severity_avg < 4.0 and pothole.severity_max < 4:
        return None

    payload = {
        "event": "CRITICAL_POTHOLE_VERIFIED",
        "id": pothole.id,
        "latitude": pothole.latitude,
        "longitude": pothole.longitude,
        "severity_avg": pothole.severity_avg,
        "severity_max": pothole.severity_max,
        "confirmation_count": pothole.confirmation_count,
        "status": pothole.status.value if hasattr(pothole.status, "value") else str(pothole.status),
        "last_detected_at": pothole.last_detected_at.isoformat() if pothole.last_detected_at else datetime.now(timezone.utc).isoformat(),
        "dispatched_at": datetime.now(timezone.utc).isoformat(),
    }

    # 1. Record to durable outbox
    outbox_entry = MunicipalOutbox(
        pothole_id=pothole.id,
        event_type="CRITICAL_POTHOLE_VERIFIED",
        payload=json.dumps(payload),
        status="pending",
    )
    db.add(outbox_entry)
    db.commit()
    db.refresh(outbox_entry)

    sent_successfully = True

    # 2. Trigger Municipal Webhook if configured
    if settings.MUNICIPAL_WEBHOOK_URL:
        try:
            resp = requests.post(
                settings.MUNICIPAL_WEBHOOK_URL,
                json=payload,
                headers={"Content-Type": "application/json", "User-Agent": "PotholeGuard-Notifier/1.0"},
                timeout=5.0,
            )
            if resp.status_code >= 400:
                logger.warning(f"Municipal webhook returned status {resp.status_code}: {resp.text}")
                sent_successfully = False
        except Exception as ex:
            logger.error(f"Failed to deliver municipal webhook to {settings.MUNICIPAL_WEBHOOK_URL}: {ex}")
            sent_successfully = False

    # 3. Trigger Email Notification via SMTP if configured
    if settings.SMTP_HOST and settings.ALERT_EMAIL_RECIPIENT:
        try:
            msg = MIMEText(
                f"Urgent Road Alert: A critical road hazard (Severity {pothole.severity_max}/5) has been confirmed "
                f"at coordinates ({pothole.latitude:.6f}, {pothole.longitude:.6f}) with {pothole.confirmation_count} passes.\n\n"
                f"Details:\n{json.dumps(payload, indent=2)}"
            )
            msg["Subject"] = f"[CRITICAL ROAD HAZARD] Pothole #{pothole.id} - Severity {pothole.severity_max}"
            msg["From"] = settings.SMTP_USER or "alerts@potholeguard.org"
            msg["To"] = settings.ALERT_EMAIL_RECIPIENT

            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=5.0) as server:
                if settings.SMTP_USER and settings.SMTP_PASSWORD:
                    server.starttls()
                    server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                server.send_message(msg)
            logger.info(f"Alert email sent to {settings.ALERT_EMAIL_RECIPIENT}")
        except Exception as ex:
            logger.error(f"Failed to send email alert: {ex}")
            sent_successfully = False

    # 4. Trigger Municipal ERP hook
    try:
        municipal_erp_hook(payload)
    except Exception as ex:
        logger.error(f"Error executing municipal ERP hook: {ex}")

    # Update outbox state
    outbox_entry.status = "sent" if sent_successfully else "failed"
    outbox_entry.sent_at = datetime.now(timezone.utc) if sent_successfully else None
    db.commit()

    return outbox_entry
