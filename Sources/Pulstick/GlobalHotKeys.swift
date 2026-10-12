import Carbon.HIToolbox
import PulstickCore

/// ポップオーバーを開かずに、どのアプリを使っていても操作できるグローバルショートカット。
/// Carbon の RegisterEventHotKey はアクセシビリティ権限が不要なので、初回起動から使える。
///
/// - ⌃⌥M: 再生 / 停止
/// - ⌃⌥T: タップテンポ（他アプリで流している曲に合わせてテンポを取る用途）
/// - ⌃⌥, / ⌃⌥.: セットリストの前の曲 / 次の曲（リハーサル中に楽器を持ったまま切り替える）。
///   キーに < > が書かれていて向きが分かり、日本語配列でも位置が変わらないキーを選んでいる
final class GlobalHotKeys {
    private enum Action: UInt32 {
        case toggle = 1
        case tap = 2
        case previousSong = 3
        case nextSong = 4
    }

    /// 他アプリと競合して登録できなかったショートカットは UI で案内しないようにする
    private(set) var isToggleAvailable = false
    private(set) var isTapAvailable = false
    private(set) var isSongStepAvailable = false

    private weak var engine: PulstickEngine?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    init(engine: PulstickEngine) {
        self.engine = engine
        installHandler()
        if let toggle = register(.toggle, keyCode: UInt32(kVK_ANSI_M)) {
            hotKeyRefs.append(toggle)
            isToggleAvailable = true
        }
        if let tap = register(.tap, keyCode: UInt32(kVK_ANSI_T)) {
            hotKeyRefs.append(tap)
            isTapAvailable = true
        }
        // 前の曲・次の曲は対で使うもの。片方しか取れなければ両方とも諦め、案内とずれないようにする
        let previous = register(.previousSong, keyCode: UInt32(kVK_ANSI_Comma))
        let next = register(.nextSong, keyCode: UInt32(kVK_ANSI_Period))
        if let previous, let next {
            hotKeyRefs += [previous, next]
            isSongStepAvailable = true
        } else {
            [previous, next].compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        }
    }

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func register(_ action: Action, keyCode: UInt32) -> EventHotKeyRef? {
        // "PLST" を4文字コードとしてアプリ固有の signature にする
        let id = EventHotKeyID(signature: 0x504C_5354, id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref
        )
        // 他アプリが同じ組み合わせを先に登録している場合は失敗する。致命的ではないので黙って諦める
        guard status == noErr else { return nil }
        return ref
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
        case .previousSong: engine.applyAdjacentSong(-1)
        case .nextSong: engine.applyAdjacentSong(1)
        case nil: break
        }
    }
}
