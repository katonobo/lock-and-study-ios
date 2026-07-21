import SwiftUI

@main
struct LockAndStudyApp: App {
  @StateObject private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(model)
        .environmentObject(model.dependencies.lockController)
        .environmentObject(model.dependencies.commerce)
        .task { await model.start() }
        .onChange(of: scenePhase) { phase in
          if phase == .active { Task { await model.start() } }
        }
    }
  }
}

