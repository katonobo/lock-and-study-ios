import SwiftUI

struct RecordsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var period = "7日"
  @State private var answers: [StudyAnswerRecord] = []

  var body: some View {
    List {
      Picker("期間", selection: $period) { ForEach(["今日", "7日", "30日", "全期間"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
      Section("概要") {
        LabeledContent("学習回答", value: "\(filteredEvents.filter { $0.kind == .answerSubmitted }.count)")
        LabeledContent("解除成功", value: "\(filteredEvents.filter { $0.kind == .unlockSuccess }.count)")
        LabeledContent("緊急解除", value: "\(filteredEvents.filter { $0.kind == .emergencyUnlock }.count)")
      }
      Section("教材別") {
        ForEach(model.manifests) { manifest in
          let count = filteredEvents.filter { $0.packID == manifest.id && $0.kind == .answerSubmitted }.count
          LabeledContent(manifest.title, value: "\(count)回答")
        }
      }
      Section("最近の回答") {
        if answers.isEmpty { Text("まだ回答履歴はありません").foregroundStyle(.secondary) }
        ForEach(answers.suffix(30).reversed()) { answer in
          NavigationLink { AnswerRecordDetailView(answer: answer) } label: {
            HStack { Image(systemName: answer.isCorrect ? "checkmark.circle.fill" : "book.circle.fill").foregroundStyle(answer.isCorrect ? .green : .orange); VStack(alignment: .leading) { Text(answer.prompt).lineLimit(1); Text(answer.answeredAt.formatted()).font(.caption).foregroundStyle(.secondary) } }
          }
        }
      }
    }.navigationTitle("記録").accessibilityIdentifier("records.screen")
      .task { answers = (try? await model.dependencies.learning.answers(monthKey: monthKey(Date()))) ?? [] }
  }
  private var filteredEvents: [LearningEvent] {
    guard let start = startDate else { return model.records }
    return model.records.filter { $0.occurredAt >= start }
  }
  private var startDate: Date? {
    switch period { case "今日": return Calendar.current.startOfDay(for: Date()); case "7日": return Date().addingTimeInterval(-7 * 86_400); case "30日": return Date().addingTimeInterval(-30 * 86_400); default: return nil }
  }
  private func monthKey(_ date: Date) -> String { let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date); return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0) }
}

private struct AnswerRecordDetailView: View {
  let answer: StudyAnswerRecord
  var body: some View {
    List {
      Section("回答時点の問題") { Text(answer.prompt); ForEach(answer.choices) { choice in Label(choice.text, systemImage: choice.id == answer.correctChoiceID ? "checkmark.circle.fill" : (choice.id == answer.selectedChoiceID ? "person.crop.circle" : "circle")) } }
      Section("回答") { LabeledContent("結果", value: answer.isCorrect ? "正解" : "不正解"); Text(answer.longExplanation) }
      Section("保存された版情報") { LabeledContent("教材", value: answer.packID.rawValue); LabeledContent("コンテンツ版", value: answer.contentVersion); LabeledContent("問題版", value: "\(answer.questionVersion)"); if let year = answer.examYear { LabeledContent("年度", value: "\(year)") }; if let date = answer.lawBasisDate { LabeledContent("法令基準日", value: date) } }
    }.navigationTitle("回答詳細")
  }
}

