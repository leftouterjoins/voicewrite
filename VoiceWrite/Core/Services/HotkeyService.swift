import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleListening = Self("toggleListening", default: .init(.v, modifiers: [.control]))
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var onToggle: (() -> Void)?

    private init() {}

    func configure(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        KeyboardShortcuts.onKeyDown(for: .toggleListening) { [weak self] in
            self?.onToggle?()
        }
    }

    func updateHandler(_ handler: @escaping () -> Void) {
        self.onToggle = handler
    }
}
