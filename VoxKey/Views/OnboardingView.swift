import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Welcome to VoxKey")
                    .font(.title)
                    .bold()

                Text("Hold Right Ctrl to dictate text anywhere on your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Required Permissions")
                    .font(.headline)

                permissionRow(
                    "Accessibility",
                    description: "Detect hotkey and insert text",
                    granted: permissionManager.accessibilityGranted,
                    action: { permissionManager.openAccessibilitySettings() }
                )

                permissionRow(
                    "Microphone",
                    description: "Record audio for transcription",
                    granted: permissionManager.microphoneGranted,
                    action: {
                        Task {
                            _ = await permissionManager.requestMicrophonePermission()
                            permissionManager.checkAllPermissions()
                        }
                    }
                )

                permissionRow(
                    "Input Monitoring",
                    description: "Monitor keyboard for hotkey",
                    granted: permissionManager.inputMonitoringGranted,
                    action: { permissionManager.openInputMonitoringSettings() }
                )
            }

            Spacer()

            Button("Refresh Permission Status") {
                permissionManager.checkAllPermissions()
            }
            .controlSize(.small)

            Button(action: onComplete) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!permissionManager.allPermissionsGranted)

            if !permissionManager.allPermissionsGranted {
                Text("Grant all permissions above, then click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Skip (I've already granted permissions)") {
                    permissionManager.overridePermissions()
                    onComplete()
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 480, height: 520)
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    private func permissionRow(_ name: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Grant") { action() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
