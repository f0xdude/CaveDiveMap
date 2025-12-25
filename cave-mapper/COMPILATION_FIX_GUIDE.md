# Compilation Fix Guide

## Issues Resolved

### 1. ✅ Duplicate SwiftUI Import
**Fixed**: Removed duplicate `import SwiftUI` statement in SettingsView.swift

### 2. ✅ Complex Expression Timeout
**Fixed**: Broke down the complex binding expression into a separate helper method `handleDetectionMethodChange()`

### 3. ⚠️ XCTest Import Error
**Solution**: The `OpticalDetectionTests.swift` file should be added to your **Test Target**, not the main app target.

## How to Add Tests (Optional)

If you want to include the unit tests:

1. In Xcode, select `OpticalDetectionTests.swift` in the Project Navigator
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership":
   - **Uncheck** `cave-mapper` (main app target)
   - **Check** `cave-mapperTests` (or your test target name)

Or simply **delete** `OpticalDetectionTests.swift` if you don't need unit tests right now.

## DetectionMethod Enum Location

The `DetectionMethod` enum is defined in `MagnetometerViewModel 2.swift`:

```swift
enum DetectionMethod: String, CaseIterable, Identifiable, Codable {
    case magnetic = "Magnetic"
    case optical = "Optical"
    var id: String { self.rawValue }
}
```

It should be accessible from SettingsView since they're in the same module. If you still see errors:

1. **Clean Build Folder**: Product → Clean Build Folder (⇧⌘K)
2. **Restart Xcode**: Sometimes helps with Swift compiler issues
3. **Check File Membership**: Ensure all Swift files are in the main target

## File Checklist for Main Target

Ensure these files are in your main app target:

- ✅ `SettingsView.swift`
- ✅ `MagnetometerViewModel 2.swift`
- ✅ `OpticalWheelDetector.swift`
- ✅ `OpticalDetectionPreviewView.swift`
- ✅ `CameraPermissionHelper.swift`
- ✅ All other existing files

## Info.plist Requirement

**Critical**: Add camera permission before building:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to detect wheel rotations for distance measurement in cave surveying.</string>
```

Without this, the app will **crash** when trying to access the camera.

## Building the Project

1. **Clean Build Folder**: ⇧⌘K (Shift-Command-K)
2. **Build**: ⌘B (Command-B)
3. **Run on Device**: Camera won't work in Simulator

## Quick Troubleshooting

### If DetectionMethod still not found:
```swift
// Add explicit import at top of SettingsView.swift if needed
// (though it should work without this)
import Foundation
```

### If compilation is still slow:
- Close other Xcode projects
- Restart Mac if needed
- Update to latest Xcode version

### If optical detection doesn't start:
- Check camera permission is granted
- Verify OpticalWheelDetector is initialized
- Check flashlight availability (won't work on simulator)

## Next Steps

1. Clean build folder
2. Build project
3. Fix any remaining issues
4. Run on physical device
5. Test optical detection!
