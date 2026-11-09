import SwiftUI
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    enum Layer { case letters, numbers, symbols }

    enum Panel: Equatable {
        case compose
        case reading(original: String, result: TranslationResult?)
    }

    @Published var layer: Layer = .letters
    @Published var shift = true
    @Published var capsLock = false
    @Published var panel: Panel = .compose
    @Published var preview: TranslationResult?
    @Published var isLoading = false
    @Published var isReading = false
    @Published var errorMessage: String?
    @Published var hasApiKey = false
    @Published var canUndo = false
    @Published var notice: String?

    private weak var controller: KeyboardViewController?
    private var previewTask: Task<Void, Never>?
    private var previewSource = ""
    private var requestID = 0
    private var readID = 0
    private var undoText: String?
    private var lastInserted: String?
    private var lastSpaceTime: Date?
    private var lastShiftTime: Date?
    private var deleteTimer: Timer?

    init(controller: KeyboardViewController) {
        self.controller = controller
        reloadSettings()
    }

    var hasFullAccess: Bool { controller?.hasFullAccess ?? false }
    var needsGlobe: Bool { controller?.needsInputModeSwitchKey ?? true }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    private var fullText: String {
        guard let proxy else { return "" }
        return (proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? "")
    }

    func reloadSettings() {
        hasApiKey = !SharedSettings.shared.apiKey.isEmpty
    }

    // MARK: Typing

    func type(_ text: String) {
        let output: String
        if layer == .letters && (shift || capsLock) {
            output = text.uppercased()
        } else {
            output = text
        }
        proxy?.insertText(output)
        if shift && !capsLock { shift = false }
        afterEdit()
    }

    func space() {
        let now = Date()
        if let last = lastSpaceTime, now.timeIntervalSince(last) < 0.4,
           let before = proxy?.documentContextBeforeInput, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            proxy?.deleteBackward()
            proxy?.insertText(". ")
            lastSpaceTime = nil
        } else {
            proxy?.insertText(" ")
            lastSpaceTime = now
        }
        afterEdit()
    }

    func newline() {
        proxy?.insertText("\n")
        afterEdit()
    }

    func deleteBackward() {
        proxy?.deleteBackward()
        afterEdit()
    }

    func startDeleteRepeat() {
        deleteBackward()
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.deleteBackward() }
                }
            }
        }
    }

    func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    func toggleShift() {
        let now = Date()
        defer { lastShiftTime = now }
        if capsLock {
            capsLock = false
            shift = false
        } else if shift, let last = lastShiftTime, now.timeIntervalSince(last) < 0.35 {
            capsLock = true
        } else {
            shift.toggle()
        }
    }

    func switchKeyboard() {
        controller?.advanceToNextInputMode()
    }

    func dismissKeyboard() {
        controller?.dismissKeyboard()
    }

    private func afterEdit() {
        updateAutoShift()
        schedulePreview()
    }

    private func updateAutoShift() {
        guard !capsLock, layer == .letters else { return }
        let before = proxy?.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        shift = trimmed.isEmpty || before.hasSuffix("\n") ||
            ((trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!")) && before.hasSuffix(" "))
    }

    // MARK: Live preview (English -> Sudanese)

    func documentChanged() {
        updateAutoShift()
        schedulePreview()
    }

    private func schedulePreview() {
        let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            previewTask?.cancel()
            requestID += 1
            preview = nil
            previewSource = ""
            isLoading = false
            if lastInserted != nil { lastInserted = nil; canUndo = false; undoText = nil }
            return
        }
        guard text != previewSource else { return }
        if let lastInserted, text == lastInserted.trimmingCharacters(in: .whitespacesAndNewlines) { return }
        if Self.containsArabic(text) { return }
        guard hasApiKey, hasFullAccess else { return }

        if canUndo {
            canUndo = false
            undoText = nil
            lastInserted = nil
        }

        previewTask?.cancel()
        requestID += 1
        let id = requestID
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.runPreview(text, id: id)
        }
    }

    private func runPreview(_ text: String, id: Int) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Translator().translate(text, .toSudanese)
            guard id == requestID else { return }
            previewSource = text
            preview = result
        } catch {
            guard id == requestID, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            errorMessage = error.localizedDescription
        }
        if id == requestID { isLoading = false }
    }

    /// Replaces the English text in the message field with the Sudanese Arabic translation.
    func insertTranslation() {
        guard checkReady() else { return }
        let english = fullText
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            notice = "Type your message in English first."
            return
        }
        if let preview, previewSource == trimmed {
            replaceDocument(with: preview.translation, original: english)
            return
        }
        previewTask?.cancel()
        requestID += 1
        let id = requestID
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await Translator().translate(trimmed, .toSudanese)
                guard id == requestID else { return }
                previewSource = trimmed
                preview = result
                isLoading = false
                replaceDocument(with: result.translation, original: english)
            } catch {
                guard id == requestID else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func undoInsert() {
        guard let undoText else { return }
        lastInserted = nil
        canUndo = false
        self.undoText = nil
        setDocumentText(undoText)
    }

    private func replaceDocument(with text: String, original: String) {
        undoText = original
        lastInserted = text
        canUndo = true
        setDocumentText(text)
        notice = "Inserted. Review it, then tap Send."
    }

    private func setDocumentText(_ text: String) {
        guard let proxy else { return }
        if let after = proxy.documentContextAfterInput, !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        for _ in 0..<30 {
            guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { break }
            for _ in 0..<before.count { proxy.deleteBackward() }
        }
        proxy.insertText(text)
    }

    // MARK: Reading (clipboard -> English)

    func translateClipboard() {
        guard checkReady() else { return }
        guard let copied = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !copied.isEmpty else {
            notice = "Long-press their message, tap Copy, then tap this again."
            return
        }
        panel = .reading(original: copied, result: nil)
        isReading = true
        errorMessage = nil
        readID += 1
        let id = readID
        Task {
            do {
                let result = try await Translator().translate(copied, .toEnglish)
                guard id == readID else { return }
                panel = .reading(original: copied, result: result)
            } catch {
                guard id == readID else { return }
                errorMessage = error.localizedDescription
            }
            if id == readID { isReading = false }
        }
    }

    func closeReading() {
        readID += 1
        isReading = false
        errorMessage = nil
        panel = .compose
        previewSource = ""
        schedulePreview()
    }

    // MARK: Setup helpers

    func pasteApiKey() {
        guard hasFullAccess else {
            notice = "Turn on Full Access first (see the Tarjim app)."
            return
        }
        guard let key = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), key.count > 20, !key.contains(" ") else {
            notice = "Copy your Gemini API key first, then tap Paste key."
            return
        }
        SharedSettings.shared.apiKey = key
        reloadSettings()
        notice = "API key saved."
        schedulePreview()
    }

    private func checkReady() -> Bool {
        notice = nil
        reloadSettings()
        if !hasFullAccess {
            errorMessage = "Turn on Full Access: Settings › General › Keyboard › Keyboards › Tarjim."
            return false
        }
        if !hasApiKey {
            errorMessage = TranslatorError.missingKey.errorDescription
            return false
        }
        return true
    }

    static func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value) }
    }
}
