import AppKit
import ApplicationServices

/// Watches the clipboard. A new image (such as a ⌃⇧⌘4 screenshot) is handed over
/// to be answered, and so is whatever `answerSelection()` copies.
@MainActor
final class ClipboardWatcher {
    var isEnabled = true
    /// Called whenever new text lands on the clipboard.
    var onTextCopied: (() -> Void)?
    /// Called when `answerSelection()` couldn't copy the text or the screen.
    var onNothingCaptured: (() -> Void)?

    /// Longest side sent to Claude; bigger images are downscaled by the API anyway.
    private static let maxSide: CGFloat = 1568
    /// How long the front app gets to copy the highlighted text.
    private static let copyWindow: TimeInterval = 0.5
    /// How long macOS gets to put a whole-screen screenshot on the clipboard.
    private static let screenshotWindow: TimeInterval = 3
    private static let maxTextLength = 4000
    private static let cKey: CGKeyCode = 8
    private static let threeKey: CGKeyCode = 20

    private enum Capture { case selection, screen }

    private let onInput: (ClaudeClient.Input) -> Void
    private var lastChange = NSPasteboard.general.changeCount
    private var pending: (capture: Capture, until: Date)?
    private var timer: Timer?

    init(onInput: @escaping (ClaudeClient.Input) -> Void) {
        self.onInput = onInput
        // Checked often so two quick copies show up as two separate changes.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    /// Presses ⌘C for the user and answers whatever that copies. With nothing
    /// highlighted, it answers a screenshot of the whole screen instead. Returns
    /// false until Glance is allowed in Accessibility, which macOS asks for here.
    func answerSelection() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        press(Self.cKey, .maskCommand)
        pending = (.selection, Date().addingTimeInterval(Self.copyWindow))
        return true
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else {
            if let pending, Date() > pending.until { timedOut(pending.capture) }
            return
        }
        lastChange = pasteboard.changeCount
        let capture = pending.flatMap { Date() < $0.until ? $0.capture : nil }
        pending = nil

        // Skip files copied in Finder; they carry a name and an icon image too.
        guard pasteboard.availableType(from: [.fileURL]) == nil else { return }

        if pasteboard.availableType(from: [.png, .tiff]) != nil {
            guard isEnabled, let image = NSImage(pasteboard: pasteboard), let png = Self.png(from: image) else { return }
            onInput(capture == .screen ? .screen(png) : .image(png))
        } else if let text = pasteboard.string(forType: .string) {
            onTextCopied?()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard capture == .selection, isEnabled, !trimmed.isEmpty, !trimmed.hasPrefix("sk-ant-") else { return }
            onInput(.text(String(trimmed.prefix(Self.maxTextLength))))
        }
    }

    private func timedOut(_ capture: Capture) {
        pending = nil
        switch capture {
        case .selection:
            // Nothing was highlighted, so macOS's own ⌃⇧⌘3 copies the whole screen.
            // That way Glance needs no screen recording permission.
            press(Self.threeKey, [.maskControl, .maskShift, .maskCommand])
            pending = (.screen, Date().addingTimeInterval(Self.screenshotWindow))
        case .screen:
            onNothingCaptured?()
        }
    }

    private func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
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
