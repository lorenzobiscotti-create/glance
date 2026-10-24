import AppKit
import ApplicationServices

/// Watches the clipboard. A new image (such as a ⌃⇧⌘4 screenshot) is handed over
/// to be answered, and so is highlighted text copied by `answerSelection()`.
@MainActor
final class ClipboardWatcher {
    var isEnabled = true
    /// Called whenever new text lands on the clipboard.
    var onTextCopied: (() -> Void)?
    /// Called when `answerSelection()` copied nothing.
    var onNothingHighlighted: (() -> Void)?

    /// Longest side sent to Claude; bigger images are downscaled by the API anyway.
    private static let maxSide: CGFloat = 1568
    /// How long the front app gets to copy the highlighted text.
    private static let copyWindow: TimeInterval = 1.0
    private static let maxTextLength = 4000
    private static let cKey: CGKeyCode = 8

    private let onInput: (ClaudeClient.Input) -> Void
    private var lastChange = NSPasteboard.general.changeCount
    private var answerCopyUntil: Date?
    private var timer: Timer?

    init(onInput: @escaping (ClaudeClient.Input) -> Void) {
        self.onInput = onInput
        // Checked often so two quick copies show up as two separate changes.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    /// Presses ⌘C for the user and answers whatever that copies. Returns false
    /// until Glance is allowed in Accessibility, which macOS asks for here.
    func answerSelection() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        answerCopyUntil = Date().addingTimeInterval(Self.copyWindow)
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: Self.cKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        return true
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else {
            if let until = answerCopyUntil, Date() > until {
                answerCopyUntil = nil
                onNothingHighlighted?()
            }
            return
        }
        lastChange = pasteboard.changeCount
        let wantsCopy = answerCopyUntil.map { Date() < $0 } ?? false
        answerCopyUntil = nil

        // Skip files copied in Finder; they carry a name and an icon image too.
        guard pasteboard.availableType(from: [.fileURL]) == nil else { return }

        if pasteboard.availableType(from: [.png, .tiff]) != nil {
            guard isEnabled, let image = NSImage(pasteboard: pasteboard), let png = Self.png(from: image) else { return }
            onInput(.image(png))
        } else if let text = pasteboard.string(forType: .string) {
            onTextCopied?()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard wantsCopy, isEnabled, !trimmed.isEmpty, !trimmed.hasPrefix("sk-ant-") else { return }
            onInput(.text(String(trimmed.prefix(Self.maxTextLength))))
        }
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
