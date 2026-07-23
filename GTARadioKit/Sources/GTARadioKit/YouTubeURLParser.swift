import Foundation

/// The result of locally classifying a pasted YouTube URL. No network, no API key.
public enum ParsedYouTubeURL: Equatable, Sendable {
    case video(id: String)
    case playlist(id: String)
    case channelID(String)
    case handle(String)
    case customName(String)
    case legacyUser(String)
}

public struct YouTubeURLParser {

    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "www.youtube-nocookie.com", "youtube-nocookie.com"
    ]

    public static func parse(_ raw: String) -> ParsedYouTubeURL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }

        guard let components = URLComponents(string: text),
              let host = components.host?.lowercased() else { return nil }

        let pathParts = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            guard let id = pathParts.first, isVideoID(id) else { return nil }
            return .video(id: id)
        }

        guard youtubeHosts.contains(host) else { return nil }

        func query(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name == name })?.value
        }

        guard let first = pathParts.first else { return nil }

        switch first {
        case "watch":
            guard let id = query("v"), isVideoID(id) else { return nil }
            return .video(id: id)
        case "playlist":
            guard let list = query("list"), isPlaylistID(list) else { return nil }
            return .playlist(id: list)
        case "shorts", "live", "embed":
            guard pathParts.count >= 2 else { return nil }
            let candidate = pathParts[1]
            if first == "embed", candidate == "videoseries",
               let list = query("list"), isPlaylistID(list) {
                return .playlist(id: list)
            }
            guard isVideoID(candidate) else { return nil }
            return .video(id: candidate)
        case "channel":
            guard pathParts.count >= 2, isChannelID(pathParts[1]) else { return nil }
            return .channelID(pathParts[1])
        case "c":
            guard pathParts.count >= 2, !pathParts[1].isEmpty else { return nil }
            return .customName(pathParts[1])
        case "user":
            guard pathParts.count >= 2, !pathParts[1].isEmpty else { return nil }
            return .legacyUser(pathParts[1])
        default:
            if first.hasPrefix("@"), first.count > 1 {
                return .handle(String(first.dropFirst()))
            }
            return nil
        }
    }

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func isPlaylistID(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func isChannelID(_ s: String) -> Bool {
        s.hasPrefix("UC") && s.count >= 10 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
