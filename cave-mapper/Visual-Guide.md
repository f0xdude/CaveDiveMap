# Visual Guide: How the Algorithm Works

## 🎡 Magnet Rotation Around Wheel

```
                    Phone
                      📱
                      |
        View from above, looking down at wheel
        
              North (0°)
                  ↑
                  |
    270° ←--------●--------→ 90°
        (West)   Wheel   (East)
                  |
                  ↓
              South (180°)


    Magnet attached to rim 🧲
    Rotates around center as wheel turns
```

## 📐 Detection Plane Concept

### For Horizontal Wheel (Z-axis rotation):
```
    Side View:          Top View (Detection Plane):
    
    ═══════════         ┌─────────────┐
       Wheel            │             │
    ═══════════         │      ●      │  ← Wheel center
         🧲             │   (Phone)   │
      Magnet            │             │
                        │   🧲→       │  ← Magnet moves in XY plane
    Detection           └─────────────┘
    happens in          
    XY plane            We track angle here!
```

## 🔄 State Machine Diagram

```
                    ┌──────────┐
                    │          │
        Start   ──→ │   IDLE   │ ←──┐
                    │          │    │
                    └────┬─────┘    │
                         │          │
                    Magnitude >     │
                    Threshold       │
                         │          │
                    ┌────▼─────┐    │
                    │APPROACH- │    │
                    │   ING    │    │
                    └────┬─────┘    │
                         │          │
                    Peak detected   │
                         │          │
                    ┌────▼─────┐    │
                    │          │    │
                    │ PASSING  │    │
                    │          │    │
                    └────┬─────┘    │
                         │          │
                   Magnitude drops  │
                         │          │
                    ┌────▼─────┐    │
                    │          │    │
                    │ RECEDING │    │
                    │          │    │
                    └────┬─────┘    │
                         │          │
                    Below threshold │
                    + Full rotation │
                         │          │
                    Count rotation! │
                         │          │
                         └──────────┘
```

## 📊 Magnetic Field Components

### What the Phone Sees:

```
    Total Field = Ambient Field + Anomaly Field
                  (Earth + env)   (Magnet)

    
    Ambient:    🌍 ──────────→  (constant, ~50 µT)
    
    Anomaly:    🧲 ─→           (varies with magnet position)
                   ↓
                  Increases as magnet approaches
                  Peaks when closest
                  Decreases as magnet recedes
```

### Example Rotation Sequence:

```
Time →  0s      0.2s     0.4s     0.6s     0.8s
        
Magnet  Before  Approach Passing  Recede   After
Pos:    ■───→─┐ ■────→─┐ ■─────→ ■←────   ■
              │        │
State:  Idle   Approach Passing  Recede   Idle

Mag:    50 µT   100 µT  180 µT   110 µT   55 µT
        ▁▁▁     ▃▃▃     ▇▇▇     ▄▄▄     ▁▁▁

Angle:   -       45°     90°     135°     -

Action:                          ✅ COUNT!
```

## 🎯 Vector Visualization Explained

### The Circular Display:

```
        ┌───────────────────────┐
        │         ↑ Y           │
        │         │             │
        │    ┌────┼────┐        │  Outer circle: Max range
        │    │    │    │        │  
        │ X ─┼────●────┼─       │  Center ●: Phone position
        │    │    │    │        │
        │    └────┼────┘        │  Inner circle: Threshold
        │         │             │
        │                       │  
        └───────────────────────┘
        
        
        Arrow shows:
        - Direction: Where magnet is relative to phone
        - Length: How strong the signal
        - Color: Current state
                 Gray   = Idle
                 Blue   = Approaching  
                 Green  = Passing
                 Orange = Receding
```

### Example Rotation Visualization:

```
    Position 1 (0°):        Position 2 (90°):      Position 3 (180°):
    
    ┌───────────────┐       ┌───────────────┐       ┌───────────────┐
    │      🧲        │       │               │       │               │
    │       ↓        │       │               │       │               │
    │       │        │       │         🧲    │       │               │
    │       ●        │       │      ← ─●     │       │       ●       │
    │               │       │               │       │       ↑       │
    │               │       │               │       │       │       │
    └───────────────┘       └───────────────┘       │      🧲        │
    State: Approaching      State: Passing          └───────────────┘
    Angle: 0°               Angle: 90°              State: Receding
                                                    Angle: 180°
```

## 📈 Signal Over Time

### Perfect Detection:

