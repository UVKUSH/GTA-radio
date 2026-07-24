//
//  PlaylistPageResolver.swift
//  GTA radio
//
//  Pulls real video IDs out of a public YouTube playlist page WITHOUT an API
//  key, so a playlist can populate the 26 slots as individual stations. We only
//  read public page data (the same info a browser sees) and never call the
//  YouTube Data API.
//

import Foundation

enum PlaylistPageResolver {

    struct Result {
        let title: String?
        let videoIDs: [String]
    }

    /// Extract ordered, de-duplicated 11-char video IDs from playlist-page HTML.
    static func extractVideoIDs(fromHTML html: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"videoId\":\"([A-Za-z0-9_-]{11})\"") else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var ids: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let id = String(html[r])
            if seen.insert(id).inserted {
                ids.append(id)
                if ids.count >= limit { break }
            }
        }
        return ids
    }

    /// Playlist title from Open Graph metadata, minus the " - YouTube" suffix.
    static func extractTitle(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<meta property=\"og:title\" content=\"([^\"]+)\""),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        var title = String(html[r])
        if let range = title.range(of: " - YouTube") { title.removeSubrange(range) }
        return title.htmlDecoded
    }

    /// Fetch + parse the public playlist page. Sends a browser UA and a consent
    /// cookie so YouTube serves the real page instead of a consent interstitial.
    static func fetch(playlistID: String, limit: Int = 26) async throws -> Result {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/playlist?list=\(playlistID)")!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)
        return Result(title: extractTitle(fromHTML: html),
                      videoIDs: extractVideoIDs(fromHTML: html, limit: limit))
    }
}

private extension String {
    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
