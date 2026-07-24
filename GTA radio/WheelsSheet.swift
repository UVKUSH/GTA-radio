//
//  WheelsSheet.swift
//  GTA radio
//
//  "My Wheels": save the whole 26-slot wheel (folders included) under a name
//  and swap between saved wheels. Loading auto-backs-up the current wheel to
//  the "Last session" preset, so a swap can never lose work.
//

import SwiftUI
import UniformTypeIdentifiers

struct WheelsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var store = AppState.shared.store
    @State private var newName = ""
    @State private var importMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("My Wheels").font(.gtaDisplay(24))
            Text("Save the whole 26-slot wheel — folders included — and reload it any time. Loading a wheel backs the current one up to “\(RadioStore.backupPresetName)”.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Name this wheel (e.g. Night Drive)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveCurrent)
                Button("Save current wheel") { saveCurrent() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newNameIsReserved)
            }
            if newNameIsReserved {
                Text("“\(RadioStore.backupPresetName)” is reserved for the automatic backup — pick another name.")
                    .font(.caption).foregroundStyle(.orange)
            }

            if store.presets.isEmpty {
                Text("No saved wheels yet — name the current one above to start.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.presets) { preset in
                            PresetRow(preset: preset,
                                      isBackup: preset.name == RadioStore.backupPresetName,
                                      onLoad: { load(preset) },
                                      onRename: { store.renamePreset(id: preset.id, to: $0) },
                                      onDelete: { store.deletePreset(id: preset.id) },
                                      onExport: { export(preset) })
                        }
                    }
                }
                .frame(maxHeight: 330)
            }

            HStack {
                Button("Import wheel…") { importWheel() }
                if let msg = importMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    /// Saving under the auto-backup's name would get silently clobbered on the
    /// next load — refuse it up front.
    private var newNameIsReserved: Bool {
        newName.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(RadioStore.backupPresetName) == .orderedSame
    }

    private func saveCurrent() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !newNameIsReserved else { return }
        store.savePreset(named: name)
        newName = ""
    }

    private func load(_ preset: WheelPreset) {
        store.loadPreset(preset)
        AppState.shared.goHome()   // old folder paths may not exist in this wheel
        isPresented = false
    }

    private func export(_ preset: WheelPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        // Wheel names are free text — strip path-hostile characters.
        let safeName = preset.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName).gtawheel.json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = store.exportData(for: preset) else { return }
        do {
            try data.write(to: url)
            importMessage = "Exported “\(preset.name)”."
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importWheel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let name = store.importPreset(from: data) else {
            importMessage = "Couldn't read that file as a wheel."
            return
        }
        importMessage = "Imported “\(name)”."
    }
}

/// One saved wheel: thumbnail collage, name (editable), meta line, actions.
private struct PresetRow: View {
    let preset: WheelPreset
    let isBackup: Bool
    let onLoad: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    @State private var renaming = false
    @State private var renameText = ""
    @State private var hovering = false

    private var filledCount: Int { preset.stations.filter { !$0.isEmpty }.count }
    private var thumbs: [URL] {
        preset.stations.compactMap { $0.thumbnailURL.flatMap(URL.init) }.prefix(4).map { $0 }
    }

    var body: some View {
        HStack(spacing: 12) {
            collage

            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { commitRename() }
                } else {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if isBackup {
                        Text("AUTO").font(.gtaMono(8))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.teal.opacity(0.85), in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Text("\(filledCount) stations · saved \(preset.savedAt, format: .relative(presentation: .named))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if renaming {
                Button("Save") { commitRename() }
                Button("Cancel") { renaming = false }
            } else {
                Button("Load") { onLoad() }
                Menu {
                    Button("Rename…") { renameText = preset.name; renaming = true }
                    Button("Export…") { onExport() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(hovering ? 0.10 : 0.05)))
        .onHover { hovering = $0 }
    }

    private func commitRename() {
        onRename(renameText)
        renaming = false
    }

    /// Up to 4 station thumbnails stacked as a mini collage.
    private var collage: some View {
        HStack(spacing: -10) {
            if thumbs.isEmpty {
                Image(systemName: "dial.medium")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.4), in: Circle())
            } else {
                ForEach(Array(thumbs.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Color.black.opacity(0.4) }
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                }
            }
        }
        .frame(width: 30 + 20 * CGFloat(max(thumbs.count - 1, 0)), alignment: .leading)
    }
}
