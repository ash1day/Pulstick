import Foundation

/// 設定の保存先。本番は UserDefaults、テストはメモリ上の実装を差し込む
public protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]

    public init() {}

    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
}
