import Carbon
import Foundation

@MainActor
final class AttentionShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func start() {
        guard hotKey == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.signature == 0x4147_444B, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in AppStore.shared.showAttention() }
                return noErr
            }, 1, &type, nil, &handler)
        guard installed == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x4147_444B, id: 1)
        let result = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(controlKey | optionKey | cmdKey), identifier,
            GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            stop()
            AppStore.shared.addLog(
                source: "app", message: "Global attention shortcut unavailable; use the menu-bar item.", level: .warn)
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
