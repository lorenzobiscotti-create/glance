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

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        watcher = ClipboardWatcher { [weak self] png in
            guard let self else { return }
            Task { await self.answer(png) }
        }
        clock = MenuBarClock(onToggleWatching: { [weak self] on in
            self?.watcher.isEnabled = on
        })
        if Keychain.apiKey == nil {
            clock.promptForAPIKey()
        }
    }

    private func answer(_ png: Data) async {
        guard let key = Keychain.apiKey else {
            clock.promptForAPIKey()
            return
        }
        clock.setThinking(true)
        defer { clock.setThinking(false) }
        do {
            let text = try await ClaudeClient(apiKey: key).answer(imagePNG: png)
            clock.show(text)
        } catch ClaudeClient.ClaudeError.http(401, _) {
            Keychain.apiKey = nil
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
