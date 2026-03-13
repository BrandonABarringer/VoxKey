import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel: String = Constants.defaultModel
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    @EnvironmentObject var transcriptionService: TranscriptionService
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Whisper Model", selection: $selectedModel) {
                    ForEach(Constants.whisperModels, id: \.self) { model in
                        Text(model.capitalized).tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, newModel in
                    Task {
                        try? await transcriptionService.switchModel(to: newModel)
                    }
                }

                if transcriptionService.isLoading {
                    ProgressView(value: transcriptionService.downloadProgress) {
                        Text("Downloading model...")
                    }
                }

                if let error = transcriptionService.errorMessage {
                    HStack {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task {
                                try? await transcriptionService.loadModel(selectedModel)
                            }
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("VoxKey: Failed to update login item: \(error)")
                        }
                    }
            }

            Section("Permissions") {
                permissionRow("Accessibility", granted: permissionManager.accessibilityGranted)
                permissionRow("Microphone", granted: permissionManager.microphoneGranted)
                permissionRow("Input Monitoring", granted: permissionManager.inputMonitoringGranted)

                Button("Check Permissions") {
                    permissionManager.checkAllPermissions()
                }
            }

            Section("About") {
                LabeledContent("App") { Text("VoxKey") }
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }

    private func permissionRow(_ name: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            Text(granted ? "Granted" : "Not Granted")
                .foregroundStyle(.secondary)
        }
    }
}
