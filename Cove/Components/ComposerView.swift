import AppKit
import AVFoundation
import Speech
import SwiftUI

struct ComposerView: View {
    @Bindable var store: ChatStore
    @State private var editorHeight: CGFloat = 30
    @State private var isPlusHovered = false
    @State private var isActionHovered = false
    @State private var isDiscardHovered = false
    @State private var pulsingDot = false
    @State private var voiceManager = VoiceInputManager()
    @AppStorage("windowMaterial") private var windowMaterial = "translucent"

    /// On a vibrant window an opaque field reads as a card pasted on top, so the
    /// composer joins the same material instead of fighting it.
    private var isTranslucent: Bool { windowMaterial == "translucent" }
    private var composerShape: RoundedRectangle { RoundedRectangle(cornerRadius: 17, style: .continuous) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if voiceManager.isRecording {
                    recorderContent
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                                removal: .opacity))
                } else {
                    standardComposerContent
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                                removal: .opacity))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                if isTranslucent {
                    composerShape.fill(.regularMaterial)
                        .overlay(composerShape.fill(.primary.opacity(0.03)))
                } else {
                    composerShape.fill(Color.chatCanvas)
                }
            }
            .overlay {
                composerShape.strokeBorder(
                    .primary.opacity(borderOpacity),
                    lineWidth: 0.75
                )
            }
            .shadow(color: .black.opacity(isTranslucent ? 0.06 : 0.035), radius: 8, y: 2)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: voiceManager.isRecording)

            if let error = voiceManager.errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error)
                    Spacer()
                    Button("Dismiss") { voiceManager.errorMessage = nil }
                        .font(.caption2)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 2)
            }
        }
    }

    private var borderOpacity: Double {
        if voiceManager.isRecording { return isTranslucent ? 0.26 : 0.22 }
        if store.draft.isEmpty { return isTranslucent ? 0.13 : 0.09 }
        return isTranslucent ? 0.20 : 0.16
    }

    /// Two rows: the message keeps the full width, and the controls sit on a
    /// toolbar underneath. Attach and model stay on the leading edge, send on the
    /// trailing edge, so a long model name never squeezes the editor.
    private var standardComposerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attachment = store.pendingAttachment {
                attachmentChip(attachment)
            }

            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty {
                    Text("Message…").font(.system(size: 14))
                        .foregroundStyle(.tertiary).padding(.top, 6)
                        .allowsHitTesting(false)
                }
                NativeComposer(text: Binding(get: { store.draft }, set: { store.draft = $0 }),
                               height: $editorHeight, focusRequest: store.focusRequest,
                               onSend: { store.requestSend() })
                    .frame(height: editorHeight)
                    .accessibilityLabel("Message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
            .padding(.top, 2)

            HStack(spacing: 6) {
                attachButton
                ModelPickerButton(store: store)
                    .frame(maxWidth: 200, alignment: .leading)
                Spacer(minLength: 8)
                actionButton
            }
        }
    }

    private var attachButton: some View {
        Button {
            store.attachFileOrImage()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary.opacity(store.canAttach ? (isPlusHovered ? 0.95 : 0.72) : 0.3))
                .frame(width: 28, height: 28)
                .background(.primary.opacity(store.canAttach ? (isPlusHovered ? 0.11 : 0.055) : 0.03), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canAttach)
        .onHover { isPlusHovered = $0 }
        .help(store.modelSupportsVision ? "Attach file or image" : "Attach text/code file (switch to a vision model for images)")
        .accessibilityLabel("Attach file or image")
    }

    private var actionButton: some View {
        Button {
            if store.isGenerating {
                store.stop()
            } else if store.draft.isEmpty {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    voiceManager.startRecording()
                }
            } else {
                store.requestSend()
            }
        } label: {
            Group {
                if store.isGenerating {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.chatCanvas)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.9), in: Circle())
                } else if store.draft.isEmpty {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(isActionHovered ? 0.95 : 0.6))
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(isActionHovered ? 0.10 : 0.05), in: Circle())
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(Color.chatCanvas)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(isActionHovered ? 0.95 : 0.82), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isActionHovered = $0 }
        .help(store.isGenerating ? "Stop · ⌘." : (store.draft.isEmpty ? "Voice input (Right-click to change language)" : "Send · Return"))
        .accessibilityLabel(store.isGenerating ? "Stop generating" : (store.draft.isEmpty ? "Voice input" : "Send message"))
        .contextMenu {
            if !store.isGenerating && store.draft.isEmpty {
                VoiceLanguageMenuItems(voiceManager: voiceManager)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: store.isGenerating)
        .animation(.easeInOut(duration: 0.15), value: store.draft.isEmpty)
    }

    private func attachmentChip(_ attachment: ChatStore.PendingAttachment) -> some View {
        HStack(spacing: 6) {
            if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text(attachment.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                store.removeAttachment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var recorderContent: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    voiceManager.cancelRecording()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(isDiscardHovered ? 0.12 : 0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { isDiscardHovered = $0 }
            .help("Cancel recording · Esc")

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6.5, height: 6.5)
                    .opacity(pulsingDot ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsingDot)
                Text(formattedDuration(voiceManager.duration))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .onAppear { pulsingDot = true }
            .onDisappear { pulsingDot = false }

            AudioWaveformView(level: voiceManager.audioLevel)
                .frame(height: 18)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    let text = voiceManager.stopRecording()
                    if !text.isEmpty {
                        store.draft = store.draft.isEmpty ? text : store.draft + " " + text
                    }
                }
            } label: {
                Group {
                    if voiceManager.transcribedText.isEmpty {
                        Text("Listening…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(voiceManager.transcribedText)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to edit before sending")

            VoiceLanguageMenu(voiceManager: voiceManager)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    let text = voiceManager.stopRecording()
                    if !text.isEmpty {
                        store.draft = store.draft.isEmpty ? text : store.draft + " " + text
                        store.requestSend()
                    }
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Color.chatCanvas)
                    .frame(width: 28, height: 28)
                    .background(
                        .primary.opacity(voiceManager.transcribedText.isEmpty && store.draft.isEmpty ? 0.35 : 0.88),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(voiceManager.transcribedText.isEmpty && store.draft.isEmpty)
            .help("Send voice message · Return")
        }
        .frame(height: 30)
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                voiceManager.cancelRecording()
            }
            return .handled
        }
    }

    private func formattedDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct AudioWaveformView: View {
    let level: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { i in
                WaveBar(index: i, level: level)
            }
        }
    }
}

