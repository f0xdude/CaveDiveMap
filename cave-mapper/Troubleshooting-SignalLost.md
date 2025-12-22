# Troubleshooting: "Signal Lost During Approach"

## Problem
You're seeing this pattern in the console:
```
🔷 Magnet detected - Approaching
❌ Signal lost during approach
🔷 Magnet detected - Approaching
❌ Signal lost during approach
```

## What This Means
The algorithm is detecting your magnet, but the signal is dropping out before it can track a complete rotation. This typically happens when:

1. **Magnet passes too quickly** - The sensor doesn't have time to track the rotation
2. **Weak magnet signal** - Not strong enough to maintain lock
3. **Intermittent signal** - Magnet orientation causes signal to fluctuate
4. **Phone positioning** - Phone is at wrong angle or too far away

## Solutions (In Order of Ease)

### 1. ⚡️ Enable Simplified Detection Mode (EASIEST)

**Go to**: Settings → Advanced Rotation Settings → Toggle "Simplified Detection Mode"

This switches to a basic peak detection algorithm that's much more forgiving. It just counts peaks instead of tracking full rotations.

**Try this first!**

### 2. 🎚️ Lower the Detection Threshold (kHigh)

**Go to**: Settings → Advanced Rotation Settings → Drag kHigh slider to **2.0 or lower**

**Current issue**: The threshold might be too high, so the algorithm loses the signal when it dips even slightly.

**What to try**:
- Start at 2.0
- If still failing, try 1.8
- If still failing, try 1.5

### 3. 📐 Lower the Minimum Rotation Angle

**Go to**: Settings → Advanced Rotation Settings → Drag "Min Rotation Angle" slider to **90° or lower**

**What it does**: Allows the algorithm to count partial rotations instead of requiring nearly a full circle.

**Good values to try**:
- 90° (quarter rotation)
- 72° (one-fifth rotation)
- 45° (one-eighth rotation)

### 4. 🧲 Check Your Magnet Setup

#### Magnet Strength Test
Watch the "Vector Magnitude" value in Advanced Settings as you rotate:
- **Good**: Peak > 150 µT
- **Okay**: Peak 100-150 µT (may need lower kHigh)
- **Weak**: Peak < 100 µT (need stronger magnet or move phone closer)

#### Phone Position
- Phone should be **perpendicular** to wheel's rotation plane
- Keep phone **5-15 cm** from magnet path
- Avoid metal objects between phone and magnet

#### Axis Selection
Try different axes in Settings:
- **Magnitude**: Best for general use
- **X/Y/Z**: Try each to see which captures most motion

### 5. 🔍 Debug with Vector Visualization

**Go to**: Settings → Vector Visualization

**What to watch**:
1. Rotate wheel slowly by hand
2. Watch the arrow in the circle
3. **Good signal**: Arrow should sweep around smoothly
4. **Bad signal**: Arrow jumps randomly or disappears

**Diagnostic values**:
```
Detection State: Should go Idle → Approach → Pass → Recede → Idle
Vector Magnitude: Should peak >100 µT
```

If the arrow doesn't sweep smoothly, try:
- Different axis selection
- Moving phone closer
- Rotating wheel slower

## Quick Fixes by Console Message

### "Signal lost during approach (mag: XX, angle: YY°)"

**If angle is < 20°**:
- Signal lost too quickly
- → Enable Simplified Mode OR lower kHigh to 1.8

**If angle is 20-60°**:
- Making progress but losing signal
- → Lower Min Rotation Angle to 45-90°

**If mag is < 60**:
- Very weak signal
- → Lower kHigh to 1.5 OR move phone much closer

### "Rotation incomplete: only XX° (need YY°)"

**Good news**: Full cycle detected, just not enough rotation!

**Solution**: Lower "Min Rotation Angle" slider until XX° exceeds the threshold

## Advanced Debugging

### Check Console for These Values

```
🔷 Magnet detected - Approaching (mag: XXX, threshold: YYY)
```
- **mag should be >> threshold** (at least 2x higher)
- If mag is barely above threshold, lower kHigh

```
❌ Signal lost during approach (mag: XXX, angle: YYY°)
```
- **If mag drops below threshold**, you need:
  - Lower kHigh (more sensitive)
  - Or Simplified Mode
