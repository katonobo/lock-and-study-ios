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
    let conceptID: (StudyAnswerRecord) -> String = { $0.conceptID ?? $0.itemID.rawValue }
    let sessionConcepts = Dictionary(grouping: answers, by: {
      "\($0.sessionID.uuidString)::\(conceptID($0))"
    })
    let newSessionConcepts = Set(sessionConcepts.compactMap { key, values -> String? in
      guard let first = values.sorted(by: answerOrder).first else { return nil }
      let learnedBeforeSession = allAnswers.contains { candidate in
        candidate.sessionID != first.sessionID
          && conceptID(candidate) == conceptID(first)
          && candidate.answeredAt < first.answeredAt
      }
      return learnedBeforeSession ? nil : key
    })
    let reviewedSessionConcepts = Set(sessionConcepts.keys).subtracting(newSessionConcepts)
    let firstAttempts = initialAttempts(answers)
    let concepts = Dictionary(grouping: answers, by: conceptID)
    let understoodConcepts = concepts.values.filter { values in
      values.sorted(by: answerOrder).last?.isCorrect == true
    }.count
    let relearnedConcepts = Set(Dictionary(grouping: answers, by: {
      "\($0.sessionID.uuidString)::\(conceptID($0))"
    }).compactMap { _, values -> String? in
      let sorted = values.sorted(by: answerOrder)
      guard let firstWrong = sorted.firstIndex(where: { !$0.isCorrect }),
        sorted.dropFirst(firstWrong + 1).contains(where: \.isCorrect)
      else { return nil }
      return sorted[firstWrong].conceptID ?? sorted[firstWrong].itemID.rawValue
    })
    let categoryRows = groupedMetrics(answers: answers, key: { $0.category }, prefix: "category")
    let subcategoryRows = groupedMetrics(
      answers: answers, key: { $0.subcategory }, prefix: "subcategory")
    let weakAreas = Dictionary(grouping: firstAttempts, by: \.category)
      .compactMap { title, values -> LearningReportWeakArea? in
        let uniqueConcepts = Set(values.map(conceptID))
        let valueAccuracy = accuracy(values)
        guard uniqueConcepts.count >= 3, valueAccuracy < 70 else { return nil }
        return .init(
          id: title, title: title, answerCount: values.count, accuracy: valueAccuracy)
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
      metric("takken.concepts", "学んだ論点", concepts.count, "論点", "square.stack.3d.up"),
      LearningReportMetric(
        id: "takken.initialAccuracy", label: "初回正答率",
        value: "\(accuracy(firstAttempts))%", systemImage: "scope"),
      metric("takken.understood", "最終理解", understoodConcepts, "論点", "checkmark.seal"),
      metric("takken.relearned", "学び直し完了", relearnedConcepts.count, "論点", "arrow.triangle.2.circlepath"),
      metric("takken.new", "新規論点", newSessionConcepts.count, "論点", "sparkles"),
      metric("takken.review", "復習論点", reviewedSessionConcepts.count, "論点", "arrow.clockwise"),
      metric("takken.unlock", "解除学習", answers.filter { $0.mode == .unlock }.count, "問", "lock.open"),
      metric("takken.practice", "通常学習", answers.filter { $0.mode != .unlock }.count, "問", "book"),
    ]
    let formatMetrics = TakkenQuestionFormat.allCases.compactMap { format -> LearningReportMetric? in
      let values = firstAttempts.filter { $0.questionFormat == format.rawValue }
      guard !values.isEmpty else { return nil }
      return LearningReportMetric(
        id: "takken.format.\(format.rawValue)", label: "\(format.displayName)正答率",
        value: "\(values.count)問・\(accuracy(values))%", systemImage: "rectangle.3.group")
    }
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
      currentMetrics: formatMetrics,
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

  private func initialAttempts(_ answers: [StudyAnswerRecord]) -> [StudyAnswerRecord] {
    let explicit = answers.filter { $0.wasFirstAttempt == true || $0.attemptNumber == 1 }
    let explicitKeys = Set(explicit.map { "\($0.sessionID.uuidString)::\($0.itemID.rawValue)" })
    let legacy = Dictionary(grouping: answers.filter {
      $0.attemptNumber == nil
        && !explicitKeys.contains("\($0.sessionID.uuidString)::\($0.itemID.rawValue)")
    }, by: { "\($0.sessionID.uuidString)::\($0.itemID.rawValue)" })
      .values.compactMap { $0.sorted(by: answerOrder).first }
    return explicit + legacy
  }

  private func answerOrder(_ lhs: StudyAnswerRecord, _ rhs: StudyAnswerRecord) -> Bool {
    if lhs.answeredAt == rhs.answeredAt {
      return (lhs.attemptNumber ?? 1) < (rhs.attemptNumber ?? 1)
    }
    return lhs.answeredAt < rhs.answeredAt
  }
}
