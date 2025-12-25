# Optical Wheel Detection - Quick Start Guide

## 🚀 30-Second Setup

### 1. Add Camera Permission
Add to `Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to detect wheel rotations for distance measurement.</string>
```

### 2. Build & Run
- Build on a **physical device** (camera required)
- Open the app
- Tap Settings ⚙️

### 3. Switch to Optical Mode
- Tap **"Detection Method"**
- Select **"Optical"**
- Grant camera permission when prompted

### 4. Calibrate
- Mount iPhone facing the wheel
- Tap **"Start Calibration (10s)"**
- Rotate wheel steadily for 10 seconds
- Done! ✅

### 5. Verify (Optional)
- Tap **"View Camera Preview"**
- Confirm brightness changes as wheel rotates
- Red marker = blocking threshold
- Green marker = visible threshold

---

## 🛠️ Physical Setup

### Wheel Requirements
- ✅ One clear opening/gap (25-35% of circumference)
- ✅ Contrasting colors (dark wheel + light opening, or vice versa)
- ✅ Clean, distinct edges

### Phone Mounting
- ✅ Front camera faces wheel
- ✅ Distance: 5-15 cm from wheel
- ✅ Stable mount (no vibration)
- ✅ Opening passes directly in front of camera

### Environment
- ✅ Works best in dim/dark conditions (caves!)
- ✅ Flashlight provides consistent lighting
- ✅ Avoid very bright ambient light

---

## 📱 Using the App

### Main Screen
- Distance updates automatically
- Each wheel rotation increments count
- Works exactly like magnetic mode

### Settings Screen

**Detection Method Section:**
- Switch between Magnetic/Optical
- Info text explains optical mode

**Calibration Section:**
- Shows current brightness (optical mode)
- Displays threshold values
- Flashlight status indicator
- "Start Calibration" button
- "View Camera Preview" button

**Debug Info Section:**
- Current brightness value
- Rotations detected
- Camera status (Active/Inactive)
- Visual brightness bar with threshold markers

---

## 🎯 Troubleshooting

### No rotations detected?
1. Check "View Camera Preview"
2. Verify wheel opening blocks camera
3. Re-run calibration
4. Ensure stable mounting

### Too many rotations?
1. Reduce vibration
2. Improve mounting stability
3. Recalibrate with slower rotation
4. Check wheel opening is distinct

### Inconsistent detection?
1. Clean camera lens
2. Check flashlight is on
3. Adjust distance (5-15cm)
4. Increase wheel contrast

---

## 🎨 UI Overview

```
Settings
├─ Detection Method: [Magnetic | Optical] ← Toggle here
│
├─ Calibration
│  ├─ Current Brightness: 0.xyz
│  ├─ Low Threshold: 0.xyz
│  ├─ High Threshold: 0.xyz
│  ├─ [Start Calibration (10s)]
│  └─ [📷 View Camera Preview]
│
└─ Debug Info
   ├─ Current Brightness: 0.xyz
   ├─ Rotations Detected: N
   ├─ Camera Status: ● Active
   └─ [━━━━━━━━━━] Brightness bar
          ↑       ↑
         Red    Green
       (Low)   (High)
```

---

## ⚡ Key Features

- **🔄 Seamless Switching**: Toggle between magnetic/optical anytime
- **🔦 Auto Flashlight**: Turns on at 50% when optical mode active
- **📊 Real-time Feedback**: Live brightness monitoring
- **🎯 Smart Calibration**: Automatic threshold calculation
- **💾 Persistent Settings**: Saves thresholds across launches
- **🌗 Dark Mode**: Optimized for cave environments
- **🔋 Battery Efficient**: 20fps, 50% flashlight power

---

## 📖 Files Created

| File | Purpose |
|------|---------|
| `OpticalWheelDetector.swift` | Core detection algorithm |
| `OpticalDetectionPreviewView.swift` | Visual setup interface |
| `CameraPermissionHelper.swift` | Permission management |
| `DetectionMethod` enum | Mode selection |
| `OPTICAL_DETECTION_GUIDE.md` | Full documentation |
| `IMPLEMENTATION_SUMMARY.md` | Technical details |
| `OpticalDetectionTests.swift` | Unit tests |

---

## 🧪 Testing Checklist

- [ ] Build on physical device
- [ ] Grant camera permission
- [ ] Switch to optical mode
- [ ] Mount phone facing wheel
- [ ] Run calibration
- [ ] Verify brightness changes in preview
- [ ] Test rotation detection
- [ ] Check flashlight turns on/off
- [ ] Verify distance increments correctly
- [ ] Test settings persistence after restart

---

## 🏔️ Cave Survey Tips

### Advantages in Caves
- ✅ No magnetic interference from iron ore
- ✅ Works near metal equipment (bolts, cables)
- ✅ Consistent in magnetically noisy areas
- ✅ Visual feedback for troubleshooting

### Best Practices
1. **Test before descent**: Calibrate in good conditions first
2. **Bring backup**: Have magnetic mode ready as fallback
3. **Clean lens**: Moisture/mud affects optical detection
4. **Check battery**: Camera + flashlight = moderate drain
5. **Stable mount**: Cave vibrations can cause false triggers

### When to Use Each Mode

**Use Magnetic:**
- Very bright ambient light
- Camera obstructed by gear
- Need to conserve battery
- Wheel far from phone

**Use Optical:**
- Near metal/magnetic interference
- In dark caves (optimal!)
- Unreliable magnetic readings
- Need visual confirmation

---

## 💡 Pro Tips

1. **Paint wheel sections**: Use contrasting colors for better detection
2. **Test indoors first**: Verify setup before field use
3. **Monitor battery**: Keep external power bank handy
4. **Clean regularly**: Wipe camera lens between sections
5. **Adjust flashlight**: Can modify brightness in code if needed (line 183 in OpticalWheelDetector.swift)

---

## 🆘 Support

For detailed information, see:
- **Setup**: `OPTICAL_DETECTION_GUIDE.md`
- **Technical**: `IMPLEMENTATION_SUMMARY.md`
- **Code**: Inline comments in Swift files

---

## 📝 Info.plist Reminder

**Don't forget to add camera permission!**

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to detect wheel rotations for distance measurement in cave surveying.</string>
```

Without this, the app will crash when accessing the camera.

---

**Happy Surveying! 🗺️🔦**
