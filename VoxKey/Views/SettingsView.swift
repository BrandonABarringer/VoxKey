import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel: String = Constants.defaultModel
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("pauseMediaWhileDictating") private var pauseMediaWhileDictating: Bool = true
    @AppStorage("activationKeyCode") private var activationKeyCode: Int = Int(Constants.defaultActivationKeyCode)
    @AppStorage("activationMode") private var activationMode: String = Constants.defaultActivationMode.rawValue

    @EnvironmentObject var transcriptionService: TranscriptionService
    @EnvironmentObject var permissionManager: PermissionManager

    @State private var dictionaryTerms: [String] = UserDefaults.standard.stringArray(forKey: "customDictionaryTerms") ?? Constants.defaultDictionaryTerms
    @State private var newTerm: String = ""

    var body: some View {
        Form {
            Section("Activation") {
                Picker("Activation Key", selection: $activationKeyCode) {
                    ForEach(ActivationKey.allCases, id: \.cgKeyCode) { key in
                        Text(key.label).tag(Int(key.cgKeyCode))
                    }
                }

                Picker("Activation Mode", selection: $activationMode) {
                    ForEach(ActivationMode.allCases, id: \.rawValue) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label)
                            Text(mode.modeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode.rawValue)
                    }
                }

                // Warn users when Caps Lock is paired with Hold mode.
                // macOS toggles the Caps Lock flag on press rather than holding it,
                // so Hold mode is unreliable with keycode 57.
                if activationKeyCode == 57 && activationMode == "hold" {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Caps Lock toggles on press and is unreliable in Hold mode. Switch to Single Tap or Double Tap.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

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

            Section("Custom Dictionary") {
                ForEach(dictionaryTerms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) {
                            dictionaryTerms.removeAll { $0 == term }
                            saveDictionaryTerms()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("New term", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTerm() }
                    Button("Add") { addTerm() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
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

                Toggle("Pause media while dictating", isOn: $pauseMediaWhileDictating)
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
        .frame(width: 450, height: 680)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !dictionaryTerms.contains(trimmed) else { return }
        dictionaryTerms.append(trimmed)
        newTerm = ""
        saveDictionaryTerms()
    }

    private func saveDictionaryTerms() {
        UserDefaults.standard.set(dictionaryTerms, forKey: "customDictionaryTerms")
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
