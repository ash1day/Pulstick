import AVFoundation

/// クリック音の出力先。エンジンのロジックを音を鳴らさずにテストできるよう分離している
public protocol ClickOutput: AnyObject {
    /// 再生開始前に呼ばれる。出力デバイスの準備が必要ならここで行う
    func prepare()
    /// タイマーキュー上から呼ばれる
    func play(_ click: ClickKind)
    func stopAll()
    func setVolumes(accent: Double, normal: Double)
    func setSound(_ sound: ClickSound)
}

/// 何も鳴らさず、鳴らしたはずのクリックを記録するだけの出力。テストやスナップショット用
public final class SilentClickOutput: ClickOutput {
    private let lock = NSLock()
    private var _played: [ClickKind] = []

    public init() {}

    public var played: [ClickKind] {
        lock.withLock { _played }
    }

    public var sound: ClickSound? {
        lock.withLock { _sound }
    }
    private var _sound: ClickSound?

    public func prepare() {}
    public func play(_ click: ClickKind) {
        lock.withLock { _played.append(click) }
    }
    public func stopAll() {}
    public func setVolumes(accent: Double, normal: Double) {}
    public func setSound(_ sound: ClickSound) {
        lock.withLock { _sound = sound }
    }
}

/// AVAudioEngine でクリック音をプログラム生成して鳴らす本番用の出力
public final class AudioClickOutput: ClickOutput {
    private let audioEngine = AVAudioEngine()
    private let accentPlayerNode = AVAudioPlayerNode()
    private let normalPlayerNode = AVAudioPlayerNode()
    /// 細分音は拍の音と重なっても途切れないよう専用ノードで鳴らす
    private let subdivisionPlayerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    /// 音色の切り替え（メインスレッド）と再生（タイマーキュー）が競合しないようロックで守る
    private let bufferLock = NSLock()
    private var buffers: [ClickKind: AVAudioPCMBuffer] = [:]

    /// 細分音は拍を邪魔しないよう弱拍の音量に対してさらに控えめにする
    private let subdivisionVolumeRatio: Float = 0.45
    private var configurationObserver: NSObjectProtocol?

    public init() {
        audioEngine.attach(accentPlayerNode)
        audioEngine.attach(normalPlayerNode)
        audioEngine.attach(subdivisionPlayerNode)
        audioEngine.connect(accentPlayerNode, to: audioEngine.mainMixerNode, format: format)
        audioEngine.connect(normalPlayerNode, to: audioEngine.mainMixerNode, format: format)
        audioEngine.connect(subdivisionPlayerNode, to: audioEngine.mainMixerNode, format: format)
        // 音色はエンジンが起動時に setSound で一度だけ設定する

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // 練習中にヘッドホンを抜き差しするなど出力先が変わると、AVAudioEngine は止まってしまう。
        // 放っておくと拍の表示は進むのに音だけ鳴らなくなるため、構成変更のたびに再始動する。
        // ノードの接続は保たれ、クリックごとに node.play() し直すので次の拍から音が戻る
        configurationObserver = NotificationCenter.default.addObserver(
            // 通知はどのスレッドからでも届くので、再始動はメインキューに寄せて start() 同士が重ならないようにする
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            self?.prepare()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        stopAll()
        audioEngine.stop()
    }

    public func prepare() {
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    public func play(_ click: ClickKind) {
        let node: AVAudioPlayerNode = switch click {
        case .accent: accentPlayerNode
        case .normal: normalPlayerNode
        case .subdivision: subdivisionPlayerNode
        }
        guard let buffer = bufferLock.withLock({ buffers[click] }) else { return }
        // 出力先の変更でエンジンが止まってから再始動するまでの間に node.play() を呼ぶと、
        // Objective-C の例外でアプリが落ちる。その間の拍は鳴らさずに見送る
        guard audioEngine.isRunning else { return }
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

    public func setSound(_ sound: ClickSound) {
        var generated: [ClickKind: AVAudioPCMBuffer] = [:]
        for kind in [ClickKind.accent, .normal, .subdivision] {
            generated[kind] = makeBuffer(ClickSynth.samples(sound, kind, sampleRate: format.sampleRate))
        }
        bufferLock.withLock { buffers = generated }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
