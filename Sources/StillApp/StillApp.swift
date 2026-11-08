import SwiftUI
import CullingCore

@main struct StillApp: App {
    @ViewState private var store = ReviewStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Still · 留选", id: "review") {
            WorkspaceView(store: store)
                .preferredColorScheme(.dark).tint(stillAccent)
                .onAppear {
                    store.startKeyboard()
                    delegate.onTerminate = { store.flushSave() }
                    if ProcessInfo.processInfo.arguments.contains("--demo") { store.loadDemo() }
                }
        }
        .defaultSize(width: 1380, height: 880)
        .windowResizability(.contentMinSize)
        .commands { ReviewCommands(store: store) }
        Window("Still 使用帮助", id: "help") { HelpView(preferences: store.preferences) }
            .defaultSize(width: 650, height: 750)
        Settings {
            SettingsView(preferences: store.preferences).preferredColorScheme(.dark).tint(stillAccent)
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { onTerminate?() }
}
