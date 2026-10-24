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
        } catch {
            clock.show("⚠ \(error.localizedDescription)")
        }
    }
}
