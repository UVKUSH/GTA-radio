//
//  HotKeyManager.swift
//  GTA radio
//
//  Global hotkey via Carbon RegisterEventHotKey. This is sandbox-safe (unlike
//  global event monitoring, it needs no Accessibility permission). Default: ⌥R.
//

import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Called on the main thread whenever the hotkey fires.
    var onTrigger: (() -> Void)?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        // 'GTRA' signature, id 1 — ⌥R.
        let hotKeyID = EventHotKeyID(signature: OSType(0x47545241), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(optionKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
