import Foundation
import PulstickCore
import Testing

/// 語順の都合で意味ベースのキー（"trainer.every" など）を使っている箇所は、
/// 訳を書き忘れるとキー名ではなく英語の defaultValue が出て気付きにくいので、テストで検出する
@Suite("Localization")
struct LocalizationTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func japaneseStrings() throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/ja.lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    private func semanticKeysInSources() throws -> Set<String> {
        let dir = root.appendingPathComponent("Sources/Pulstick")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let regex = try NSRegularExpression(pattern: #"String\(localized: "([^"]+)""#)
        var keys = Set<String>()
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        return keys
    }

    @Test func japaneseStringsFileParses() throws {
        #expect(try !japaneseStrings().isEmpty)
    }

    @Test func everySemanticKeyHasJapaneseTranslation() throws {
        let keys = try semanticKeysInSources()
        #expect(!keys.isEmpty)
        let translated = Set(try japaneseStrings().keys)
        #expect(keys.subtracting(translated).isEmpty, "missing: \(keys.subtracting(translated).sorted())")
    }

    /// ステッパーを差し込む文の訳で、差し込み番号が英語と食い違っていないこと。
    /// 食い違うと実行時はステッパーが黙って欠けるので、ここで検出する
    @Test func sentenceTemplatesUseTheSameSlotsAsEnglish() throws {
        let dir = root.appendingPathComponent("Sources/Pulstick")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let regex = try NSRegularExpression(pattern: #"String\(localized: "([^"]+)", defaultValue: "([^"]*%\d+\$@[^"]*)"\)"#)
        let japanese = try japaneseStrings()
        var checked = 0
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                let english = String(text[Range(match.range(at: 2), in: text)!])
                let translated = try #require(japanese[key], "missing: \(key)")
                #expect(slots(in: translated) == slots(in: english), "\(key)")
                #expect(slots(in: english) == Set(0..<slots(in: english).count), "\(key) は 1 から連番にする")
                checked += 1
            }
        }
        #expect(checked >= 4)
    }

    private func slots(in template: String) -> Set<Int> {
        Set(SentenceTemplate.parse(template).compactMap {
            if case .slot(let index) = $0 { index } else { nil }
        })
    }
}
