//
//  ContentView.swift
//  GTA radio
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var store = AppState.shared.store
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var playerCtl = AppState.shared.player
    private var player: YouTubePlayerController { app.player }
    @State private var pasteSlot: Int?
    @State private var pasteText = ""
    @State private var renameSlot: Int?
    @State private var renameText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            playerBar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.stations) { station in
                        StationTile(station: station, isPlaying: app.nowPlaying == station.id)
                            .onTapGesture { tap(station) }
                            .contextMenu { menu(for: station) }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .sheet(item: Binding(get: { pasteSlot.map { IntId(id: $0) } },
                             set: { pasteSlot = $0?.id })) { item in
            pasteSheet(slot: item.id)
        }
        .sheet(item: Binding(get: { renameSlot.map { IntId(id: $0) } },
                             set: { renameSlot = $0?.id })) { item in
            renameSheet(slot: item.id)
        }
    }

    // MARK: Player bar

    private var playerBar: some View {
        ZStack {
            // The web view stays mounted the whole time so audio keeps playing.
            // When audio-only, we simply cover it with station artwork.
            YouTubePlayerView(controller: player)
                .opacity(app.nowPlaying == nil ? 0 : 1)

            if app.nowPlaying == nil {
                Rectangle().fill(.black)
                    .overlay(Text("Press \(settings.shortcutDescription) for the radio dial, or pick a station")
                        .foregroundStyle(.secondary))
            } else if settings.audioOnly, let id = app.nowPlaying {
                artwork(for: store.stations[id])
            }
        }
        .frame(height: 240)
        .overlay(alignment: .topLeading) {
            if let id = app.nowPlaying {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.stations[id].displayName)
                        .font(.headline).foregroundStyle(.white)
                    if let t = playerCtl.nowPlayingTitle {
                        Text(t).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .padding(8).background(.black.opacity(0.5)).cornerRadius(6)
                .padding(8)
            }
        }
    }

    /// Full-bleed blurred artwork with a crisp centered thumbnail — the
    /// audio-only "album art" view.
    private func artwork(for station: Station) -> some View {
        ZStack {
            if let t = station.thumbnailURL, let url = URL(string: t) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.35))

                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12)
            } else {
                Color.black
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipped()
    }

    // MARK: Actions

    private func tap(_ station: Station) {
        if station.isEmpty {
            pasteText = ""
            pasteSlot = station.id
        } else {
            play(station)
        }
    }

    private func play(_ station: Station) {
        app.play(station)
    }

    @ViewBuilder
    private func menu(for station: Station) -> some View {
        if !station.isEmpty {
            Button("Play") { play(station) }
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

    private func pasteSheet(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add station to slot \(slot + 1)").font(.headline)
            Text("Paste a YouTube video, Shorts, live, or playlist URL.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://youtube.com/watch?v=…", text: $pasteText)
                .textFieldStyle(.roundedBorder).frame(width: 380)
            HStack {
                Spacer()
                Button("Cancel") { pasteSlot = nil }
                Button("Add") {
                    let url = pasteText; let s = slot
                    pasteSlot = nil
                    Task { await store.assign(url: url, toSlot: s) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(RadioStore.classify(pasteText) == nil)
            }
        }
        .padding(20)
    }

    private func renameSheet(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename station").font(.headline)
            TextField("Station name", text: $renameText)
                .textFieldStyle(.roundedBorder).frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { renameSlot = nil }
                Button("Save") {
                    store.rename(slot: slot, to: renameText); renameSlot = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

private struct IntId: Identifiable { let id: Int }

struct StationTile: View {
    let station: Station
    let isPlaying: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(station.isEmpty ? Color.gray.opacity(0.15) : Color.black)
                if let t = station.thumbnailURL, let url = URL(string: t) {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.black }
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if station.isEmpty {
                    Image(systemName: "plus").font(.title).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title).foregroundStyle(.white)
                }
            }
            .frame(height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isPlaying ? Color.accentColor : .clear, lineWidth: 3)
            )
            Text(station.displayName)
                .font(.caption).lineLimit(1)
                .foregroundStyle(station.isEmpty ? .secondary : .primary)
        }
    }
}

#Preview {
    ContentView()
}
