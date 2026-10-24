import AppKit

/// A menu bar item that shows the time like the system clock, and briefly
/// swaps to the latest answer. Clicking it shows the full answer.
@MainActor
final class MenuBarClock: NSObject {
    /// How long an answer stays in the menu bar before the time comes back.
    var answerSeconds: TimeInterval = 6
    /// Longest answer shown in the menu bar; longer ones are cut with "…".
    var maxChars = 28

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let formatter = DateFormatter()
    private let answerItem = NSMenuItem()
    private let copyItem = NSMenuItem(title: "Copy Answer", action: #selector(copyAnswer), keyEquivalent: "")
    private let onToggleWatching: (Bool) -> Void
    private let onCheckForUpdates: () -> Void
    private var timer: Timer?
    private var answer: String?
    private var answerUntil: Date?
    private var isThinking = false

    init(onToggleWatching: @escaping (Bool) -> Void, onCheckForUpdates: @escaping () -> Void) {
        self.onToggleWatching = onToggleWatching
        self.onCheckForUpdates = onCheckForUpdates
        super.init()
        // Same shape as the system clock, e.g. "Fri Oct 23 3:41 PM".
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d j:mm")
        item.button?.font = NSFont.menuBarFont(ofSize: 0)
        buildMenu()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func setThinking(_ thinking: Bool) {
        isThinking = thinking
        tick()
    }

    func show(_ text: String) {
        answer = text
        setAnswerView(text)
        answerUntil = Date().addingTimeInterval(answerSeconds)
        item.button?.title = shortVersion(of: text)
    }

    /// Asks for the key without a text box: you copy it, then click one button.
    /// (Glance also picks up a copied key by itself while it has none.)
    func promptForAPIKey(problem: String? = nil) {
        let alert = NSAlert()
        alert.messageText = problem ?? "Anthropic API key"
        alert.informativeText = """
        1. Copy your key from console.anthropic.com → API Keys (it starts with sk-ant-api).
        2. Click Use Copied Key.
        """
        alert.addButton(withTitle: "Use Copied Key")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            if !saveKeyFromClipboard() {
                promptForAPIKey(problem: "No API key on the clipboard")
            }
        }
    }

    /// Saves an API key from the clipboard. Returns false if there isn't one.
    @discardableResult
    func saveKeyFromClipboard() -> Bool {
        guard let key = Self.apiKey(in: NSPasteboard.general) else { return false }
        KeyStore.apiKey = key
        show("Checking key…")
        Task {
            switch await ClaudeClient(apiKey: key).checkKey() {
            case .some(true):
                show("✓ API key works")
            case .some(false):
                KeyStore.apiKey = nil
                show("⚠ That key didn't work")
            case .none:
                show("✓ API key saved")
            }
        }
        return true
    }

    static func apiKey(in pasteboard: NSPasteboard) -> String? {
        guard let text = pasteboard.string(forType: .string)?.filter({ !$0.isWhitespace }),
              text.hasPrefix("sk-ant-")
        else { return nil }
        return text
    }

    private func tick() {
        if let answerUntil, Date() < answerUntil { return }
        answerUntil = nil
        let time = formatter.string(from: Date())
        item.button?.title = isThinking ? time + " ·" : time
    }

    /// The first line of the answer, cut to fit the menu bar.
    private func shortVersion(of text: String) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > maxChars ? String(trimmed.prefix(maxChars - 1)) + "…" : trimmed
    }

    private func buildMenu() {
        let menu = NSMenu()
        answerItem.isHidden = true
        copyItem.target = self
        copyItem.isHidden = true
        menu.addItem(answerItem)
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let watch = NSMenuItem(title: "Answer Screenshots & Text", action: #selector(toggleWatching(_:)), keyEquivalent: "")
        watch.target = self
        watch.state = .on
        menu.addItem(watch)
        for tip in ["⌃⇧⌘4, then drag a box", "Or highlight text, then tap ⌘ twice"] {
            let hint = NSMenuItem(title: tip, action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        let key = NSMenuItem(title: "Use Copied API Key", action: #selector(setKey), keyEquivalent: "")
        key.target = self
        menu.addItem(key)
        let forget = NSMenuItem(title: "Remove API Key", action: #selector(forgetKey), keyEquivalent: "")
        forget.target = self
        menu.addItem(forget)
        menu.addItem(.separator())

        let version = NSMenuItem(title: "Glance build \(Updater.currentBuild)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let update = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    /// Shows the full answer as wrapping text at the top of the menu.
    private func setAnswerView(_ text: String) {
        let width: CGFloat = 300
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.menuFont(ofSize: 0)
        label.isSelectable = true
        let height = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? 20
        label.frame = NSRect(x: 14, y: 4, width: width, height: height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width + 28, height: height + 8))
        container.addSubview(label)
        answerItem.view = container
        answerItem.isHidden = false
        copyItem.isHidden = false
    }

    @objc private func checkForUpdates() { onCheckForUpdates() }

    @objc private func forgetKey() {
        KeyStore.apiKey = nil
        show("API key removed")
    }

    @objc private func toggleWatching(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        onToggleWatching(sender.state == .on)
    }
    @objc private func setKey() {
        if !saveKeyFromClipboard() { promptForAPIKey(problem: "No API key on the clipboard") }
    }

    @objc private func copyAnswer() {
        guard let answer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }
}
