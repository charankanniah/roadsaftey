import os
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "PotholeGuard API"
    APP_ENV: str = "development"
    DEBUG: bool = False
    PORT: int = 8000

    # PostgreSQL + PostGIS Connection
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg2://potholeguard:potholeguard_secret@localhost:5432/potholeguard"
    )

    # Authority Administration Key
    AUTHORITY_API_KEY: str = os.getenv("AUTHORITY_API_KEY", "potholeguard_admin_key_2026")

    # Ingestion & Spatial Thresholds
    RATE_LIMIT_PER_MINUTE: int = 120
    CLUSTER_DISTANCE_METERS: float = 10.0
    VERIFICATION_THRESHOLD: int = 3
    DECAY_DAYS: int = 30
    NEGATIVE_PASSES_FIXED_THRESHOLD: int = 5

    # Notification Hooks
    MUNICIPAL_WEBHOOK_URL: str = os.getenv("MUNICIPAL_WEBHOOK_URL", "")
    SMTP_HOST: str = os.getenv("SMTP_HOST", "")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER: str = os.getenv("SMTP_USER", "")
    SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
    ALERT_EMAIL_RECIPIENT: str = os.getenv("ALERT_EMAIL_RECIPIENT", "")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()
