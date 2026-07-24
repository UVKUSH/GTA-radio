//
//  OnboardingOverlay.swift
//  GTA radio
//
//  First-run "welcome tour": a non-interactive scrim that dims the window and
//  spotlights real UI elements (located via anchorPreference), with a callout
//  beside each. Shown once (see hasCompletedOnboarding) after the intro, and
//  replayable from Settings.
//

import SwiftUI

/// Real UI elements the tour can point at. The radial dial is a separate ⌥R
/// overlay window, so the main-window filmstrip stands in as `.stations`.
enum CoachTarget: Hashable { case stations, wheels, settings }

/// Collects the on-screen bounds of every tagged target, keyed by target.
struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [CoachTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachTarget: Anchor<CGRect>],
                       nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds so the onboarding overlay can spotlight it.
    func coachAnchor(_ target: CoachTarget) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// One tour card. `target == nil` → a centered card (no spotlight).
struct OnboardingStep {
    let target: CoachTarget?
    let title: String
    let body: String
}

let onboardingSteps: [OnboardingStep] = [
    .init(target: nil,        title: "Wasted FM",       body: "GTA Radio — your personal radio, built from any YouTube link."),
    .init(target: .stations,  title: "Your stations",   body: "Click a station to tune in. Every wheel holds 26 slots."),
    .init(target: .stations,  title: "Add anything",    body: "Click an empty slot to paste any YouTube video or playlist. No API key, no sign-in."),
    .init(target: nil,        title: "Pop it anywhere", body: "Press ⌥R anywhere on your Mac to summon the radial dial over any app."),
    .init(target: .wheels,    title: "Wheels",          body: "Save whole 26-station layouts as Wheels — switch between them with ⌘1–9."),
    .init(target: .settings,  title: "Settings",        body: "Audio-only mode, a custom hotkey, and appearance all live here."),
]

struct OnboardingOverlay: View {
    let anchors: [CoachTarget: Anchor<CGRect>]
    let proxy: GeometryProxy
    var onFinish: () -> Void
    @State private var index = 0
    @State private var opacity: Double = 0

    private var step: OnboardingStep { onboardingSteps[index] }
    private var isLast: Bool { index == onboardingSteps.count - 1 }

    /// Resolved spotlight rect for the active step, or nil (→ centered card).
    private var spotlight: CGRect? {
        guard let t = step.target, let a = anchors[t] else { return nil }
        return proxy[a].insetBy(dx: -10, dy: -10)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            scrim
            callout
            Button("Skip", action: finish)
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .padding(16)

            // Esc = skip. Invisible cancel-shortcut button (fires regardless of
            // focus in a window) — same proven trick IntroSplashView uses;
            // .onExitCommand is focus-dependent and can silently miss Esc here.
            Button("", action: finish)
                .keyboardShortcut(.cancelAction)
                .opacity(0).allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { opacity = 1 } }
    }

    /// Dim everything; punch a rounded hole around the spotlight rect.
    private var scrim: some View {
        Color.black.opacity(0.72)
            .contentShape(Rectangle())
            .mask {
                ZStack {
                    Rectangle()
                    if let r = spotlight {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .animation(.easeInOut(duration: 0.25), value: index)
    }

    /// Callout: near the spotlight (below, or above if low); centered if none.
    @ViewBuilder private var callout: some View {
        if let r = spotlight {
            calloutCard
                .frame(maxWidth: 340)
                .position(calloutPosition(for: r))
                .animation(.easeInOut(duration: 0.25), value: index)
        } else {
            calloutCard
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func calloutPosition(for r: CGRect) -> CGPoint {
        let size = proxy.size
        let below = r.maxY + 90
        let y = below + 60 < size.height ? below : r.minY - 90
        let x = min(max(r.midX, 190), size.width - 190)
        return CGPoint(x: x, y: y)
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title).font(.gtaDisplay(26)).foregroundStyle(Theme.bone)
            Text(step.body).font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(onboardingSteps.indices, id: \.self) { i in
                    Circle().fill(i == index ? Theme.magenta : .white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if index > 0 {
                    Button("Back") { withAnimation { index -= 1 } }.buttonStyle(.plain)
                }
                Button(isLast ? "Get started" : "Next") {
                    if isLast { finish() } else { withAnimation { index += 1 } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .shadow(radius: 30)
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: onFinish)
    }
}
