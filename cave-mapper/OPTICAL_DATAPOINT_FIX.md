# Optical Detection Data Point Collection Fix - December 25, 2025

## Issue
When using optical detection method, the main screen's "Datapoints collected" counter was not updating when rotations were detected. The optical detector was working (rotations were being detected and counted), but this wasn't reflected in the UI or triggering auto-save of data points.

## Root Cause Analysis

### The Data Flow Chain:
1. **OpticalWheelDetector** detects rotation → increments `rotationCount`
2. **MagnetometerViewModel** subscribes to `opticalDetector.$rotationCount` → updates `revolutions`
3. **ContentView** observes `magnetometer.revolutionCount` (computed from `revolutions`) → auto-saves data point
4. **ContentView** displays `pointNumber` which is incremented after each save

### Problems Identified:

1. **Missing Subscription Cleanup**: When `stopMonitoring()` was called, the Combine subscription (`opticalCancellable`) was not being cancelled. This could cause:
   - Memory leaks
   - Duplicate subscriptions if monitoring was started multiple times
   - Stale subscriptions that don't update properly

2. **Weak Subscription Setup**: The subscription logic only updated `revolutions` if the new count was greater than current. This could miss updates if the detector was restarted or reset.

3. **Insufficient Logging**: No visibility into:
   - When rotations are detected in OpticalWheelDetector
   - When subscription fires in MagnetometerViewModel
   - When ContentView's onChange triggers
   - When data points are saved

4. **Timing Issues**: The print statement for rotation detection was happening before the actual increment, showing incorrect count values.

## Fixes Applied

### 1. OpticalWheelDetector.swift

**Fixed rotation detection logging:**
```swift
// Before: printed count before incrementing
if isReadyForNewRotation && brightness < lowBrightnessThreshold {
    DispatchQueue.main.async { [weak self] in
        self?.rotationCount += 1
    }
    isReadyForNewRotation = false
    print("🔄 Rotation detected! Count: \(rotationCount + 1)...")  // Wrong!
}

// After: increment first, then print correct count
if isReadyForNewRotation && brightness < lowBrightnessThreshold {
    isReadyForNewRotation = false
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.rotationCount += 1
        print("🔄 Rotation detected! Count now: \(self.rotationCount)...")
    }
}
```

### 2. MagnetometerViewModel.swift

**Added proper subscription cleanup:**
```swift
func stopMonitoring() {
    switch detectionMethod {
    case .magnetic:
        motionManager.stopMagnetometerUpdates()
    case .optical:
        opticalDetector.stopDetection()
        // NEW: Cancel the optical subscription when stopping
        opticalCancellable?.cancel()
        opticalCancellable = nil
    }
    // ... rest of cleanup
}
```

**Improved startOpticalDetection with better logging and unconditional sync:**
```swift
private func startOpticalDetection() {
    print("🔦 Starting optical detection from ViewModel...")
    print("   Current revolutions in ViewModel: \(revolutions)")
    print("   Current rotationCount in OpticalDetector: \(opticalDetector.rotationCount)")
    
    // Cancel any existing subscription first
    opticalCancellable?.cancel()
    opticalCancellable = nil
    
    // Start the optical detector
    opticalDetector.startDetection()
    
    // Monitor optical detector's rotation count and sync to our revolutions
    opticalCancellable = opticalDetector.$rotationCount
        .sink { [weak self] newCount in
            guard let self = self else { return }
            // Only update and log if there's an actual change
            if self.revolutions != newCount {
                print("🔄 Optical rotation detected! Count: \(newCount) (was: \(self.revolutions))")
                self.revolutions = newCount
                print("   ✅ Revolutions updated to: \(self.revolutions)")
            }
        }
    
    print("✅ Optical detection binding established")
}
```

**Added logging to revolutions property:**
```swift
@Published var revolutions = DataManager.loadPointNumber() {
    didSet {
        print("📈 MagnetometerViewModel: revolutions changed from \(oldValue) to \(revolutions)")
    }
}
```

### 3. ContentView.swift

**Enhanced onChange logging:**
```swift
.onChange(of: magnetometer.revolutionCount) { oldValue, newValue in
    print("📊 ContentView: revolutionCount changed from \(oldValue) to \(newValue)")
    _ = DataManager.loadLastSavedDepth()

    let savedData = SavedData(
        recordNumber: pointNumber,
        distance: magnetometer.roundedDistanceInMeters,
        heading: magnetometer.roundedMagneticHeading ?? 0,
        depth: 0.00,
        left: 0.0, right: 0.0, up: 0.0, down: 0.0,
        rtype: "auto"
    )

    pointNumber += 1
    DataManager.save(savedData: savedData)
    DataManager.savePointNumber(pointNumber)
    print("   ✅ Data point saved! Point number now: \(pointNumber)")
}
```

