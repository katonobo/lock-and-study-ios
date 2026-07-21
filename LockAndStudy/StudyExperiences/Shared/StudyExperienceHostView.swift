import SwiftUI

struct StudyExperienceHostView: View {
  let factory: any StudyExperienceFactory
  let baseContext: StudyExperienceContext
  @State private var firstRunCompleted: Bool

  init(factory: any StudyExperienceFactory, context: StudyExperienceContext, requiresFirstRun: Bool)
  {
    self.factory = factory
    self.baseContext = context
    let key = "lockandstudy.experience.\(factory.descriptor.id.rawValue).first-run.completed"
    _firstRunCompleted = State(
      initialValue: !requiresFirstRun || LockAndStudySharedConstants.defaults.bool(forKey: key))
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
      destination: baseContext.destination,
      openMaterialSelection: baseContext.openMaterialSelection,
      beginUnlockStudy: baseContext.beginUnlockStudy,
      completeFirstRun: {
        let key = "lockandstudy.experience.\(factory.descriptor.id.rawValue).first-run.completed"
        LockAndStudySharedConstants.defaults.set(true, forKey: key)
        firstRunCompleted = true
        baseContext.completeFirstRun()
      }
    )
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
