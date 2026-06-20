import SwiftUI
import AppKit

/// Grid of summary-mode apps shown in the main item's popover. Each cell is the
/// app's monochrome icon with its notification badge; clicking opens the app.
struct GroupGridView: View {
    @ObservedObject var store: AppStore
    let onOpen: (ManagedApp) -> Void

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 0)]

    var body: some View {
        let apps = store.summaryApps
        Group {
            if apps.isEmpty {
                Text("No notifications")
                    .foregroundStyle(.secondary)
                    .padding(28)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(apps) { app in
                        Button { onOpen(app) } label: {
                            Image(nsImage: IconRenderer.badgedIcon(
                                forAppPath: app.path,
                                badge: store.badge(for: app),
                                side: 36,
                                colorMode: store.colorMode,
                                badgeColor: store.badgeColor))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(app.name)
                    }
                }
                .padding(10)
                .frame(width: 280)
            }
        }
    }
}
