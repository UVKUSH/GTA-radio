//
//  HotKeyManager.swift
//  GTA radio
//
//  Global hotkey via Carbon RegisterEventHotKey. This is sandbox-safe (unlike
//  global event monitoring, it needs no Accessibility permission).
//

import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Called on the main thread whenever the hotkey fires.
    var onTrigger: (() -> Void)?

    /// Register (or re-register) the given key + Carbon modifier mask.
    func register(keyCode: UInt32, modifiers: UInt32) {
        installHandlerIfNeeded()
        unregisterHotKey()
        let hotKeyID = EventHotKeyID(signature: OSType(0x47545241), id: 1) // 'GTRA'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregisterHotKey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
