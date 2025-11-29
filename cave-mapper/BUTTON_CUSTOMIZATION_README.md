# Button Customization Feature

## Overview
I've added a comprehensive button customization system to your cave-mapper app that allows users to adjust the position and size of buttons on both the main screen and the manual data point save screen.

## New Files Created

### 1. ButtonCustomizationSettings.swift
- **Purpose**: Manages all button configurations and persists them to UserDefaults
- **Features**:
  - Stores button size and position (offsetX, offsetY) for each button
  - Automatically saves changes to UserDefaults
  - Provides default configurations
  - Includes a `resetToDefaults()` method

### 2. ButtonCustomizationView.swift
- **Purpose**: Provides the UI for users to customize button layouts
- **Features**:
  - Segmented picker to switch between Main Screen and Save Data View
  - Select which button to customize
  - Sliders to adjust:
    - Size (40-150 points)
    - Horizontal position (-200 to +200)
    - Vertical position (-200 to +200)
  - Live preview of the selected button with current settings
  - Reset all buttons to defaults option

## Modified Files

### 1. ContentView.swift
- Added `@ObservedObject var buttonSettings = ButtonCustomizationSettings.shared`
- Updated all 4 buttons (Save, Map, Reset, Camera) to use dynamic sizing and positioning
- Button sizes and icon sizes now scale proportionally

### 2. SaveDataView.swift
- Added `@ObservedObject var buttonSettings = ButtonCustomizationSettings.shared`
- Updated all 4 buttons (Save, Increment, Decrement, Cycle) to use dynamic sizing and positioning
- Icon sizes scale based on button size (40% of button size)

### 3. SettingsView.swift
- Added new "Interface" section with a link to ButtonCustomizationView
- Placed above the documentation links for easy access

## How to Use

1. **Access Settings**: Tap the gear icon in the top-left of the main screen
2. **Navigate to Button Customization**: Tap "Customize Button Layout" in the Interface section
3. **Select Screen**: Choose either "Main Screen" or "Save Data View"
4. **Select Button**: Use the segmented picker to choose which button to customize
5. **Adjust Settings**: 
   - Drag the "Size" slider to make buttons bigger or smaller
   - Drag the "Horizontal Position" slider to move buttons left/right
   - Drag the "Vertical Position" slider to move buttons up/down
6. **Preview**: Watch the preview update in real-time as you adjust settings
7. **Reset if Needed**: Use the "Reset All to Defaults" button to restore original positions

## Technical Details

### Button Configuration Structure
```swift
struct ButtonConfig: Codable {
    var size: CGFloat        // Button diameter
    var offsetX: CGFloat     // Horizontal offset from center
    var offsetY: CGFloat     // Vertical offset from center
}
```

### Default Button Positions

**Main Screen:**
- Save Button: size 75, offset (0, 20)
- Map Button: size 75, offset (130, 10)
- Reset Button: size 75, offset (-70, -70)
- Camera Button: size 75, offset (70, -70)

**Save Data View:**
- Save Button: size 70, offset (0, 120)
- Increment Button: size 70, offset (100, 80)
- Decrement Button: size 70, offset (-100, 80)
- Cycle Button: size 70, offset (150, 150)

### Proportional Scaling
- Icon sizes scale at 35-40% of button size
- Text sizes scale at 20-26% of button size
- This ensures buttons remain visually balanced at any size

## Benefits

1. **Accessibility**: Users can make buttons larger for easier tapping
2. **Customization**: Users can arrange buttons to match their workflow
3. **Adaptability**: Works with different hand sizes and grip styles
4. **Persistence**: Settings are saved and restored across app launches
5. **Safety**: All changes are non-destructive and can be reset

## Future Enhancements (Optional)

If you want to extend this feature later, you could:
- Add preset layouts (e.g., "Left-handed", "Right-handed")
- Add rotation/angle support for buttons
- Add color customization
- Export/import button configurations
- Add haptic feedback when adjusting positions
