import AppKit
import ApplicationServices

/// Watches the clipboard. A new image (such as a ⌃⇧⌘4 screenshot) is handed over
/// to be answered, and so is the whole-screen screenshot `answerScreen()` takes.
@MainActor
final class ClipboardWatcher {
    var isEnabled = true
    /// Called whenever new text lands on the clipboard.
    var onTextCopied: (() -> Void)?
    /// Called when `answerScreen()` got no screenshot back.
    var onNoScreenshot: (() -> Void)?

    /// Longest side sent to Claude; bigger images are downscaled by the API anyway.
    private static let maxSide: CGFloat = 1568
    /// How long macOS gets to put the screenshot on the clipboard.
    private static let screenshotWindow: TimeInterval = 3
    private static let threeKey: CGKeyCode = 20

    private let onInput: (ClaudeClient.Input) -> Void
    private var lastChange = NSPasteboard.general.changeCount
    private var screenshotUntil: Date?
    /// A typed question waiting for its screenshot.
    private var question: String?
    private var timer: Timer?

    init(onInput: @escaping (ClaudeClient.Input) -> Void) {
        self.onInput = onInput
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    /// Answers whatever question is on screen, or `question` with the screen attached
    /// in case it's about something on it. Glance presses macOS's own ⌃⇧⌘3, which
    /// copies the whole screen, so it needs no screen recording permission.
    /// Returns false until Glance is allowed in Accessibility, which macOS asks for here.
    func answerScreen(question: String? = nil) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        self.question = question
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: Self.threeKey, keyDown: keyDown)
            event?.flags = [.maskControl, .maskShift, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
        screenshotUntil = Date().addingTimeInterval(Self.screenshotWindow)
        return true
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else {
            if let until = screenshotUntil, Date() > until {
                screenshotUntil = nil
                if let question {
                    // No screenshot, but the typed question can still be answered.
                    self.question = nil
                    onInput(.question(question, screen: nil))
                } else {
                    onNoScreenshot?()
                }
            }
            return
        }
        lastChange = pasteboard.changeCount
        let isScreen = screenshotUntil.map { Date() < $0 } ?? false
        let question = isScreen ? question : nil
        screenshotUntil = nil
        self.question = nil

        // Skip files copied in Finder; they carry a name and an icon image too.
        let isFile = pasteboard.availableType(from: [.fileURL]) != nil
        let hasImage = !isFile && pasteboard.availableType(from: [.png, .tiff]) != nil
        if let question {
            // Whatever landed on the clipboard, the typed question still gets answered.
            let png = hasImage ? NSImage(pasteboard: pasteboard).flatMap(Self.png(from:)) : nil
            onInput(.question(question, screen: png))
            return
        }
        guard !isFile else { return }

        if hasImage {
            guard isEnabled, let image = NSImage(pasteboard: pasteboard), let png = Self.png(from: image) else { return }
            onInput(isScreen ? .screen(png) : .image(png))
        } else if pasteboard.string(forType: .string) != nil {
            onTextCopied?()
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
