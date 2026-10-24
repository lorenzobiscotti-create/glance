import AppKit

/// Spots ⌘ tapped twice quickly on its own, with no other key, modifier or
/// click in between. It polls the keyboard state, which needs no permission.
@MainActor
final class CommandTapWatcher {
    /// Longest ⌘ can be held and still count as a tap.
    private static let maxHold: TimeInterval = 0.35
    /// Longest from the first press to the second release.
    private static let maxDoubleTap: TimeInterval = 0.6
    private static let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]

    private let onDoubleTap: () -> Void
    private var timer: Timer?
    private var pressedAt: Date?
    private var isSpoiled = false
    private var firstTapAt: Date?

    init(onDoubleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
        // Checked often enough to catch a quick tap.
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let now = Date()
        if flags.contains(.maskCommand) {
            if pressedAt == nil {
                pressedAt = now
                isSpoiled = false
            }
            if !flags.isDisjoint(with: Self.otherModifiers) { isSpoiled = true }
            return
        }

        guard let pressed = pressedAt else { return }
        pressedAt = nil
        guard !isSpoiled, now.timeIntervalSince(pressed) < Self.maxHold, !somethingPressed(since: pressed, now: now) else {
            firstTapAt = nil
            return
        }
        if let first = firstTapAt, now.timeIntervalSince(first) < Self.maxDoubleTap, !somethingPressed(since: first, now: now) {
            firstTapAt = nil
            onDoubleTap()
        } else {
            firstTapAt = pressed
        }
    }

    /// Whether a key or mouse button went down since `start` (⌘C, ⌘Tab, ⌘-click…).
    private func somethingPressed(since start: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(start)
        return [CGEventType.keyDown, .leftMouseDown, .rightMouseDown].contains {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < elapsed
        }
    }
}
