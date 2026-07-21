import SwiftUI

struct LearningReportSampleView: View {
  private let report = LearningReport.sample

  var body: some View {
    ScrollView {
      LearningReportBody(report: report, shareText: nil, sampleBadge: true)
        .frame(maxWidth: 780)
        .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("学習レポートの例")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("report.sample.screen")
  }
}

private extension LearningReport {
  static let sample: LearningReport = {
    let start = Date(timeIntervalSince1970: 1_774_915_200)
    let points = [7, 0, 15, 9, 0, 13, 12].enumerated().map { offset, count in
      DailyLearningReportPoint(
        day: Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: start) ?? start,
        answerCount: count,
        correctCount: Int(Double(count) * 0.84))
    }
    let section = StudyMaterialReportSection(
      packID: "english3000.v1",
      title: "英単語3,000語",
      subtitle: "今週の成果",
      systemImage: "character.book.closed.fill",
      metrics: [
        .init(id: "sample.new", label: "新しく学んだ", value: "22語", systemImage: "sparkles"),
        .init(id: "sample.review", label: "復習した", value: "18語", systemImage: "arrow.clockwise"),
        .init(id: "sample.unlock", label: "解除学習", value: "40問", systemImage: "lock.open"),
      ],
      currentMetrics: [
        .init(id: "sample.learned", label: "学習済み", value: "147語", systemImage: "checkmark.seal"),
        .init(id: "sample.due", label: "期限到来", value: "12語", systemImage: "calendar.badge.clock"),
      ],
      progressRows: [
        .init(id: "sample.level0", label: "中学基礎", completed: 96, available: 600),
      ],
      categoryRows: [], subcategoryRows: [], weakAreas: [],
      recommendation: nil, footer: nil)
    return .init(
      period: .init(
        startInclusive: start,
        endExclusive: Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: start)
          ?? start.addingTimeInterval(604_800)),
      scope: .pack("english3000.v1"),
      headline: "今週、8回の「使う前」が学習に変わりました",
      learningOpportunityCount: 8,
      learningStartedCount: 8,
      earnedUnlockCount: 7,
      shieldEarnedUnlockCount: 7,
      answerCount: 56,
      correctCount: 47,
      uniqueItemCount: 40,
      studyDayCount: 4,
      streak: 4,
      dailyPoints: points,
      materialSections: [section],
      recommendation: "今のペースを維持し、期限の来た復習を優先しましょう。")
  }()
}
