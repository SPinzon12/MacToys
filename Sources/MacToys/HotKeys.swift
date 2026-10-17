import Carbon
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey`.
/// Carbon is still the boring native way to get system-wide chords from a bare executable.
final class HotKeys {
    private struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let title: String
    }

    private let bindings: [Binding] = [
        Binding(id: 1, keyCode: UInt32(kVK_ANSI_C), title: "⌃⇧C"),
        Binding(id: 2, keyCode: UInt32(kVK_ANSI_O), title: "⌃⇧O"),
        Binding(id: 3, keyCode: UInt32(kVK_ANSI_V), title: "⌃⇧V")
    ]

    private static let signature: OSType = 0x4D505459 // 'MPTY'

    private let modifiers = UInt32(controlKey | shiftKey)
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    /// Registers every binding. A chord that is already taken is logged and skipped;
    /// the remaining hotkeys and the menu still work.
    func register() {
        installHandlerIfNeeded()
        for binding in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: binding.id)
            let status = RegisterEventHotKey(
                binding.keyCode,
                modifiers,
                id,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr {
                refs.append(ref)
            } else {
                print("HotKeys: could not register \(binding.title) (OSStatus \(status)); continuing")
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        // ponytail: bare C callback over an install counter; no dispatcher class for 3 chords
        _ = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                Unmanaged<HotKeys>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .fire(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )
        // ponytail: if the handler install fails we only log — the menu still runs
        if handler == nil {
            print("HotKeys: could not install event handler; global hotkeys disabled")
        }
    }

    private func fire(id: UInt32) {
        switch id {
        case 1: ColorPickerModule.trigger()
        case 2: TextExtractorModule.trigger()
        case 3: AdvancedPasteModule.trigger()
        default: break
        }
    }
}
