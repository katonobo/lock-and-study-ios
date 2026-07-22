import Foundation

struct VocabularyReportProvider: StudyExperienceReportProviding {
  let supportedExperienceID = StudyExperienceID.vocabulary

  func makeReportSection(
    snapshot: LearningReportDataSnapshot,
    manifest: StudyPackManifest,
    period: LearningReportPeriod,
    now: Date,
    calendar: Calendar
  ) throws -> StudyMaterialReportSection {
    let allAnswers = snapshot.answers.filter {
      $0.packID == manifest.id && $0.experienceID == .vocabulary
    }
    let answers = allAnswers.filter { period.contains($0.answeredAt) }
    let newItems = Set(answers.filter { snapshot.effectiveLearningRole(for: $0) == .newItem }.map(\.itemID))
    let reviewedItems = Set(answers.filter { snapshot.effectiveLearningRole(for: $0) != .newItem }.map(\.itemID))
    let hasFullAccess = ContentAccessService().decision(
      isFreeSample: false,
      manifest: manifest,
      entitlement: snapshot.entitlement
    ).isAllowed
    let availableCount = hasFullAccess
      ? manifest.expectedItemCount : manifest.sampleDefinition.count
    let scopedProgress = snapshot.progress.values.filter { $0.id.packID == manifest.id }
    let learned = scopedProgress.filter { $0.answerCount > 0 }.count
    let due = scopedProgress.filter { $0.dueAt.map { $0 <= now } ?? false }.count
    let weak = scopedProgress.filter { $0.incorrectCount > 0 && $0.consecutiveCorrect == 0 }.count
    let metrics = [
      metric("vocabulary.answers", "回答", answers.count, "問", "checklist"),
      LearningReportMetric(
        id: "vocabulary.accuracy", label: "正答率", value: "\(accuracy(answers))%",
        systemImage: "target"),
      metric("vocabulary.unique", "回答した単語", Set(answers.map(\.itemID)).count, "語", "character.book.closed"),
      metric("vocabulary.new", "新しく学んだ", newItems.count, "語", "sparkles"),
      metric("vocabulary.review", "復習した", reviewedItems.count, "語", "arrow.clockwise"),
      metric("vocabulary.unlock", "解除学習", answers.filter { $0.mode == .unlock }.count, "問", "lock.open"),
      metric("vocabulary.practice", "通常学習", answers.filter { $0.mode != .unlock }.count, "問", "book"),
    ]
    let currentMetrics = [
      metric("vocabulary.learned", "学習済み", learned, "語", "checkmark.seal"),
      metric("vocabulary.due", "期限到来", due, "語", "calendar.badge.clock"),
      metric("vocabulary.weak", "学び直し対象", weak, "語", "arrow.counterclockwise"),
    ]
    let progressRows = VocabularyLevel.allCases.map { level in
      let learnedCount = Set(
        allAnswers.filter { $0.category == level.rawValue }.map(\.itemID)
      ).count
      return LearningReportProgressRow(
        id: level.rawValue,
        label: level.title,
        completed: learnedCount,
        available: availableCount / max(1, VocabularyLevel.allCases.count))
    }
    return .init(
      packID: manifest.id,
      title: manifest.title,
      subtitle: "今週の成果",
      systemImage: "character.book.closed.fill",
      metrics: metrics,
      currentMetrics: currentMetrics,
      progressRows: progressRows,
      categoryRows: [],
      subcategoryRows: [],
      weakAreas: [],
      recommendation: due > 0
        ? "期限の来た復習を先に済ませると、短い時間でも定着につながります。"
        : nil,
      footer: nil
    )
  }

  private func metric(
    _ id: String, _ label: String, _ count: Int, _ unit: String, _ image: String
  ) -> LearningReportMetric {
    .init(id: id, label: label, value: "\(count)\(unit)", systemImage: image)
  }

  private func accuracy(_ answers: [StudyAnswerRecord]) -> Int {
    answers.isEmpty
      ? 0 : Int((Double(answers.filter(\.isCorrect).count) / Double(answers.count) * 100).rounded())
  }
}