private struct WaveBar: View {
    let index: Int
    let level: CGFloat

    private var baseFactor: CGFloat {
        let pattern: [CGFloat] = [0.35, 0.55, 0.75, 0.95, 1.0, 0.85, 0.65, 0.8, 1.0, 0.9, 0.75, 0.55, 0.4, 0.3]
        return pattern[index % pattern.count]
    }

    private var height: CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 18
        let dynamic = minH + (maxH - minH) * level * baseFactor
        return max(minH, min(maxH, dynamic))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.65))
            .frame(width: 2, height: height)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: level)
    }
}

final class RequestHolder: @unchecked Sendable {
    var request: SFSpeechAudioBufferRecognitionRequest?
}

@MainActor
@Observable
final class VoiceInputManager: NSObject {
    var isRecording = false
    var transcribedText = ""
    var audioLevel: CGFloat = 0.1
    var duration: TimeInterval = 0
    var errorMessage: String?
    var selectedLocale: Locale

    private var speechRecognizer: SFSpeechRecognizer?
    private let requestHolder = RequestHolder()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var timer: Timer?

    override init() {
        let initial = Self.initialLocale()
        self.selectedLocale = initial
        self.speechRecognizer = SFSpeechRecognizer(locale: initial)
        super.init()
    }

    func setLanguage(_ locale: Locale) {
        selectedLocale = locale
        UserDefaults.standard.set(locale.identifier, forKey: "voiceInputLanguage")
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        if isRecording, let recognizer = speechRecognizer, recognizer.isAvailable {
            recognitionTask?.cancel()
            recognitionTask = nil
            requestHolder.request?.endAudio()

            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.shouldReportPartialResults = true
            requestHolder.request = newRequest
            recognitionRequest = newRequest

            recognitionTask = Self.startRecognitionTask(
                recognizer: recognizer,
                request: newRequest,
                onResult: { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.transcribedText = text
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        let nsError = error as NSError
                        if nsError.code != 216 && nsError.code != 203 {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        }
    }

    static func initialLocale() -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        if let saved = UserDefaults.standard.string(forKey: "voiceInputLanguage"),
           let loc = supported.first(where: { $0.identifier == saved }) {
            return loc
        }
        return suggestedLocales().first ?? supported.first(where: { $0.identifier == "en-US" }) ?? Locale(identifier: "en-US")
    }

    static func suggestedLocales() -> [Locale] {
        let supported = SFSpeechRecognizer.supportedLocales()
        var results: [Locale] = []
        var seen = Set<String>()

        // 1. Exact match for each preferred language
        for pref in Locale.preferredLanguages {
            let normalized = pref.replacingOccurrences(of: "_", with: "-")
            if let exact = supported.first(where: { $0.identifier == normalized }) {
                if seen.insert(exact.identifier).inserted {
                    results.append(exact)
                }
            }
        }

        // 2. Primary dialect for each preferred language
        for pref in Locale.preferredLanguages {
            let langCode = pref.components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? ""
            let defaultDialect: String = {
                switch langCode {
                case "en": return "en-US"
                case "es": return "es-MX"
                case "fr": return "fr-FR"
                case "de": return "de-DE"
                case "it": return "it-IT"
                case "pt": return "pt-BR"
                case "ja": return "ja-JP"
                case "zh": return "zh-CN"
                default: return ""
                }
            }()
            if !defaultDialect.isEmpty, let loc = supported.first(where: { $0.identifier == defaultDialect }) {
                if seen.insert(loc.identifier).inserted {
                    results.append(loc)
                }
            }
        }

        // 3. Popular regional fallbacks
        let popular = ["en-US", "es-MX", "es-ES", "es-419", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP", "zh-CN"]
        for p in popular {
            if let loc = supported.first(where: { $0.identifier == p }), seen.insert(loc.identifier).inserted {
                results.append(loc)
            }
        }

        return results
    }

    static func allSupportedLocales() -> [Locale] {
        let supported = Array(SFSpeechRecognizer.supportedLocales())
        return supported.sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    static func displayName(for locale: Locale) -> String {
        let name = locale.localizedString(forIdentifier: locale.identifier)
            ?? Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
        return name.prefix(1).capitalized + name.dropFirst()
    }

    static func shortCode(for locale: Locale) -> String {
        if #available(macOS 13, *) {
            return (locale.language.languageCode?.identifier ?? "en").uppercased()
        } else {
            return (locale.languageCode ?? "en").uppercased()
        }
    }

    func startRecording() {
        errorMessage = nil
        let recognizer = speechRecognizer ?? SFSpeechRecognizer(locale: selectedLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer for \(Self.displayName(for: selectedLocale)) is not available on this Mac"
            return
        }

        Task { @MainActor in
            let speechStatus = await Self.requestSpeechAuth()
            guard speechStatus == .authorized else {
                if speechStatus == .denied || speechStatus == .restricted {
                    self.errorMessage = "Speech recognition access denied. Enable in System Settings."
                }
                return
            }

            let micGranted = await Self.requestMicrophoneAccess()
            guard micGranted else {
                self.errorMessage = "Microphone access denied. Enable in System Settings."
                return
            }

            self.beginAudioEngine(with: recognizer)
        }
    }

    nonisolated private static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    nonisolated private static func requestMicrophoneAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    nonisolated private static func installAudioTap(
        on inputNode: AVAudioNode,
        format: AVAudioFormat,
        holder: RequestHolder,
        onLevel: @escaping @Sendable (CGFloat) -> Void
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            holder.request?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            let step = max(1, frameLength / 64)
            var count = 0
            for i in stride(from: 0, to: frameLength, by: step) {
                let sample = channelData[i]
                sum += sample * sample
                count += 1
            }
            let rms = sqrt(sum / Float(max(1, count)))
            let level = max(0.08, min(1.0, CGFloat(rms * 14)))
            onLevel(level)
        }
    }

    nonisolated private static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onResult(result.bestTranscription.formattedString)
            }
            if let error {
                onError(error)
            }
        }
    }

    private func beginAudioEngine(with recognizer: SFSpeechRecognizer) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        requestHolder.request = request
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone audio input available"
            return
        }

        Self.installAudioTap(on: inputNode, format: format, holder: requestHolder) { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()

            transcribedText = ""
            duration = 0
            audioLevel = 0.1
            isRecording = true

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.duration += 0.1
                }
            }

            recognitionTask = Self.startRecognitionTask(
                recognizer: recognizer,
                request: request,
                onResult: { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.transcribedText = text
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        let nsError = error as NSError
                        if nsError.code != 216 && nsError.code != 203 {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        } catch {
            errorMessage = "Audio engine error: \(error.localizedDescription)"
            stopRecording()
        }
    }

    @discardableResult
    func stopRecording() -> String {
        timer?.invalidate()
        timer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        requestHolder.request?.endAudio()
        requestHolder.request = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        let final = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return final
    }

    func cancelRecording() {
        _ = stopRecording()
        transcribedText = ""
        duration = 0
        audioLevel = 0.1
    }
}

