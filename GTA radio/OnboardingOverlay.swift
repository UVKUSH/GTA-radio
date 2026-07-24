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
    var onFinish: () -> Void
    @State private var index = 0
    @State private var opacity: Double = 0

    private var step: OnboardingStep { onboardingSteps[index] }
    private var isLast: Bool { index == onboardingSteps.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            // Resolve the active step's target rect (nil → centered card).
            let overlay = overlayContent(proxy: proxy)
            overlay
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { opacity = 1 } }
    }

    @ViewBuilder
    private func overlayContent(proxy: GeometryProxy) -> some View {
        // The parent supplies anchors via .overlayPreferenceValue; this view is
        // rendered inside that closure (see RootView), so we read them there and
        // pass a resolved rect down. Here we just lay out scrim + callout.
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.72)
                .contentShape(Rectangle())            // eat all clicks (non-interactive app beneath)
            calloutCard
                .frame(maxWidth: 360)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

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
