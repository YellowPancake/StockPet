import Carbon
import Foundation

final class GlobalHotKeyController {
    var onPress: (() -> Void)?

    private let signature: OSType = 0x5354_5054 // STPT
    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                if status == noErr, identifier.signature == controller.signature {
                    controller.onPress?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
    }

    func register(
        enabled: Bool,
        modifier: ShortcutModifierOption,
        key: ShortcutKeyOption
    ) {
        unregister()
        guard enabled else { return }

        let identifier = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            key.carbonKeyCode,
            modifier.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    deinit {
        unregister()
        if let handlerReference {
            RemoveEventHandler(handlerReference)
        }
    }
}

private extension ShortcutModifierOption {
    var carbonModifiers: UInt32 {
        switch self {
        case .commandOption:
            UInt32(cmdKey) | UInt32(optionKey)
        case .commandShift:
            UInt32(cmdKey) | UInt32(shiftKey)
        case .controlOption:
            UInt32(controlKey) | UInt32(optionKey)
        case .controlShift:
            UInt32(controlKey) | UInt32(shiftKey)
        }
    }
}

private extension ShortcutKeyOption {
    var carbonKeyCode: UInt32 {
        switch self {
        case .s: 1
        case .p: 35
        case .h: 4
        case .k: 40
        case .d: 2
        case .f: 3
        case .space: 49
        }
    }
}
