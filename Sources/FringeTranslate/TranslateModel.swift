import AppKit
import Combine
import FringeCore

extension Translator {
    /// Google over the network, Apple Translation on device.
    static func live(bridge: AppleSessionBridge) -> Translator {
        Translator(
            google: { text, source, target throws(TranslateError) in
                try await GoogleTranslateAPI.translate(text: text, source: source, target: target, fetch: GoogleTranslateAPI.liveFetch)
            },
            apple: { text, source, target throws(TranslateError) in
                try await AppleTranslate.translate(text: text, source: source, target: target, bridge: bridge)
            })
    }
}

/// The tab's state. Owned by the module so the text and result survive closing the panel.
@MainActor final class TranslateModel: ObservableObject {
    static let debounce = Duration.milliseconds(400)

    @Published var input = "" {
        didSet { if input != oldValue, !applyingBatch { schedule(after: Self.debounce) } }
    }
    @Published var pair: LanguagePair {
        didSet {
            guard pair != oldValue else { return }
            pair.save(to: defaults)
            if !applyingBatch { schedule(after: .zero) }
        }
    }
    @Published var settings: TranslateSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            if settings.engine != oldValue.engine { schedule(after: .zero) }
        }
    }
    @Published private(set) var output: TranslationOutput?
    @Published private(set) var failure: TranslationFailure?
    @Published private(set) var isTranslating = false
    @Published private(set) var copied = false

    let bridge = AppleSessionBridge()
    /// The last `hub.focusRequest` the view acted on.
    var handledFocusRequest = 0

    private let defaults: UserDefaults
    private var translator: Translator!
    private var task: Task<Void, Never>?
    private var copiedTask: Task<Void, Never>?
    private var applyingBatch = false
    /// Requests run only while the tab is on screen; a change made in Settings waits for the next open.
    private var visible = false
    private var lastPasteboardChange: Int?
    /// What the shown result (or error) was produced for.
    private var completedKey: RequestKey?

    private struct RequestKey: Equatable {
        let text: String
        let pair: LanguagePair
        let engine: TranslateEngine
    }

    init(defaults: UserDefaults = .standard, makeTranslator: (AppleSessionBridge) -> Translator = Translator.live) {
        self.defaults = defaults
        pair = LanguagePair.load(from: defaults)
        settings = TranslateSettings.load(from: defaults)
        translator = makeTranslator(bridge)
    }

    private var currentKey: RequestKey {
        RequestKey(text: input.trimmingCharacters(in: .whitespacesAndNewlines), pair: pair, engine: settings.engine)
    }

    /// Debounced translation; a newer call cancels the waiting or running one.
    func schedule(after delay: Duration) {
        task?.cancel()
        let key = currentKey
        guard !key.text.isEmpty else {
            isTranslating = false; output = nil; failure = nil; completedKey = nil
            return
        }
        guard visible else { return }
        let translator = translator!
        task = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
            }
            self?.isTranslating = true
            let result = await translator.translate(key.text, pair: key.pair, engine: key.engine)
            guard !Task.isCancelled, let self else { return }
            self.isTranslating = false
            switch result {
            case .success(let value):
                self.output = value; self.failure = nil
            case .failure(let error):
                if error.primary == .cancelled { return }
                self.output = nil; self.failure = error
            }
            self.completedKey = key
        }
    }

    func swapLanguages() {
        let swapped = pair.swapped(detected: output?.detectedSource)
        applyingBatch = true
        pair = swapped
        if let output { input = output.text }
        applyingBatch = false
        schedule(after: .zero)
    }

    func clear() { input = "" }

    func copyResult() {
        guard let output else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output.text, forType: .string)
        // Our own copy is not offered back as input next time.
        lastPasteboardChange = pasteboard.changeCount
        copied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { self?.copied = false }
        }
    }

    func becameVisible() {
        visible = true
        prefillFromClipboard()
        if currentKey != completedKey || failure != nil { schedule(after: .zero) }
    }

    func becameHidden() {
        visible = false
        task?.cancel()
        isTranslating = false
    }

    /// Takes the clipboard text once per clipboard change, so edits are not overwritten on every open.
    private func prefillFromClipboard() {
        guard settings.prefillFromClipboard else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChange else { return }
        lastPasteboardChange = pasteboard.changeCount
        // The user denied pasteboard access to Fringe in System Settings; do not ask again.
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        applyingBatch = true
        input = text
        applyingBatch = false
    }
}
