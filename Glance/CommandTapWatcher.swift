import AppKit

/// Spots ⌘ tapped two or three times quickly on its own, with no other key,
/// modifier or click in between. It polls the keyboard state, which needs no permission.
@MainActor
final class CommandTapWatcher {
    /// Longest ⌘ can be held and still count as a tap.
    private static let maxHold: TimeInterval = 0.35
    /// Longest from letting go of one tap to pressing the next.
    private static let maxGap: TimeInterval = 0.3
    /// How long after a double tap to wait for a third before acting on it.
    private static let tripleWait: TimeInterval = 0.3
    private static let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]

    private let onDoubleTap: () -> Void
    private let onTripleTap: () -> Void
    private var timer: Timer?
    private var pressedAt: Date?
    private var isSpoiled = false
    private var tapCount = 0
    private var firstTapAt = Date.distantPast
    private var lastReleaseAt = Date.distantPast

    init(onDoubleTap: @escaping () -> Void, onTripleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
        self.onTripleTap = onTripleTap
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

        if let pressed = pressedAt {
            pressedAt = nil
            tapReleased(pressedAt: pressed, now: now)
        } else if tapCount == 2, now.timeIntervalSince(lastReleaseAt) > Self.tripleWait {
            // No third tap came.
            tapCount = 0
            onDoubleTap()
        }
    }

    private func tapReleased(pressedAt pressed: Date, now: Date) {
        guard !isSpoiled, now.timeIntervalSince(pressed) < Self.maxHold, !somethingPressed(since: pressed, now: now) else {
            tapCount = 0
            return
        }
        let continues = tapCount > 0
            && pressed.timeIntervalSince(lastReleaseAt) < Self.maxGap
            && !somethingPressed(since: firstTapAt, now: now)
        if continues {
            tapCount += 1
        } else {
            tapCount = 1
            firstTapAt = pressed
        }
        lastReleaseAt = now
        if tapCount == 3 {
            tapCount = 0
            onTripleTap()
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
