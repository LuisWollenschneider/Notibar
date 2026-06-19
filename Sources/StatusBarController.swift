import AppKit
import SwiftUI
import Combine
import ApplicationServices

/// Manages all NSStatusItems: the main app item (combined summary badge + group
/// popover), and one dedicated item per dedicated-mode app. Polls badges on a timer.
@MainActor
final class StatusBarController {
    private let store: AppStore
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    private let mainItem: NSStatusItem   // combined summary badge + group popover
    private var dedicatedItems: [String: NSStatusItem] = [:]   // bundleID -> item

    private var settingsController: SettingsWindowController?

    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(
            rootView: GroupGridView(store: store, onOpen: { [weak self] app in
                self?.openAppPath(app.path)
                self?.popover.performClose(nil)
            }))
        return p
    }()

    init(store: AppStore) {
        self.store = store
        self.mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMainItem()
        rebuild()

        // Rebuild items when the registered app set changes; refresh labels on badge change.
        store.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        store.$badges
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshLabels() }
            .store(in: &cancellables)

        store.refreshBadges()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak store] _ in
            Task { @MainActor in store?.refreshBadges() }
        }
    }

    // MARK: - Main item

    private func configureMainItem() {
        guard let button = mainItem.button else { return }
        button.imagePosition = .imageOnly
        button.action = #selector(mainItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Left-click toggles the group popover; right-click shows Settings/Quit.
    @objc private func mainItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = mainItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility…",
                                  action: #selector(grantAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Notibar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        mainItem.menu = menu
        mainItem.button?.performClick(nil)
        mainItem.menu = nil
    }

    // MARK: - Rebuild / refresh

    /// Recreate dedicated items to match current modes.
    private func rebuild() {
        let wanted = Set(store.dedicatedApps.map { $0.bundleID })
        for (bundleID, item) in dedicatedItems where !wanted.contains(bundleID) {
            NSStatusBar.system.removeStatusItem(item)
            dedicatedItems[bundleID] = nil
        }
        for app in store.dedicatedApps where dedicatedItems[app.bundleID] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageOnly
            item.button?.action = #selector(openApp(_:))
            item.button?.target = self
            item.button?.representedObject = app.path
            dedicatedItems[app.bundleID] = item
        }

        refreshLabels()
    }

    /// Update the combined main item + dedicated items from current badges.
    private func refreshLabels() {
        if let button = mainItem.button {
            button.image = IconRenderer.summaryIcon(total: store.summaryTotal)
            button.attributedTitle = NSAttributedString(string: "")
        }

        for app in store.dedicatedApps {
            guard let item = dedicatedItems[app.bundleID], let button = item.button else { continue }
            button.image = IconRenderer.badgedIcon(forAppPath: app.path,
                                                   badge: store.badge(for: app), side: 18)
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    // MARK: - Actions

    @objc private func openApp(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let path = button.representedObject as? String else { return }
        openAppPath(path)
    }

    private func openAppPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store)
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func grantAccessibility() {
        DockBadgeReader.ensureTrusted(prompt: true)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// NSStatusBarButton has no representedObject by default; add storage.
private var representedObjectKey: UInt8 = 0
extension NSStatusBarButton {
    var representedObject: Any? {
        get { objc_getAssociatedObject(self, &representedObjectKey) }
        set { objc_setAssociatedObject(self, &representedObjectKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}
