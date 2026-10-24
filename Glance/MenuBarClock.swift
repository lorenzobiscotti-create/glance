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
    private var timer: Timer?
    private var answer: String?
    private var answerUntil: Date?
    private var isThinking = false

    init(onToggleWatching: @escaping (Bool) -> Void) {
        self.onToggleWatching = onToggleWatching
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

    func promptForAPIKey(problem: String? = nil) {
        let alert = NSAlert()
        alert.messageText = problem ?? "Anthropic API key"
        alert.informativeText = "Paste your key from console.anthropic.com → API Keys. It starts with sk-ant-api and is stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.filter { !$0.isWhitespace }
            guard key.hasPrefix("sk-ant-") else {
                promptForAPIKey(problem: "That doesn't look like an API key")
                return
            }
            Keychain.apiKey = key
        }
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

        let watch = NSMenuItem(title: "Answer Screenshots", action: #selector(toggleWatching(_:)), keyEquivalent: "")
        watch.target = self
        watch.state = .on
        menu.addItem(watch)
        let hint = NSMenuItem(title: "⌃⇧⌘4, then drag a box", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        let key = NSMenuItem(title: "Set API Key…", action: #selector(setKey), keyEquivalent: "")
        key.target = self
        menu.addItem(key)
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

    @objc private func toggleWatching(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        onToggleWatching(sender.state == .on)
    }
    @objc private func setKey() { promptForAPIKey() }

    @objc private func copyAnswer() {
        guard let answer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }
}
