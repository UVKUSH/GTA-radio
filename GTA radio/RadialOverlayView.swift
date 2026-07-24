//
//  RadialOverlayView.swift
//  GTA radio
//
//  The GTA-style radio dial: the current folder's 26 options arranged on a
//  circle. Populated stations are crisp and clickable; empty slots are dimmed
//  and inert; folders open into their own 26. Hover previews + plays a blip.
//  Esc / background click closes (closing does NOT stop playback).
//

import SwiftUI

struct RadialOverlayView: View {
    let onClose: () -> Void

    @ObservedObject private var store = AppState.shared.store
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var hovered: Int?

    private var stations: [Station] { app.currentStations }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.40

            ZStack {
                Color.black.opacity(settings.backgroundOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                centerPanel.position(center)

                ForEach(stations) { station in
                    let angle = Double(station.id) / Double(RadioStore.slotCount) * 2 * .pi - .pi / 2
                    StationNode(station: station,
                                isCurrent: station.uid == app.nowPlayingUID,
                                isHovered: hovered == station.id)
                        .position(x: center.x + radius * cos(angle),
                                  y: center.y + radius * sin(angle))
                        .onHover { inside in
                            guard !station.isEmpty else { return }
                            if inside, hovered != station.id { SoundPlayer.shared.hoverRotate() }
                            hovered = inside ? station.id : (hovered == station.id ? nil : hovered)
                        }
                        .onTapGesture { select(station) }
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onExitCommand { app.isInFolder ? app.goBack() : onClose() }
    }

    private func select(_ station: Station) {
        if station.isFolder {
            app.enterFolder(index: station.id)
            hovered = nil
        } else if !station.isEmpty {
            app.play(path: app.currentPath + [station.id])
            onClose()
        }
    }

    private var focusStation: Station? {
        if let h = hovered, let s = stations.first(where: { $0.id == h }) { return s }
        return nil
    }

    private var centerPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("GTA").font(.gtaDisplay(15)).foregroundStyle(Theme.bone.opacity(0.7))
                Text("RADIO").font(.gtaDisplay(15)).foregroundStyle(Theme.magenta.opacity(0.9))
            }
            if app.isInFolder {
                Button { app.goBack() } label: {
                    Label(app.currentFolderName ?? "Folder", systemImage: "chevron.left")
                        .font(.gtaMono(10)).tracking(1).foregroundStyle(Theme.muted)
                }.buttonStyle(.plain)
            }

            if let s = focusStation {
                Text(s.displayName)
                    .font(.gtaDisplay(30)).foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.center).lineLimit(2)
                Text(s.isFolder ? "OPEN FOLDER"
                     : (s.uid == app.nowPlayingUID ? "▶ NOW PLAYING · \(Theme.frequency(for: s.id)) FM" : "CLICK TO TUNE IN"))
                    .font(.gtaMono(10)).tracking(1)
                    .foregroundStyle(s.uid == app.nowPlayingUID ? Theme.teal : Theme.muted)
            } else {
                Text("Hover a station")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
            }

            if app.hasNowPlaying {
                TransportControls(showsVolume: true, playSize: 40).padding(.top, 6)
            }
        }
        .frame(width: 300)
    }
}

private struct StationNode: View {
    let station: Station
    let isCurrent: Bool
    let isHovered: Bool

    private var diameter: CGFloat { isHovered ? 74 : 58 }

    var body: some View {
        VStack(spacing: 5) {
            circle
            Text(station.isEmpty ? "\(Theme.frequency(for: station.id)) FM" : station.displayName)
                .font(.gtaDisplay(12))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .frame(width: 96)
                .shadow(color: .black.opacity(0.8), radius: 3)
        }
        .scaleEffect(isHovered ? 1.18 : 1)
        .zIndex(isHovered ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isHovered)
        .opacity(station.isEmpty ? 0.32 : 1)
    }

    private var circle: some View {
        ZStack {
            Circle().fill(station.isEmpty ? Color.white.opacity(0.05) : Color.black)
            if station.isFolder {
                Image(systemName: "folder.fill").font(.system(size: 20)).foregroundStyle(Theme.magenta)
            } else if let t = station.thumbnailURL, let url = URL(string: t) {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.black }
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else if station.isEmpty {
                Text(Theme.emoji(for: station.id)).font(.system(size: 22))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(strokeColor, lineWidth: isCurrent ? 3 : (isHovered ? 3 : 1)))
        .shadow(color: isCurrent ? Theme.teal.opacity(0.6) : .black.opacity(0.5),
                radius: isHovered ? 12 : 4)
    }

    private var strokeColor: Color {
        if isCurrent { return Theme.teal }
        if isHovered { return Theme.bone }
        return .white.opacity(0.15)
    }

    private var labelColor: Color {
        if isCurrent { return Theme.teal }
        if station.isEmpty { return Theme.muted }
        return Theme.bone
    }
}
