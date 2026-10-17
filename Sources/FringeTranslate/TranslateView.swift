import SwiftUI
import FringeCore
import FringeNotch

struct TranslateView: View {
    @ObservedObject var model: TranslateModel
    @ObservedObject var hub: NotchHub
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            languageBar
            inputCard
            resultCard
        }
        .modifier(AppleSessionHost(bridge: model.bridge))
        .onAppear { if hub.focusRequest != model.handledFocusRequest { focusInput() } }
        .onChange(of: hub.focusRequest) { _, _ in focusInput() }
    }

    private func focusInput() {
        model.handledFocusRequest = hub.focusRequest
        // The view may not be in the key window yet on the frame it appears.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            inputFocused = true
        }
    }

    // MARK: Languages

    private var languageBar: some View {
        HStack(spacing: 6) {
            Picker(L10n.text("С языка", "From"), selection: $model.pair.source) {
                Text(L10n.text("Автоопределение", "Detect language")).tag(String?.none)
                Divider()
                ForEach(TranslateLanguage.all) { Text($0.name()).tag(Optional($0.code)) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button { model.swapLanguages() } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Поменять языки местами", "Swap languages"))

            Picker(L10n.text("На язык", "To"), selection: $model.pair.target) {
                ForEach(TranslateLanguage.all) { Text($0.name()).tag($0.code) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
    }

    // MARK: Input

    private var inputCard: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.input)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($inputFocused)
                .padding(.horizontal, 6).padding(.vertical, 8)
                .padding(.trailing, 18)
                // NSTextView turns Esc into completion; close the panel like everywhere else.
                .onKeyPress(.escape) { hub.closePanel(); return .handled }
            if model.input.isEmpty {
                Text(L10n.text("Введите или вставьте текст", "Type or paste text"))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !model.input.isEmpty {
                Button { model.clear(); inputFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                        .padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.text("Очистить", "Clear"))
            }
        }
        .frame(height: 112)
        .fringeCard(highlighted: inputFocused)
    }

    // MARK: Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                resultBody
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fringeCard()
    }

    @ViewBuilder private var resultBody: some View {
        if let failure = model.failure {
            Label {
                Text(failure.message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else if let output = model.output {
            Text(output.text)
                .font(.system(size: 13)).foregroundStyle(.white.opacity(model.isTranslating ? 0.55 : 1))
                .textSelection(.enabled)
        } else {
            Text(L10n.text("Перевод появится здесь", "The translation appears here"))
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.35))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let output = model.output, model.failure == nil {
                Text(sourceLine(output))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
                    .help(output.googleFailure?.message ?? "")
            }
            Spacer(minLength: 0)
            if model.isTranslating { ProgressView().controlSize(.mini) }
            Button(model.copied ? L10n.text("Скопировано", "Copied") : L10n.text("Копировать", "Copy")) { model.copyResult() }
                .buttonStyle(FringeButtonStyle(prominent: false))
                .disabled(model.output == nil || model.failure != nil)
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    private func sourceLine(_ output: TranslationOutput) -> String {
        var parts = [output.engine.title]
        if output.googleFailure != nil { parts[0] += L10n.text(" (Google недоступен)", " (Google unavailable)") }
        if let detected = output.detectedSource {
            parts.append(L10n.text("Определён: ", "Detected: ") + TranslateLanguage.displayName(for: detected))
        }
        return parts.joined(separator: " · ")
    }
}

struct TranslateSettingsView: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        Toggle(L10n.text("Подставлять текст из буфера обмена при открытии", "Fill in clipboard text when the tab opens"),
               isOn: $model.settings.prefillFromClipboard)
        Text(L10n.text("macOS может спросить разрешение на чтение буфера обмена.", "macOS may ask for permission to read the clipboard."))
            .font(.caption).foregroundStyle(.secondary)
        Picker(L10n.text("Движок перевода", "Translation engine"), selection: $model.settings.engine) {
            ForEach(TranslateEngine.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(L10n.text(
            "Google: текст для перевода отправляется в Google через неофициальный бесплатный адрес, который Google может ограничить без предупреждения. Если Google недоступен, перевод делает Apple офлайн.\nApple: перевод на этом Mac без сети. Языки нужно скачать: Системные настройки → Основные → Язык и регион → Языки перевода.",
            "Google: the text you translate is sent to Google through an unofficial free endpoint that Google may limit without notice. If Google is unavailable, Apple translates offline instead.\nApple: translation on this Mac without a network. Download languages in System Settings → General → Language & Region → Translation Languages."))
            .font(.caption).foregroundStyle(.secondary)
    }
}
