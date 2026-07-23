//
//  SettingsView.swift
//  GTA radio
//
//  Preferences window (⌘,): global hotkey, overlay background opacity,
//  and audio-only playback.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Radio Dial Hotkey") {
                HStack {
                    Toggle("⌃", isOn: $settings.modControl)
                    Toggle("⌥", isOn: $settings.modOption)
                    Toggle("⇧", isOn: $settings.modShift)
                    Toggle("⌘", isOn: $settings.modCommand)
                    Picker("Key", selection: $settings.hotKeyCode) {
                        ForEach(SettingsStore.keyChoices, id: \.code) { choice in
                            Text(choice.label).tag(choice.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }
                .toggleStyle(.button)
                Text("Current: \(settings.shortcutDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                VStack(alignment: .leading) {
                    Text("Overlay background opacity: \(Int(settings.backgroundOpacity * 100))%")
                    Slider(value: $settings.backgroundOpacity, in: 0.15...0.95)
                }
            }

            Section("Playback") {
                Toggle("Audio only (hide video, show artwork)", isOn: $settings.audioOnly)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
