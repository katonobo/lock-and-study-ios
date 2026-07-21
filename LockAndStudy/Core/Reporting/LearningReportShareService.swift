import Foundation

struct LearningReportShareService: Sendable {
  func text(for report: LearningReport, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d"
    let endDay =
      calendar.date(byAdding: .day, value: -1, to: report.period.endExclusive)
      ?? report.period.endExclusive
    var lines = [
      "ロックンスタディ 今週の学習レポート",
      "\(formatter.string(from: report.period.startInclusive))〜\(formatter.string(from: endDay))",
      "",
      report.headline + "。",
      "学習日数 \(report.studyDayCount)日",
      "回答 \(report.answerCount)問",
      "正答率 \(report.accuracy)%",
    ]
    for section in report.materialSections {
      let summary = section.metrics.prefix(3).map { "\($0.label)\($0.value)" }.joined(
        separator: "・")
      if !summary.isEmpty { lines.append("\(section.title)：\(summary)") }
    }
    lines.append(contentsOf: ["", "次週も、短い学習を続けます。"])
    let value = lines.joined(separator: "\n")
    guard LearningReportPrivacyPolicy.validateShareText(value) else {
      return "ロックンスタディで学習を続けています。"
    }
    return value
  }
}
