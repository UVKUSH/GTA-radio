//
//  RadioStore.swift
//  GTA radio
//
//  26 radio slots. Paste any YouTube URL, we classify it locally and fetch
//  what metadata we can WITHOUT an API key (public oEmbed only).
//

import Foundation
import Combine
import GTARadioKit

enum StationSource: Codable, Equatable {
    case video(id: String)
    case playlist(id: String)
}

struct Station: Codable, Equatable, Identifiable {
    var id: Int              // index within its parent folder (0...25)
    var uid: UUID = UUID()   // stable identity — resume + now-playing track this
    var sourceURL: String?
    var source: StationSource?
    var name: String?        // generated or custom
    var customName: Bool = false
    var thumbnailURL: String?
    var isFolder: Bool = false
    var children: [Station]? = nil   // 26 slots when this is a folder

    init(id: Int, sourceURL: String? = nil, source: StationSource? = nil, name: String? = nil,
         customName: Bool = false, thumbnailURL: String? = nil,
         isFolder: Bool = false, children: [Station]? = nil) {
        self.id = id; self.sourceURL = sourceURL; self.source = source; self.name = name
        self.customName = customName; self.thumbnailURL = thumbnailURL
        self.isFolder = isFolder; self.children = children
    }

    var isEmpty: Bool { source == nil && !isFolder }
    var displayName: String {
        if let name { return name }
        if isFolder { return "Folder" }
        return isEmpty ? "Empty" : "YouTube Radio"
    }

    /// "VIDEO" / "PLAYLIST" / "FOLDER" badge, or nil when empty.
    var kind: String? {
        if isFolder { return "FOLDER" }
        switch source {
        case .video: return "VIDEO"
        case .playlist: return "PLAYLIST"
        case .none: return nil
        }
    }

    // Custom decoding so pre-folder saved files (no uid/isFolder/children) still load.
    enum CodingKeys: String, CodingKey {
        case id, uid, sourceURL, source, name, customName, thumbnailURL, isFolder, children
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        uid = (try? c.decode(UUID.self, forKey: .uid)) ?? UUID()
        sourceURL = try? c.decode(String.self, forKey: .sourceURL)
        source = try? c.decode(StationSource.self, forKey: .source)
        name = try? c.decode(String.self, forKey: .name)
        customName = (try? c.decode(Bool.self, forKey: .customName)) ?? false
        thumbnailURL = try? c.decode(String.self, forKey: .thumbnailURL)
        isFolder = (try? c.decode(Bool.self, forKey: .isFolder)) ?? false
        children = try? c.decode([Station].self, forKey: .children)
    }
}

/// Where a station was last playing, so it resumes instead of restarting.
struct Resume: Codable, Equatable {
    var seconds: Double
    var index: Int   // playlist index (-1 / 0 for single videos)
}

/// A named snapshot of the whole 26-slot wheel — folders, names, thumbnails,
/// and uids included (so resume positions survive a save/load round-trip).
struct WheelPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var savedAt: Date
    var stations: [Station]
}

@MainActor
final class RadioStore: ObservableObject {
    static let slotCount = 26
    @Published private(set) var stations: [Station]
    @Published private(set) var presets: [WheelPreset]

    private let saveURL: URL
    private let resumeURL: URL
    private let presetsURL: URL
    // Keyed by station uid (stable across reorder/nesting), kept out of @Published
    // so frequent position saves don't redraw the grid.
    private var resumes: [String: Resume]

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTARadio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("stations.json")
        resumeURL = dir.appendingPathComponent("resumes.json")
        presetsURL = dir.appendingPathComponent("presets.json")

        if let data = try? Data(contentsOf: presetsURL),
           let loaded = try? JSONDecoder().decode([WheelPreset].self, from: data) {
            presets = loaded
        } else {
            presets = []
        }

        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode([Station].self, from: data),
           loaded.count == Self.slotCount {
            stations = loaded
        } else {
            stations = Self.seededDefaults()
        }

