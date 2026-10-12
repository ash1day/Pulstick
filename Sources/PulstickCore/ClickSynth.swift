import Foundation

/// クリック音の種類
public enum ClickSound: String, CaseIterable, Codable, Sendable {
    /// サイン波の電子音。従来の音
    case beep
    /// ウッドブロック風。打楽器奏者に馴染みのある木の音
    case wood
    /// 機械式メトロノーム風の短いチック音。他の音に埋もれにくい
    case tick
}

/// クリック音の波形を生成する純粋な関数群。外部ファイル不要で、テストで波形の性質を検証できる
public enum ClickSynth {
    public static func samples(_ sound: ClickSound, _ kind: ClickKind, sampleRate: Double = 44100) -> [Float] {
        let raw: [Double]
        switch sound {
        case .beep: raw = beep(kind, sampleRate: sampleRate)
        case .wood: raw = wood(kind, sampleRate: sampleRate)
        case .tick: raw = tick(kind, sampleRate: sampleRate)
        }
        return fadeEdges(normalize(raw, peak: 0.8), sampleRate: sampleRate).map(Float.init)
    }

    /// サイン波にエンベロープ（attack 2ms → sustain → release 8ms）を掛ける。
    /// Release を Attack より長くしているのは、立ち下がりの方が耳につきやすいため
    private static func beep(_ kind: ClickKind, sampleRate: Double) -> [Double] {
        let frequency: Double = switch kind {
        case .accent: 1500
        case .normal: 800
        case .subdivision: 2400
        }
        let count = Int(sampleRate * 0.03)
        let attack = Int(sampleRate * 0.002)
        let releaseStart = count - Int(sampleRate * 0.008)
        return (0..<count).map { i in
            let envelope: Double
            if i < attack {
                envelope = Double(i) / Double(attack)
            } else if i > releaseStart {
                envelope = Double(count - i) / Double(count - releaseStart)
            } else {
                envelope = 1
            }
            return sin(2 * .pi * frequency * Double(i) / sampleRate) * envelope
        }
    }

    /// 基音と、木材特有の非整数倍音（約 2.7 倍）を指数減衰させて重ねる
    private static func wood(_ kind: ClickKind, sampleRate: Double) -> [Double] {
        let f0: Double = switch kind {
        case .accent: 1250
        case .normal: 950
        case .subdivision: 1600
        }
        let count = Int(sampleRate * 0.06)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let body = sin(2 * .pi * f0 * t) * exp(-t / 0.012)
            let overtone = 0.5 * sin(2 * .pi * f0 * 2.7 * t) * exp(-t / 0.005)
            return body + overtone
        }
    }

    /// 高域を強調したノイズを数 ms で減衰させ、音程感を出すため短いサイン波を少し混ぜる。
    /// ノイズは固定シードの LCG なので毎回同じ波形になる
    private static func tick(_ kind: ClickKind, sampleRate: Double) -> [Double] {
        let tone: Double = switch kind {
        case .accent: 3200
        case .normal: 2200
        case .subdivision: 4200
        }
        let count = Int(sampleRate * 0.02)
        var seed: UInt32 = 0x1234_5678
        var previousNoise = 0.0
        return (0..<count).map { i in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            // 1 次の差分で低域を削り、カチッとした硬さを出す
            let highPassed = noise - previousNoise
            previousNoise = noise
            let t = Double(i) / sampleRate
            return (0.6 * highPassed + 0.4 * sin(2 * .pi * tone * t)) * exp(-t / 0.003)
        }
    }

    private static func normalize(_ wave: [Double], peak: Double) -> [Double] {
        let maxAbs = wave.map(abs).max() ?? 0
        guard maxAbs > 0 else { return wave }
        return wave.map { $0 / maxAbs * peak }
    }

    /// 先頭 1ms と末尾 2ms を直線的に 0 へ寄せ、再生の開始・終了時のプチノイズを防ぐ
    private static func fadeEdges(_ wave: [Double], sampleRate: Double) -> [Double] {
        let fadeIn = max(1, Int(sampleRate * 0.001))
        let fadeOut = max(1, Int(sampleRate * 0.002))
        let count = wave.count
        return wave.enumerated().map { i, sample in
            var gain = 1.0
            if i < fadeIn { gain = min(gain, Double(i) / Double(fadeIn)) }
            if i >= count - fadeOut { gain = min(gain, Double(count - 1 - i) / Double(fadeOut)) }
            return sample * gain
        }
    }
}
