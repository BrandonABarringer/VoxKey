import SwiftUI

@main
struct VoxKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarIconView()
                .environmentObject(appDelegate.appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.transcriptionService)
                .environmentObject(appDelegate.permissionManager)
        }
    }
}

/// The menu bar dropdown content
private struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            switch appState.currentState {
            case .idle:
                Text("Ready")
            case .recording:
                Text("Recording...")
            case .processing:
                Text("Processing...")
            }

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit VoxKey") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// The menu bar icon label that updates based on app state
private struct MenuBarIconView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch appState.currentState {
        case .idle:
            Image(systemName: "mic")
        case .recording:
            Image(systemName: "mic.fill")
        case .processing:
            Image(systemName: "ellipsis.circle")
        }
    }
}
