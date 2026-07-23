//
//  RadialOverlayView.swift
//  GTA radio
//
//  The GTA-style radio dial: 26 stations arranged on a circle. Hover to
//  preview in the center, click to tune in. Esc or a background click closes.
//

import SwiftUI

struct RadialOverlayView: View {
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = AppState.shared.store
    @ObservedObject private var app = AppState.shared
    @State private var hovered: Int?

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.40

            ZStack {
                // Dim backdrop — click anywhere empty to dismiss.
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                centerPanel
                    .position(center)

                ForEach(store.stations) { station in
                    let angle = Double(station.id) / Double(RadioStore.slotCount) * 2 * .pi - .pi / 2
                    StationNode(station: station,
                                isCurrent: app.nowPlaying == station.id,
                                isHovered: hovered == station.id)
                        .position(x: center.x + radius * cos(angle),
                                  y: center.y + radius * sin(angle))
                        .onHover { hovered = $0 ? station.id : (hovered == station.id ? nil : hovered) }
                        .onTapGesture {
                            guard !station.isEmpty else { return }
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
        VStack(spacing: 8) {
            Text("GTA RADIO")
                .font(.system(size: 13, weight: .heavy)).tracking(4)
                .foregroundStyle(.white.opacity(0.5))
            if let s = focusStation, !s.isEmpty {
                Text(s.displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(app.nowPlaying == s.id ? "▶ Now Playing" : "Click to tune in")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.nowPlaying == s.id ? .green : .white.opacity(0.6))
            } else {
                Text("Hover a station")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 220)
    }
}

private struct StationNode: View {
    let station: Station
    let isCurrent: Bool
    let isHovered: Bool

    private var diameter: CGFloat { isHovered ? 72 : 60 }

    var body: some View {
        ZStack {
            Circle().fill(station.isEmpty ? Color.white.opacity(0.06) : Color.black)
            if let t = station.thumbnailURL, let url = URL(string: t) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
                .clipShape(Circle())
            } else if station.isEmpty {
                Image(systemName: "plus").foregroundStyle(.white.opacity(0.25))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            Circle().stroke(isCurrent ? Color.green : (isHovered ? Color.white : Color.white.opacity(0.15)),
                            lineWidth: isCurrent ? 3 : (isHovered ? 3 : 1))
        )
        .shadow(color: .black.opacity(0.5), radius: isHovered ? 10 : 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .opacity(station.isEmpty ? 0.5 : 1)
    }
}
