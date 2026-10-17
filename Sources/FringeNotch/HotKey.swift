import Carbon.HIToolbox
import FringeCore

/// One system-wide shortcut through Carbon's hot-key API, which needs no Accessibility permission.
@MainActor public final class HotKey {
    private var reference: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    /// Returns nil when the system refuses the combination (taken by another app or invalid).
    public init?(_ combo: KeyCombo, action: @escaping () -> Void) {
        guard combo.isValid, Self.installHandler() else { return nil }
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4652_4E47), id: id) // "FRNG"
        guard RegisterEventHotKey(combo.keyCode, Self.carbonModifiers(combo.modifiers), hotKeyID,
                                  GetApplicationEventTarget(), 0, &reference) == noErr else { return nil }
        Self.actions[id] = action
    }

    public func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    /// One application handler dispatches every registered shortcut by its ID.
    private static func installHandler() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.actions[id]?() } }
            return noErr
        }, 1, &spec, nil, &handler)
        return status == noErr
    }

    private static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
