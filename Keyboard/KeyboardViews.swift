import SwiftUI
import UIKit

private extension Color {
    static let keyFace = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    static let specialKeyFace = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1) })
    static let panelFace = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.97, alpha: 1) })
    static let brand = Color(red: 0, green: 0.48, blue: 0.24)
}

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            TranslationPanel(model: model)
                .frame(height: KeyboardMetrics.panelHeight)
            KeysView(model: model)
        }
        .padding(.horizontal, 3)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

// MARK: - Translation panel

struct TranslationPanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if case .reading = model.panel {
                PillButton(title: "Done", systemImage: "chevron.down", prominent: false) { model.closeReading() }
                Spacer(minLength: 0)
                PillButton(title: "Translate copied", systemImage: "doc.on.clipboard", prominent: false) { model.translateClipboard() }
            } else {
                PillButton(title: "Read copied", systemImage: "doc.on.clipboard", prominent: false) { model.translateClipboard() }
                Spacer(minLength: 0)
                if model.canUndo {
                    PillButton(title: "English", systemImage: "arrow.uturn.backward", prominent: false) { model.undoInsert() }
                }
                PillButton(title: "Insert Arabic", systemImage: "character.bubble", prominent: true) { model.insertTranslation() }
            }
        }
        .frame(height: 30)
    }

    private var content: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10).fill(Color.panelFace)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    panelText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            if model.isLoading || model.isReading {
                ProgressView().padding(8)
            }
        }
    }

    @ViewBuilder
    private var panelText: some View {
        if let error = model.errorMessage {
            Text(error).font(.footnote).foregroundColor(.red)
            if !model.hasApiKey && model.hasFullAccess {
                Button("Paste key from clipboard") { model.pasteApiKey() }.font(.footnote.bold())
            }
        } else if let notice = model.notice, model.preview == nil, model.panel == .compose {
            Text(notice).font(.footnote).foregroundColor(.secondary)
        } else if !model.hasFullAccess {
            Text("Turn on Full Access to translate: Settings › General › Keyboard › Keyboards › Tarjim › Allow Full Access.")
                .font(.footnote).foregroundColor(.secondary)
        } else if !model.hasApiKey {
            Text("No Gemini API key yet. Copy your key, then tap below (or add it in the Tarjim app).")
                .font(.footnote).foregroundColor(.secondary)
            Button("Paste key from clipboard") { model.pasteApiKey() }.font(.footnote.bold())
        } else if case .reading(let original, let result) = model.panel {
            if let result {
                Text(result.translation).font(.body)
                if !result.notes.isEmpty {
                    Text(result.notes).font(.caption).foregroundColor(.secondary)
                }
            } else {
                Text(original).font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        } else if let preview = model.preview {
            Text(preview.translation)
                .font(.system(size: 18))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
            if !preview.notes.isEmpty {
                Text("“\(preview.notes)”").font(.caption).foregroundColor(.secondary)
            }
            if let notice = model.notice {
                Text(notice).font(.caption2).foregroundColor(.brand)
            }
        } else {
            Text("Type in English — the Sudanese Arabic preview shows here. To read their message: long-press it › Copy › Read copied.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

struct PillButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .foregroundColor(prominent ? .white : .primary)
                .background(Capsule().fill(prominent ? Color.brand : Color.keyFace))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keys

struct KeysView: View {
    @ObservedObject var model: KeyboardModel

    private let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private let numberRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    private let symbolRows = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let unit = (geo.size.width - spacing * 9) / 10
            VStack(spacing: KeyboardMetrics.rowSpacing) {
                let rows = currentRows
                row(rows[0], unit: unit, spacing: spacing)
                row(rows[1], unit: unit, spacing: spacing)
                HStack(spacing: spacing) {
                    leftModifierKey(width: unit * 1.35)
                    Spacer(minLength: 0)
                    ForEach(rows[2], id: \.self) { key in
                        CharacterKey(label: display(key), width: model.layer == .letters ? unit : unit * 1.32) { model.type(key) }
                    }
                    Spacer(minLength: 0)
                    DeleteKey(model: model, width: unit * 1.35)
                }
                HStack(spacing: spacing) {
                    SpecialKey(label: model.layer == .letters ? "123" : "ABC", width: unit * 1.25) {
                        model.layer = model.layer == .letters ? .numbers : .letters
                    }
                    if model.needsGlobe {
                        SpecialKey(systemImage: "globe", width: unit * 1.1) { model.switchKeyboard() }
                    }
                    CharacterKey(label: "space", width: nil) { model.space() }
                    SpecialKey(label: "return", width: unit * 2.1) { model.newline() }
                }
            }
        }
        .frame(height: KeyboardMetrics.keyHeight * 4 + KeyboardMetrics.rowSpacing * 3)
    }

    private var currentRows: [[String]] {
        switch model.layer {
        case .letters: return letterRows
        case .numbers: return numberRows
        case .symbols: return symbolRows
        }
    }

    private func display(_ key: String) -> String {
        model.layer == .letters && (model.shift || model.capsLock) ? key.uppercased() : key
    }

    private func row(_ keys: [String], unit: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys, id: \.self) { key in
                CharacterKey(label: display(key), width: unit) { model.type(key) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func leftModifierKey(width: CGFloat) -> some View {
        switch model.layer {
        case .letters:
            ShiftKey(model: model, width: width)
        case .numbers:
            SpecialKey(label: "#+=", width: width) { model.layer = .symbols }
        case .symbols:
            SpecialKey(label: "123", width: width) { model.layer = .numbers }
        }
    }
}

struct KeyFace<Content: View>: View {
    let special: Bool
    let width: CGFloat?
    let pressed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: width == nil ? .infinity : width, minHeight: KeyboardMetrics.keyHeight, maxHeight: KeyboardMetrics.keyHeight)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(pressed ? (special ? Color.keyFace : Color.specialKeyFace) : (special ? Color.specialKeyFace : Color.keyFace))
                    .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
            )
            .foregroundColor(.primary)
            .contentShape(Rectangle())
    }
}

struct KeyPressStyle: ButtonStyle {
    let special: Bool
    let width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(special: special, width: width, pressed: configuration.isPressed) { configuration.label }
    }
}

struct CharacterKey: View {
    let label: String
    let width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: label.count > 1 ? 16 : 22))
        }
        .buttonStyle(KeyPressStyle(special: false, width: width))
    }
}

struct SpecialKey: View {
    var label: String? = nil
    var systemImage: String? = nil
    let width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 18))
            } else {
                Text(label ?? "").font(.system(size: 16))
            }
        }
        .buttonStyle(KeyPressStyle(special: true, width: width))
    }
}

struct ShiftKey: View {
    @ObservedObject var model: KeyboardModel
    let width: CGFloat

    var body: some View {
        KeyFace(special: !(model.shift || model.capsLock), width: width, pressed: false) {
            Image(systemName: model.capsLock ? "capslock.fill" : (model.shift ? "shift.fill" : "shift"))
                .font(.system(size: 18))
        }
        .onTapGesture { model.toggleShift() }
    }
}

struct DeleteKey: View {
    @ObservedObject var model: KeyboardModel
    let width: CGFloat
    @State private var pressed = false

    var body: some View {
        KeyFace(special: true, width: width, pressed: pressed) {
            Image(systemName: pressed ? "delete.left.fill" : "delete.left").font(.system(size: 18))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        model.startDeleteRepeat()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    model.stopDeleteRepeat()
                }
        )
    }
}
