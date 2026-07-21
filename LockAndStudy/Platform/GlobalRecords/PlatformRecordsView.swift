import SwiftUI

private enum GlobalRecordsPeriod: String, CaseIterable, Identifiable { case today = "今日", week = "7日", month = "30日", all = "全期間"; var id: String { rawValue } }

struct PlatformRecordsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var period = GlobalRecordsPeriod.week
  @State private var answers: [StudyAnswerRecord] = []
  private var start: Date? {
    switch period { case .today: return Calendar.current.startOfDay(for: Date()); case .week: return Date().addingTimeInterval(-7 * 86_400); case .month: return Date().addingTimeInterval(-30 * 86_400); case .all: return nil }
  }
  private var scopedEvents: [LearningEvent] { guard let start else { return model.records }; return model.records.filter { $0.occurredAt >= start } }
  private var streak: Int {
    let days = Set(answers.map { Calendar.current.startOfDay(for: $0.answeredAt) }); var value = 0
    for offset in 0..<365 { guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: Date())), days.contains(day) else { break }; value += 1 }
    return value
  }
  var body: some View {
    List {
      Picker("期間", selection: $period) { ForEach(GlobalRecordsPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
      Section("全教材") {
        LabeledContent("回答", value: "\(answers.count)問")
        LabeledContent("正答率", value: "\(answers.isEmpty ? 0 : Int(Double(answers.filter(\.isCorrect).count) / Double(answers.count) * 100))%")
        LabeledContent("解除成功", value: "\(scopedEvents.filter { $0.kind == .unlockSuccess }.count)回")
        LabeledContent("緊急解除", value: "\(scopedEvents.filter { $0.kind == .emergencyUnlock }.count)回")
        LabeledContent("連続学習", value: "\(streak)日")
      }
      Section("教材別") {
        ForEach(model.manifests) { manifest in
          let values = answers.filter { $0.packID == manifest.id }
          Button { model.openExperience(packID: manifest.id, destination: .records) } label: {
            HStack { VStack(alignment: .leading) { Text(manifest.title).font(.headline); Text("\(values.count)問・正答率 \(values.isEmpty ? 0 : Int(Double(values.filter(\.isCorrect).count) / Double(values.count) * 100))%").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }
          }.buttonStyle(.plain)
        }
      }
      Section("分野別") {
        ForEach(Dictionary(grouping: answers, by: \.category).keys.sorted(), id: \.self) { category in
          let values = answers.filter { $0.category == category }
          LabeledContent(category, value: "\(values.count)問・\(values.isEmpty ? 0 : Int(Double(values.filter(\.isCorrect).count) / Double(values.count) * 100))%")
        }
      }
      Section("小分野別") {
        ForEach(Dictionary(grouping: answers.filter { $0.subcategory != nil }, by: { $0.subcategory ?? "未分類" }).keys.sorted(), id: \.self) { subCategory in
          let values = answers.filter { $0.subcategory == subCategory }
          LabeledContent(subCategory, value: "\(values.count)問・\(values.isEmpty ? 0 : Int(Double(values.filter(\.isCorrect).count) / Double(values.count) * 100))%")
        }
      }
      Section("最近の誤答") {
        ForEach(answers.filter { !$0.isCorrect }.suffix(30).reversed()) { answer in
          VStack(alignment: .leading) { Text(answer.prompt).lineLimit(2); Text("\(packName(answer.packID))・\(answer.answeredAt.formatted())").font(.caption).foregroundStyle(.secondary) }
        }
      }
    }.navigationTitle("記録").task(id: period) { await load() }.accessibilityIdentifier("platform.records")
  }
  private func load() async { answers = (try? await model.dependencies.learning.answers(from: start, through: Date())) ?? [] }
  private func packName(_ id: StudyPackID) -> String { model.manifests.first(where: { $0.id == id })?.title ?? "教材" }
}
