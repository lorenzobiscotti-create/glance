import SwiftUI

@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No windows: the app lives entirely in the menu bar.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clock: MenuBarClock!
    private var watcher: ClipboardWatcher!
    private var commandTaps: CommandTapWatcher!
    private var updater: Updater!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        watcher = ClipboardWatcher { [weak self] input in
            guard let self else { return }
            Task { await self.answer(input) }
        }
        clock = MenuBarClock(
            onToggleWatching: { [weak self] on in self?.watcher.isEnabled = on },
            onCheckForUpdates: { [weak self] in
                guard let self else { return }
                Task { await self.updater.check(userAsked: true) }
            }
        )
        updater = Updater(onStatus: { [weak self] status in self?.clock.show(status) })
        // Double-tapping ⌘ answers whatever question is on screen.
        commandTaps = CommandTapWatcher { [weak self] in
            guard let self, self.watcher.isEnabled else { return }
            if !self.watcher.answerScreen() {
                self.clock.show("⚠ Allow Glance in Accessibility")
            }
        }
        watcher.onNoScreenshot = { [weak self] in self?.clock.show("⚠ Couldn't screenshot the screen") }
        // With no key saved yet, copying one is enough.
        watcher.onTextCopied = { [weak self] in
            guard let self, KeyStore.apiKey == nil else { return }
            self.clock.saveKeyFromClipboard()
        }
        if KeyStore.apiKey == nil && !clock.saveKeyFromClipboard() {
            clock.promptForAPIKey()
        }
    }

    private func answer(_ input: ClaudeClient.Input) async {
        guard let key = KeyStore.apiKey else {
            clock.promptForAPIKey()
            return
        }
        clock.setThinking(true)
        defer { clock.setThinking(false) }
        do {
            let text = try await ClaudeClient(apiKey: key).answer(input)
            clock.show(text)
        } catch ClaudeClient.ClaudeError.http(401, _) {
            KeyStore.apiKey = nil
            clock.show("⚠ API key didn't work")
            clock.promptForAPIKey(problem: "That API key didn't work")
        } catch {
            clock.show("⚠ \(error.localizedDescription)")
        }
    }

    /// Menu bar apps have no Edit menu, so ⌘V/⌘C/⌘A don't reach text fields
    /// (like the API key box) without one. It's never shown.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
