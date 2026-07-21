import Foundation

enum LearningReportScope: Hashable, Sendable {
  case allMaterials
  case pack(StudyPackID)
}

struct DailyLearningReportPoint: Identifiable, Equatable, Sendable {
  var id: Date { day }
  let day: Date
  let answerCount: Int
  let correctCount: Int
}

struct LearningReportMetric: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let value: String
  let systemImage: String
  let accessibilityValue: String

  init(
    id: String,
    label: String,
    value: String,
    systemImage: String,
    accessibilityValue: String? = nil
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.systemImage = systemImage
    self.accessibilityValue = accessibilityValue ?? "\(label) \(value)"
  }
}

struct LearningReportProgressRow: Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let completed: Int
  let available: Int
  var fraction: Double {
    available == 0 ? 0 : min(1, Double(completed) / Double(available))
  }
}

struct LearningReportWeakArea: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let answerCount: Int
  let accuracy: Int
}

struct StudyMaterialReportSection: Identifiable, Equatable, Sendable {
  var id: StudyPackID { packID }
  let packID: StudyPackID
  let title: String
  let subtitle: String
  let systemImage: String
  let metrics: [LearningReportMetric]
  let currentMetrics: [LearningReportMetric]
  let progressRows: [LearningReportProgressRow]
  let categoryRows: [LearningReportMetric]
  let subcategoryRows: [LearningReportMetric]
  let weakAreas: [LearningReportWeakArea]
  let recommendation: String?
  let footer: String?
}

struct LearningReport: Equatable, Sendable {
  let period: LearningReportPeriod
  let scope: LearningReportScope
  let headline: String
  let learningOpportunityCount: Int
  let learningStartedCount: Int
  let earnedUnlockCount: Int
  let shieldEarnedUnlockCount: Int
  let answerCount: Int
  let correctCount: Int
  let uniqueItemCount: Int
  let studyDayCount: Int
  let streak: Int
  let dailyPoints: [DailyLearningReportPoint]
  let materialSections: [StudyMaterialReportSection]
  let recommendation: String

  var accuracy: Int {
    answerCount == 0 ? 0 : Int((Double(correctCount) / Double(answerCount) * 100).rounded())
  }
  var learningConversionRate: Int {
    learningOpportunityCount == 0
      ? 0
      : Int((Double(learningStartedCount) / Double(learningOpportunityCount) * 100).rounded())
  }
  var compactSummary: String {
    "\(studyDayCount)日学習・\(answerCount)問・正答率\(accuracy)%"
  }
  var isEmpty: Bool {
    answerCount == 0 && learningOpportunityCount == 0 && earnedUnlockCount == 0
  }
}

struct LearningReportDataSnapshot: Sendable {
  let answers: [StudyAnswerRecord]
  let events: [LearningEvent]
  let progress: [String: ItemProgress]
  let manifests: [StudyPackManifest]
  let entitlement: CommerceEntitlementSnapshot

  func answers(for scope: LearningReportScope) -> [StudyAnswerRecord] {
    switch scope {
    case .allMaterials: return answers
    case .pack(let packID): return answers.filter { $0.packID == packID }
    }
  }

  func events(for scope: LearningReportScope) -> [LearningEvent] {
    switch scope {
    case .allMaterials: return events
    case .pack(let packID): return events.filter { $0.packID == packID }
    }
  }

  func effectiveLearningRole(for answer: StudyAnswerRecord) -> AnswerLearningRole {
    if let role = answer.learningRole { return role }
    if answer.wasNewAtSubmission == true { return .newItem }
    if answer.wasNewAtSubmission == false { return .generalReview }
    let first = answers
      .filter { $0.packID == answer.packID && $0.itemID == answer.itemID }
      .min { lhs, rhs in
        if lhs.answeredAt == rhs.answeredAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.answeredAt < rhs.answeredAt
      }
    return first?.id == answer.id ? .newItem : .generalReview
  }
}

protocol StudyExperienceReportProviding: Sendable {
  var supportedExperienceID: StudyExperienceID { get }
  func makeReportSection(
    snapshot: LearningReportDataSnapshot,
    manifest: StudyPackManifest,
    period: LearningReportPeriod,
    now: Date,
    calendar: Calendar
  ) throws -> StudyMaterialReportSection
}
