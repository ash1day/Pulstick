import AVFoundation
import Combine

public struct BeatPreset: Codable, Equatable {
    public var beats: Int
    public var accents: [Int]

    public var accentSet: Set<Int> { Set(accents) }

    public init(beats: Int, accents: [Int]) {
        self.beats = beats
        self.accents = accents
    }

    public static let defaults: [BeatPreset] = [
        BeatPreset(beats: 4, accents: [0]),
        BeatPreset(beats: 3, accents: [0]),
        BeatPreset(beats: 6, accents: [0, 3]),
        BeatPreset(beats: 9, accents: [0, 3, 6]),
    ]
}

/// メトロノームのオーディオ再生とタイミング制御を担当するエンジン。
/// AVAudioEngine でクリック音をプログラム生成し、DispatchSourceTimer で正確なビート間隔を維持する。
public final class PulstickEngine: ObservableObject {
    @Published public var presets: [BeatPreset] = []
    private let presetsKey = "pulstick.presets"

    @Published public var bpm: Double = 120 {
        // didSet 内で clamp して再代入すると didSet が再発火するため、
        // 値が変わった場合のみ return で抜けてループを防ぐ
        didSet {
            let clamped = bpm.clamped(to: 40...240)
            if bpm != clamped {
                bpm = clamped
                return
            }
            if bpm != oldValue {
                restartTimerIfPlaying()
            }
        }
    }
    @Published public var isPlaying: Bool = false
    @Published public var beatsPerMeasure: Int = 4
    @Published public var currentBeat: Int = 0
    /// ユーザーが選択したアクセント拍の位置。タップで自由にon/off可能
    @Published public var accentBeats: Set<Int> = [0]

    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var timerSource: DispatchSourceTimer?
    /// メインスレッドとは別のキューでタイマーを駆動する。
    /// メインスレッドは UI 描画で占有されるため、そこにタイマーを載せると
    /// 描画負荷に引きずられてビートが遅延する可能性がある。
    /// .userInteractive は OS に最高優先度の CPU 割り当てを要求し、
    /// 他アプリのバックグラウンド処理（Spotlight 等）よりタイマー発火を優先させる。
    private let timerQueue = DispatchQueue(label: "com.pulstick.metronome", qos: .userInteractive)

    private let sampleRate: Double = 44100
    private let accentFrequency: Double = 1500
    private let normalFrequency: Double = 800
    private let clickDuration: Double = 0.03  // 30ms のシャープなクリック

    private var tapTimes: [Date] = []
    private let maxTapCount = 4
    private let tapTimeout: TimeInterval = 2.0

    public init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        accentBuffer = generateClickBuffer(format: format, frequency: accentFrequency)
        normalBuffer = generateClickBuffer(format: format, frequency: normalFrequency)

        loadPresets()

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([BeatPreset].self, from: data),
           saved.count == BeatPreset.defaults.count
        {
            presets = saved
        } else {
            presets = BeatPreset.defaults
        }
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    public func applyPreset(at index: Int) {
        guard index < presets.count else { return }
        let preset = presets[index]
        beatsPerMeasure = preset.beats
        accentBeats = preset.accentSet
        currentBeat = 0
    }

    public func saveCurrentAsPreset(at index: Int) {
        guard index < presets.count else { return }
        presets[index] = BeatPreset(beats: beatsPerMeasure, accents: Array(accentBeats).sorted())
        persistPresets()
    }

    public func resetPreset(at index: Int) {
        guard index < BeatPreset.defaults.count else { return }
        presets[index] = BeatPreset.defaults[index]
        persistPresets()
    }

    /// サイン波にエンベロープ（attack 2ms → sustain → release 8ms）を掛けて
    /// クリック音のPCMバッファを生成する。外部ファイル不要。
    private func generateClickBuffer(format: AVAudioFormat, frequency: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * clickDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let sine = sin(2.0 * .pi * frequency * t)
            // サイン波をいきなり開始/終了すると波形が不連続になりプチノイズが鳴る。
            // Attack(2ms) で徐々に立ち上げ、Release(8ms) で徐々に減衰させることで滑らかにする。
            // Release を Attack より長くしているのは、立ち下がりの方が耳につきやすいため。
            let envelope: Double
            let attackFrames = Int(sampleRate * 0.002)
            let releaseStart = Int(frameCount) - Int(sampleRate * 0.008)
            if i < attackFrames {
                envelope = Double(i) / Double(attackFrames)
            } else if i > releaseStart {
                let remaining = Double(Int(frameCount) - i)
                let releaseLength = Double(Int(frameCount) - releaseStart)
                envelope = remaining / releaseLength
            } else {
                envelope = 1.0
            }
            floatData[i] = Float(sine * envelope * 0.8)
        }

