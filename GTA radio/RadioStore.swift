//
//  RadioStore.swift
//  GTA radio
//
//  26 radio slots. Paste any YouTube URL, we classify it locally and fetch
//  what metadata we can WITHOUT an API key (public oEmbed only).
//

import Foundation
import Combine

enum StationSource: Codable, Equatable {
    case video(id: String)
    case playlist(id: String)
}

struct Station: Codable, Equatable, Identifiable {
    var id: Int              // 0...25
    var sourceURL: String?
    var source: StationSource?
    var name: String?        // generated or custom
    var customName: Bool = false
    var thumbnailURL: String?

    var isEmpty: Bool { source == nil }
    var displayName: String { name ?? (isEmpty ? "Empty" : "YouTube Radio") }
}

@MainActor
final class RadioStore: ObservableObject {
    static let slotCount = 26
    @Published private(set) var stations: [Station]

    private let saveURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTARadio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("stations.json")

        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode([Station].self, from: data),
           loaded.count == Self.slotCount {
            stations = loaded
        } else {
            stations = (0..<Self.slotCount).map { Station(id: $0) }
        }
    }

    // MARK: Mutations

    func assign(url: String, toSlot slot: Int) async {
        guard let source = Self.classify(url) else { return }
        var station = stations[slot]
        station.sourceURL = url
        station.source = source
        station.customName = false
        // Provisional name so the UI updates instantly.
        station.name = provisionalName(for: source)
        station.thumbnailURL = thumbnail(for: source)
        stations[slot] = station
        persist()

        // Best-effort async metadata (no key). Never blocks, never overwrites custom.
        // We keep our own mqdefault thumbnail (16:9, no letterbox) rather than
        // oEmbed's hqdefault (4:3 with black bars).
        if case .video(let id) = source,
           let meta = try? await OEmbed.fetch(videoID: id) {
            guard !stations[slot].customName, stations[slot].source == source else { return }
            stations[slot].name = Self.stationName(fromCreator: meta.authorName)
            persist()
        }
    }

    func rename(slot: Int, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stations[slot].name = trimmed
        stations[slot].customName = true
        persist()
    }

    func clear(slot: Int) {
        stations[slot] = Station(id: slot)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stations) {
            try? data.write(to: saveURL)
        }
    }

    // MARK: Naming

    private func provisionalName(for source: StationSource) -> String {
        switch source {
        case .video: return "YouTube Radio"
        case .playlist: return "YouTube Playlist FM"
        }
    }

    private func thumbnail(for source: StationSource) -> String? {
        switch source {
        // mqdefault is native 16:9 (no black bars); fills a circle cleanly.
        case .video(let id): return "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"
        case .playlist: return nil
        }
    }

    static func stationName(fromCreator raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(" - Topic") { name = String(name.dropLast(8)) }
        if !name.lowercased().hasSuffix("fm") && !name.lowercased().hasSuffix("radio") {
            name += " FM"
        }
        if name.count > 40 { name = String(name.prefix(40)) }
        return name
    }

    // MARK: Local URL classification (no network)

    static func classify(_ raw: String) -> StationSource? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let c = URLComponents(string: text), let host = c.host?.lowercased() else { return nil }

        func q(_ n: String) -> String? { c.queryItems?.first { $0.name == n }?.value }
        let parts = c.path.split(separator: "/").map(String.init)

        if host == "youtu.be", let id = parts.first, isVideoID(id) { return .video(id: id) }

        let youtube = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
        guard youtube.contains(host), let first = parts.first else { return nil }

        switch first {
        case "watch":
            if let v = q("v"), isVideoID(v) { return .video(id: v) }
        case "playlist":
            if let l = q("list"), !l.isEmpty { return .playlist(id: l) }
        case "shorts", "live", "embed":
            if parts.count >= 2 {
                if first == "embed", parts[1] == "videoseries", let l = q("list") { return .playlist(id: l) }
                if isVideoID(parts[1]) { return .video(id: parts[1]) }
            }
        default: break
        }
        return nil
    }

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

// MARK: - Public oEmbed (no API key)

struct OEmbedMetadata { let title: String; let authorName: String; let thumbnailURL: URL? }

enum OEmbed {
    private struct Response: Decodable {
        let title: String
        let author_name: String
        let thumbnail_url: String?
    }

    static func fetch(videoID: String) async throws -> OEmbedMetadata {
        let target = "https://www.youtube.com/watch?v=\(videoID)"
        var comps = URLComponents(string: "https://www.youtube.com/oembed")!
        comps.queryItems = [.init(name: "url", value: target), .init(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)
        return OEmbedMetadata(title: r.title, authorName: r.author_name,
                              thumbnailURL: r.thumbnail_url.flatMap(URL.init))
    }
}
