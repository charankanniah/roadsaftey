# PotholeGuard Detection Algorithm Specification

## 1. Mathematical Formulation & Coordinate Invariance

Smartphones are positioned arbitrarily inside vehicles (dashboard suction mounts, air vent clips, or cup holders). Therefore, fixed axes ($x, y, z$) cannot be assumed to align with the vehicle body frame. PotholeGuard computes an orientation-invariant reference frame dynamically.

### A. Gravity Estimation & Linear Acceleration Separation
Let $\mathbf{a}_t = [a_x, a_y, a_z]^T$ be the tri-axial acceleration sampled from the IMU at approximately 50 Hz ($\Delta t \approx 0.02\text{ s}$).

1. **Low-Pass Filter for Gravity Vector**:
   $$\mathbf{g}_t = \alpha \mathbf{g}_{t-1} + (1 - \alpha) \mathbf{a}_t$$
   Where $\alpha = 0.92$ (time constant $\tau \approx 0.25\text{ s}$).

2. **Gravity Unit Direction**:
   $$\hat{\mathbf{g}}_t = \frac{\mathbf{g}_t}{\|\mathbf{g}_t\|}$$

3. **Linear (Dynamic) Acceleration Vector**:
   $$\mathbf{a}_{\text{dyn}, t} = \mathbf{a}_t - \mathbf{g}_t$$

4. **True Vertical Acceleration ($a_v$)**:
   $$a_{v, t} = \mathbf{a}_{\text{dyn}, t} \cdot \hat{\mathbf{g}}_t$$

By projecting linear acceleration onto the dynamically tracked gravity normal vector $\hat{\mathbf{g}}_t$, $a_{v, t}$ precisely isolates vertical vehicle displacement irrespective of phone orientation.

---

## 2. Multi-Stage Detection Pipeline

An event is flagged as a pothole if and only if **ALL** of the following conditions are satisfied:

```
[IMU Stream: 50 Hz]
        |
        v
[Gravity Projection -> a_v]
        |
        +---> Condition 1: Peak Vertical Spike > 3.5 m/s² * sensitivity_scale
        |
        +---> Condition 2: Dip-Rebound Signature (opposite-sign rebound within 100 - 400 ms)
        |
        +---> Condition 3: Gyroscope Pitch/Roll Angular Rate Change
        |
        +---> Condition 4: Vehicle Speed > 10 km/h (Geolocator)
        |
        +---> Condition 5: Cooldown Timer (>= 2.0s since last detection)
        |
        +---> Condition 6: False Positive Rejection (Speed Bumps, Braking, Drops)
        |
        v
[VALID POTHOLE EVENT] -> Compute Severity Score (1-5) -> Geo-Tag -> Queue
```

### Detailed Criteria:

1. **Vertical Threshold Spike**:
   $$|a_{v, t}| \ge \theta_{\text{base}} \times k_{\text{sensitivity}}$$
   - $\theta_{\text{base}} = 3.5\text{ m/s}^2$
   - $k_{\text{sensitivity}} \in [0.7, 1.4]$ (Low: 1.3, Medium: 1.0, High: 0.8)

2. **Dip-Rebound Shape Profile**:
   When a tyre drops into a depression and strikes the trailing rim, the acceleration profile exhibits an initial negative (downward drop) acceleration spike immediately followed by a steep positive rebound (upward impact) within a narrow window:
   $$t_{\text{rebound}} - t_{\text{dip}} \in [0.100\text{ s},\, 0.400\text{ s}]$$
   Both the drop and the rebound magnitudes must exceed $0.5 \times \text{threshold}$.

3. **Angular Rate Confirmation (Gyroscope)**:
   A single-wheel or axle pothole encounter induces rapid angular roll or pitch rotation:
   $$\|\boldsymbol{\omega}_t\| = \sqrt{\omega_{\text{pitch}}^2 + \omega_{\text{roll}}^2 + \omega_{\text{yaw}}^2} \ge 0.35\text{ rad/s}$$

4. **Speed Gate**:
   GPS velocity $v \ge 2.78\text{ m/s}$ ($10\text{ km/h}$). Shocks below this velocity are discarded to prevent walking, stationary handling, or door slams from triggering false alerts.

5. **Temporal Cooldown**:
   A minimum interval of $\Delta t_{\text{cooldown}} = 2.0\text{ s}$ is enforced between discrete detections to prevent multi-triggering from the front and rear tyres of the same vehicle.

---

## 3. False Positive Rejection Engine

| False Positive Candidate | Identifying Physical Characteristics | Rejection Rule |
| :--- | :--- | :--- |
| **Speed Bump / Table** | Extended wave period ($\Delta t > 0.45\text{ s}$), smooth parabolic crest without sharp rebound, preceding vehicle deceleration ($\Delta v < 0$). | If rebound occurs after $> 0.45\text{ s}$ and acceleration profile is convex/smooth without high-frequency jerk, classify as Speed Bump and discard. |
| **Railway Crossing** | Periodic rhythmic oscillations across $\ge 3$ repeated cycles with consistent frequency. | If zero-crossing count $\ge 4$ within $1.2\text{ s}$ with near-uniform amplitude, classify as Railway and discard. |
| **Phone Drop / Handling** | Enormous rotational rate ($\|\boldsymbol{\omega}\| > 4.0\text{ rad/s}$) without synchronized GPS displacement or road impact profile. | If rotational velocity exceeds $4.0\text{ rad/s}$ without directional vertical rebound alignment, discard as Phone Drop. |
| **Hard Braking** | Sustained longitudinal acceleration with near-zero vertical drop-rebound. | Vector projection along gravity normal has small variance compared to horizontal braking axis. |

---

## 4. Speed-Normalized Severity Rating (1 to 5)

Vehicle velocity significantly influences measured impact acceleration: a minor defect hit at $80\text{ km/h}$ generates higher raw acceleration than a deep crater traversed at $15\text{ km/h}$. PotholeGuard normalizes impact force by reference speed ($v_{\text{ref}} = 45\text{ km/h} \approx 12.5\text{ m/s}$).

### Severity Formula:
$$S_{\text{raw}} = \frac{|a_{v, \text{peak}}|}{\theta_{\text{base}}} \times \left(\frac{v_{\text{ref}}}{\max(v,\, 3.0)}\right)^{0.35}$$

Integer Mapping:
$$S = \text{clamp}\Big(1,\, 5,\, \text{round}(S_{\text{raw}})\Big)$$

- **Level 1 (Minor)**: Surface degradation, slight dip (no rim danger).
- **Level 2 (Moderate)**: Shallow pothole, minor suspension thud.
- **Level 3 (Notable)**: Substantial pothole, sharp jolt, alignment hazard.
- **Level 4 (Severe)**: Deep pothole, rim pinching hazard, high blowout risk.
- **Level 5 (Critical)**: Dangerous crater, immediate vehicle damage / loss of control hazard.
