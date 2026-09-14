import Carbon
import MiracleShotCore

/// Registers global hotkeys through Carbon and maps them back to `CaptureAction`.
///
/// Construct once and keep for the process lifetime: the Carbon handler holds an unretained pointer to this
/// object and is never removed, so deallocating a manager while hotkeys are registered would be a use-after-free.
@MainActor
public final class HotkeyManager {
    public typealias Handler = @MainActor (CaptureAction) -> Void

    private static let signature: OSType = 0x4D53_4854 // "MSHT"
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: CaptureAction] = [:]
    private var eventHandler: EventHandlerRef?
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
        installEventHandler()
    }

    /// Replaces all bindings. Returns the actions whose hotkey could not be registered: taken by another app, or the
    /// same combination bound to an earlier action in `CaptureAction.allCases` order.
    @discardableResult
    public func register(_ bindings: [CaptureAction: HotkeySpec]) -> [CaptureAction] {
        unregisterAll()
        var failed: [CaptureAction] = []
        for (index, action) in CaptureAction.allCases.enumerated() {
            guard let spec = bindings[action] else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(spec.carbonKeyCode, spec.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionsByID[id.id] = action
            } else {
                failed.append(action)
            }
        }
        return failed
    }

    public func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        // The C callback cannot capture context; `userData` carries the manager. Carbon delivers on the main thread.
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
        assert(status == noErr, "InstallEventHandler failed with status \(status); hotkeys will never fire")
    }

    private func fire(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        handler(action)
    }
}
