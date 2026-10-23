import Foundation

/// Only app-level volume commands. Unsupported sources never fall back to
/// changing the system output or an unrelated running music application.
enum PlayerVolumeCommands {
    static func script(bundleID: String?, value: Double? = nil) -> String? {
        let application: String
        switch bundleID {
        case "com.apple.Music": application = "Music"
        case "com.spotify.client": application = "Spotify"
        default: return nil
        }
        if let value, !value.isFinite { return nil }
        let percent = value.map { Int((min(1, max(0, $0)) * 100).rounded()) }
        if application == "Music" {
            // AirPlay has its own receiver gain. Use selected remote outputs,
            // keeping the Mac's CoreAudio output completely separate.
            let action: String
            if let percent {
                action = """
                if (count of remoteOutputs) > 0 then
                    repeat with outputDevice in remoteOutputs
                        set sound volume of outputDevice to \(percent)
                    end repeat
                else
                    set sound volume to \(percent)
                end if
                """
            } else {
                action = """
                if (count of remoteOutputs) > 0 then
                    return sound volume of item 1 of remoteOutputs
                else
                    return sound volume
                end if
                """
            }
            return """
            if application "Music" is running then
                tell application "Music"
                    set remoteOutputs to (every AirPlay device whose selected is true and kind is not computer)
                    \(action)
                end tell
            end if
            """
        }
        let command = percent.map { "set sound volume to \($0)" } ?? "get sound volume"
        return "if application \"\(application)\" is running then\n tell application \"\(application)\" to \(command)\nend if"
    }
}
