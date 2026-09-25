import AppKit
import CoreImage

/// Builds the images used in the status bar and the group popover.
/// App icons are rendered as monochrome silhouettes; notification counts are
/// drawn as a red circular badge overlaid on the top-right of the icon.
enum IconRenderer {
    private static let barIcon: CGFloat = 18
    /// Shared context; creating one per draw (as NSCIImageRep does) is very expensive.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Plain template bell (no badge).
    static func bell() -> NSImage {
        let img = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
            ?? NSImage(size: NSSize(width: barIcon, height: barIcon))
        img.isTemplate = true
        return img
    }

    /// Bell for the combined summary item, with the total count in a colored circle.
    /// The bell is baked into a non-template bitmap (the badge must keep its color),
    /// so `.labelColor` is resolved against `appearance` — pass the status button's
    /// `effectiveAppearance`, since the menu bar can differ from the system appearance.
    static func summaryIcon(total: Int, badgeColor: NSColor = .systemRed,
                            appearance: NSAppearance? = nil) -> NSImage {
        let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
            ?? NSImage(size: NSSize(width: barIcon, height: barIcon))
        var result = NSImage()
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            let base = silhouette(bell, side: barIcon, color: .labelColor)
            result = composite(base) { size in
                if total > 0 { drawBadge(.count(total), in: size, badgeColor: badgeColor) }
            }
        }
        return result
    }

    /// App icon with its badge on top. Coloring follows `colorMode`: full color
    /// always, monochrome always, or (default) monochrome when idle and full
    /// color when a notification is present, to draw attention to it.
    static func badgedIcon(forAppPath path: String, badge: Badge, side: CGFloat,
                           colorMode: ColorMode = .notificationsColor,
                           badgeColor: NSColor = .systemRed) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let useColor: Bool
        switch colorMode {
        case .fullColor: useColor = true
        case .notificationsColor: useColor = badge.isVisible
        case .alwaysMono: useColor = false
        }
        let base = useColor ? resized(icon, side: side) : grayscale(icon, side: side)
        return composite(base) { size in drawBadge(badge, in: size, badgeColor: badgeColor) }
    }

    /// Plain full-color resize at the given size.
    private static func resized(_ image: NSImage, side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    // MARK: - Drawing helpers

    /// Recolor an image to a flat single-color silhouette at the given size.
    private static func silhouette(_ image: NSImage, side: CGFloat, color: NSColor) -> NSImage {
        let size = NSSize(width: side, height: side)
        let out = NSImage(size: size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)   // tint only where the icon is opaque
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    /// Desaturate an icon to grayscale while keeping its internal detail and
    /// transparency (rounded corners stay clear). Slight contrast bump so the
    /// logo reads against its background tile.
    private static func grayscale(_ image: NSImage, side: CGFloat) -> NSImage {
        let target = NSSize(width: side, height: side)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let out = NSImage(size: target)
            out.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: target))
            out.unlockFocus()
            return out
        }
        let mono = CIImage(cgImage: cg).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.1,
        ])
        guard let monoCG = ciContext.createCGImage(mono, from: CIImage(cgImage: cg).extent) else {
            return resized(image, side: side)
        }
        let monoImage = NSImage(cgImage: monoCG, size: NSSize(width: cg.width, height: cg.height))

        let out = NSImage(size: target)
        out.lockFocus()
        monoImage.draw(in: NSRect(origin: .zero, size: target),
                       from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    /// Draw `base` into a fresh image, then run `overlay` to add the badge.
    private static func composite(_ base: NSImage, overlay: (NSSize) -> Void) -> NSImage {
        let img = NSImage(size: base.size)
        img.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        overlay(base.size)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// Circular/pill badge anchored to the top-right corner, in `badgeColor`.
    private static func drawBadge(_ badge: Badge, in size: NSSize, badgeColor: NSColor = .systemRed) {
        switch badge {
        case .none:
            return
        case .dot:
            let d = max(6, size.width * 0.34)
            let rect = NSRect(x: size.width - d, y: size.height - d, width: d, height: d)
            badgeColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
        case .count(let n):
            let text = n > 99 ? "99+" : "\(n)"
            let fontSize = max(7, size.width * 0.30)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let tSize = (text as NSString).size(withAttributes: attrs)
            let h = tSize.height + 2
            let w = max(h, tSize.width + 6)
            let rect = NSRect(x: size.width - w, y: size.height - h, width: w, height: h)
            badgeColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
            let tRect = NSRect(x: rect.midX - tSize.width / 2,
                               y: rect.midY - tSize.height / 2,
                               width: tSize.width, height: tSize.height)
            (text as NSString).draw(in: tRect, withAttributes: attrs)
        }
    }
}
