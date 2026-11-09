import Foundation

enum OutputScript: String, CaseIterable, Identifiable {
    case arabic
    case arabizi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arabic: return "Arabic script (عربي)"
        case .arabizi: return "Arabizi (Latin letters)"
        }
    }
}

/// Settings shared between the app and the keyboard. Values are written to both the
/// App Group container and local defaults, so the keyboard still works if the
/// sideloading tool doesn't preserve the App Group entitlement.
final class SharedSettings {
    static let appGroup = "group.com.elshiekhahmed.tarjim"
    static let shared = SharedSettings()

    private let group = UserDefaults(suiteName: SharedSettings.appGroup)
    private let local = UserDefaults.standard

    private func string(_ key: String) -> String? {
        if let value = group?.string(forKey: key), !value.isEmpty { return value }
        if let value = local.string(forKey: key), !value.isEmpty { return value }
        return nil
    }

    private func set(_ value: String, _ key: String) {
        group?.set(value, forKey: key)
        local.set(value, forKey: key)
    }

    var apiKey: String {
        get { string("apiKey") ?? "" }
        set { set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), "apiKey") }
    }

    var model: String {
        get { string("model") ?? Translator.defaultModel }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            set(trimmed.isEmpty ? Translator.defaultModel : trimmed, "model")
        }
    }

    var script: OutputScript {
        get { OutputScript(rawValue: string("script") ?? "") ?? .arabic }
        set { set(newValue.rawValue, "script") }
    }
}
