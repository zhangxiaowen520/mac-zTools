import AppKit
import Carbon.HIToolbox

/// Thread-safe-ish Carbon hotkey registry. All public methods must be called on main.
@MainActor
final class HotKeyManager {
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerID: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var installed = false

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        // Best-effort cleanup; avoid crashing if already torn down.
        for (_, ref) in hotKeys {
            UnregisterEventHotKey(ref)
        }
        if let handlerID {
            RemoveEventHandler(handlerID)
        }
    }

    func register(_ chord: KeyChord, id: String, handler: @escaping () -> Void) {
        installHandlerIfNeeded()

        // Skip empty / invalid chords
        guard chord.carbonModifiers != 0 else {
            NSLog("Skip hotkey \(id): no modifiers")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x7A546C73), id: nextID) // 'zTls'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("Failed to register hotkey \(id): \(status)")
            return
        }
        hotKeys[nextID] = ref
        handlers[nextID] = handler
        nextID = nextID &+ 1
        if nextID == 0 { nextID = 1 }
    }

    func unregisterAll() {
        for (_, ref) in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Retain self for the lifetime of the handler
        let retained = Unmanaged.passRetained(self).toOpaque()
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr else { return paramStatus }
                // Hop to main — Carbon may deliver off-main
                DispatchQueue.main.async {
                    manager.handlers[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            retained,
            &ref
        )
        if status == noErr {
            handlerID = ref
            installed = true
        } else {
            Unmanaged<HotKeyManager>.fromOpaque(retained).release()
            NSLog("InstallEventHandler failed: \(status)")
        }
    }
}
