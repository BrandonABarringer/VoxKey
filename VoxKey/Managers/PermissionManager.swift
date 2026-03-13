import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionManager: ObservableObject {
    @Published var accessibilityGranted: Bool = false
    @Published var microphoneGranted: Bool = false
    @Published var inputMonitoringGranted: Bool = false
    @Published var overridden: Bool = false

    var allPermissionsGranted: Bool {
        overridden || (accessibilityGranted && microphoneGranted && inputMonitoringGranted)
    }

    func checkAllPermissions() {
        accessibilityGranted = checkAccessibility()
        microphoneGranted = checkMicrophone()
        inputMonitoringGranted = checkInputMonitoring()
    }

    func checkAccessibility() -> Bool {
        // AXIsProcessTrusted() is unreliable for unsigned apps even when
        // the app is listed in System Settings. Fall back to attempting
        // a CGEventTap creation as the real test.
        if AXIsProcessTrusted() { return true }
        // Try creating a tap as a practical check
        return checkInputMonitoring()
    }

    func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func checkInputMonitoring() -> Bool {
        // Try to create a temporary event tap — this is the only reliable way
        // to check Input Monitoring permission on macOS
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else {
            return false
        }
        // Tap created successfully — permission is granted. Clean up.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        return true
    }

    /// Skip permission checks (for unsigned apps where detection is unreliable)
    func overridePermissions() {
        overridden = true
    }

    func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