## Expected Behavior After Fix

When optical detection is running and a rotation is detected, you should see this sequence in the console:

```
🔄 Rotation detected! Count now: 1, Brightness: 0.234
🔄 Optical rotation detected! Count: 1 (was: 0)
   ✅ Revolutions updated to: 1
📈 MagnetometerViewModel: revolutions changed from 0 to 1
📊 ContentView: revolutionCount changed from 0 to 1
   ✅ Data point saved! Point number now: 1
```

And in the UI:
- "Distance" should update to show: `0.12 m` (or whatever your wheel circumference calculates)
- "Datapoints collected" should update to show: `1`
- A new data point should be saved automatically

## Testing Checklist

To verify the fix is working:

### ✅ Basic Functionality
- [ ] Switch to Optical detection method in Settings
- [ ] Verify camera and flashlight activate
- [ ] Return to main screen
- [ ] "Datapoints collected" starts at correct number
- [ ] Trigger a rotation (cover/uncover camera)
- [ ] "Datapoints collected" increments by 1
- [ ] Distance updates based on wheel circumference

### ✅ Console Logs
- [ ] See "🔄 Rotation detected!" when rotation happens
- [ ] See "🔄 Optical rotation detected!" in ViewModel
- [ ] See "📈 MagnetometerViewModel: revolutions changed"
- [ ] See "📊 ContentView: revolutionCount changed"
- [ ] See "✅ Data point saved!"

### ✅ Data Persistence
- [ ] Trigger several rotations
- [ ] Close the app completely
- [ ] Reopen the app
- [ ] "Datapoints collected" shows correct count from before close
- [ ] Continue detecting - count increments correctly

### ✅ Method Switching
- [ ] Start with Optical, trigger some rotations
- [ ] Switch to Magnetic in Settings
- [ ] Return to main screen
- [ ] Count is preserved
- [ ] Magnetic detection works and increments count
- [ ] Switch back to Optical
- [ ] Count is still preserved
- [ ] Optical detection continues from correct count

## Key Improvements

1. **Proper Resource Management**: Combine subscriptions are now properly cancelled when stopping monitoring
2. **Better Synchronization**: Revolutions always sync with optical detector's count when it changes
3. **Enhanced Debugging**: Comprehensive logging at every step makes troubleshooting easier
4. **Fixed Timing**: Rotation count is incremented before logging, showing accurate values
5. **Consistency**: Both magnetic and optical detection now trigger the same data flow

## Architecture Notes

### The Complete Data Flow:

```
OpticalWheelDetector
  └─> @Published rotationCount: Int
       └─> Combine subscription ($rotationCount.sink)
            └─> MagnetometerViewModel.revolutions
                 └─> @Published property change
                      └─> revolutionCount computed property
                           └─> ContentView.onChange(of: revolutionCount)
                                └─> Auto-save data point
                                └─> Increment pointNumber
                                └─> Update UI
```

### Important Patterns:

1. **Main Thread Updates**: All UI-affecting properties (`rotationCount`, `revolutions`) are updated on the main thread
2. **Combine Subscriptions**: Used for reactive updates from optical detector to view model
3. **SwiftUI onChange**: Used for reactive updates from view model to view
4. **Computed Properties**: `revolutionCount` provides clean abstraction over `revolutions`

## Future Enhancements

Potential improvements for even better robustness:

- [ ] Add `.receive(on: DispatchQueue.main)` to Combine subscription for safety
- [ ] Add counter mismatch detection and auto-correction
- [ ] Persist optical detector rotation count to UserDefaults
- [ ] Add UI indicator showing when data point is auto-saved
- [ ] Add manual sync button to force synchronization
- [ ] Add batch save optimization for rapid rotations
- [ ] Add undo functionality for accidental rotations

## Related Files Modified

1. **OpticalWheelDetector.swift** - Fixed rotation logging
2. **MagnetometerViewModel 2.swift** - Added subscription cleanup and better logging
3. **ContentView.swift** - Enhanced onChange logging

## Verification Commands

To verify the fix is working, check the Xcode console for this pattern:
```bash
# Search for these in console when testing:
grep "Rotation detected!" xcode_console.log
grep "revolutionCount changed" xcode_console.log
grep "Data point saved!" xcode_console.log
```

All three should appear in sequence for each rotation.
