import Foundation

/// UserDefaults のキー。フィールドの追加は codable(forKey:default:) と各型の decodeIfPresent が吸収するが、
/// 既存フィールドの型や意味を変えるときはキー名も変えて旧データと衝突させないこと
enum SettingsKeys {
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
    static let selectedSong = "pulstick.selectedSong"
}

/// 起動時に読む保存済みの設定。読み込みと検証（範囲外・壊れた値の補正）だけを行う。
/// エンジンはこの値を初期値として使うので、復元で didSet（保存し直し・反映）が走らない
struct StoredSettings {
    var bpm: Double = 120
    var beatsPerMeasure = 4
    var accentBeats: Set<Int> = [0]
    var restBeats: Set<Int> = []
    var subdivision: Subdivision = .quarter
    var accentVolume = 1.0
    var normalVolume = 0.7
    var clickSound: ClickSound = .beep
    var speedTrainer = SpeedTrainer()
    var speedTrainerEnabled = false
    var gapTrainer = GapTrainer()
    var gapTrainerEnabled = false
    var practiceLog = PracticeLog()
    var presets = BeatPreset.defaults
    var songs: [Song] = []
    /// 保存されていた選択。曲が残っているときだけ値を持つ
    var selectedSongID: UUID?

    init() {}

    init(reading store: SettingsStore) {
        if let saved = store.object(forKey: SettingsKeys.bpm) as? Double, saved.isFinite {
            bpm = saved.clamped(to: PulstickEngine.bpmRange)
        }
        if let saved = store.object(forKey: SettingsKeys.beats) as? Int {
            beatsPerMeasure = saved.clamped(to: PulstickEngine.beatsRange)
        }
        // 拍数を先に決めてから、その範囲にあるアクセントと休符だけを残す
        let beatRange = 0..<beatsPerMeasure
        if let saved = store.object(forKey: SettingsKeys.accents) as? [Int] {
            accentBeats = Set(saved.filter(beatRange.contains))
        }
        if let saved = store.object(forKey: SettingsKeys.rests) as? [Int] {
            restBeats = Set(saved.filter(beatRange.contains))
        }
        if let raw = store.object(forKey: SettingsKeys.subdivision) as? Int, let saved = Subdivision(rawValue: raw) {
            subdivision = saved
        }
        if let saved = store.object(forKey: SettingsKeys.accentVolume) as? Double {
            accentVolume = saved.clamped(to: 0...1)
        }
        if let saved = store.object(forKey: SettingsKeys.normalVolume) as? Double {
            normalVolume = saved.clamped(to: 0...1)
        }
        if let raw = store.object(forKey: SettingsKeys.clickSound) as? String, let saved = ClickSound(rawValue: raw) {
            clickSound = saved
        }
        speedTrainer = store.codable(forKey: SettingsKeys.speedTrainer, default: speedTrainer)
        speedTrainerEnabled = store.object(forKey: SettingsKeys.speedTrainerEnabled) as? Bool ?? false
        gapTrainer = store.codable(forKey: SettingsKeys.gapTrainer, default: gapTrainer)
        gapTrainerEnabled = store.object(forKey: SettingsKeys.gapTrainerEnabled) as? Bool ?? false
        practiceLog = store.codable(forKey: SettingsKeys.practiceLog, default: practiceLog)
        if let saved = store.codable([BeatPreset].self, forKey: SettingsKeys.presets),
           saved.count == BeatPreset.defaults.count
        {
            presets = saved
        }
        songs = store.codable([Song].self, forKey: SettingsKeys.songs) ?? []
        if let saved = (store.object(forKey: SettingsKeys.selectedSong) as? String).flatMap(UUID.init(uuidString:)),
           songs.contains(where: { $0.id == saved })
        {
            selectedSongID = saved
        }
    }
}
