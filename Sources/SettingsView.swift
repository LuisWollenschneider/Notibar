import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    iconsSection
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 520)
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General").font(.title3.bold())
            VStack(spacing: 0) {
                Toggle("Start at login", isOn: $store.startAtLogin)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                Divider()
                Toggle("Show window on startup", isOn: $store.showWindowOnStartup)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Icons / apps

    private var iconsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icons").font(.title3.bold())
            VStack(spacing: 0) {
                if store.apps.isEmpty {
                    Text("No apps added yet. Use + to add one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(store.apps) { app in
                        appRow(app)
                        if app.id != store.apps.last?.id { Divider() }
                    }
                }
                Divider()
                toolbar
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func appRow(_ app: ManagedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().frame(width: 22, height: 22)
            Text(app.name)
            Spacer()
            Picker("", selection: Binding(
                get: { app.mode },
                set: { store.setMode($0, for: app) }
            )) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selection == app.id ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = app.id }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button(action: addApp) { Image(systemName: "plus") }
            Button(action: removeSelected) { Image(systemName: "minus") }
                .disabled(selection == nil)
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK {
            for url in panel.urls { store.addApp(at: url) }
        }
    }

    private func removeSelected() {
        guard let id = selection, let app = store.apps.first(where: { $0.id == id }) else { return }
        store.removeApp(app)
        selection = nil
    }
}

/// Hosts the SwiftUI settings view in a standard window.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: AppStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Notibar"
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}
