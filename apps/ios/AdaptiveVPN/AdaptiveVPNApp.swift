import SwiftUI

@main
struct AdaptiveVPNApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .task {
                    await state.bootstrap()
                }
        }
    }
}
