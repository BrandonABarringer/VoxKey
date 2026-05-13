import Foundation
import Cocoa
import CoreAudio
import os.log

private let logger = Logger(subsystem: "com.voxkey.VoxKey", category: "media-pause")

// Pauses ambient media for the duration of a dictation. Decision tree:
//
//   output device running?  input device running?   action
//   -----------------------+----------------------+---------------------------------
//   no                     | (any)                | skip — nothing audible to pause
//   yes                    | yes                  | skip — mic is in use, likely a
//                          |                      |   call (Zoom/Teams/Slack). Don't
//                          |                      |   risk toggling unrelated media.
//   yes                    | no                   | pause: MediaRemote first; fall
//                          |                      |   back to media-key toggle if
//                          |                      |   nothing is in the Now Playing
//                          |                      |   registry (covers Prime Video
//                          |                      |   and other browser players that
//                          |                      |   intercept media keys directly).
//
// Must be called BEFORE this app starts its own mic recording, otherwise the input
// device shows as running because of *us* and the call-detection short-circuits.
//
// MediaRemote and media-key event posting both use private/HID-level APIs. VoxKey is
// already outside the sandbox for the global event tap, so this changes nothing about
// distribution; not App-Store-safe regardless.
@MainActor
final class MediaPauseManager {
    private enum PauseSource {
        case none
        case mediaRemote
        case mediaKey
    }

    private typealias SendCommand = @convention(c) (Int32, AnyObject?) -> Bool
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void

    private static let commandPlay: Int32 = 0
    private static let commandPause: Int32 = 1
    private static let nxKeyTypePlay: Int = 16

    private var sendCommand: SendCommand?
    private var getNowPlayingInfo: GetNowPlayingInfo?

    private var pauseRequested = false
    private var pauseSource: PauseSource = .none

    init() {
        loadFramework()
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            logger.error("Failed to dlopen MediaRemote.framework")
            return
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(sym, to: SendCommand.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(sym, to: GetNowPlayingInfo.self)
        }
    }

    func pauseIfPlaying() {
        let outputRunning = isDeviceRunning(.output)
        let inputRunning = isDeviceRunning(.input)
        logger.info("Pre-pause check: outputRunning=\(outputRunning) inputRunning=\(inputRunning)")

        guard outputRunning else {
            logger.info("Output idle, skipping pause")
            return
        }
        guard !inputRunning else {
            logger.info("Input active (likely in a call), skipping pause")
            return
        }

        pauseRequested = true
        attemptPause()
    }

    private func attemptPause() {
        guard let getNowPlayingInfo, let sendCommand else {
            sendMediaKeyToggle()
            pauseSource = .mediaKey
            logger.info("MediaRemote unavailable, used media-key toggle")
            return
        }
        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self, self.pauseRequested else { return }
            let hasClient = (info?.count ?? 0) > 0
            if hasClient {
                _ = sendCommand(Self.commandPause, nil)
                self.pauseSource = .mediaRemote
                logger.info("Paused via MediaRemote (keyCount=\(info?.count ?? 0))")
            } else {
                self.sendMediaKeyToggle()
                self.pauseSource = .mediaKey
                logger.info("MediaRemote empty, used media-key toggle")
            }
        }
    }

    func resumeIfPaused() {
        pauseRequested = false
        switch pauseSource {
        case .none:
            return
        case .mediaRemote:
            _ = sendCommand?(Self.commandPlay, nil)
            logger.info("Resumed via MediaRemote")
        case .mediaKey:
            sendMediaKeyToggle()
            logger.info("Resumed via media-key toggle")
        }
        pauseSource = .none
    }

    // MARK: - CoreAudio device-running check

    private enum DeviceScope { case input, output }

    private func isDeviceRunning(_ scope: DeviceScope) -> Bool {
        let selector: AudioObjectPropertySelector = scope == .output
            ? kAudioHardwarePropertyDefaultOutputDevice
            : kAudioHardwarePropertyDefaultInputDevice

        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let gotDevice = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        guard gotDevice == noErr, deviceID != 0 else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let gotRunning = AudioObjectGetPropertyData(
            deviceID, &addr, 0, nil, &size, &running
        )
        return gotRunning == noErr && running != 0
    }

    // MARK: - Media-key fallback

    private func sendMediaKeyToggle() {
        postMediaKey(state: 0xa) // key down
        postMediaKey(state: 0xb) // key up
    }

    private func postMediaKey(state: Int) {
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (Self.nxKeyTypePlay << 16) | (state << 8),
            data2: -1
        ), let cgEvent = event.cgEvent else { return }
        cgEvent.post(tap: .cghidEventTap)
    }
}
