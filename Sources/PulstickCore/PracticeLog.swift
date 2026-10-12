import Foundation

/// 日ごとの練習時間（秒）を記録する。キーはその日の "yyyy-MM-dd"
public struct PracticeLog: Codable, Equatable {
    public private(set) var secondsByDay: [String: Double] = [:]

    public init() {}

    public mutating func record(from start: Date, to end: Date, calendar: Calendar = .current) {
        // 日付をまたいだ練習は、それぞれの日に分けて記録する
        var cursor = start
        while cursor < end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
            let segmentEnd = min(end, dayEnd)
            secondsByDay[Self.key(for: cursor, calendar: calendar), default: 0] += segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
        }
    }

    public func seconds(on day: Date, calendar: Calendar = .current) -> Double {
        secondsByDay[Self.key(for: day, calendar: calendar)] ?? 0
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 今日（今日まだ練習していなければ昨日）から遡って、練習した日が何日続いているか
    public func streak(endingAt today: Date, calendar: Calendar = .current) -> Int {
        var day = today
        if seconds(on: day, calendar: calendar) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while seconds(on: day, calendar: calendar) > 0 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
