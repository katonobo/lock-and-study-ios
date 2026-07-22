import SwiftUI

struct StudyExperienceHostView: View {
  let factory: any StudyExperienceFactory
  let baseContext: StudyExperienceContext
  @State private var firstRunCompleted: Bool

  init(factory: any StudyExperienceFactory, context: StudyExperienceContext, requiresFirstRun: Bool)
  {
    self.factory = factory
    self.baseContext = context
    _firstRunCompleted = State(
      initialValue: !requiresFirstRun
        || PackFirstRunStore().isCompleted(
          packID: context.manifest.id,
          legacyExperienceID: factory.descriptor.id))
  }

  var body: some View {
    Group {
      if firstRunCompleted {
        factory.makeRootView(context: context)
      } else if let firstRun = factory.makeFirstRunView(context: context) {
        firstRun
      } else {
        factory.makeRootView(context: context)
      }
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
  }

  private var context: StudyExperienceContext {
    .init(
      manifest: baseContext.manifest,
      dependencies: baseContext.dependencies,
      reportProviders: baseContext.reportProviders,
      destination: baseContext.destination,
      openMaterialSelection: baseContext.openMaterialSelection,
      beginUnlockStudy: baseContext.beginUnlockStudy,
      completeFirstRun: {
        PackFirstRunStore().setCompleted(packID: baseContext.manifest.id)
        firstRunCompleted = true
        baseContext.completeFirstRun()
      }
    )
  }
}

struct PackFirstRunStore {
  let defaults: UserDefaults

  init(defaults: UserDefaults = LockAndStudySharedConstants.defaults) {
    self.defaults = defaults
  }

  func isCompleted(packID: StudyPackID, legacyExperienceID: StudyExperienceID) -> Bool {
    let packKey = key(packID)
    if defaults.bool(forKey: packKey) { return true }
    let legacyPackMatches =
      (packID == "english3000.v1" && legacyExperienceID == .vocabulary)
      || (packID == "takken2026.v1" && legacyExperienceID == .takken)
    let legacyKey =
      "lockandstudy.experience.\(legacyExperienceID.rawValue).first-run.completed"
    if legacyPackMatches, defaults.bool(forKey: legacyKey) {
      defaults.set(true, forKey: packKey)
      return true
    }
    return false
  }

  func setCompleted(packID: StudyPackID) {
    defaults.set(true, forKey: key(packID))
  }

  private func key(_ packID: StudyPackID) -> String {
    let v2 = "lockandstudy.pack.\(packID.rawValue).first-run.completed.v2"
    if !defaults.bool(forKey: v2) {
      let v1 = "lockandstudy.pack.\(packID.rawValue).first-run.completed.v1"
      if defaults.bool(forKey: v1) { defaults.set(true, forKey: v2) }
    }
    return v2
  }
}

struct UnlockChallengeHostView: View {
  let factory: any StudyExperienceFactory
  let bundle: ExperienceUnlockBundleSnapshot
  let context: UnlockChallengeViewContext

  var body: some View {
    factory.makeUnlockChallengeView(snapshot: bundle, context: context)
  }
}
