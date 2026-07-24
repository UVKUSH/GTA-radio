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
    @State private var appeared = false   // drives the open "bloom"
    @State private var spin = false       // slow ambient ring rotation

    private var stations: [Station] { app.currentStations }
    private var folderSpring: Animation { .spring(response: 0.35, dampingFraction: 0.8) }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.40

            ZStack {
                Color.black.opacity(appeared ? settings.backgroundOpacity : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                tickRings(radius: radius).position(center)

                centerPanel
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .position(center)

                wheel(center: center, radius: radius)
                    .id(app.currentPath)   // folder change = a fresh wheel blooms in
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
            }
            // Hover = mouse angle around the center, not the node bounds. The
            // nodes MOVE on hover (lean, fisheye, pop-out); hit-testing them
            // directly made them slide out from under the cursor and flicker.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): setHovered(slot(at: p, center: center, radius: radius))
                case .ended: setHovered(nil)
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onExitCommand {
            if app.isInFolder { withAnimation(folderSpring) { app.goBack() } } else { onClose() }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    /// The 26 nodes, blooming out from the center with a per-slot stagger.
    /// Hover gives dock-style "play": the hovered node pops outward and its
    /// neighbors swell and nudge with it.
    private func wheel(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach(stations) { station in
                let angle = Double(station.id) / Double(RadioStore.slotCount) * 2 * .pi - .pi / 2
                    + wheelTwist * .pi / 180
                let boost = hoverBoost(for: station.id)
                let r = (appeared ? radius : radius * 0.35) + boost * 18
                Button { select(station) } label: {
                    StationNode(station: station,
                                isCurrent: station.uid == app.nowPlayingUID,
                                isHovered: hovered == station.id)
                }
                .buttonStyle(PressBounce())
                // Neighbors swell via `boost`; the hovered node scales itself.
                .scaleEffect((appeared ? 1 : 0.2) * (hovered == station.id ? 1 : 1 + boost * 0.12))
                .opacity(appeared ? 1 : 0)
                .position(x: center.x + r * cos(angle),
                          y: center.y + r * sin(angle))
                .animation(.spring(response: 0.42, dampingFraction: 0.68)
                    .delay(Double(station.id) * 0.018), value: appeared)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: hovered)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: hovered)
    }

    /// Degrees the whole wheel leans while hovering: it rotates a few degrees
    /// the short way round, as if dragged toward 12 o'clock by the hovered
    /// station. Positions rotate; the nodes themselves stay upright.
    private var wheelTwist: Double {
        guard let h = hovered else { return 0 }
        var deg = Double(h) / Double(RadioStore.slotCount) * 360   // 0 = 12 o'clock
        if deg > 180 { deg -= 360 }                                // signed, -180…180
        return -deg * 0.05                                         // up to ~±9°
    }

    /// 0 at rest → 1 on the hovered node, falling off around the ring so the
    /// wheel reacts like the macOS Dock.
    private func hoverBoost(for id: Int) -> Double {
        guard let h = hovered else { return 0 }
        let d = abs(id - h)
        switch min(d, RadioStore.slotCount - d) {
        case 0: return 1
        case 1: return 0.45
        case 2: return 0.15
        default: return 0
        }
    }

    /// Faint counter-rotating "tuning tick" rings behind the wheel.
    private func tickRings(radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 10]))
                .foregroundStyle(Theme.bone.opacity(0.10))
                .frame(width: radius * 2 + 70, height: radius * 2 + 70)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 26]))
                .foregroundStyle(Theme.teal.opacity(0.12))
                .frame(width: radius * 2 - 40, height: radius * 2 - 40)
                .rotationEffect(.degrees(spin ? -360 : 0))
        }
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        // Lean with the wheel (outer layer, so the slow spin keeps running).
        .rotationEffect(.degrees(wheelTwist))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: hovered)
        .allowsHitTesting(false)
    }

    /// Which of the 26 fixed angular sectors the point falls in, or nil when
    /// the cursor is over the center panel or outside the wheel's band.
    private func slot(at p: CGPoint, center: CGPoint, radius: CGFloat) -> Int? {
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > radius * 0.45, dist < radius * 1.35 else { return nil }
        var turns = (atan2(dy, dx) + .pi / 2) / (2 * .pi)   // 0 = 12 o'clock
        turns -= turns.rounded(.down)                        // wrap into 0…1
        return Int((turns * Double(RadioStore.slotCount)).rounded()) % RadioStore.slotCount
    }

    private func setHovered(_ id: Int?) {
        guard hovered != id else { return }
        if id != nil { SoundPlayer.shared.hoverRotate() }   // blip on every hop
        hovered = id
    }

    private func select(_ station: Station) {
        if station.isFolder {
            SoundPlayer.shared.hoverRotate()
            withAnimation(folderSpring) { app.enterFolder(index: station.id) }
            hovered = nil
        } else if !station.isEmpty {
            SoundPlayer.shared.hoverRotate()
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
                Button { withAnimation(folderSpring) { app.goBack() } } label: {
                    Label(app.currentFolderName ?? "Folder", systemImage: "chevron.left")
                        .font(.gtaMono(10)).tracking(1).foregroundStyle(Theme.muted)
                }.buttonStyle(.plain)
            }

            ZStack {
                if let s = focusStation {
                    VStack(spacing: 4) {
                        Text(s.displayName)
                            .font(.gtaDisplay(30)).foregroundStyle(Theme.bone)
                            .multilineTextAlignment(.center).lineLimit(2)
                        Text(s.isFolder ? "OPEN FOLDER"
                             : s.isEmpty ? "EMPTY SLOT"
                             : (s.uid == app.nowPlayingUID ? "▶ NOW PLAYING · \(Theme.frequency(for: s.id)) FM" : "CLICK TO TUNE IN"))
                            .font(.gtaMono(10)).tracking(1)
                            .foregroundStyle(s.uid == app.nowPlayingUID ? Theme.teal : Theme.muted)
                    }
                    .id(s.uid)   // new station = fresh view, so the transition runs
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    Text("Hover a station")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovered)

            if app.hasNowPlaying {
                TransportControls(showsVolume: true, playSize: 40).padding(.top, 6)
            }
        }
        .frame(width: 340)   // fits transport + volume (300 made them overflow)
    }
}

