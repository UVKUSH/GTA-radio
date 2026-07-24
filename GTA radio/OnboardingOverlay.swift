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
