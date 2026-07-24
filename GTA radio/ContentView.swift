//
//  ContentView.swift
//  GTA radio
//
//  "Los Santos night HUD": the video (or artwork) plays full-bleed behind a
//  glass HUD. Stations live in a horizontal filmstrip of circular dials that
//  echoes the radial wheel — no plain grid.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var store = AppState.shared.store
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var playerCtl = AppState.shared.player
    @Environment(\.openSettings) private var openSettings

    @State private var pasteSlot: Int?
    @State private var pasteText = ""
    @State private var renameSlot: Int?
    @State private var renameText = ""

    private var player: YouTubePlayerController { app.player }

    var body: some View {
        ZStack {
            background
            scrims
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomHUD
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Theme.ink)
        .sheet(item: sheetBinding($pasteSlot)) { pasteSheet(slot: $0.id) }
        .sheet(item: sheetBinding($renameSlot)) { renameSheet(slot: $0.id) }
    }

    // MARK: Background

    // The web view is ALWAYS mounted at full size with stable identity — we only
    // change what's layered over it. Swapping it in/out was what left the layout
    // stale (things vanished) until the next resize.
    private var background: some View {
        ZStack {
            Theme.ink
            YouTubePlayerView(controller: player)
                .opacity(app.nowPlaying != nil && !settings.audioOnly ? 1 : 0)
            if app.nowPlaying == nil {
                LinearGradient(colors: [Theme.ink, .black], startPoint: .top, endPoint: .bottom)
            } else if settings.audioOnly, let id = app.nowPlaying {
                artwork(for: store.stations[id])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var scrims: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("GTA").font(.gtaDisplay(30)).foregroundStyle(Theme.bone)
                    Text("RADIO").font(.gtaDisplay(30)).foregroundStyle(Theme.magenta)
                }
                Text("PRESS \(settings.shortcutDescription) FOR THE DIAL")
                    .font(.gtaMono(10)).tracking(1.5).foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 10) {
                HUDIconButton(system: "shuffle") { app.shuffleAllStations() }
                HUDIconButton(system: settings.audioOnly ? "waveform" : "video.fill",
                              active: !settings.audioOnly) {
                    settings.audioOnly.toggle()
                }
                HUDIconButton(system: "gearshape.fill") { openSettings() }
            }
        }
        .padding(20)
    }

    // MARK: Bottom HUD

    private var bottomHUD: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 20) {
                    nowPlayingBlock
                    Spacer(minLength: 12)
                    TransportControls()
                }
                SeekBar()
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .glassPanel()
            .opacity(settings.controlsOpacity)

            filmstrip
        }
        .padding(20)
    }

    @ViewBuilder private var nowPlayingBlock: some View {
        if let id = app.nowPlaying {
            let s = store.stations[id]
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(playerCtl.lastErrorCode == nil ? "NOW PLAYING · \(Theme.frequency(for: id)) FM"
                                                         : "CAN'T EMBED THIS ONE")
                        .font(.gtaMono(10)).tracking(1.5)
                        .foregroundStyle(playerCtl.lastErrorCode == nil ? Theme.teal : Theme.magenta)
                    if let kind = s.kind { KindBadge(kind: kind) }
                }
                Text(s.displayName)
                    .font(.gtaDisplay(28)).foregroundStyle(Theme.bone).lineLimit(1)
                if let t = playerCtl.nowPlayingTitle {
                    Text(t).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("OFF AIR").font(.gtaMono(10)).tracking(1.5).foregroundStyle(Theme.muted)
                Text("Pick a station").font(.gtaDisplay(28)).foregroundStyle(Theme.bone.opacity(0.7))
            }
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.stations) { station in
                    StationDial(station: station, isCurrent: app.nowPlaying == station.id)
                        .onTapGesture { tap(station) }
                        .contextMenu { menu(for: station) }
                        .draggable(String(station.id))
                        .dropDestination(for: String.self) { items, _ in
                            guard let first = items.first, let from = Int(first) else { return false }
                            app.moveStation(from: from, to: station.id)
                            return true
                        }
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 6)
        }
    }

    // MARK: Artwork (audio-only background)

    private func artwork(for station: Station) -> some View {
        ZStack {
            if let t = station.thumbnailURL, let url = URL(string: t) {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Theme.ink }
                    .blur(radius: 60).overlay(Color.black.opacity(0.45))
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Theme.ink }
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
                    .shadow(radius: 24)
            } else {
                Theme.ink
            }
        }
    }

    // MARK: Actions

    private func tap(_ station: Station) {
        if station.isEmpty { pasteText = ""; pasteSlot = station.id }
        else { app.play(slot: station.id) }
    }

    @ViewBuilder private func menu(for station: Station) -> some View {
        if !station.isEmpty {
            Button("Play") { app.play(slot: station.id) }
            Button("Rename…") { renameText = station.displayName; renameSlot = station.id }
            Divider()
            Button("Clear", role: .destructive) {
                if app.nowPlaying == station.id { app.stop() }
                store.clear(slot: station.id)
            }
        } else {
            Button("Add YouTube URL…") { pasteText = ""; pasteSlot = station.id }
        }
    }

    // MARK: Sheets

    private func sheetBinding(_ source: Binding<Int?>) -> Binding<IntId?> {
        Binding(get: { source.wrappedValue.map { IntId(id: $0) } },
                set: { source.wrappedValue = $0?.id })
    }

    private func pasteSheet(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add station").font(.gtaDisplay(24)).foregroundStyle(.primary)
            Text("Paste a YouTube video, Shorts, live, or playlist link.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://youtube.com/watch?v=…", text: $pasteText)
                .textFieldStyle(.roundedBorder).frame(width: 400)
            detectionLabel

            // A playlist can either become one station, fill all 26 with its
            // videos, or set all 26 to the whole playlist.
            if case .playlist(let listID) = RadioStore.classify(pasteText) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This is a playlist — how should it fill the slots?")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Add as one station") {
                            let url = pasteText, s = slot; pasteSlot = nil
                            Task { await store.assign(url: url, toSlot: s) }
                        }
                        Button("Fill 26 slots from playlist") {
                            pasteSlot = nil
                            Task { await store.fillFromPlaylist(listID) }
                        }
                        Button("Set all 26 to this playlist") {
                            pasteSlot = nil
                            Task {
                                let info = try? await PlaylistPageResolver.fetch(playlistID: listID, limit: 1)
                                store.setAllToPlaylist(listID, name: info?.title)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { pasteSlot = nil }
                Button("Add") {
                    let url = pasteText, s = slot
                    pasteSlot = nil
                    Task { await store.assign(url: url, toSlot: s) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(RadioStore.classify(pasteText) == nil)
            }
        }
        .padding(24)
    }

    @ViewBuilder private var detectionLabel: some View {
        let trimmed = pasteText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Label("Paste a link to detect its type", systemImage: "link")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            switch RadioStore.classify(pasteText) {
            case .video:
                Label("Detected: Video", systemImage: "play.rectangle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .playlist:
                Label("Detected: Playlist", systemImage: "music.note.list")
                    .font(.caption).foregroundStyle(.blue)
            case .none:
                Label("Not a recognized YouTube link", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func renameSheet(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename station").font(.gtaDisplay(24))
            TextField("Station name", text: $renameText)
                .textFieldStyle(.roundedBorder).frame(width: 340)
            HStack {
                Spacer()
                Button("Cancel") { renameSlot = nil }
                Button("Save") { store.rename(slot: slot, to: renameText); renameSlot = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

struct IntId: Identifiable { let id: Int }

/// Small "VIDEO" / "PLAYLIST" pill.
struct KindBadge: View {
    let kind: String
    var body: some View {
        Text(kind)
            .font(.gtaMono(9)).tracking(0.5)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.magenta.opacity(0.9), in: Capsule())
            .foregroundStyle(.black)
    }
}

// MARK: - Station dial (filmstrip element)

struct StationDial: View {
    let station: Station
    let isCurrent: Bool

    private var diameter: CGFloat { isCurrent ? 70 : 60 }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.black.opacity(0.45))
                if let t = station.thumbnailURL, let url = URL(string: t) {
                    AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Color.black }
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                } else if station.isEmpty {
                    Text(Theme.emoji(for: station.id)).font(.system(size: 24)).opacity(0.85)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Theme.bone)
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay(ring)
            .overlay(alignment: .bottomTrailing) {
                if case .playlist = station.source {
                    kindIcon("music.note.list")
                } else if case .video = station.source {
                    kindIcon("play.fill")
                }
            }
            .shadow(color: isCurrent ? Theme.teal.opacity(0.5) : .black.opacity(0.4),
                    radius: isCurrent ? 10 : 5)

            Text(station.isEmpty ? "EMPTY" : station.displayName)
                .font(.gtaDisplay(13))
                .foregroundStyle(station.isEmpty ? Theme.muted : Theme.bone)
                .lineLimit(1)
            Text(station.isEmpty ? "ADD" : "\(Theme.frequency(for: station.id)) FM")
                .font(.gtaMono(9)).tracking(0.5)
                .foregroundStyle(isCurrent ? Theme.teal : Theme.muted)
        }
        .frame(width: 88, height: 116)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrent)
    }

    private func kindIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(Theme.magenta, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder private var ring: some View {
        if station.isEmpty {
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(Theme.magenta.opacity(0.6))
        } else if isCurrent {
            Circle().stroke(Theme.teal, lineWidth: 3)
        } else {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}

#Preview {
    ContentView()
}
