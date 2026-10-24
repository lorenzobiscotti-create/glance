import Foundation

/// Stores the Anthropic API key in a file only your Mac account can read.
/// Not the Keychain: each Glance update has a new signature, and macOS would
/// ask permission to read the Keychain item again after every update.
enum KeyStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glance/api-key")
    }

    static var apiKey: String? {
        get {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        }
        set {
            let files = FileManager.default
            guard let newValue else {
                try? files.removeItem(at: fileURL)
                return
            }
            try? files.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            files.createFile(atPath: fileURL.path, contents: Data(newValue.utf8), attributes: [.posixPermissions: 0o600])
        }
    }
}
