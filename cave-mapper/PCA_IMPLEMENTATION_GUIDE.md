# PCA Magnetic Rotation Detection - Implementation Guide

## Overview

This implementation adds a secondary PCA-based magnetic rotation detection algorithm to your cave mapper app. The PCA (Principal Component Analysis) method is more robust to phone orientation changes compared to single-axis detection.

## How PCA Detection Works

### 1. **Data Collection**
- Maintains a sliding window of recent 3D magnetometer samples: `B_t = (x_t, y_t, z_t)`
- Window size: 100 samples (configurable)
- Sample rate: 50 Hz

### 2. **Principal Component Analysis**
- Computes the covariance matrix of the 3D magnetic field samples
- Finds the dominant direction of variation (first principal component) `û` via eigenvalue decomposition
- This direction represents the axis along which the magnetic field varies most (due to wheel rotation)

### 3. **Signal Projection**
- Projects each 3D sample onto the principal component: `s_t = û · B_t`
- This converts the "3D spinning magnet signal" into a clean 1D periodic waveform
- Much more robust than single-axis methods

### 4. **Rotation Counting**
- Performs peak detection on the projected signal `s_t`
- Uses high/low threshold hysteresis to avoid noise
- Counts rotations based on threshold crossings

### 5. **Motion Filtering**
- Uses gyroscope data to detect phone movement
- Suppresses rotation counting when phone is being actively rotated
- Helps reject false positives from "figure-8" calibration motions

### 6. **Signal Quality Metric**
- Computes ratio of largest eigenvalue to sum of all eigenvalues
- Values near 1.0 indicate strong 1D periodic motion (good signal)
- Values near 0.33 indicate random motion (poor signal)
- Exposed as `signalQuality` property

## Files Modified

### New Files
- **PCAMagneticDetector.swift**: Core PCA rotation detection implementation

### Modified Files
- **WheelDetectionMethod.swift**: Added `.magneticPCA` case
- **WheelDetectionManager.swift**: Integrated PCA detector alongside existing detectors
- **ContentView.swift**: Initialized PCA detector
- **SettingsView.swift**: Added PCA-specific UI sections

## Using the PCA Detector

### In the App UI

1. **Switch to PCA Mode**
   - Open Settings (gear icon)
   - Tap the "PCA" button in the Detection Method section

2. **Calibration**
   - Tap "Start Calibration (10s)"
   - Rotate the wheel steadily for 10 seconds
   - The system will automatically compute optimal thresholds
   - Signal quality indicator shows detection confidence (>60% is good)

3. **Monitor Signal Quality**
   - Check the "Signal Quality" percentage in the calibration section
   - Higher values indicate better detection
   - If quality is low (<40%), try recalibrating or adjusting wheel position

### Key Parameters

- **Window Size**: 100 samples (~2 seconds at 50 Hz)
- **PCA Update Frequency**: Every 10 samples
- **Gyro Threshold**: 0.5 rad/s for motion suppression
- **Default Thresholds**: ±0.5 (automatically calibrated)

## Technical Details

### Advantages over Single-Axis Detection
1. **Orientation Independence**: Works regardless of phone orientation
2. **Noise Robustness**: PCA filters out non-rotational variations
3. **Signal Quality Metric**: Provides confidence in detection
4. **Motion Rejection**: Gyroscope integration prevents false positives

### Performance
- Uses Apple's Accelerate framework for fast linear algebra
- LAPACK's `dsyev` for eigenvalue decomposition
- Minimal overhead: PCA computed only every 10 samples
- Real-time performance on all iOS devices

### Signal Quality Interpretation
- **80-100%**: Excellent - Very strong rotation signal
- **60-80%**: Good - Reliable detection
- **40-60%**: Fair - May work but consider recalibration
- **<40%**: Poor - Recalibration strongly recommended

## Troubleshooting

### Low Signal Quality
- Ensure magnet is properly positioned on wheel
- Check that wheel rotates smoothly
- Avoid holding phone during calibration
- Try different wheel positions relative to phone

### Missed Rotations
- Increase window size (edit `windowSize` in PCAMagneticDetector.swift)
- Lower high threshold via calibration
- Check gyro threshold isn't too sensitive

### False Positives
- Increase gyro threshold to be more aggressive about motion rejection
- Raise high threshold via calibration
- Ensure phone is stable during measurement

## Future Enhancements

Possible improvements:
1. Adaptive window size based on rotation speed
2. Multiple-peak detection for faster rotations
3. Phase unwrapping for sub-rotation accuracy
4. Machine learning-based quality assessment
5. Real-time visualization of projected signal

## References

This implementation is based on the PCA rotation detection algorithm commonly used in:
- Wheel odometry systems
- Rotational motion analysis
- Periodic signal extraction from multi-dimensional data

The algorithm converts 3D magnetometer data into a robust 1D signal for reliable rotation counting.
