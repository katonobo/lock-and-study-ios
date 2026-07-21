import Foundation

struct TakkenReportProvider: StudyExperienceReportProviding {
  let supportedExperienceID = StudyExperienceID.takken

  func makeReportSection(
    snapshot: LearningReportDataSnapshot,
    manifest: StudyPackManifest,
    period: LearningReportPeriod,
    now: Date,
    calendar: Calendar
  ) throws -> StudyMaterialReportSection {
    let allAnswers = snapshot.answers.filter {
      $0.packID == manifest.id && $0.experienceID == .takken
    }
    let answers = allAnswers.filter { period.contains($0.answeredAt) }
    let newItems = Set(answers.filter { snapshot.effectiveLearningRole(for: $0) == .newItem }.map(\.itemID))
    let reviewedItems = Set(answers.filter { snapshot.effectiveLearningRole(for: $0) != .newItem }.map(\.itemID))
    let categoryRows = groupedMetrics(answers: answers, key: { $0.category }, prefix: "category")
    let subcategoryRows = groupedMetrics(
      answers: answers, key: { $0.subcategory }, prefix: "subcategory")
    let weakAreas = Dictionary(grouping: allAnswers, by: \.category)
      .compactMap { title, values -> LearningReportWeakArea? in
        guard values.count >= 3 else { return nil }
        return .init(
          id: title, title: title, answerCount: values.count, accuracy: accuracy(values))
      }
      .sorted {
        if $0.accuracy == $1.accuracy { return $0.answerCount > $1.answerCount }
        return $0.accuracy < $1.accuracy
      }
      .prefix(3)
    let metrics = [
      metric("takken.answers", "回答", answers.count, "問", "checklist"),
      LearningReportMetric(
        id: "takken.accuracy", label: "正答率", value: "\(accuracy(answers))%",
        systemImage: "target"),
      metric("takken.unique", "解いた問題", Set(answers.map(\.itemID)).count, "問", "list.number"),
      metric("takken.new", "初めて解いた", newItems.count, "問", "sparkles"),
      metric("takken.review", "復習した", reviewedItems.count, "問", "arrow.clockwise"),
      metric("takken.unlock", "解除学習", answers.filter { $0.mode == .unlock }.count, "問", "lock.open"),
      metric("takken.practice", "通常学習", answers.filter { $0.mode != .unlock }.count, "問", "book"),
    ]
    let qualification = manifest.qualification
    let footer = [
      qualification?.examYear.map { "教材年度 \($0)年度" },
      qualification?.lawBasisDate.map { "法令基準日 \($0)" },
    ].compactMap { $0 }.joined(separator: "・")
    return .init(
      packID: manifest.id,
      title: manifest.title,
      subtitle: "今週の成果",
      systemImage: "building.columns.fill",
      metrics: metrics,
      currentMetrics: [],
      progressRows: [],
      categoryRows: categoryRows,
      subcategoryRows: subcategoryRows,
      weakAreas: Array(weakAreas),
      recommendation: weakAreas.first.map {
        "今週は「\($0.title)」を少量ずつ復習するのがおすすめです。"
      },
      footer: footer.isEmpty ? nil : footer
    )
  }

  private func groupedMetrics(
    answers: [StudyAnswerRecord],
    key: (StudyAnswerRecord) -> String?,
    prefix: String
  ) -> [LearningReportMetric] {
    Dictionary(grouping: answers, by: { key($0) ?? "未分類" })
      .map { title, values in
        LearningReportMetric(
          id: "takken.\(prefix).\(title)", label: title,
          value: "\(values.count)問・\(accuracy(values))%", systemImage: "chart.bar")
      }
      .sorted { $0.label < $1.label }
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
