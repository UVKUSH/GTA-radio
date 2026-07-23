//
//  ContentView.swift
//  GTA radio
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RadioStore()
    @StateObject private var player = YouTubePlayerController()
    @State private var nowPlaying: Int?
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
                        StationTile(station: station, isPlaying: nowPlaying == station.id)
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
            if nowPlaying != nil {
                YouTubePlayerView(controller: player)
            } else {
                Rectangle().fill(.black)
                    .overlay(Text("Select a station").foregroundStyle(.secondary))
            }
        }
        .frame(height: 240)
        .overlay(alignment: .topLeading) {
            if let id = nowPlaying {
                Text(store.stations[id].displayName)
                    .font(.headline).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.5)).cornerRadius(6)
                    .padding(8)
            }
        }
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
        switch station.source {
        case .video(let id): player.playVideo(id)
        case .playlist(let id): player.playPlaylist(id)
        case .none: return
        }
        nowPlaying = station.id
    }

    @ViewBuilder
    private func menu(for station: Station) -> some View {
        if !station.isEmpty {
            Button("Play") { play(station) }
            Button("Rename…") { renameText = station.displayName; renameSlot = station.id }
            Divider()
            Button("Clear", role: .destructive) {
                if nowPlaying == station.id { player.stop(); nowPlaying = nil }
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
