import AVFoundation
import Combine

enum TimeSignature: String, CaseIterable, Identifiable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case sixEight = "6/8"

    var id: String { rawValue }

    var beatsPerMeasure: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .sixEight: return 6
        }
    }
}

final class PulstickEngine: ObservableObject {
    @Published var bpm: Double = 120
    @Published var isPlaying: Bool = false
    @Published var timeSignature: TimeSignature = .fourFour
    @Published var currentBeat: Int = 0

    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    private let sampleRate: Double = 44100
    private let accentFrequency: Double = 1500
    private let normalFrequency: Double = 800
    private let clickDuration: Double = 0.03

    // Tap tempo
    private var tapTimes: [Date] = []
    private let maxTapCount = 4
    private let tapTimeout: TimeInterval = 2.0

    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        audioEngine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        accentBuffer = generateClickBuffer(format: format, frequency: accentFrequency)
        normalBuffer = generateClickBuffer(format: format, frequency: normalFrequency)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

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
        currentBeat = 0

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
        currentBeat = 0
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

    func tapTempo() {
        let now = Date()

        // Reset if too much time has passed since last tap
        if let lastTap = tapTimes.last, now.timeIntervalSince(lastTap) > tapTimeout {
            tapTimes.removeAll()
        }

        tapTimes.append(now)

        // Keep only the most recent taps
        if tapTimes.count > maxTapCount {
            tapTimes.removeFirst(tapTimes.count - maxTapCount)
        }

        // Need at least 2 taps to calculate BPM
        guard tapTimes.count >= 2 else { return }

        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i - 1])
        }
        let averageInterval = totalInterval / Double(tapTimes.count - 1)
        let newBPM = 60.0 / averageInterval

        bpm = newBPM.clamped(to: 40...240)
        restartTimerIfPlaying()
    }

    func setTimeSignature(_ sig: TimeSignature) {
        timeSignature = sig
        if isPlaying {
            currentBeat = 0
        }
    }

    private func restartTimerIfPlaying() {
        guard isPlaying else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = 60.0 / bpm
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceBeat()
            self?.playClick()
        }
        timer?.tolerance = 0.005
    }

    private func advanceBeat() {
        currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure
    }

    private func playClick() {
        let isAccent = currentBeat == 0
        guard let buffer = isAccent ? accentBuffer : normalBuffer else { return }
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
