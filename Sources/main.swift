import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask for Accessibility permission (needed to read Dock badges).
        DockBadgeReader.ensureTrusted(prompt: true)

        controller = StatusBarController(store: .shared)

        if AppStore.shared.showWindowOnStartup {
            controller.openSettings()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

@main
enum Notibar {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
        app.run()
    }
}
