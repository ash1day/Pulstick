import AVFoundation
import Combine

final class PulstickEngine: ObservableObject {
    @Published var bpm: Double = 120
    @Published var isPlaying: Bool = false

    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var clickBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    private let sampleRate: Double = 44100
    private let clickFrequency: Double = 1000
    private let clickDuration: Double = 0.05

    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        clickBuffer = generateClickBuffer(format: format)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func generateClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * clickDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let sine = sin(2.0 * .pi * clickFrequency * t)
            // Apply envelope to avoid clicks
            let envelope: Double
            let attackFrames = Int(sampleRate * 0.005)
            let releaseStart = Int(frameCount) - Int(sampleRate * 0.01)
            if i < attackFrames {
                envelope = Double(i) / Double(attackFrames)
            } else if i > releaseStart {
                envelope = Double(Int(frameCount) - i) / Double(Int(frameCount) - releaseStart)
            } else {
                envelope = 1.0
            }
            floatData[i] = Float(sine * envelope * 0.8)
        }

        return buffer
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true

        if !playerNode.engine!.isRunning {
            try? audioEngine.start()
        }

        playClick()
        scheduleTimer()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        playerNode.stop()
    }

    func incrementBPM() {
        bpm = min(bpm + 1, 240)
        restartTimerIfPlaying()
    }

    func decrementBPM() {
        bpm = max(bpm - 1, 40)
        restartTimerIfPlaying()
    }

    func bpmChanged() {
        bpm = bpm.clamped(to: 40...240)
        restartTimerIfPlaying()
    }

    private func restartTimerIfPlaying() {
        guard isPlaying else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = 60.0 / bpm
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.playClick()
        }
        timer?.tolerance = 0.005
    }

    private func playClick() {
        guard let buffer = clickBuffer else { return }
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