private struct VoiceLanguageMenuItems: View {
    @Bindable var voiceManager: VoiceInputManager

    var body: some View {
        Section("Suggested") {
            ForEach(VoiceInputManager.suggestedLocales(), id: \.identifier) { locale in
                Button {
                    voiceManager.setLanguage(locale)
                } label: {
                    HStack {
                        Text(VoiceInputManager.displayName(for: locale))
                        if voiceManager.selectedLocale.identifier == locale.identifier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Section("All Languages (\(VoiceInputManager.allSupportedLocales().count))") {
            ForEach(VoiceInputManager.allSupportedLocales(), id: \.identifier) { locale in
                Button {
                    voiceManager.setLanguage(locale)
                } label: {
                    HStack {
                        Text(VoiceInputManager.displayName(for: locale))
                        if voiceManager.selectedLocale.identifier == locale.identifier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

private struct VoiceLanguageMenu: View {
    @Bindable var voiceManager: VoiceInputManager

    var body: some View {
        Menu {
            VoiceLanguageMenuItems(voiceManager: voiceManager)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.system(size: 9.5))
                Text(VoiceInputManager.shortCode(for: voiceManager.selectedLocale))
                    .font(.system(size: 10.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3.5)
            .background(.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Speech language: \(VoiceInputManager.displayName(for: voiceManager.selectedLocale))")
    }
}

