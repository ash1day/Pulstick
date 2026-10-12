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

    /// アプリ本体のソースを正規表現で走査し、マッチごとのキャプチャグループ（1 番目以降）を返す
    private func matches(of pattern: String, excluding excludedFiles: Set<String> = []) throws -> [(file: String, groups: [String])] {
        let dir = root.appendingPathComponent("Sources/Pulstick")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let regex = try NSRegularExpression(pattern: pattern)
        var results: [(file: String, groups: [String])] = []
        for file in files where file.pathExtension == "swift" && !excludedFiles.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let groups = (1..<match.numberOfRanges).map { String(text[Range(match.range(at: $0), in: text)!]) }
                results.append((file.lastPathComponent, groups))
            }
        }
        return results
    }

    private func semanticKeysInSources() throws -> Set<String> {
        Set(try matches(of: #"String\(localized: "([^"]+)""#).map { $0.groups[0] })
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
        let japanese = try japaneseStrings()
        var checked = 0
        for match in try matches(of: #"String\(localized: "([^"]+)", defaultValue: "([^"]*%\d+\$@[^"]*)"\)"#) {
            let key = match.groups[0]
            let english = match.groups[1]
            let translated = try #require(japanese[key], "missing: \(key)")
            #expect(slots(in: translated) == slots(in: english), "\(key)")
            #expect(slots(in: english) == Set(0..<slots(in: english).count), "\(key) は 1 から連番にする")
            checked += 1
        }
        #expect(checked >= 4)
    }

    private func slots(in template: String) -> Set<Int> {
        Set(SentenceTemplate.parse(template).compactMap {
            if case .slot(let index) = $0 { index } else { nil }
        })
    }

    /// Text("…") や .help("…") などに直接書いた文言に日本語訳があること。
    /// 訳が無いと日本語の画面に英語がそのまま出るので、ここで検出する
    @Test func everyLiteralUIStringHasJapaneseTranslation() throws {
        let callSites = [
            #"(?<![A-Za-z])Text\("((?:[^"\\]|\\.)*)"\)"#,
            #"\.help\("((?:[^"\\]|\\.)*)""#,
            #"(?<![A-Za-z])Button\("((?:[^"\\]|\\.)*)""#,
            #"(?<![A-Za-z])Label\("((?:[^"\\]|\\.)*)", systemImage"#,
            #"Picker\("((?:[^"\\]|\\.)*)""#,
            #"(?:title|help|label): "((?:[^"\\]|\\.)*)""#,
            #"LocalizedStringKey\("((?:[^"\\]|\\.)*)"\)"#,
            #"case \([a-z]+, [a-z]+\): "((?:[^"\\]|\\.)*)""#,
        ]
        let japanese = try japaneseStrings()
        var missing: [String] = []
        for pattern in callSites {
            for match in try matches(of: pattern, excluding: ["Snapshot.swift"]) {
                let literal = match.groups[0]
                guard isTranslatable(literal) else { continue }
                if !candidateKeys(for: literal).contains(where: { japanese[$0] != nil }) {
                    missing.append("\(match.file): \(literal)")
                }
            }
        }
        #expect(missing.isEmpty, "missing ja: \(Set(missing).sorted())")
    }

    /// 記号・数字・補間だけの文言は訳さない
    private func isTranslatable(_ literal: String) -> Bool {
        let withoutInterpolation = literal.replacingOccurrences(of: #"\\\([^)]*\)+"#, with: "", options: .regularExpression)
        return withoutInterpolation.rangeOfCharacter(from: .letters) != nil
    }

    /// \(…) を、補間する値の型に合わせて %lld か %@ に置き換えたキー（LocalizedStringKey の補間と同じ規則）。
    /// 型を取り違えた訳（"Today %@ min" など）は実行時に見つからないので、両方を許さず 1 つに決める
    private func candidateKeys(for literal: String) -> [String] {
        let parts = literal.components(separatedBy: #"\("#)
        guard parts.count > 1 else { return [literal] }
        var key = parts[0]
        for part in parts.dropFirst() {
            // 補間の閉じ括弧の位置を、括弧の対応で探す
            var depth = 1
            var end = part.startIndex
            for index in part.indices {
                if part[index] == "(" { depth += 1 }
                if part[index] == ")" { depth -= 1 }
                if depth == 0 { end = index; break }
            }
            let expression = String(part[..<end])
            key += specifier(for: expression) + String(part[part.index(after: end)...])
        }
        return [key]
    }

    /// 補間している式から型を判断する。このアプリで補間しているのは整数か文字列だけ
    private func specifier(for expression: String) -> String {
        let integerNames: Set = ["streak", "minutes", "value", "index"]
        let isInteger = expression.hasPrefix("Int(") || expression.hasSuffix("+ 1")
            || expression.hasSuffix(".beats") || integerNames.contains(expression)
        return isInteger ? "%lld" : "%@"
    }
}
