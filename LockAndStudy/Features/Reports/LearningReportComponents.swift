import Charts
import SwiftUI

struct LearningReportBody: View {
  let report: LearningReport
  let shareText: String?
  var sampleBadge = false

  private var primaryMetrics: [LearningReportMetric] {
    if report.learningOpportunityCount > 0 {
      return [
        .init(
          id: "report.opportunities", label: "使う前の学習チャンス",
          value: "\(report.learningOpportunityCount)回", systemImage: "shield.lefthalf.filled"),
        .init(
          id: "report.started", label: "学習まで進んだ",
          value: "\(report.learningStartedCount)回", systemImage: "book.fill"),
        .init(
          id: "report.unlocked", label: "解除できた",
          value: "\(report.shieldEarnedUnlockCount)回", systemImage: "lock.open.fill"),
      ]
    }
    return [
      .init(id: "report.answers", label: "回答", value: "\(report.answerCount)問", systemImage: "checklist"),
      .init(id: "report.accuracy", label: "正答率", value: "\(report.accuracy)%", systemImage: "target"),
      .init(id: "report.days", label: "学習日数", value: "\(report.studyDayCount)日", systemImage: "calendar"),
    ]
  }

  var body: some View {
    LazyVStack(spacing: 18) {
      if sampleBadge {
        Text("サンプル")
          .font(.headline.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 18).padding(.vertical, 8)
          .background(LockAndStudyTheme.teal, in: Capsule())
          .accessibilityIdentifier("report.sample.badge")
      }
      hero
      metricGrid(primaryMetrics)
      dailyChart
      learningSummary
      ForEach(report.materialSections) { section in
        materialSection(section)
      }
      recommendation
      if let shareText {
        ShareLink(item: shareText) {
          Label("家族に共有", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
        }
        .primaryActionStyle()
        .accessibilityIdentifier("report.share")
      }
      privacy
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("今週の学習レポート", systemImage: "chart.bar.xaxis")
        .font(.headline)
      Text(periodText)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(report.headline)
        .font(.title.bold())
        .fixedSize(horizontal: false, vertical: true)
      Text(report.compactSummary)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studyCard()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("report.hero")
  }

  private func metricGrid(_ metrics: [LearningReportMetric]) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
      ForEach(metrics) { metric in
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: metric.systemImage).foregroundStyle(LockAndStudyTheme.teal)
          Text(metric.value).font(.title2.bold()).minimumScaleFactor(0.75)
          Text(metric.label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .studyCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityValue)
      }
    }
  }

  private var dailyChart: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("7日間の積み上げ").font(.title3.bold())
      Chart(report.dailyPoints) { point in
        BarMark(
          x: .value("日", point.day, unit: .day),
          y: .value("回答数", point.answerCount)
        )
        .foregroundStyle(LockAndStudyTheme.teal.gradient)
      }
      .frame(height: 190)
      .chartYAxis { AxisMarks(position: .leading) }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("7日間の回答グラフ")
      .accessibilityValue(
        report.dailyPoints.map { "\($0.day.formatted(.dateTime.weekday(.abbreviated))) \($0.answerCount)問" }
          .joined(separator: "、"))
      .accessibilityIdentifier("report.chart")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studyCard()
  }

  private var learningSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("学習成果").font(.title3.bold())
      LabeledContent("回答数", value: "\(report.answerCount)問")
      LabeledContent("ユニーク問題", value: "\(report.uniqueItemCount)問")
      LabeledContent("正答率", value: "\(report.accuracy)%")
      LabeledContent("学習日数", value: "\(report.studyDayCount)日")
      LabeledContent("連続学習", value: "\(report.streak)日")
      if report.safeFallbackUnlockCount > 0 {
        LabeledContent("安全問題で解除", value: "\(report.safeFallbackUnlockCount)回")
      }
      if report.learningOpportunityCount > 0 {
        LabeledContent("学習転換率", value: "\(report.learningConversionRate)%")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studyCard()
    .accessibilityIdentifier("report.learningSummary")
  }

  @ViewBuilder private func materialSection(_ section: StudyMaterialReportSection) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(section.title, systemImage: section.systemImage).font(.title2.bold())
      Text(section.subtitle).font(.headline).foregroundStyle(.secondary)
      metricGrid(section.metrics)
      if !section.currentMetrics.isEmpty {
        Text("現在の進捗").font(.headline)
        metricGrid(section.currentMetrics)
      }
      if !section.progressRows.isEmpty {
        VStack(spacing: 12) {
          ForEach(section.progressRows) { row in
            VStack(alignment: .leading, spacing: 6) {
              LabeledContent(row.label, value: "\(row.completed) / \(row.available)")
              ProgressView(value: row.fraction)
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
      if !section.categoryRows.isEmpty {
        Text("分野別").font(.headline)
        ForEach(section.categoryRows) { row in
          LabeledContent(row.label, value: row.value)
        }
      }
      if !section.subcategoryRows.isEmpty {
        DisclosureGroup("小分野別") {
          ForEach(section.subcategoryRows) { row in
            LabeledContent(row.label, value: row.value).padding(.vertical, 4)
          }
        }
      }
      if !section.weakAreas.isEmpty {
        Text("今週、復習を優先したい分野").font(.headline)
        ForEach(section.weakAreas) { area in
          LabeledContent(area.title, value: "\(area.answerCount)問・\(area.accuracy)%")
        }
      }
      if let footer = section.footer {
        Text(footer).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("report.material.\(section.packID.rawValue)")
  }

  private var recommendation: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("次週のおすすめ", systemImage: "lightbulb.fill").font(.title3.bold())
      Text(report.recommendation).fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studyCard()
  }

  private var privacy: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("共有されない情報", systemImage: "hand.raised.fill").font(.headline)
      Text("ロック対象のアプリ名やtoken、管理コード、緊急解除理由、購入情報、個別の問題文・誤答内容は共有されません。共有はボタンを押したときだけ行われます。")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .studyCard()
    .accessibilityIdentifier("report.privacy")
  }

  private var periodText: String {
    let calendar = Calendar.current
    let end = calendar.date(byAdding: .day, value: -1, to: report.period.endExclusive)
      ?? report.period.endExclusive
    let startText = report.period.startInclusive.formatted(.dateTime.month().day())
    let endText = end.formatted(.dateTime.month().day())
    return "\(startText)〜\(endText)"
  }
}
