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
            Section {
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
            } header: {
                Label("Radio Dial Hotkey", systemImage: "dial.medium.fill")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Overlay background opacity: \(Int(settings.backgroundOpacity * 100))%")
                    Slider(value: $settings.backgroundOpacity, in: 0.15...0.95)
                }
                VStack(alignment: .leading) {
                    Text("Audio controls opacity: \(Int(settings.controlsOpacity * 100))%")
                    Slider(value: $settings.controlsOpacity, in: 0.2...1.0)
                }
                VStack(alignment: .leading) {
                    Text("Dial station opacity: \(Int(settings.dialIconOpacity * 100))%")
                    Slider(value: $settings.dialIconOpacity, in: 0.25...1.0)
                    Text("Hovered and now-playing stations always show at full strength.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("Appearance", systemImage: "paintbrush.fill")
            }

            Section {
                Toggle("Audio only (hide video, show artwork)", isOn: $settings.audioOnly)
                Toggle("Dial sound effects", isOn: $settings.uiSounds)
            } header: {
                Label("Playback", systemImage: "play.circle.fill")
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
