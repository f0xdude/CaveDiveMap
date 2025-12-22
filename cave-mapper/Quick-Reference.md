# Quick Reference: Magnetic Rotation Detection

## 🚀 Quick Start

1. **Select axis** that matches your wheel rotation plane
2. **Start monitoring** - algorithm auto-adapts to environment
3. **Rotate wheel** - watch state cycle through colors
4. **Done!** No calibration needed for basic use

## 🎨 State Colors

| Color | State | Meaning |
|-------|-------|---------|
| 🟤 Gray | Idle | No magnet detected |
| 🔵 Blue | Approaching | Magnet signal increasing |
| 🟢 Green | Passing | Magnet at closest point |
| 🟠 Orange | Receding | Magnet moving away |

**Complete cycle = 1 rotation counted**

## 🎯 Axis Selection Guide

| Wheel Orientation | Select Axis |
|------------------|-------------|
| Horizontal rotation (like a record player) | **Z** or **Magnitude** |
| Vertical rotation (like a Ferris wheel) | **X** or **Y** |
| Custom orientation | Try each, use **Vector Visualization** to verify |

**Tip**: Use Vector Visualization to see which plane captures the most motion

## 🔧 Sensitivity Settings

### kHigh (Detection Threshold)

```
1.5 ━━━━━ 2.0 ━━━━━ 2.5 ━━━━━ 3.0 ━━━━━ 3.5 ━━━━━ 4.0
│          │         │          │         │          │
Very       More     Default    Less      Very       Barely
Sensitive  Sensitive           Sensitive Sensitive  Detects
```

**Too many counts?** → Increase kHigh to 3.0-3.5  
**Missing counts?** → Decrease kHigh to 2.0-2.3

### kLow (Reset Threshold)

Usually set to **1.0** (default)

- Keep it lower than kHigh
- Only adjust if getting stuck in detection state

## 📊 Diagnostic Values

### Vector Magnitude
- **Normal (idle)**: 40-60 µT
- **Magnet detected**: 100-300 µT
- **Too weak**: < 80 µT peak → Move phone closer or use stronger magnet
- **Too strong**: > 500 µT → May saturate sensor, move phone farther

### Ambient Field
- **Typical**: 40-60 µT (Earth's field)
- **Stable**: Good environment
- **Fluctuating**: Magnetic interference nearby

### Detection Threshold
- Automatically calculated: `kHigh × Variability`
- Should be **below peak magnitude** but **above idle level**

## ✅ Testing Procedure

1. **Open Settings** → Vector Visualization
2. **Observe idle state**: 
   - State should be gray "Idle"
   - Magnitude around 40-60 µT
3. **Slowly rotate wheel once**:
   - State: Gray → Blue → Green → Orange → Gray
   - Arrow should sweep around circle
   - Revolution counter should increment by 1
4. **Check console** for: `✅ ROTATION DETECTED!`

## ❌ Common Issues

### Issue: Double counting
**Quick Fix**: Increase kHigh to 3.0-3.5

### Issue: No detection
**Quick Fix**: 
1. Check Vector Magnitude during rotation (should peak >100 µT)
2. Decrease kHigh to 2.0
3. Try different axis

### Issue: Erratic behavior
**Quick Fix**:
1. Verify ambient field is stable (<10 µT variation)
2. Move away from speakers, motors, metal objects
3. Ensure magnet is securely attached

## 🛠️ Advanced Features

### Vector Visualization
- **Real-time 2D plot** of magnet position
- **Component bars** showing X, Y, Z strengths
- **State indicator** with color coding
- **Angle display** in degrees

**Access**: Settings → Vector Visualization

### Advanced Settings
- **Parameter sliders** for fine control
- **Live diagnostics** during rotation
- **Algorithm information**
- **State machine overview**

**Access**: Settings → Advanced Rotation Settings

## 💡 Pro Tips

1. **Test first without load**: Verify detection works by manually rotating wheel
2. **Watch the state sequence**: Should always be idle → approaching → passing → receding → idle
3. **Use visualization**: When tuning, keep Vector Visualization open
4. **Check console logs**: Detailed info printed for each detection
5. **Stable mounting**: Phone should maintain consistent position relative to wheel
6. **Magnet placement**: Center of wheel works best for circular path
7. **Multiple magnets**: Algorithm works best with single magnet (for now)

## 🔬 Understanding the Numbers

**Scenario: Perfect Detection**
```
Ambient Field:    50 µT   (stable Earth field)
Variability:      20      (quiet environment)
kHigh:           2.5      (default)
Detection Threshold: 50   (2.5 × 20)
Peak Magnitude:  180 µT   (magnet at closest)
Result: ✅ Detected! (180 >> 50)
```

**Scenario: Missed Detection**
```
Ambient Field:    50 µT
Variability:      15      (quiet)
kHigh:           3.5      (too high!)
Detection Threshold: 52.5 (3.5 × 15)
Peak Magnitude:   75 µT   (weak magnet)
Result: ❌ Not detected (75 > 52.5 but not enough rotation)
```

## 📱 UI Locations

```
Settings
├─ Magnetic Axis for Detection
│  └─ Axis Picker (X/Y/Z/Magnitude)
│
├─ Peak Detection Sensitivity  
│  ├─ Advanced Rotation Settings → (sliders)
│  └─ kHigh / kLow fields
│
├─ Vector Rotation Analysis
│  ├─ Detection State (colored)
│  ├─ Magnet Angle
│  ├─ Vector Magnitude
│  └─ Estimated Distance
│
├─ Magnetic Field Strength
│  └─ Raw X/Y/Z values
│
├─ Button Customization
├─ Vector Visualization → (2D plot view)
└─ PointCloud to Map
```

## 🎓 Learning Path

**Beginner**: 
- Just use default settings
- Select appropriate axis
- Watch for state changes

**Intermediate**:
- Open Vector Visualization
- Adjust kHigh based on behavior
- Understand magnitude values

**Advanced**:
- Study VectorRotationAlgorithm.md
- Modify detection parameters in code
- Implement custom filtering

## 📚 Documentation Files

- **MagneticRotationDetection-Summary.md**: Complete overview
- **VectorRotationAlgorithm.md**: Technical deep-dive
- **Quick-Reference.md**: This file
- Code comments in `MagnetometerViewModel 2.swift`

---

**Remember**: The algorithm learns your environment automatically. Just set the axis and start rolling! 🎡
