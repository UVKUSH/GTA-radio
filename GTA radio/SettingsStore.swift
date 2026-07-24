//
//  SettingsStore.swift
//  GTA radio
//
//  User-configurable settings: global hotkey, overlay background opacity,
//  and audio-only playback. Persisted to UserDefaults.
//

import Foundation
import Carbon.HIToolbox
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    /// Called (main thread) whenever the hotkey combo changes, so it can be re-registered.
    var onHotKeyChange: (() -> Void)?

    @Published var hotKeyCode: Int { didSet { defaults.set(hotKeyCode, forKey: "hotKeyCode"); onHotKeyChange?() } }
    @Published var modOption: Bool { didSet { defaults.set(modOption, forKey: "modOption"); onHotKeyChange?() } }
    @Published var modCommand: Bool { didSet { defaults.set(modCommand, forKey: "modCommand"); onHotKeyChange?() } }
    @Published var modControl: Bool { didSet { defaults.set(modControl, forKey: "modControl"); onHotKeyChange?() } }
    @Published var modShift: Bool { didSet { defaults.set(modShift, forKey: "modShift"); onHotKeyChange?() } }

    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: "backgroundOpacity") } }
    @Published var controlsOpacity: Double { didSet { defaults.set(controlsOpacity, forKey: "controlsOpacity") } }
    @Published var audioOnly: Bool { didSet { defaults.set(audioOnly, forKey: "audioOnly") } }

    private init() {
        hotKeyCode = defaults.object(forKey: "hotKeyCode") as? Int ?? kVK_ANSI_R
        modOption = defaults.object(forKey: "modOption") as? Bool ?? true
        modCommand = defaults.object(forKey: "modCommand") as? Bool ?? false
        modControl = defaults.object(forKey: "modControl") as? Bool ?? false
        modShift = defaults.object(forKey: "modShift") as? Bool ?? false
        backgroundOpacity = defaults.object(forKey: "backgroundOpacity") as? Double ?? 0.55
        controlsOpacity = defaults.object(forKey: "controlsOpacity") as? Double ?? 1.0
        audioOnly = defaults.object(forKey: "audioOnly") as? Bool ?? false
    }

    // MARK: Carbon translation

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modOption { m |= UInt32(optionKey) }
        if modCommand { m |= UInt32(cmdKey) }
        if modControl { m |= UInt32(controlKey) }
        if modShift { m |= UInt32(shiftKey) }
        return m
    }

    var shortcutDescription: String {
        var s = ""
        if modControl { s += "⌃" }
        if modOption { s += "⌥" }
        if modShift { s += "⇧" }
        if modCommand { s += "⌘" }
        s += SettingsStore.keyLabel(for: hotKeyCode)
        return s
    }

    /// (keyCode, label) options offered in the settings picker.
    static let keyChoices: [(code: Int, label: String)] = {
        let letters: [(Int, String)] = [
            (kVK_ANSI_A,"A"),(kVK_ANSI_B,"B"),(kVK_ANSI_C,"C"),(kVK_ANSI_D,"D"),(kVK_ANSI_E,"E"),
            (kVK_ANSI_F,"F"),(kVK_ANSI_G,"G"),(kVK_ANSI_H,"H"),(kVK_ANSI_I,"I"),(kVK_ANSI_J,"J"),
            (kVK_ANSI_K,"K"),(kVK_ANSI_L,"L"),(kVK_ANSI_M,"M"),(kVK_ANSI_N,"N"),(kVK_ANSI_O,"O"),
            (kVK_ANSI_P,"P"),(kVK_ANSI_Q,"Q"),(kVK_ANSI_R,"R"),(kVK_ANSI_S,"S"),(kVK_ANSI_T,"T"),
            (kVK_ANSI_U,"U"),(kVK_ANSI_V,"V"),(kVK_ANSI_W,"W"),(kVK_ANSI_X,"X"),(kVK_ANSI_Y,"Y"),
            (kVK_ANSI_Z,"Z")
        ]
        let digits: [(Int, String)] = [
            (kVK_ANSI_0,"0"),(kVK_ANSI_1,"1"),(kVK_ANSI_2,"2"),(kVK_ANSI_3,"3"),(kVK_ANSI_4,"4"),
            (kVK_ANSI_5,"5"),(kVK_ANSI_6,"6"),(kVK_ANSI_7,"7"),(kVK_ANSI_8,"8"),(kVK_ANSI_9,"9")
        ]
        return letters + digits
    }()

    static func keyLabel(for code: Int) -> String {
        keyChoices.first { $0.code == code }?.label ?? "?"
    }
}
