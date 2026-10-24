import AppKit

/// Checks GitHub for a newer build every 30 minutes and on wake. When there is one, it
/// downloads it, swaps it in for the running copy and restarts Glance.
@MainActor
final class Updater {
    private static let latestRelease = URL(string: "https://api.github.com/repos/lorenzobiscotti-create/glance/releases/latest")!

    /// The build number GitHub stamped into this copy (0 for local builds).
    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private let onStatus: (String) -> Void
    private var timer: Timer?
    private var isChecking = false

    init(onStatus: @escaping (String) -> Void) {
        self.onStatus = onStatus
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        // Timers don't run while the Mac sleeps, so also check on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    /// `userAsked` reports "up to date" and failures; background checks stay quiet.
    func check(userAsked: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: Self.latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let latest = Int(release.tag_name.replacingOccurrences(of: "build-", with: "")),
                  latest > Self.currentBuild,
                  let asset = release.assets.first(where: { $0.name == "Glance.zip" })
            else {
                if userAsked { onStatus("✓ Glance is up to date") }
                return
            }
            onStatus("Updating Glance…")
            try await install(from: asset.browser_download_url)
        } catch {
            if userAsked { onStatus("⚠ Update failed") }
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    private func install(from url: URL) async throws {
        let (zip, _) = try await URLSession.shared.download(from: url)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        // The running copy keeps working after its files are replaced.
        let current = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(current, withItemAt: work.appendingPathComponent("Glance.app"))

        // Reopen the new copy once this one has quit.
        try run("/bin/sh", ["-c", "(sleep 1; /usr/bin/open \"$0\") > /dev/null 2>&1 &", current.path])
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
