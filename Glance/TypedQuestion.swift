import AppKit
import ApplicationServices

/// After a triple tap of ⌘, catches what you type (the front app never sees it)
/// until Return, then hands the text over. Esc or a click cancels. Uses an event
/// tap, which needs the same Accessibility permission as the rest of Glance.
@MainActor
final class TypedQuestion {
    private(set) var isListening = false

    /// Stops listening after this long without a key, so typing can't stay swallowed.
    private static let idleLimit: TimeInterval = 30
    private static let returnKey: Int64 = 36
    private static let enterKey: Int64 = 76
    private static let escapeKey: Int64 = 53
    private static let deleteKey: Int64 = 51

    private let onQuestion: (String) -> Void
    private let onListeningChanged: (Bool) -> Void
    private var text = ""
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var idleTimer: Timer?

    init(onQuestion: @escaping (String) -> Void, onListeningChanged: @escaping (Bool) -> Void) {
        self.onQuestion = onQuestion
        self.onListeningChanged = onListeningChanged
    }

    /// Returns false until Glance is allowed in Accessibility, which macOS asks for here.
    func start() -> Bool {
        guard !isListening else { return true }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }

        let types: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<TypedQuestion>.fromOpaque(info).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { listener.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        text = ""
        isListening = true
        restartIdleTimer()
        onListeningChanged(true)
        return true
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        text = ""
        idleTimer?.invalidate()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        onListeningChanged(false)
    }

    /// Returns true to keep the event from reaching the front app.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            stop()
            return false
        case .keyUp:
            return true
        case .keyDown:
            break
        default:
            return false
        }

        restartIdleTimer()
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Self.returnKey, Self.enterKey:
            let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
            stop()
            if !question.isEmpty { onQuestion(question) }
        case Self.escapeKey:
            stop()
        case Self.deleteKey:
            if !text.isEmpty { text.removeLast() }
        default:
            // Skip shortcuts, and arrow/function keys (control or private-use characters).
            guard event.flags.isDisjoint(with: [.maskCommand, .maskControl]),
                  let characters = NSEvent(cgEvent: event)?.characters
            else { break }
            text += characters.filter { character in
                character.unicodeScalars.allSatisfy { scalar in
                    !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
                }
            }
        }
        return true
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }
}
