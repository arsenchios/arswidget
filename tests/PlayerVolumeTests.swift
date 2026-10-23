import Foundation

@main
struct PlayerVolumeTests {
    static func main() async throws {
        precondition(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: 0.24)?.contains("set sound volume of outputDevice to 24") == true)
        precondition(PlayerVolumeCommands.script(bundleID: "com.spotify.client", value: 2)?.contains("set sound volume to 100") == true)
        precondition(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: -2)?.contains("set sound volume of outputDevice to 0") == true)
        precondition(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: .nan) == nil)
        precondition(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: .infinity) == nil)
        precondition(PlayerVolumeCommands.script(bundleID: "org.mozilla.firefox", value: 0.2) == nil)
        precondition(PlayerVolumeCommands.script(bundleID: nil) == nil)
        let musicScript = PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: 0.24)!
        precondition(musicScript.contains("selected is true and kind is not computer"))
        precondition(!musicScript.contains("set volume output volume"))
        precondition(PlayerVolumeCommands.script(bundleID: "com.apple.Music")!.contains("sound volume of item 1 of remoteOutputs"))
        print("Player-level routing, clamps and unsupported-source checks: PASS")
        guard CommandLine.arguments.contains("--live") else { return }
        let read = PlayerVolumeCommands.script(bundleID: "com.apple.Music")!
        guard let initial = try await AppleScriptHelper.execute(read), initial.descriptorType != typeNull else {
            print("Apple Music is not running: live check skipped")
            return
        }
        let original = initial.int32Value
        let systemBefore = try await AppleScriptHelper.execute("output volume of (get volume settings)")?.int32Value
        let test = original == 0 ? 1 : original - 1
        do {
            try await AppleScriptHelper.executeVoid(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: Double(test)/100)!)
            let actual = try await AppleScriptHelper.execute(read)?.int32Value
            let systemAfter = try await AppleScriptHelper.execute("output volume of (get volume settings)")?.int32Value
            try await AppleScriptHelper.executeVoid(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: Double(original)/100)!)
            precondition(actual == test, "Apple Music volume did not change")
            precondition(systemBefore == systemAfter, "System volume changed")
            let restored = try await AppleScriptHelper.execute(read)?.int32Value
            precondition(restored == original, "Original Music volume must be restored")
            print("Live Apple Music volume \(original) → \(test) → \(original), system volume unchanged: PASS")
        } catch {
            try? await AppleScriptHelper.executeVoid(PlayerVolumeCommands.script(bundleID: "com.apple.Music", value: Double(original)/100)!)
            throw error
        }
    }
}
