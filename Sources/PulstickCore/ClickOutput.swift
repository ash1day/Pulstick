import AVFoundation

/// クリック音の出力先。エンジンのロジックを音を鳴らさずにテストできるよう分離している
public protocol ClickOutput: AnyObject {
    /// 再生開始前に呼ばれる。出力デバイスの準備が必要ならここで行う
    func prepare()
    /// タイマーキュー上から呼ばれる
    func play(_ click: ClickKind)
    func stopAll()
    func setVolumes(accent: Double, normal: Double)
}

/// 何も鳴らさず、鳴らしたはずのクリックを記録するだけの出力。テストやスナップショット用
public final class SilentClickOutput: ClickOutput {
    private let lock = NSLock()
    private var _played: [ClickKind] = []

    public init() {}

    public var played: [ClickKind] {
        lock.withLock { _played }
    }

    public func prepare() {}
    public func play(_ click: ClickKind) {
        lock.withLock { _played.append(click) }
    }
    public func stopAll() {}
    public func setVolumes(accent: Double, normal: Double) {}
}

/// AVAudioEngine でクリック音をプログラム生成して鳴らす本番用の出力
public final class AudioClickOutput: ClickOutput {
    private let audioEngine = AVAudioEngine()
    private let accentPlayerNode = AVAudioPlayerNode()
    private let normalPlayerNode = AVAudioPlayerNode()
    /// 細分音は拍の音と重なっても途切れないよう専用ノードで鳴らす
    private let subdivisionPlayerNode = AVAudioPlayerNode()
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var subdivisionBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 44100
    private let accentFrequency: Double = 1500
    private let normalFrequency: Double = 800
    private let subdivisionFrequency: Double = 2400
    /// 細分音は拍を邪魔しないよう弱拍の音量に対してさらに控えめにする
    private let subdivisionVolumeRatio: Float = 0.45
    private let clickDuration: Double = 0.03  // 30ms のシャープなクリック

    public init() {
        audioEngine.attach(accentPlayerNode)
        audioEngine.attach(normalPlayerNode)
        audioEngine.attach(subdivisionPlayerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioEngine.connect(accentPlayerNode, to: audioEngine.mainMixerNode, format: format)
        audioEngine.connect(normalPlayerNode, to: audioEngine.mainMixerNode, format: format)
        audioEngine.connect(subdivisionPlayerNode, to: audioEngine.mainMixerNode, format: format)

        accentBuffer = generateClickBuffer(format: format, frequency: accentFrequency)
        normalBuffer = generateClickBuffer(format: format, frequency: normalFrequency)
        subdivisionBuffer = generateClickBuffer(format: format, frequency: subdivisionFrequency)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    deinit {
        stopAll()
        audioEngine.stop()
    }

    public func prepare() {
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    public func play(_ click: ClickKind) {
        let node: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer?
        switch click {
        case .accent: (node, buffer) = (accentPlayerNode, accentBuffer)
        case .normal: (node, buffer) = (normalPlayerNode, normalBuffer)
        case .subdivision: (node, buffer) = (subdivisionPlayerNode, subdivisionBuffer)
        }
        guard let buffer else { return }
        node.stop()
        node.play()
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    public func stopAll() {
        accentPlayerNode.stop()
        normalPlayerNode.stop()
        subdivisionPlayerNode.stop()
    }

    public func setVolumes(accent: Double, normal: Double) {
        accentPlayerNode.volume = Float(accent)
        normalPlayerNode.volume = Float(normal)
        subdivisionPlayerNode.volume = Float(normal) * subdivisionVolumeRatio
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
}
