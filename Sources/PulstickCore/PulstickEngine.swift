import Foundation
import Combine

/// メトロノームのオーディオ再生とタイミング制御を担当するエンジン。
/// DispatchSourceTimer で正確なビート間隔を維持し、ClickOutput に音を鳴らさせる。
public final class PulstickEngine: ObservableObject {
    public static let bpmRange: ClosedRange<Double> = 30...300
    public static let beatsRange: ClosedRange<Int> = 1...16

    /// UserDefaults のキー。フィールドの追加は codable(forKey:default:) が吸収するが、
    /// 既存フィールドの型や意味を変えるときはキー名も変えて旧データと衝突させないこと
    private enum Keys {
        static let presets = "pulstick.presets"
        static let bpm = "pulstick.bpm"
        static let beats = "pulstick.beats"
        static let accents = "pulstick.accents"
        static let rests = "pulstick.rests"
        static let accentVolume = "pulstick.accentVolume"
        static let normalVolume = "pulstick.normalVolume"
        static let subdivision = "pulstick.subdivision"
        static let speedTrainerEnabled = "pulstick.speedTrainerEnabled"
        static let speedTrainer = "pulstick.speedTrainer"
        static let gapTrainerEnabled = "pulstick.gapTrainerEnabled"
        static let gapTrainer = "pulstick.gapTrainer"
        static let practiceLog = "pulstick.practiceLog"
        static let clickSound = "pulstick.clickSound"
        static let songs = "pulstick.songs"
    }

    /// batchPatternChange の入れ子の深さ。0 より大きい間は、拍のパターン変更の反映を後回しにする
    var patternBatchDepth = 0

    /// 起動時の復元中は didSet の副作用（保存・タイマーキューへの反映・音色生成）を止め、
    /// 復元後に一度だけまとめて反映する
    var isRestoring = false