```
Magnitude
(µT)
300 ┤
    │                      Peak (passing)
250 ┤                     ╱────╲
    │                   ╱        ╲
200 ┤                 ╱            ╲
    │               ╱                ╲
150 ┤             ╱                    ╲
    │           ╱                        ╲
100 ┤         ╱                            ╲
    │       ╱                                ╲
 50 ┤─────╱────────────────────────────────────╲──────
    │   Approach                           Recede
  0 └─────┬────────┬────────┬────────┬────────┬──────→
        0s      0.2s     0.4s     0.6s     0.8s   Time

State:  Idle   →  Approach → Pass → Recede → Idle
Threshold: ─ ─ ─ ─ ─ ─ 50 µT ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
```

### Problem: Noisy Signal:

```
Magnitude
(µT)
200 ┤          ╱╲  ╱╲      Without vector analysis,
    │         ╱  ╲╱  ╲     these would be false
150 ┤        ╱        ╲    positives!
    │       ╱          ╲       ↓    ↓
100 ┤    ╱─╲  ╱──╲  ╱──╲╲   ╱╲  ╱╲
    │   ╱   ╲╱    ╲╱    ╲ ╲╱  ╲╱  ╲
 50 ┤──╱────────────────────────────╲─────
    │                                 ╲
  0 └──────────────────────────────────╲──→ Time

    With vector analysis: ✅ Only counts complete
    rotation cycles with proper angle coverage
```

## 🧮 Math in Action

### Angle Calculation:

```
    Detection Plane (XY example):
    
         Y
         ↑
         │
         │    🧲 (x=30, y=40)
         │   ╱
         │  ╱
         │ ╱
         │╱ θ = atan2(40, 30)
    ─────●────────→ X
         │         = 53.1°
         
    As magnet rotates:
    θ changes from 0° → 360°
    
    We track: Δθ = θ_current - θ_previous
    Cumulative: Σ Δθ
    
    When Σ Δθ ≥ 288° (80% of 360°):
    ✅ Count rotation!
```

### Threshold Adaptation:

```
    Adaptive Threshold = kHigh × Variability
    
    Example in quiet environment:
    Variability = 20
    kHigh = 2.5
    Threshold = 2.5 × 20 = 50 µT
    
    Example in noisy environment:
    Variability = 40  (higher noise)
    kHigh = 2.5
    Threshold = 2.5 × 40 = 100 µT  (auto-increased!)
```

## 🔬 Component Breakdown

### What Each Bar Shows:

```
    X Component Bar:    Y Component Bar:    Z Component Bar:
    
    ▓▓▓ 100%           ▓▓▓ 100%           ▓▓▓ 100%
    ▓▓▓                ░░░                ▓▓▓
    ▓▓▓  80 µT         ░░░  20 µT        ▓▓▓  90 µT
    ▓▓▓                ░░░                ▓▓▓
    ░░░                ░░░                ▓▓▓
    ░░░  0%            ░░░  0%            ▓▓▓  0%
    
    Red = Strong        Blue = Weak       Red = Strong
    Magnet is mainly    Little Y          Magnet has strong
    in X direction      component         Z component
```

## 🎮 Interactive Elements

### What Happens When You Tap "Advanced Settings":

```
    1. Opens slider interface
    2. Shows live magnitude
    3. Displays current state
    4. Updates threshold in real-time
    5. You can tune while rotating wheel!
```

### What Happens During Calibration:

```
    Old System:         New System:
    Collect peaks   →   Not really needed!
    Set thresholds      Algorithm adapts
                        automatically
    
    But still available for fine-tuning
```

## 🎪 Complete Workflow

```
    START
      ↓
    Open App
      ↓
    Select Axis (X/Y/Z/Magnitude)
      ↓
    Place Phone Near Wheel
      ↓
    Start Monitoring
      ↓
    ┌─────────────────────┐
    │ Algorithm           │
    │ • Measures field    │
    │ • Estimates ambient │
    │ • Calculates anomaly│
    │ • Tracks angle      │
    │ • Updates state     │
    │ • Counts rotations  │
    └─────────────────────┘
      ↓
    Rotate Wheel
      ↓
    Watch State Change
    (Gray → Blue → Green → Orange → Gray)
      ↓
    Counter Increments ✅
      ↓
    Distance Calculated
    (Revolutions × Circumference)
      ↓
    Data Logged
      ↓
    END (or continue monitoring)
```

## 🎨 Color Coding Throughout UI

| Color | Meaning | Where Used |
|-------|---------|------------|
| 🟤 Gray | Idle/Normal | State indicator, bars at rest |
| 🔵 Blue | Active/Approaching | State, info text, settings links |
| 🟢 Green | Success/Passing | Checkmarks, peak state, "good" values |
| 🟠 Orange | Warning/Receding | Thresholds, receding state |
| 🔴 Red | High/Critical | High magnitude, errors, reset button |

---

**Visual learning tip**: Open Vector Visualization and rotate wheel slowly to see all these concepts in action! 🎡
