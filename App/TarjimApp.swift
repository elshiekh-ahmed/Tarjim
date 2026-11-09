import SwiftUI
import UIKit

@main
struct TarjimApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var apiKey: String { didSet { SharedSettings.shared.apiKey = apiKey } }
    @Published var model: String { didSet { SharedSettings.shared.model = model } }
    @Published var script: OutputScript { didSet { SharedSettings.shared.script = script } }

    @Published var input = ""
    @Published var output: TranslationResult?
    @Published var isWorking = false
    @Published var status: String?

    init() {
        let settings = SharedSettings.shared
        apiKey = settings.apiKey
        model = settings.model
        script = settings.script
    }

    func pasteKey() {
        if let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            apiKey = value
        }
    }

    func testKey() {
        run("Hi! How are you all doing?", .toSudanese, showsAsTest: true)
    }

    func translate(_ direction: TranslationDirection) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        run(text, direction, showsAsTest: false)
    }

    private func run(_ text: String, _ direction: TranslationDirection, showsAsTest: Bool) {
        isWorking = true
        status = nil
        Task {
            do {
                let result = try await Translator().translate(text, direction)
                if showsAsTest {
                    status = "✅ Key works: “\(result.translation)”"
                } else {
                    output = result
                }
            } catch {
                status = "⚠️ " + error.localizedDescription
            }
            isWorking = false
        }
    }
}

struct ContentView: View {
    @StateObject private var app = AppModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tarjim is a keyboard that translates between English and Sudanese Arabic inside Messages (or any app).")
                        .font(.callout)
                }

                Section("1 · Free Gemini API key") {
                    Link("Get a free key at Google AI Studio ↗", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    HStack {
                        SecureField("Paste API key", text: $app.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Paste") { app.pasteKey() }
                    }
                    Button("Test key") { app.testKey() }
                        .disabled(app.apiKey.isEmpty || app.isWorking)
                    if let status = app.status {
                        Text(status).font(.footnote)
                    }
                }

                Section("2 · Turn on the keyboard") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Settings › General › Keyboard › Keyboards › Add New Keyboard… › **Tarjim**")
                        Text("2. Tap **Tarjim** › turn on **Allow Full Access** (needed for internet and reading copied text).")
                        Text("3. In Messages, hold the 🌐 key and pick **Tarjim**.")
                    }
                    .font(.footnote)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("How to use") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("**Read their message:** long-press it › Copy › tap **Read copied** on the keyboard.")
                        Text("**Reply:** type in English. The Sudanese Arabic preview (with an English back-translation) appears above the keys. Tap **Insert Arabic** to swap it into the message box, review, then Send. Tap **English** to undo.")
                    }
                    .font(.footnote)
                }

                Section("Options") {
                    Picker("Reply script", selection: $app.script) {
                        ForEach(OutputScript.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("Model")
                        TextField(Translator.defaultModel, text: $app.model)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Quick translator") {
                    TextEditor(text: $app.input)
                        .frame(minHeight: 90)
                        .focused($inputFocused)
                    HStack {
                        Button("→ English") { inputFocused = false; app.translate(.toEnglish) }
                        Spacer()
                        if app.isWorking { ProgressView() }
                        Spacer()
                        Button("→ Sudanese") { inputFocused = false; app.translate(.toSudanese) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(app.input.isEmpty || app.isWorking)
                    if let output = app.output {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(output.translation).textSelection(.enabled)
                            if !output.notes.isEmpty {
                                Text(output.notes).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                        Button("Copy translation") { UIPasteboard.general.string = output.translation }
                    }
                }

                Section {
                    Text("Messages you translate are sent to Google's Gemini API. On the free tier, Google may use this data to improve its products.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tarjim ترجم")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Link(destination: BugReport.url) {
                        Image(systemName: "ladybug")
                    }
                    .accessibilityLabel("Report a bug")
                }
            }
        }
    }
}

enum BugReport {
    static let repo = "elshiekh-ahmed/Tarjim"

    static var environment: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let device = UIDevice.current
        return """
        App: Tarjim \(version) (\(build))
        iOS: \(device.systemName) \(device.systemVersion)
        Device: \(machine)
        Model: \(SharedSettings.shared.model)
        Reply script: \(SharedSettings.shared.script.rawValue)
        """
    }

    static var url: URL {
        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "environment", value: environment),
        ]
        return components.url!
    }
}
