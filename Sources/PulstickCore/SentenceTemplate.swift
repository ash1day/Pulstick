import Foundation

/// "%2$@ 小節ごとに %1$@ BPM" のような位置指定つきテンプレートを、文字列部分と差し込み位置に分ける。
/// 言語によって語順が違う文の途中に、ステッパーなどのビューを差し込むために使う
public enum SentenceTemplate {
    public enum Part: Equatable {
        case text(String)
        /// 0 始まりの差し込み位置
        case slot(Int)
    }

    public static func parse(_ template: String) -> [Part] {
        var parts: [Part] = []
        var rest = Substring(template)
        // Swift 5 モードでは /…/ リテラルが使えないため文字列から組み立てる
        let placeholder = try! Regex(#"%(\d+)\$@"#, as: (Substring, Substring).self)
        while let match = rest.firstMatch(of: placeholder) {
            appendText(rest[..<match.range.lowerBound], to: &parts)
            parts.append(.slot(Int(match.output.1)! - 1))
            rest = rest[match.range.upperBound...]
        }
        appendText(rest, to: &parts)
        return parts
    }

    /// 差し込み位置の前後の空白は HStack の間隔で表すので取り除く
    private static func appendText(_ text: Substring, to parts: inout [Part]) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(.text(trimmed))
        }
    }
}