- **If angle is small (<30°)**, magnet visible for very short arc:
  - Lower Min Rotation Angle
  - Or Simplified Mode

### Understanding the State Machine

**Idle** → Magnet far away  
**Approaching** → Magnet detected, signal increasing  
**Passing** → Magnet at closest point (peak)  
**Receding** → Magnet moving away, signal decreasing  
**Idle** → Magnet gone, rotation counted (if enough angle accumulated)

**Problem**: You're stuck in Idle ↔ Approaching loop

**Why**: Signal not strong/stable enough to reach Passing state

**Fix**: Simplified Mode bypasses this entirely!

## Recommended Settings for Different Scenarios

### Fast Rotating Wheel
```
Simplified Detection: ON
kHigh: 2.0
kLow: 1.0
```

### Weak Magnet
```
Simplified Detection: ON
kHigh: 1.5
kLow: 0.8
```

### Strong Magnet, Slow Rotation
```
Simplified Detection: OFF
kHigh: 2.5
kLow: 1.0
Min Rotation Angle: 90°
```

### Intermittent/Noisy Signal
```
Simplified Detection: ON
kHigh: 2.0-2.5
kLow: 0.8
```

## Step-by-Step Troubleshooting Session

1. **Open Advanced Rotation Settings**
2. **Enable Simplified Mode** → Try rotating
3. **If still failing**: Lower kHigh to 1.8 → Try rotating
4. **If still failing**: Lower kHigh to 1.5 → Try rotating
5. **If still failing**: Open Vector Visualization
   - Check if you see ANY response when rotating
   - Try different axis (X, Y, Z, Magnitude)
   - Move phone closer to magnet
6. **If Vector Magnitude never goes above 80-100 µT**:
   - Need stronger magnet OR
   - Need to move phone much closer

## Success Indicators

When it's working, you'll see:

**Console**:
```
🔷 Magnet detected - Approaching (mag: 150, threshold: 50)
🔶 Magnet passing - Peak magnitude: 180, Angle so far: 45°
🔻 Magnet receding (mag: 120, angle: 90°)
✅ ROTATION DETECTED! Total: 1, Angle traveled: 144°
```

**OR** (Simplified Mode):
```
🔷 Peak detected (simplified mode)
✅ ROTATION DETECTED (simplified)! Total: 1
```

**UI**:
- State cycles through colors: Gray → Blue → Green → Orange → Gray
- Datapoints counter increments
- Distance increases

## Still Not Working?

### Hardware Checklist
- [ ] Magnet is neodymium (strong rare-earth magnet)
- [ ] Magnet is at least 1cm diameter
- [ ] Phone is within 15cm of magnet path
- [ ] No large metal objects nearby
- [ ] Phone case doesn't have metal parts

### Software Checklist
- [ ] Simplified Mode is ON
- [ ] kHigh is 2.0 or lower
- [ ] Correct axis is selected
- [ ] App has location/motion permissions
- [ ] Phone isn't in Low Power Mode

### Test Procedure
1. Hold magnet in your hand
2. Open Vector Visualization
3. Move magnet in circle around phone (10cm away)
4. Watch Vector Magnitude:
   - Should spike >100 µT as magnet passes
   - Should drop <60 µT when magnet is far

If this test fails, issue is hardware/positioning, not algorithm settings.

## When to Use Each Mode

| Scenario | Mode | kHigh | Min Angle |
|----------|------|-------|-----------|
| **First time setup** | Simplified | 2.0 | N/A |
| **Fast wheel (>1 rev/sec)** | Simplified | 2.0 | N/A |
| **Weak magnet signal** | Simplified | 1.5-1.8 | N/A |
| **Strong magnet, slow wheel** | Full Vector | 2.5 | 90-144° |
| **Very strong magnet** | Full Vector | 3.0 | 144° |

**Bottom line**: When in doubt, use Simplified Mode! It's more reliable for most real-world conditions.

---

**Pro tip**: Once you get it working in Simplified Mode, you can try switching to Full Vector mode later for more accuracy. But Simplified Mode is perfectly fine for production use!
