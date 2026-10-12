import Foundation
import Combine

/// メトロノームのオーディオ再生とタイミング制御を担当するエンジン。
/// DispatchSourceTimer で正確なビート間隔を維持し、ClickOutput に音を鳴らさせる。
public final class PulstickEngine: ObservableObject {
    public static let bpmRange: ClosedRange<Double> = 30...300
    public static let beatsRange: ClosedRange<Int> = 1...16
    public static let countInRange: ClosedRange<Int> = 0...2

    /// batchPatternChange の入れ子の深さ。0 より大きい間は、拍のパターン変更の反映を後回しにする
    var patternBatchDepth = 0

    @Published public var presets: [BeatPreset] = []
    /// セットリストの順（追加した順、moveSong で並べ替え可能）
    @Published public internal(set) var songs: [Song] = [] {
        didSet {
            defaults.setCodable(songs, forKey: SettingsKeys.songs)
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
            guard bpm != oldValue else { return }
            defaults.set(bpm, forKey: SettingsKeys.bpm)
            retimeIfPlaying()
            updateTempoStepCountdown()  // 手で目標より上げたら、上がる予定はもうない
            // 曲の切り替えと一緒に変わったテンポを前の曲の記録にしないよう、一括変更中は後回しにする
            // （一括変更の終わりに patternDidChange が曲を切り替えてから記録する）
            if patternBatchDepth == 0 {
                followCurrentSongIfPlaying()
                if isPlaying { songPractice.notePlaying(bpm: bpm) }
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
            defaults.set(beatsPerMeasure, forKey: SettingsKeys.beats)
            patternDidChange()
        }
    }
    /// 拍ごとに変わる表示用の状態。このオブジェクト自体の変更通知とは分けてある
    public let beatClock = BeatClock()
    public var currentBeat: Int { beatClock.current }
    /// ユーザーが選択したアクセント拍の位置。タップで自由にon/off可能
    @Published public var accentBeats: Set<Int> = [0] {
        didSet {
            defaults.set(Array(accentBeats).sorted(), forKey: SettingsKeys.accents)
            patternDidChange()
        }
    }

    /// 休符にした拍。拍の表示は進むが音は鳴らさない
    @Published public var restBeats: Set<Int> = [] {
        didSet {
            defaults.set(Array(restBeats).sorted(), forKey: SettingsKeys.rests)
            patternDidChange()
        }
    }

    @Published public var subdivision: Subdivision = .quarter {
        didSet {
            guard subdivision != oldValue else { return }
            defaults.set(subdivision.rawValue, forKey: SettingsKeys.subdivision)
            patternDidChange()
            retimeIfPlaying()
        }
    }

    @Published public var speedTrainerEnabled = false {
        didSet {
            defaults.set(speedTrainerEnabled, forKey: SettingsKeys.speedTrainerEnabled)
            speedTrainerProgress.restart()
            updateTempoStepCountdown()
        }
    }
    @Published public var speedTrainer = SpeedTrainer() {
        didSet {
            defaults.setCodable(speedTrainer, forKey: SettingsKeys.speedTrainer)
            updateTempoStepCountdown()
        }
    }
    /// 設定と違い毎小節変わるので @Published にも保存対象にもしない
    var speedTrainerProgress = SpeedTrainerProgress()
    /// スピードトレーナーがテンポを変えたときに、新しい BPM で呼ばれる（VoiceOver の読み上げに使う）
    public var onTempoStep: ((Double) -> Void)?

    @Published public var gapTrainerEnabled = false {
        didSet {
            defaults.set(gapTrainerEnabled, forKey: SettingsKeys.gapTrainerEnabled)
            patternDidChange()
        }
    }
    @Published public var gapTrainer = GapTrainer() {
        didSet {
            defaults.setCodable(gapTrainer, forKey: SettingsKeys.gapTrainer)
            patternDidChange()
        }
    }

    @Published public internal(set) var practiceLog = PracticeLog() {
        didSet {
            defaults.setCodable(practiceLog, forKey: SettingsKeys.practiceLog)
        }
    }
    /// ユーザーが選んだ（呼び出した・保存した）曲。設定の一致から推測すると同じ設定の曲を区別できないため覚えておく
    @Published public internal(set) var selectedSongID: UUID? {
        didSet {
            // 起動し直してもリハーサルの続き（[ ] で次の曲）から再開できるよう保存する
            defaults.set(selectedSongID?.uuidString, forKey: SettingsKeys.selectedSong)
        }
    }

    /// 起動時に戻した選択が、終了時の設定と一致していなかったか。
    /// その場合は曲を選び直すまで、設定が完全に一致するときだけ「いまの曲」とみなす
    /// （次の起動での関係ない練習を、その曲の練習として数えないため）。[ ] の起点には使う
    var selectedSongIsTentative = false

    /// 曲ごとの練習時間のうち、この再生でまだ確定していない分
    var songPractice = SongPracticeTracker()
    /// 練習時間の計測に使う時計。テストでは差し替えて時間経過を再現する
    var now: () -> Date = Date.init
    /// これより短い再生は練習として記録しない（うっかり押しただけで記録が付かないように）
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

    /// 練習が始まったか。カウントインがあれば、それが終わるまでは false（練習として記録しない）
    var practiceHasBegun = false

    /// 再生開始時に鳴らす予備の小節数（0 ならすぐ始める）。楽器を構える間や録音の入りのため
    @Published public var countInBars = 0 {
        didSet {
            let clamped = countInBars.clamped(to: Self.countInRange)
            guard countInBars == clamped else {
                countInBars = clamped
                return
            }
            defaults.set(countInBars, forKey: SettingsKeys.countInBars)
        }
    }

    /// 音だけを止める。拍の表示や練習時間の記録は続く。誤操作で無音のまま起動しないよう保存しない
    @Published public var isMuted = false {
        didSet { patternDidChange() }
    }

    @Published public var clickSound: ClickSound = .beep {
        didSet {
            guard clickSound != oldValue else { return }
            defaults.set(clickSound.rawValue, forKey: SettingsKeys.clickSound)
            output.setSound(clickSound)
        }
    }

    /// スライダーのドラッグ中は値が細かく変わり続けるため、同じ値の書き込みは省く
    @Published public var accentVolume: Double = 1.0 {
        didSet {
            guard accentVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(accentVolume, forKey: SettingsKeys.accentVolume)
            syncCountInSounds()
        }
    }
    @Published public var normalVolume: Double = 0.7 {
        didSet {
            guard normalVolume != oldValue else { return }
            output.setVolumes(accent: accentVolume, normal: normalVolume)
            defaults.set(normalVolume, forKey: SettingsKeys.normalVolume)
            syncCountInSounds()
        }
    }

    let output: ClickOutput
    /// 直前に鳴らした時刻。タイマーキュー上でのみ読み書きする
    var lastFireTime: UInt64 = 0
    /// 再生開始からの小節番号と、無音小節の設定。タイマーキュー上でのみ読み書きする
    var measureIndex = 0
    var activeGap: GapTrainer?
    var activeMute = false
    var activeCountIn = TickPlan.CountInSounds()
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
        // 保存済みの値はプロパティの裏側に初期値として入れる。didSet が走らないので、
        // 復元のたびに保存し直したり、途中の状態をタイマーキューへ送ったりしない
        let stored = StoredSettings(reading: defaults)
        _bpm = Published(initialValue: stored.bpm)
        _beatsPerMeasure = Published(initialValue: stored.beatsPerMeasure)
        _accentBeats = Published(initialValue: stored.accentBeats)
        _restBeats = Published(initialValue: stored.restBeats)
        _subdivision = Published(initialValue: stored.subdivision)
        _accentVolume = Published(initialValue: stored.accentVolume)
        _normalVolume = Published(initialValue: stored.normalVolume)
        _clickSound = Published(initialValue: stored.clickSound)
        _speedTrainer = Published(initialValue: stored.speedTrainer)
        _speedTrainerEnabled = Published(initialValue: stored.speedTrainerEnabled)
        _gapTrainer = Published(initialValue: stored.gapTrainer)
        _gapTrainerEnabled = Published(initialValue: stored.gapTrainerEnabled)
        _practiceLog = Published(initialValue: stored.practiceLog)
        _presets = Published(initialValue: stored.presets)
        _songs = Published(initialValue: stored.songs)
        _selectedSongID = Published(initialValue: stored.selectedSongID)
        _countInBars = Published(initialValue: stored.countInBars)
        // 終了時の設定がその曲のままでなければ、仮の選択（[ ] の起点）として戻す
        if let selected = songs.first(where: { $0.id == selectedSongID }) {
            selectedSongIsTentative = !matchesCurrentSettings(selected)
        }
        syncSequencer()
        output.setVolumes(accent: accentVolume, normal: normalVolume)
        output.setSound(clickSound)
    }

    /// プレビューやスクリーンショット用に、曲の練習時間を見本の値にする
    public func seedSongPractice(_ seconds: Double, bestBPM: Double? = nil, forSongAt index: Int) {
        guard songs.indices.contains(index) else { return }
        songs[index].practiceSeconds = seconds
        songs[index].bestBPM = bestBPM
    }

    /// プレビューやスクリーンショット用に、見本の練習記録で置き換える
    public func seedPracticeLog(_ log: PracticeLog) {
        practiceLog = log
    }

    /// スクリーンショット用に、再生せずにスピードトレーナーの予告を出す
    public func seedTempoStepCountdown(_ bars: Int) {
        beatClock.barsUntilTempoStep = bars
    }

    func persistPresets() {
        defaults.setCodable(presets, forKey: SettingsKeys.presets)
    }

    deinit {
        timerSource?.cancel()
    }
}