        if let data = try? Data(contentsOf: resumeURL),
           let loaded = try? JSONDecoder().decode([String: Resume].self, from: data) {
            resumes = loaded
        } else {
            resumes = [:]
        }

        // Bake in uids on first load (pre-folder saves had none) so resume
        // positions, which key off uid, stay stable across launches.
        persist()
        pruneResumes()
    }

    static func emptyChildren() -> [Station] { (0..<slotCount).map { Station(id: $0) } }

    // MARK: Tree navigation

    /// Children shown for a folder path ([] = root).
    func children(at path: [Int]) -> [Station] {
        path.isEmpty ? stations : (node(at: path)?.children ?? [])
    }

    /// The node at a path, or nil for the (folder-less) root.
    func node(at path: [Int]) -> Station? {
        var current = stations
        var found: Station?
        for idx in path {
            guard current.indices.contains(idx) else { return nil }
            found = current[idx]
            current = current[idx].children ?? []
        }
        return found
    }

    /// Depth-first search for a station by uid, returning its path.
    func path(forUID uid: UUID) -> [Int]? {
        func search(_ nodes: [Station], _ prefix: [Int]) -> [Int]? {
            for n in nodes {
                let p = prefix + [n.id]
                if n.uid == uid { return p }
                if let kids = n.children, let hit = search(kids, p) { return hit }
            }
            return nil
        }
        return search(stations, [])
    }

    // MARK: Path-addressed mutation

    private func mutate(_ nodes: inout [Station], _ path: ArraySlice<Int>, _ body: (inout Station) -> Void) {
        guard let idx = path.first, nodes.indices.contains(idx) else { return }
        if path.count == 1 { body(&nodes[idx]); return }
        if nodes[idx].children == nil { nodes[idx].children = RadioStore.emptyChildren() }
        mutate(&nodes[idx].children!, path.dropFirst(), body)
    }

    private func update(at path: [Int], _ body: (inout Station) -> Void) {
        guard !path.isEmpty else { return }
        mutate(&stations, path[...], body)
        persist()
    }

    /// First-run demo stations so the app isn't empty. The user can clear or
    /// replace any of them. Empty slots stay empty (they show emoji placeholders).
    private static func seededDefaults() -> [Station] {
        let defaults: [Int: (String, String)] = [
            0: ("jfKfPfyJRdk", "Lofi Girl FM"),
            1: ("5yx6BWlEVcY", "Chillhop FM"),
            2: ("aqz-KE-bpKQ", "Blender FM"),
            3: ("21X5lGlDOfg", "Nature FM"),
            4: ("M7lc1UVf-VE", "Developers FM"),
        ]
        return (0..<slotCount).map { i in
            if let (vid, name) = defaults[i] {
                return Station(id: i, sourceURL: "https://youtu.be/\(vid)",
                               source: .video(id: vid), name: name, customName: false,
                               thumbnailURL: "https://i.ytimg.com/vi/\(vid)/mqdefault.jpg")
            }
            return Station(id: i)
        }
    }

    // MARK: Resume positions (keyed by station uid)

    func resume(forUID uid: UUID) -> Resume? { resumes[uid.uuidString] }

    func setResume(_ resume: Resume, forUID uid: UUID) {
        resumes[uid.uuidString] = resume
        persistResumes()
    }

    private func persistResumes() {
        if let data = try? JSONEncoder().encode(resumes) { try? data.write(to: resumeURL, options: [.atomic]) }
    }

    /// Drop resume entries whose uid no longer exists in the live tree or any
    /// saved wheel — otherwise resumes.json grows forever.
    private func pruneResumes() {
        var known = Set<String>()
        func walk(_ nodes: [Station]) {
            for n in nodes {
                known.insert(n.uid.uuidString)
                if let kids = n.children { walk(kids) }
            }
        }
        walk(stations)
        for p in presets { walk(p.stations) }
        let before = resumes.count
        resumes = resumes.filter { known.contains($0.key) }
        if resumes.count != before { persistResumes() }
    }

    // MARK: Reorder within a folder

    /// Move a child within the folder at `parent` from index `from` to `to`.
    /// Resume follows each station by uid, so nothing needs remapping.
    func move(inFolder parent: [Int], from: Int, to: Int) {
        func reorder(_ nodes: inout [Station]) {
            guard from != to, nodes.indices.contains(from), nodes.indices.contains(to) else { return }
            let moved = nodes.remove(at: from)
            nodes.insert(moved, at: to)
            for i in nodes.indices { nodes[i].id = i }   // keep local index == position
        }
        if parent.isEmpty { reorder(&stations); persist() }
        else { update(at: parent) { if $0.children != nil { reorder(&$0.children!) } } }
    }

    // MARK: Path-addressed mutations

    func assign(url: String, at path: [Int], nameByTitle: Bool = false) async {
        guard let source = Self.classify(url), !path.isEmpty else { return }
        var uid = UUID()
        update(at: path) { node in
            node.isFolder = false
            node.children = nil
            node.sourceURL = url
            node.source = source
            node.customName = false
            node.name = provisionalName(for: source)
            node.thumbnailURL = thumbnail(for: source)
            uid = node.uid
        }
        resumes[uid.uuidString] = nil
        persistResumes()

        // Best-effort metadata (no key). Never blocks, never overwrites a custom name.
        switch source {
        case .video(let id):
            if let meta = try? await OEmbed.fetch(videoID: id) {
                update(at: path) { node in
                    guard node.source == source, !node.customName else { return }
                    // Playlist-fill names each slot by the track's title; a single
                    // add names it by the creator ("Lofi Girl FM").
                    node.name = nameByTitle ? Self.trackName(fromTitle: meta.title)
                                            : Self.stationName(fromCreator: meta.authorName)
                    // Thumbnail stays the provisional mqdefault (16:9, no black bars).
                }
            }
        case .playlist(let pid):
            // Playlists have no thumbnail of their own — borrow the first video's.
            if let result = try? await PlaylistPageResolver.fetch(playlistID: pid) {
                update(at: path) { node in
                    guard node.source == source else { return }
                    if let first = result.videoIDs.first {
                        node.thumbnailURL = "https://i.ytimg.com/vi/\(first)/mqdefault.jpg"
                    }
                    if !node.customName, let title = result.title, !title.isEmpty {
                        node.name = Self.stationName(fromCreator: title)
                    }
                }
            }
        }
    }

    func makeFolder(at path: [Int], name: String?) {
        update(at: path) { node in
            node.source = nil
            node.sourceURL = nil
            node.thumbnailURL = nil
            node.isFolder = true
            node.name = name
            node.children = RadioStore.emptyChildren()
        }
    }

    /// Fill `parent`'s EMPTY slots with a playlist's videos, in order. Occupied
    /// slots (and folders) are never touched — same contract as the picker.
    func fillFromPlaylist(_ playlistID: String, at parent: [Int]) async {
        guard let result = try? await PlaylistPageResolver.fetch(playlistID: playlistID),
              !result.videoIDs.isEmpty else { return }
        let targets = children(at: parent).filter(\.isEmpty).map(\.id)
        for (slot, vid) in zip(targets, result.videoIDs) {
            await assign(url: "https://youtu.be/\(vid)", at: parent + [slot], nameByTitle: true)
        }
    }

    /// Set every child of `parent` to the same playlist.
    func setAllToPlaylist(_ playlistID: String, name: String?, at parent: [Int]) {
        let url = "https://www.youtube.com/playlist?list=\(playlistID)"
        func fill(_ nodes: inout [Station]) {
            for i in nodes.indices {
                var s = Station(id: i)
                s.sourceURL = url
                s.source = .playlist(id: playlistID)
                s.name = name ?? "YouTube Playlist FM"
                nodes[i] = s
            }
        }
        if parent.isEmpty { fill(&stations); persist() }
        else { update(at: parent) { if $0.children == nil { $0.children = RadioStore.emptyChildren() }; fill(&$0.children!) } }
    }

    // MARK: Wheel presets (saved 26-slot layouts)

    /// The auto-backup written just before any preset load, so swapping wheels
    /// can never destroy the one you were on.
    static let backupPresetName = "Last session"

    /// Snapshot the current wheel. Saving under an existing name overwrites
    /// that preset instead of piling up duplicates.
    func savePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        upsertPreset(named: name, snapshot: stations)
    }

    /// Swap the whole wheel for a saved one (current wheel goes to the backup).
    func loadPreset(_ preset: WheelPreset) {
        upsertPreset(named: Self.backupPresetName, snapshot: stations)
        stations = preset.stations
        persist()
    }

    func renamePreset(id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].name = name
        persistPresets()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persistPresets()
        pruneResumes()
    }

    private func upsertPreset(named name: String, snapshot: [Station]) {
        if let i = presets.firstIndex(where: { $0.name == name }) {
            presets[i].stations = snapshot
            presets[i].savedAt = Date()
        } else {
            presets.insert(WheelPreset(name: name, savedAt: Date(), stations: snapshot), at: 0)
        }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) { try? data.write(to: presetsURL, options: [.atomic]) }
    }

    // MARK: Wheel export / import (shareable .json files)

    func exportData(for preset: WheelPreset) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(preset)
    }

    /// Import a wheel from an exported file (also accepts a raw stations array,
    /// i.e. someone's stations.json). Returns the imported name, nil on failure.
    @discardableResult
    func importPreset(from data: Data) -> String? {
        let dec = JSONDecoder()
        var preset: WheelPreset?
        if let p = try? dec.decode(WheelPreset.self, from: data) {
            preset = p
        } else if let stations = try? dec.decode([Station].self, from: data), !stations.isEmpty {
            preset = WheelPreset(name: "Imported wheel", savedAt: Date(), stations: stations)
        }
        guard var p = preset, !p.stations.isEmpty else { return nil }

        // Normalize to exactly 26 slots with positional ids, whatever came in.
        if p.stations.count > Self.slotCount { p.stations = Array(p.stations.prefix(Self.slotCount)) }
        while p.stations.count < Self.slotCount { p.stations.append(Station(id: p.stations.count)) }
        for i in p.stations.indices { p.stations[i].id = i }

        p.id = UUID()   // never collide with an existing preset's identity
        p.savedAt = Date()
        var name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Imported wheel" }
        let base = name
        var n = 2
        while presets.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        p.name = name

        presets.insert(p, at: 0)
        persistPresets()
        return name
    }

    func rename(at path: [Int], to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(at: path) { $0.name = trimmed; $0.customName = true }
    }

    func clear(at path: [Int]) {
        guard let idx = path.last else { return }
        update(at: path) { $0 = Station(id: idx) }
        pruneResumes()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stations) {
            // .atomic: a crash mid-write must never truncate the wheel (a broken
            // stations.json silently falls back to seeded defaults on launch).
            try? data.write(to: saveURL, options: [.atomic])
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

    /// Name a station after a video's title (used when filling slots from a
    /// playlist, where each slot is a distinct track). No "FM" suffix — the
    /// title is the identity — just trimmed and length-capped.
    static func trackName(fromTitle raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "YouTube Radio" }
        if name.count > 40 { name = String(name.prefix(39)).trimmingCharacters(in: .whitespaces) + "…" }
        return name
    }

    // MARK: Local URL classification (no network)

    /// Delegates to the tested GTARadioKit parser (charset-validated IDs are a
    /// security boundary: they're interpolated into player JavaScript).
    /// Channels/handles/users aren't playable sources here, so they map to nil.
    static func classify(_ raw: String) -> StationSource? {
        switch YouTubeURLParser.parse(raw) {
        case .video(let id): return .video(id: id)
        case .playlist(let id): return .playlist(id: id)
        default: return nil
        }
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
