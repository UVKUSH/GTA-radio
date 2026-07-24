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
            } header: {
                Label("Appearance", systemImage: "paintbrush.fill")
            }

            Section {
                Toggle("Audio only (hide video, show artwork)", isOn: $settings.audioOnly)
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
