//
//  AppleMusicController.swift
//  ArsWidget
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music",
        playbackRate: 1
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool {
        return true
    }

    private var notificationTask: Task<Void, Never>?
    @MainActor private var playbackUpdateRevision = 0
    @MainActor private var systemArtworkKey: String?
    @MainActor private var systemArtworkTask: Task<Data?, Never>?
    @MainActor private var systemArtworkAttempts = 0
    @MainActor private var systemArtworkRetryAfter = Date.distantPast

    // MARK: - Initialization
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )

            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
    }

    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }

    func pause() async {
        await executeCommand("pause")
    }

    func togglePlay() async {
        await executeCommand("playpause")
    }

    func nextTrack() async {
        await executeCommand("next track")
    }

    func previousTrack() async {
        await executeCommand("previous track")
    }

    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }

    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func setFavorite(_ favorite: Bool) async {
        let script = """
        tell application \"Music\"
            try
                set favorited of current track to " + (favorite ? "true" : "false") + "
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    @MainActor
    func updatePlaybackInfo() async {
        playbackUpdateRevision += 1
        let revision = playbackUpdateRevision
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard revision == playbackUpdateRevision, descriptor.numberOfItems >= 11 else { return }
        var updatedState = self.playbackState

        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        if updatedState.isPlaying && (updatedState.title.isEmpty || updatedState.title == "Unknown" || updatedState.title == "Not Playing") { return }
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0
        updatedState.isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        updatedState.repeatMode = RepeatMode(rawValue: Int(repeatModeValue)) ?? .off
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        updatedState.volume = Double(volumePercentage) / 100.0
        // An empty AppleScript string also has descriptor data, but is not an
        // image. Treat it as unavailable so the manager can retain/retry artwork.
        if let data = descriptor.atIndex(10)?.data, NSImage(data: data) != nil {
            updatedState.artwork = data
        } else {
            updatedState.artwork = await systemArtwork(
                title: updatedState.title, artist: updatedState.artist, album: updatedState.album)
        }
        guard revision == playbackUpdateRevision else { return }
        let lovedState = descriptor.atIndex(11)?.booleanValue ?? false
        updatedState.isFavorite = lovedState
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }

    // MARK: - Private Methods

    /// Streaming Music tracks can have zero AppleScript artworks while the
    /// system media session has a cover. Reuse the bundled adapter once per
    /// track; never use another application's or another track's image.
    @MainActor
    private func systemArtwork(title: String, artist: String, album: String) async -> Data? {
        guard title != "Not Playing", !title.isEmpty else { return nil }
        let key = "\(title)\u{001F}\(artist)\u{001F}\(album)"
        if systemArtworkKey == key {
            if let task = systemArtworkTask { return await task.value }
            guard systemArtworkAttempts < 3, Date() >= systemArtworkRetryAfter else { return nil }
        } else {
            systemArtworkAttempts = 0
            systemArtworkRetryAfter = .distantPast
        }
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else { return nil }
        systemArtworkKey = key
        systemArtworkAttempts += 1
        let task = Task.detached(priority: .utility) { () -> Data? in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [script.path, framework, "get"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
            defer { timeout.cancel() }
            let json = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let payload = try? JSONDecoder().decode(NowPlayingPayload.self, from: json),
                  (payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier) == "com.apple.Music",
                  payload.title == title, payload.artist == artist, payload.album == album,
                  let encoded = payload.artworkData,
                  let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
                  NSImage(data: data) != nil else { return nil }
            return data
        }
        systemArtworkTask = task
        let result = await task.value
        guard systemArtworkKey == key else { return nil }
        // A transient missing cover may be retried by the manager's bounded
        // startup retry. Successful covers stay cached until the track changes.
        if result == nil {
            systemArtworkTask = nil
            systemArtworkRetryAfter = Date().addingTimeInterval(1)
        }
        return result
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try

                set remoteOutputs to (every AirPlay device whose selected is true and kind is not computer)
                if (count of remoteOutputs) > 0 then
                    set currentVolume to sound volume of item 1 of remoteOutputs
                else
                    set currentVolume to sound volume
                end if
                set favoriteState to false
                try
                    set favoriteState to favorited of current track
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, currentVolume, artData, favoriteState}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, 50, "", false}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }

}
