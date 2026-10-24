import AppKit

/// Watches the clipboard for new images, such as a ⌃⇧⌘4 screenshot,
/// and hands each one over as PNG data.
@MainActor
final class ClipboardWatcher {
    var isEnabled = true

    /// Longest side sent to Claude; bigger images are downscaled by the API anyway.
    private static let maxSide: CGFloat = 1568

    private let onImage: (Data) -> Void
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    init(onImage: @escaping (Data) -> Void) {
        self.onImage = onImage
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount

        // Skip files copied in Finder; they carry an icon image too.
        guard isEnabled,
              pasteboard.availableType(from: [.fileURL]) == nil,
              pasteboard.availableType(from: [.png, .tiff]) != nil,
              let image = NSImage(pasteboard: pasteboard),
              let png = Self.png(from: image)
        else { return }
        onImage(png)
    }

    private static func png(from image: NSImage) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}
