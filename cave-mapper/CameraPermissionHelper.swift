//
//  CameraPermissionHelper.swift
//  cave-mapper
//
//  Created on 12/25/25.
//

import AVFoundation
import SwiftUI

/// Helper for managing camera permissions
struct CameraPermissionHelper {
    
    /// Check current camera authorization status
    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    /// Check if camera access is authorized
    static var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
    
    /// Request camera permission
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    /// Check permission status and show alert if needed
    static func checkPermissionWithAlert(presentAlert: @escaping (Alert) -> Void, onAuthorized: @escaping () -> Void) {
        switch authorizationStatus {
        case .authorized:
            onAuthorized()
            
        case .notDetermined:
            requestPermission { granted in
                if granted {
                    onAuthorized()
                } else {
                    presentAlert(deniedAlert)
                }
            }
            
        case .denied, .restricted:
            presentAlert(deniedAlert)
            
        @unknown default:
            presentAlert(deniedAlert)
        }
    }
    
    /// Alert for when camera access is denied
    static var deniedAlert: Alert {
        Alert(
            title: Text("Camera Access Required"),
            message: Text("Optical wheel detection requires camera access. Please enable it in Settings → Privacy → Camera."),
            primaryButton: .default(Text("Open Settings"), action: {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }),
            secondaryButton: .cancel()
        )
    }
}

/// SwiftUI View modifier to check camera permission before presenting
struct CameraPermissionModifier: ViewModifier {
    let isPresented: Binding<Bool>
    let onAuthorized: () -> Void
    
    @State private var showPermissionAlert = false
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented.wrappedValue) { _, newValue in
                if newValue {
                    CameraPermissionHelper.checkPermissionWithAlert(
                        presentAlert: { _ in
                            showPermissionAlert = true
                            isPresented.wrappedValue = false
                        },
                        onAuthorized: onAuthorized
                    )
                }
            }
            .alert(isPresented: $showPermissionAlert) {
                CameraPermissionHelper.deniedAlert
            }
    }
}

extension View {
    /// Check camera permission before presenting a view
    func requireCameraPermission(isPresented: Binding<Bool>, onAuthorized: @escaping () -> Void) -> some View {
        modifier(CameraPermissionModifier(isPresented: isPresented, onAuthorized: onAuthorized))
    }
}
