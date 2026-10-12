import Carbon.HIToolbox
import PulstickCore

/// ポップオーバーを開かずに、どのアプリを使っていても操作できるグローバルショートカット。
/// Carbon の RegisterEventHotKey はアクセシビリティ権限が不要なので、初回起動から使える。
///
/// - ⌃⌥M: 再生 / 停止
/// - ⌃⌥T: タップテンポ（他アプリで流している曲に合わせてテンポを取る用途）
final class GlobalHotKeys {
    private enum Action: UInt32 {
        case toggle = 1
        case tap = 2
    }

    private weak var engine: PulstickEngine?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    init(engine: PulstickEngine) {
        self.engine = engine
        installHandler()
        register(.toggle, keyCode: UInt32(kVK_ANSI_M))
        register(.tap, keyCode: UInt32(kVK_ANSI_T))
    }

    deinit {
        hotKeyRefs.forEach { if let ref = $0 { UnregisterEventHotKey(ref) } }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func register(_ action: Action, keyCode: UInt32) {
        // "PLST" を4文字コードとしてアプリ固有の signature にする
        let id = EventHotKeyID(signature: 0x504C_5354, id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref
        )
        // 他アプリが同じ組み合わせを先に登録している場合は失敗する。致命的ではないので無視する
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            hotKeys.perform(Action(rawValue: hotKeyID.id))
            return noErr
        }, 1, &eventType, selfPointer, &handlerRef)
    }

    private func perform(_ action: Action?) {
        guard let engine else { return }
        switch action {
        case .toggle: engine.toggle()
        case .tap: engine.tapTempo()
        case nil: break
        }
    }
}
