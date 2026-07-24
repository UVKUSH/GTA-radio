//
//  RadialOverlayView.swift
//  GTA radio
//
//  The GTA-style radio dial: 26 stations arranged on a circle. Populated
//  stations are crisp and clickable; empty slots are dimmed and inert.
//  Hover to preview in the center, click to tune. Esc / background click closes.
//

import SwiftUI

struct RadialOverlayView: View {
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = AppState.shared.store
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var hovered: Int?

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

                ForEach(store.stations) { station in
                    let angle = Double(station.id) / Double(RadioStore.slotCount) * 2 * .pi - .pi / 2
                    StationNode(station: station,
                                isCurrent: app.nowPlaying == station.id,
                                isHovered: hovered == station.id)
                        .position(x: center.x + radius * cos(angle),
                                  y: center.y + radius * sin(angle))
                        .onHover { inside in
                            guard !station.isEmpty else { return }   // empties never highlight
                            if inside, hovered != station.id { SoundPlayer.shared.hoverRotate() }
                            hovered = inside ? station.id : (hovered == station.id ? nil : hovered)
                        }
                        .onTapGesture {
                            guard !station.isEmpty else { return }   // empties are non-selectable
                            onSelect(station.id)
                        }
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onExitCommand { onClose() }
    }

    private var focusStation: Station? {
        if let h = hovered { return store.stations[h] }
        if let n = app.nowPlaying { return store.stations[n] }
        return nil
    }

    private var centerPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("GTA").font(.gtaDisplay(15)).foregroundStyle(Theme.bone.opacity(0.7))
                Text("RADIO").font(.gtaDisplay(15)).foregroundStyle(Theme.magenta.opacity(0.9))
            }
            if let s = focusStation, !s.isEmpty {
                Text(s.displayName)
                    .font(.gtaDisplay(30))
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let t = app.player.nowPlayingTitle, app.nowPlaying == s.id {
                    Text(t)
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .lineLimit(1).frame(width: 240)
                }
                Text(app.nowPlaying == s.id ? "▶ NOW PLAYING · \(Theme.frequency(for: s.id)) FM" : "CLICK TO TUNE IN")
                    .font(.gtaMono(10)).tracking(1)
                    .foregroundStyle(app.nowPlaying == s.id ? Theme.teal : Theme.muted)
            } else {
                Text("Hover a station")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            if app.nowPlaying != nil {
                TransportControls(showsVolume: true, playSize: 40)
                    .padding(.top, 6)
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
        // The hovered node pops forward above its neighbours.
        .scaleEffect(isHovered ? 1.18 : 1)
        .zIndex(isHovered ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isHovered)
        .opacity(station.isEmpty ? 0.32 : 1)
    }

    private var circle: some View {
        ZStack {
            Circle().fill(station.isEmpty ? Color.white.opacity(0.05) : Color.black)
            if let t = station.thumbnailURL, let url = URL(string: t) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
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