    @Published public var presets: [BeatPreset] = []
    /// セットリストの順（追加した順、moveSong で並べ替え可能）
    @Published public internal(set) var songs: [Song] = [] {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(songs, forKey: Keys.songs)
        }
    }

    @Published public var bpm: Double = 120 {
        // didSet 内で clamp して再代入すると didSet が再発火するため、
        // 値が変わった場合のみ return で抜けてループを防ぐ
        didSet {
            // NaN は比較が常に不一致になり clamp の再代入が止まらなくなるため、非有限値は元に戻す
            guard bpm.isFinite else {
                bpm = oldValue
                return
            }
            let clamped = bpm.clamped(to: Self.bpmRange)
            if bpm != clamped {
                bpm = clamped
                return
            }
            guard !isRestoring, bpm != oldValue else { return }
            defaults.set(bpm, forKey: Keys.bpm)
            retimeIfPlaying()
            if patternBatchDepth == 0 {
                followCurrentSongIfPlaying()
            }
        }
    }
    @Published public var isPlaying: Bool = false
    /// 再生開始時刻。練習時間の表示に使う
    @Published public internal(set) var playStartedAt: Date?
    /// 再生開始時の BPM。スピードトレーナーで上がったテンポを元に戻すために使う
    @Published public internal(set) var sessionStartBPM: Double?
    @Published public var beatsPerMeasure: Int = 4 {
        didSet {
            guard !isRestoring else { return }
            defaults.set(beatsPerMeasure, forKey: Keys.beats)
            patternDidChange()
        }
    }
    /// 拍ごとに変わる表示用の状態。このオブジェクト自体の変更通知とは分けてある
    public let beatClock = BeatClock()
    public var currentBeat: Int { beatClock.current }
    /// ユーザーが選択したアクセント拍の位置。タップで自由にon/off可能
    @Published public var accentBeats: Set<Int> = [0] {
        didSet {
            guard !isRestoring else { return }
            defaults.set(Array(accentBeats).sorted(), forKey: Keys.accents)
            patternDidChange()
        }
    }

    /// 休符にした拍。拍の表示は進むが音は鳴らさない
    @Published public var restBeats: Set<Int> = [] {
        didSet {
            guard !isRestoring else { return }
            defaults.set(Array(restBeats).sorted(), forKey: Keys.rests)
            patternDidChange()
        }
    }

    @Published public var subdivision: Subdivision = .quarter {
        didSet {
            guard !isRestoring, subdivision != oldValue else { return }
            defaults.set(subdivision.rawValue, forKey: Keys.subdivision)
            patternDidChange()
            retimeIfPlaying()
        }
    }

    @Published public var speedTrainerEnabled = false {
        didSet {
            guard !isRestoring else { return }
            defaults.set(speedTrainerEnabled, forKey: Keys.speedTrainerEnabled)
            speedTrainerProgress.restart()
        }
    }
    @Published public var speedTrainer = SpeedTrainer() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(speedTrainer, forKey: Keys.speedTrainer)
        }
    }
    /// 設定と違い毎小節変わるので @Published にも保存対象にもしない
    var speedTrainerProgress = SpeedTrainerProgress()

    @Published public var gapTrainerEnabled = false {
        didSet {
            guard !isRestoring else { return }
            defaults.set(gapTrainerEnabled, forKey: Keys.gapTrainerEnabled)
            patternDidChange()
        }
    }
    @Published public var gapTrainer = GapTrainer() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(gapTrainer, forKey: Keys.gapTrainer)
            patternDidChange()
        }
    }

    @Published public internal(set) var practiceLog = PracticeLog() {
        didSet {
            guard !isRestoring else { return }
            defaults.setCodable(practiceLog, forKey: Keys.practiceLog)
        }
    }
    /// ユーザーが選んだ（呼び出した・保存した）曲。設定の一致から推測すると同じ設定の曲を区別できないため覚えておく
    @Published public internal(set) var selectedSongID: UUID?

    /// 曲ごとの練習時間のうち、この再生でまだ確定していない分
    var songPractice = SongPracticeTracker()
    /// 練習時間の計測に使う時計。テストでは差し替えて時間経過を再現する
    var now: () -> Date = Date.init
    /// これより短い再生は練習として記録しない（うっかり押しただけで連続日数が伸びないように）
    var minimumLoggedSession: TimeInterval = 5

    /// 練習タイマー。設定すると、再生開始からこの秒数で自動的に止まる。nil なら止まらない
    @Published public var stopAfter: TimeInterval? {
        didSet {
            // 再生中に選んだら「ここから N 分」。経過時間より短い値を選んでも即座には止めない
            if isPlaying { practiceTimerStartedAt = now() }
            schedulePracticeTimer()
        }
    }
    /// 練習タイマーを数え始めた時刻（再生開始時、または再生中にタイマーを選んだ時刻）
    @Published public internal(set) var practiceTimerStartedAt: Date?
    var practiceTimer: DispatchWorkItem?

    /// 音だけを止める。拍の表示や練習時間の記録は続く。誤操作で無音のまま起動しないよう保存しない
    @Published public var isMuted = false {
        didSet { patternDidChange() }
    }

    @Published public var clickSound: ClickSound = .beep {
        didSet {
            guard !isRestoring, clickSound != oldValue else { return }
            defaults.set(clickSound.rawValue, forKey: Keys.clickSound)
            output.setSound(clickSound)
        }
    }

    /// スライダーのドラッグ中は値が細かく変わり続けるため、同じ値の書き込みは省く
    @Published public var accentVolume: Double = 1.0 {
        didSet {
            guard !isRestoring, accentVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(accentVolume, forKey: Keys.accentVolume)
        }
    }
    @Published public var normalVolume: Double = 0.7 {
        didSet {
            guard !isRestoring, normalVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(normalVolume, forKey: Keys.normalVolume)
        }
    }

    let output: ClickOutput
    /// 直前に鳴らした時刻。タイマーキュー上でのみ読み書きする
    var lastFireTime: UInt64 = 0
    /// 再生開始からの小節番号と、無音小節の設定。タイマーキュー上でのみ読み書きする
    var measureIndex = 0
    var activeGap: GapTrainer?
    var activeMute = false
    /// 再生のたびに増える番号。停止直後に届いた前の再生の拍を、次の再生に反映しないために使う
    var playbackGeneration = 0
    /// タイマーキュー上でのみ読み書きする
    var sequencer = BeatSequencer(beatsPerMeasure: 4, accents: [0])
    var timerSource: DispatchSourceTimer?
    /// メインスレッドとは別のキューでタイマーを駆動する。
    /// メインスレッドは UI 描画で占有されるため、そこにタイマーを載せると
    /// 描画負荷に引きずられてビートが遅延する可能性がある。
    /// .userInteractive は OS に最高優先度の CPU 割り当てを要求し、
    /// 他アプリのバックグラウンド処理（Spotlight 等）よりタイマー発火を優先させる。
    let timerQueue = DispatchQueue(label: "com.pulstick.metronome", qos: .userInteractive)

    var tapTempoEstimator = TapTempo()

    let defaults: SettingsStore

    /// - Parameter output: 本番は AudioClickOutput、テストは SilentClickOutput。
    ///   テストで誤って音が鳴らないよう、あえてデフォルト値を持たせていない
    public init(defaults: SettingsStore = UserDefaults.standard, output: ClickOutput) {
        self.defaults = defaults
        self.output = output
        isRestoring = true
        loadPresets()
        restoreSettings()
        isRestoring = false
        syncSequencer()
        output.setVolumes(accent: accentVolume, normal: normalVolume)
        output.setSound(clickSound)
    }

    private func restoreSettings() {
        if let saved = defaults.object(forKey: Keys.bpm) as? Double {
            bpm = saved
        }
        if let saved = defaults.object(forKey: Keys.beats) as? Int {
            beatsPerMeasure = saved.clamped(to: Self.beatsRange)
        }
        if let saved = defaults.object(forKey: Keys.accents) as? [Int] {
            accentBeats = validBeatIndices(saved)
        }
        if let saved = defaults.object(forKey: Keys.rests) as? [Int] {
            restBeats = validBeatIndices(saved)
        }
        if let saved = defaults.object(forKey: Keys.accentVolume) as? Double {
            accentVolume = saved.clamped(to: 0...1)
        }
        if let saved = defaults.object(forKey: Keys.normalVolume) as? Double {
            normalVolume = saved.clamped(to: 0...1)
        }
        if let raw = defaults.object(forKey: Keys.subdivision) as? Int, let saved = Subdivision(rawValue: raw) {
            subdivision = saved
        }
        if let raw = defaults.object(forKey: Keys.clickSound) as? String, let saved = ClickSound(rawValue: raw) {
            clickSound = saved
        }
        speedTrainer = defaults.codable(forKey: Keys.speedTrainer, default: speedTrainer)
        speedTrainerEnabled = defaults.object(forKey: Keys.speedTrainerEnabled) as? Bool ?? false
        gapTrainer = defaults.codable(forKey: Keys.gapTrainer, default: gapTrainer)
        gapTrainerEnabled = defaults.object(forKey: Keys.gapTrainerEnabled) as? Bool ?? false
        practiceLog = defaults.codable(forKey: Keys.practiceLog, default: practiceLog)
        songs = defaults.codable([Song].self, forKey: Keys.songs) ?? []
    }

    /// プレビューやスクリーンショット用に、曲の練習時間を見本の値にする
    public func seedSongPractice(_ seconds: Double, forSongAt index: Int) {
        guard songs.indices.contains(index) else { return }
        songs[index].practiceSeconds = seconds
    }

    /// プレビューやスクリーンショット用に、見本の練習記録で置き換える
    public func seedPracticeLog(_ log: PracticeLog) {
        practiceLog = log
    }

    private func loadPresets() {
        if let saved = defaults.codable([BeatPreset].self, forKey: Keys.presets),
           saved.count == BeatPreset.defaults.count
        {
            presets = saved
        } else {
            presets = BeatPreset.defaults
        }
    }

    func persistPresets() {
        defaults.setCodable(presets, forKey: Keys.presets)
    }

    deinit {
        timerSource?.cancel()
    }
}

