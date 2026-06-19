import AppKit
import Combine
import ServiceManagement

/// Central observable state: registered apps, their modes, live badge values,
/// and general preferences. Persists registered apps + prefs to UserDefaults.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var apps: [ManagedApp] = []
    @Published var badges: [String: Badge] = [:]     // bundleID -> badge
    @Published var startAtLogin: Bool = false { didSet { applyLoginItem() } }
    @Published var showWindowOnStartup: Bool = true { didSet { savePrefs() } }

    private let defaults = UserDefaults.standard
    private let appsKey = "registeredApps"
    private let showWindowKey = "showWindowOnStartup"

    private init() {
        load()
    }

    // MARK: - Derived

    var summaryApps: [ManagedApp] { apps.filter { $0.mode == .summary } }
    var dedicatedApps: [ManagedApp] { apps.filter { $0.mode == .dedicated } }

    func badge(for app: ManagedApp) -> Badge { badges[app.bundleID] ?? .none }

    /// Combined total across every summary-mode app (empty badges count as 1).
    var summaryTotal: Int {
        summaryApps.reduce(0) { $0 + badge(for: $1).value }
    }

    // MARK: - Mutations

    func addApp(at url: URL) {
        guard let bundle = Bundle(path: url.path),
              let bundleID = bundle.bundleIdentifier else { return }
        guard !apps.contains(where: { $0.bundleID == bundleID }) else { return }

        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        apps.append(ManagedApp(bundleID: bundleID, name: name, path: url.path, mode: .summary))
        save()
    }

    func removeApp(_ app: ManagedApp) {
        apps.removeAll { $0.bundleID == app.bundleID }
        badges[app.bundleID] = nil
        save()
    }

    func setMode(_ mode: AppMode, for app: ManagedApp) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == app.bundleID }) else { return }
        apps[idx].mode = mode
        save()
    }

    // MARK: - Badge refresh

    /// Poll the Dock and update badges for every registered app, matching by name.
    func refreshBadges() {
        let raw = DockBadgeReader.readBadges()   // title -> label
        var updated: [String: Badge] = [:]
        for app in apps {
            updated[app.bundleID] = Badge.from(label: raw[app.name])
        }
        if updated != badges { badges = updated }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: appsKey),
           let decoded = try? JSONDecoder().decode([ManagedApp].self, from: data) {
            apps = decoded
        }
        showWindowOnStartup = defaults.object(forKey: showWindowKey) as? Bool ?? true
        if #available(macOS 13.0, *) {
            startAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            defaults.set(data, forKey: appsKey)
        }
    }

    private func savePrefs() {
        defaults.set(showWindowOnStartup, forKey: showWindowKey)
    }

    private func applyLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if startAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Notibar login item error: \(error)")
        }
    }
}
