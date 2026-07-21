import Foundation

struct LearningReportPeriod: Equatable, Sendable {
  let startInclusive: Date
  let endExclusive: Date

  func contains(_ date: Date) -> Bool {
    date >= startInclusive && date < endExclusive
  }

  static func currentSevenDays(now: Date, calendar: Calendar) -> LearningReportPeriod {
    let today = calendar.startOfDay(for: now)
    let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
    let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
    return .init(startInclusive: start, endExclusive: end)
  }
}
