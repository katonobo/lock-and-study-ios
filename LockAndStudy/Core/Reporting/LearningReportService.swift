import Foundation

struct LearningReportService: Sendable {
  let providers: [any StudyExperienceReportProviding]

  func makeReport(
    snapshot: LearningReportDataSnapshot,
    scope: LearningReportScope,
    now: Date,
    calendar: Calendar
  ) throws -> LearningReport {
    let period = LearningReportPeriod.currentSevenDays(now: now, calendar: calendar)
    let scopedAnswersIncludingFallback = snapshot.answers(for: scope)
    let allScopedAnswers = scopedAnswersIncludingFallback.filter { !$0.isSafeFallback }
    let answers = allScopedAnswers.filter { period.contains($0.answeredAt) }
    let fallbackAnswers = scopedAnswersIncludingFallback.filter {
      $0.isSafeFallback && period.contains($0.answeredAt)
    }
    let events = snapshot.events(for: scope).filter { period.contains($0.occurredAt) }

    let shieldStarts = uniqueSessionEvents(
      events.filter {
        $0.kind == .unlockChallengeStarted && $0.resolvedUnlockOrigin == .shield
      })
    let answeredSessionIDs = Set(answers.map(\.sessionID))
      .union(events.filter { $0.kind == .answerSubmitted }.compactMap(\.sessionID))
    let learningStarted = shieldStarts.filter {
      $0.sessionID.map(answeredSessionIDs.contains) ?? false
    }
    let unlocks = uniqueSessionEvents(events.filter { $0.kind == .unlockSuccess })
    let shieldUnlocks = unlocks.filter { $0.resolvedUnlockOrigin == .shield }
    let fallbackSessionIDs = Set(fallbackAnswers.map(\.sessionID))
    let fallbackUnlocks = unlocks.filter {
      $0.sessionID.map(fallbackSessionIDs.contains) ?? false
    }

    let today = calendar.startOfDay(for: now)
    let dailyPoints = (0..<7).compactMap { offset -> DailyLearningReportPoint? in
      guard let day = calendar.date(byAdding: .day, value: offset, to: period.startInclusive),
        let end = calendar.date(byAdding: .day, value: 1, to: day)
      else { return nil }
      let values = answers.filter { $0.answeredAt >= day && $0.answeredAt < end }
      return .init(day: day, answerCount: values.count, correctCount: values.filter(\.isCorrect).count)
    }
    let studyDays = Set(answers.map { calendar.startOfDay(for: $0.answeredAt) }).count
    let streak = streakCount(answers: allScopedAnswers, today: today, calendar: calendar)

    let selectedManifests: [StudyPackManifest]
    switch scope {
    case .allMaterials:
      selectedManifests = snapshot.manifests.filter { manifest in
        allScopedAnswers.contains { $0.packID == manifest.id }
          || snapshot.progress.values.contains {
            $0.id.packID == manifest.id && $0.answerCount > 0
              && !$0.isSafeFallbackArtifact
          }
      }
    case .pack(let packID):
      selectedManifests = snapshot.manifests.filter { $0.id == packID }
    }
    let sections = try selectedManifests.compactMap { manifest -> StudyMaterialReportSection? in
      guard let provider = providers.first(where: {
        $0.supportedExperienceID.rawValue == manifest.moduleType.rawValue
      }) else { return nil }
      return try provider.makeReportSection(
        snapshot: snapshot, manifest: manifest, period: period, now: now, calendar: calendar)
    }

    let headline: String
    if !learningStarted.isEmpty {
      headline = "今週、\(learningStarted.count)回の「使う前」が学習に変わりました"
    } else if !answers.isEmpty {
      headline = "今週、\(answers.count)問の学習が積み上がりました"
    } else {
      headline = "今週の学習を、ここに積み上げていきます"
    }
    let correct = answers.filter(\.isCorrect).count
    let recommendation: String
    if answers.isEmpty {
      recommendation = "まずは1日5問から始めてみましょう。"
    } else if studyDays <= 2 {
      recommendation = "問題数を増やすより、1日1回だけでも学習する日を増やしてみましょう。"
    } else {
      recommendation = sections.compactMap(\.recommendation).first
        ?? "今のペースを維持し、期限の来た復習を優先しましょう。"
    }

    return .init(
      period: period,
      scope: scope,
      headline: headline,
      learningOpportunityCount: shieldStarts.count,
      learningStartedCount: learningStarted.count,
      earnedUnlockCount: unlocks.count,
      shieldEarnedUnlockCount: shieldUnlocks.count,
      safeFallbackUnlockCount: fallbackUnlocks.count,
      answerCount: answers.count,
      correctCount: correct,
      uniqueItemCount: Set(answers.map { CompositeStudyItemID(packID: $0.packID, itemID: $0.itemID) }).count,
      studyDayCount: studyDays,
      streak: streak,
      dailyPoints: dailyPoints,
      materialSections: sections,
      recommendation: recommendation
    )
  }

  private func uniqueSessionEvents(_ events: [LearningEvent]) -> [LearningEvent] {
    var sessionIDs: Set<UUID> = []
    var eventIDs: Set<UUID> = []
    return events.sorted { $0.occurredAt < $1.occurredAt }.filter { event in
      if let sessionID = event.sessionID { return sessionIDs.insert(sessionID).inserted }
      return eventIDs.insert(event.id).inserted
    }
  }

  private func streakCount(
    answers: [StudyAnswerRecord],
    today: Date,
    calendar: Calendar
  ) -> Int {
    let days = Set(
      answers.filter { $0.answeredAt < (calendar.date(byAdding: .day, value: 1, to: today) ?? .distantFuture) }
        .map { calendar.startOfDay(for: $0.answeredAt) })
    var count = 0
    for offset in 0..<10_000 {
      guard let day = calendar.date(byAdding: .day, value: -offset, to: today), days.contains(day)
      else { break }
      count += 1
    }
    return count
  }
}
