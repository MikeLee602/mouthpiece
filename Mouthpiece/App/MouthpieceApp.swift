import SwiftUI

@main
struct MouthpieceApp: App {
    var body: some Scene {
        MenuBarExtra("Mouthpiece", systemImage: "mic.fill") {
            Text("Mouthpiece 启动了")
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
