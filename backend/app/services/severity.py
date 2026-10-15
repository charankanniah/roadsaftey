import math


def calculate_severity(
    peak_vertical_acceleration: float,
    speed_mps: float,
    base_threshold: float = 3.5,
    ref_speed_mps: float = 12.5,
) -> int:
    """
    Computes a speed-normalized severity score on a 1-5 scale.
    
    Formula:
        S_raw = (|a_v| / theta_base) * (v_ref / max(v, 3.0))^0.35
        S = clamp(1, 5, round(S_raw))
    """
    effective_speed = max(float(speed_mps), 3.0)  # clamp lower bound to avoid division by zero
    speed_factor = math.pow(ref_speed_mps / effective_speed, 0.35)
    raw_score = (abs(float(peak_vertical_acceleration)) / base_threshold) * speed_factor
    rounded = int(round(raw_score))
    return max(1, min(5, rounded))


def update_rolling_average(current_avg: float, current_count: int, new_value: float) -> float:
    """
    Computes new rolling arithmetic mean:
        avg_new = (avg_old * N + val_new) / (N + 1)
    """
    if current_count <= 0:
        return float(new_value)
    total = (current_avg * current_count) + new_value
    return round(total / (current_count + 1), 2)


def is_high_severity(severity_score: float | int) -> bool:
    """True if severity reaches emergency attention threshold (Level 4 or 5)."""
    return severity_score >= 4.0