        return buffer
    }

    public func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    public func start() {
        guard !isPlaying else { return }
        isPlaying = true
        currentBeat = 0

        if !playerNode.engine!.isRunning {
            try? audioEngine.start()
        }

        playClick(accent: accentBeats.contains(0))
        scheduleTimer()
    }

    public func stop() {
        isPlaying = false
        timerSource?.cancel()
        timerSource = nil
        playerNode.stop()
        currentBeat = 0
    }

    public func incrementBPM() {
        bpm = min(bpm + 1, 240)
    }

    public func decrementBPM() {
        bpm = max(bpm - 1, 40)
    }

    /// 直近の最大4回のタップ間隔の平均からBPMを算出する。
    /// 2秒以上間隔が空くとタップ履歴をリセット。
    public func tapTempo() {
        let now = Date()

        if let lastTap = tapTimes.last, now.timeIntervalSince(lastTap) > tapTimeout {
            tapTimes.removeAll()
        }

        tapTimes.append(now)

        if tapTimes.count > maxTapCount {
            tapTimes.removeFirst(tapTimes.count - maxTapCount)
        }

        guard tapTimes.count >= 2 else { return }

        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i - 1])
        }
        let averageInterval = totalInterval / Double(tapTimes.count - 1)

        bpm = 60.0 / averageInterval
    }

    public func setBeats(_ beats: Int) {
        beatsPerMeasure = max(1, min(beats, 16))
        accentBeats = [0]
        currentBeat = 0
    }

    public func addBeat() {
        guard beatsPerMeasure < 16 else { return }
        beatsPerMeasure += 1
        // 追加した拍はデフォルトで弱（accentBeats に追加しない）
    }

    public func removeBeat() {
        guard beatsPerMeasure > 1 else { return }
        let last = beatsPerMeasure - 1
        accentBeats.remove(last)
        beatsPerMeasure -= 1
        if currentBeat >= beatsPerMeasure {
            currentBeat = 0
        }
    }

    public func toggleAccent(_ beat: Int) {
        if accentBeats.contains(beat) {
            accentBeats.remove(beat)
        } else {
            accentBeats.insert(beat)
        }
    }

    private func restartTimerIfPlaying() {
        guard isPlaying else { return }
        timerSource?.cancel()
        scheduleTimer()
    }

    /// DispatchSourceTimer を高優先度キューで駆動する。
    /// タイマーコールバック内で次のビートとアクセントを先に確定し、
    /// 音を鳴らしてから UI 更新をメインスレッドに送ることで、
    /// 音とビート表示のズレを防ぐ。
    private func scheduleTimer() {
        let interval = 60.0 / bpm
        // .strict: macOS は省電力のために複数タイマーの発火をまとめる（timer coalescing）が、
        // メトロノームでは数ms のズレも体感できるため、まとめずに即発火させる。
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        // leeway は OS がタイマー発火を遅延させてよい許容幅。
        // デフォルトだと数十ms 遅れうるため、1ms に制限して精度を確保する。
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // 音の再生はタイマーキュー上で即実行する。
            // メインスレッドに送ると UI 処理の順番待ちで音が遅延するため。
            // 人間は視覚より聴覚のズレに敏感なので、音を優先し UI 更新だけ非同期で送る。
            let nextBeat = (self.currentBeat + 1) % self.beatsPerMeasure
            let isAccent = self.accentBeats.contains(nextBeat)
            self.playClick(accent: isAccent)
            DispatchQueue.main.async {
                self.currentBeat = nextBeat
            }
        }
        source.resume()
        timerSource = source
    }

    private func playClick(accent: Bool) {
        guard let buffer = accent ? accentBuffer : normalBuffer else { return }
        // 前回のバッファ再生が残っていると音が重なるため、一度停止してからスケジュールする。
        // stop() → play() を挟まないと scheduleBuffer が無視されるケースがある。
        playerNode.stop()
        playerNode.play()
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    deinit {
        stop()
        audioEngine.stop()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
