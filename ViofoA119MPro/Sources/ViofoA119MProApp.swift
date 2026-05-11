import SwiftUI

@main
struct ViofoA119MProApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var liveVideo = LiveVideoModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(liveVideo)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
