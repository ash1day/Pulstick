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

extension SettingsStore {
    /// Codable な値を JSON として保存・復元する。壊れたデータは nil として扱い既定値に戻す
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = object(forKey: key) as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 保存済みの JSON を既定値の JSON の上に重ねてからデコードする。
    /// 型にフィールドを足しても、古い保存データの残りの値を捨てずに済む
    func codable<T: Codable>(forKey key: String, default fallback: T) -> T {
        guard let data = object(forKey: key) as? Data else { return fallback }
        if let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(fallback),
              let base = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new }),
              let decoded = try? JSONDecoder().decode(T.self, from: merged)
        else { return fallback }
        return decoded
    }

    func setCodable<T: Encodable>(_ value: T, forKey key: String) {
        set(try? JSONEncoder().encode(value), forKey: key)
    }
}