/// Squash-on-press so clicking a station feels tactile, then spring back.
private struct PressBounce: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

private struct StationNode: View {
    let station: Station
    let isCurrent: Bool
    let isHovered: Bool
    @ObservedObject private var settings = SettingsStore.shared

    /// User-set dial opacity; hover/now-playing always render full-strength
    /// so feedback stays readable, and empty slots keep their extra dimming.
    private var nodeOpacity: Double {
        let user = (isHovered || isCurrent) ? 1 : settings.dialIconOpacity
        let empty = station.isEmpty ? (isHovered ? 0.65 : 0.32) : 1
        return user * empty
    }

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
        // Gentle tilt with a soft overshoot — playful but not jittery.
        .rotationEffect(.degrees(isHovered ? -4 : 0))
        .animation(.spring(response: 0.4, dampingFraction: 0.45), value: isHovered)
        .scaleEffect(isHovered ? 1.24 : 1)
        .zIndex(isHovered ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHovered)
        .opacity(nodeOpacity)
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
        .overlay { if isCurrent { BroadcastRipple() } }
        .overlay(alignment: .bottom) {
            if isCurrent {
                EqualizerBadge()
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.black.opacity(0.75), in: Capsule())
                    .offset(y: 8)
            }
        }
        .shadow(color: isCurrent ? Theme.teal.opacity(0.6)
                     : isHovered ? Theme.magenta.opacity(0.55) : .black.opacity(0.5),
                radius: isHovered ? 14 : 4)
    }

    // Teal = on air (always wins), magenta = where your cursor is.
    private var strokeColor: Color {
        if isCurrent { return Theme.teal }
        if isHovered { return Theme.magenta }
        return .white.opacity(0.15)
    }

    private var labelColor: Color {
        if isCurrent { return Theme.teal }
        if isHovered { return Theme.magenta }
        if station.isEmpty { return Theme.muted }
        return Theme.bone
    }
}
