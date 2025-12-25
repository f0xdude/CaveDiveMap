# Optical Detection Bug Fixes - December 25, 2025

## Issues Fixed

### 1. **Camera Permission Not Requested**
**Problem:** When camera permission was `.notDetermined`, the app would just fail silently without requesting permission.

**Solution:** Added automatic permission request in `startDetection()`:
```swift
if status == .notDetermined {
    print("📹 Camera permission not determined, requesting...")
    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        print("📹 Camera permission granted: \(granted)")
        if granted {
            DispatchQueue.main.async {
                self?.startDetection()
            }
        } else {
            print("❌ Camera permission denied by user")
        }
    }
    return
}
```

### 2. **Flashlight Not Turning On**
**Problem:** Multiple issues prevented the flashlight from activating:
- Flashlight was being called before camera session was fully started
- No delay to let session stabilize
- Insufficient checks for torch availability
- Main thread blocking issues

**Solution:**
- Increased camera setup timeout from 5 to 10 seconds
- Added retry logic if camera setup fails
- Added 0.5 second delay after session start before enabling flashlight
- Added 0.3 second delay specifically for flashlight to stabilize
- Improved `enableFlashlight()` with better availability checks:

```swift
guard device.isTorchAvailable else {
    print("⚠️ Torch is not available right now")
    DispatchQueue.main.async {
        self.flashlightEnabled = false
    }
    return
}
```

- Changed flashlight brightness from 50% to 100% for better detection
- All UI updates now dispatched to main thread properly

### 3. **Camera Setup Not Completing**
**Problem:** Camera setup was running asynchronously but without proper completion checks.

**Solution:**
- Added check to prevent duplicate camera setup
- Reset `isCameraSetupComplete` flag at start of setup
- Added detailed logging throughout setup process
- Check for existing inputs/outputs before adding new ones
- Added input/output count logging after setup

### 4. **Exposure and Focus Settings**
**Problem:** Camera was set to locked exposure/focus which could cause poor detection.

**Solution:** Changed to adaptive settings for better performance:
```swift
// Set focus mode to continuous auto focus for better adaptability
if device.isFocusModeSupported(.continuousAutoFocus) {
    device.focusMode = .continuousAutoFocus
}

// Use continuous auto exposure for consistent measurements
if device.isExposureModeSupported(.continuousAutoExposure) {
    device.exposureMode = .continuousAutoExposure
}
```

### 5. **Stop Detection Issues**
**Problem:** When stopping detection, flashlight might not turn off properly.

**Solution:** Improved stop sequence:
- Turn off flashlight first
- Wait 0.2 seconds
- Then stop capture session
- Proper logging at each step

### 6. **Missing Diagnostic Tools**
**Problem:** Hard to debug camera and flashlight issues without visibility.

**Solution:** Added comprehensive debugging features:
- New `checkCameraStatus()` method that returns:
  - Camera ready status
  - Torch availability
  - Session running status
- Added diagnostic UI in SettingsView showing:
  - Camera Ready indicator (green/red)
  - Torch Available indicator (green/red)
  - Session Running indicator (green/red)
- Manual "Toggle Flashlight" button for testing
- Enhanced logging throughout the detection lifecycle

## Testing Checklist

When testing the optical detection, verify:

✅ **Permission Flow:**
- [ ] First launch shows camera permission request
- [ ] Denying permission shows alert with Settings link
- [ ] Granting permission starts detection immediately
- [ ] Settings properly remembers permission state

✅ **Camera Activation:**
- [ ] Camera session starts (Session Running: Yes)
- [ ] Camera Ready shows green
- [ ] All three diagnostic indicators are green when running

✅ **Flashlight Activation:**
- [ ] Flashlight turns on automatically when detection starts
- [ ] Flashlight status in Settings shows "Flashlight ON"
- [ ] Yellow flashlight icon appears in UI
- [ ] Manual toggle button works when running
- [ ] Torch Available shows green

✅ **Detection:**
- [ ] Brightness value updates in real-time
- [ ] Brightness indicator bar moves smoothly
- [ ] Rotation count increments when wheel blocks camera
- [ ] Calibration completes successfully

✅ **Stopping:**
- [ ] Flashlight turns off when stopping detection
- [ ] Camera session stops cleanly
- [ ] Status indicators turn red when stopped

## Code Changes Summary

### Modified Files:
1. **OpticalWheelDetector.swift**
   - Enhanced `startDetection()` with permission request
   - Improved `setupCamera()` with better error handling
   - Upgraded `enableFlashlight()` with comprehensive checks
   - Better `stopDetection()` sequence
   - Added `toggleFlashlight()` for manual control
   - Added `checkCameraStatus()` diagnostic method

2. **SettingsView.swift**
   - Enhanced debug section with diagnostic indicators
   - Added manual flashlight toggle button
   - Added camera status, torch availability, and session status displays
   - Improved detection method switching logic

## Performance Notes

- Camera setup timeout increased from 5s to 10s (more reliable on slower devices)
- Flashlight now runs at 100% brightness (was 50%) for better detection
- Added strategic delays to ensure proper initialization:
  - 0.5s after session start
  - 0.3s before flashlight enable
  - 0.2s before session stop

## Known Limitations

1. **Camera Warmup:** First detection start may take 2-3 seconds as camera initializes
2. **Thermal Throttling:** Extended use at 100% flashlight brightness may cause device to warm up
3. **Battery Impact:** Camera + flashlight use moderate battery - monitor during long surveys

## Recommendations

1. **Always calibrate** before each survey session
2. **Check diagnostic indicators** before starting - all should be green
3. **Use "Restart Optical Detection"** button if issues occur mid-session
4. **Mount phone securely** to prevent vibration interference
5. **Shield from bright ambient light** for best results

## Future Improvements

- [ ] Add automatic retry if flashlight fails to enable
- [ ] Implement flashlight brightness control (25%, 50%, 75%, 100%)
- [ ] Add camera feed preview in SettingsView
- [ ] Battery level warning when flashlight is on
- [ ] Thermal throttling detection and warning
- [ ] Auto-calibration based on ambient light changes
