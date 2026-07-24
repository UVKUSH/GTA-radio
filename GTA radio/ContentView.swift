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

    @ViewBuilder private var background: some View {
        if app.nowPlaying != nil, !settings.audioOnly {
            YouTubePlayerView(controller: player).ignoresSafeArea()
        } else if let id = app.nowPlaying {
            artwork(for: store.stations[id]).ignoresSafeArea()
            // Keep the (muted-of-video, still-audible) web view mounted off-screen.
            YouTubePlayerView(controller: player).frame(width: 2, height: 2).opacity(0.02)
        } else {
            LinearGradient(colors: [Theme.ink, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            YouTubePlayerView(controller: player).frame(width: 2, height: 2).opacity(0.02)
        }
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
            HStack(alignment: .center, spacing: 20) {
                nowPlayingBlock
                Spacer(minLength: 12)
                TransportControls()
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .glassPanel()

            filmstrip
        }
        .padding(20)
    }

    @ViewBuilder private var nowPlayingBlock: some View {
        if let id = app.nowPlaying {
            let s = store.stations[id]
            VStack(alignment: .leading, spacing: 3) {
                Text(playerCtl.lastErrorCode == nil ? "NOW PLAYING · \(Theme.frequency(for: id)) FM"
                                                     : "CAN'T EMBED THIS ONE")
                    .font(.gtaMono(10)).tracking(1.5)
                    .foregroundStyle(playerCtl.lastErrorCode == nil ? Theme.teal : Theme.magenta)
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
                    Image(systemName: "plus").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.magenta)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Theme.bone)
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay(ring)
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
