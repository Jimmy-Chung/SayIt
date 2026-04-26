import SwiftUI

// MARK: - Section Enum

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case transcription
    case ai
    case dictionary
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:       return "通用"
        case .transcription: return "转写引擎"
        case .ai:            return "AI 优化"
        case .dictionary:    return "词典"
        case .snippets:      return "快捷片段"
        }
    }

    var iconName: String {
        switch self {
        case .general:       return "gearshape.fill"
        case .transcription: return "waveform"
        case .ai:            return "sparkles"
        case .dictionary:    return "book.fill"
        case .snippets:      return "text.snippet"
        }
    }

    var iconColors: [Color] {
        switch self {
        case .general:       return [Color(red: 1, green: 159/255, blue: 10/255), Color(red: 1, green: 122/255, blue: 0)]
        case .transcription: return [Color(red: 74/255, green: 154/255, blue: 1), Color(red: 36/255, green: 118/255, blue: 238/255)]
        case .ai:            return [Color(red: 191/255, green: 90/255, blue: 242/255), Color(red: 138/255, green: 63/255, blue: 199/255)]
        case .dictionary:    return [Color(red: 52/255, green: 208/255, blue: 88/255), Color(red: 31/255, green: 168/255, blue: 58/255)]
        case .snippets:      return [Color(red: 1, green: 94/255, blue: 94/255), Color(red: 224/255, green: 45/255, blue: 45/255)]
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    @AppStorage("sttEngine") private var sttEngine: String = "local"
    @AppStorage("deepgramApiKey") private var deepgramKey: String = ""
    @AppStorage("openaiWhisperApiKey") private var openaiWhisperKey: String = ""
    @AppStorage("openaiWhisperBaseURL") private var openaiWhisperBaseURL: String = "https://api.openai.com"
    @AppStorage("openaiWhisperModel") private var openaiWhisperModel: String = "whisper-1"

    @AppStorage("selectedLLMProvider") private var selectedProviderRaw: String = LLMProvider.none.rawValue
    @AppStorage("deepseekApiKey") private var deepseekKey: String = ""
    @AppStorage("geminiApiKey")   private var geminiKey: String = ""
    @AppStorage("minimaxApiKey")  private var minimaxKey: String = ""
    @AppStorage("minimaxBaseURL") private var minimaxBaseURL: String = "https://api.minimax.chat"

    @AppStorage("triggerKey") private var triggerKey: String = "fn"

    @AppStorage("soundFeedback") private var soundFeedback: Bool = true
    @AppStorage("voiceCommands") private var voiceCommands: Bool = true
    @AppStorage("speechLanguage") private var speechLanguage: String = "auto"
    @AppStorage("overlayPosition") private var overlayPosition: String = "bottom_center"

    @State private var sttValidationStatus: ValidationStatus = .idle
    @State private var isSttValidating = false
    @State private var isSttKeyVisible = false

    @State private var llmValidationStatus: ValidationStatus = .idle
    @State private var isLlmValidating = false
    @State private var isLlmKeyVisible = false

    @State private var dictEntries: [DictionaryEntry] = UserDictionary.shared.allEntries
    @State private var newDictPhrase = ""
    @State private var newDictReplacements = ""

    @State private var snippetEntries: [Snippet] = SnippetManager.shared.allSnippets
    @State private var newSnippetTrigger = ""
    @State private var newSnippetExpansion = ""

    private var isLlmEnabled: Binding<Bool> {
        Binding(
            get: { selectedProviderRaw != LLMProvider.none.rawValue },
            set: { on in
                selectedProviderRaw = on ? LLMProvider.deepseek.rawValue : LLMProvider.none.rawValue
                llmValidationStatus = .idle
                isLlmKeyVisible = false
            }
        )
    }

    private var selectedProvider: LLMProvider { LLMProvider(rawValue: selectedProviderRaw) ?? .none }

    private var currentLlmKey: Binding<String> {
        switch selectedProvider {
        case .deepseek: return $deepseekKey
        case .gemini:   return $geminiKey
        case .minimax:  return $minimaxKey
        case .none:     return .constant("")
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundLayers

            VStack(spacing: 0) {
                titleBar
                HStack(spacing: 0) {
                    sidebar
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 0.5)
                    panel
                }
            }
        }
        .frame(width: 660, height: 600)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundLayers: some View {
        ZStack {
            Color(red: 32/255, green: 32/255, blue: 40/255)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        ZStack {
            Text("SayIt 设置")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.85))
                .tracking(-0.1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 168, alignment: .top)
        .background(Color.black.opacity(0.12))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        let active = selectedSection == section
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: section.iconColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.black.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                Image(systemName: section.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)

            Text(section.title)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundColor(active ? .white : Color.white.opacity(0.75))

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Group {
                if active {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .overlay(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        )
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSection = section }
    }

    // MARK: - Panel

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(selectedSection.title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundColor(.white)
                    .padding(.bottom, -2)

                switch selectedSection {
                case .general:       generalPanel
                case .transcription: transcriptionPanel
                case .ai:            aiPanel
                case .dictionary:    dictionaryPanel
                case .snippets:      snippetsPanel
                }

                Text("SayIt v0.2.0 (build \(Int(Date().timeIntervalSince1970)))")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.30))
                    .padding(.top, 18)

            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - General Panel

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionCard(label: "快捷键") {
                rowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("语音输入触发键")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.92))
                        Text("按住录音，再按一次结束。录音中按 Esc 取消")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ForEach(TriggerKey.allCases) { key in
                            keycap(label: triggerKeyLabel(key), selected: triggerKey == key.rawValue) {
                                triggerKey = key.rawValue
                                NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                            }
                        }
                    }
                }

                if triggerKey == TriggerKey.fn.rawValue {
                    rowDivider()
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.96, green: 0.726, blue: 0.30))
                        Text("建议在「系统设置 → 键盘」中将「按下 🌐 键时」设为「不执行任何操作」")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.96, green: 0.726, blue: 0.30))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 180/255, blue: 40/255).opacity(0.08))
                }
            }

            sectionCard(label: "反馈与行为") {
                rowContainer {
                    Text("录音音效")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.92))
                    Spacer()
                    GlassToggle(isOn: $soundFeedback)
                }
                rowDivider()
                rowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("语音命令")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.92))
                        Text("「换行」→ 换行符，「句号」→ 。等")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    Spacer()
                    GlassToggle(isOn: $voiceCommands)
                }
            }

            sectionCard(label: "显示") {
                rowContainer {
                    Text("识别语言")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.92))
                    Spacer()
                    Picker("", selection: $speechLanguage) {
                        ForEach(SpeechLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                rowDivider()
                rowContainer {
                    Text("浮窗位置")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.92))
                    Spacer()
                    Picker("", selection: $overlayPosition) {
                        ForEach(OverlayPosition.allCases) { pos in
                            Text(pos.displayName).tag(pos.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }
        }
    }

    private func triggerKeyLabel(_ key: TriggerKey) -> String {
        switch key {
        case .fn:      return "Fn"
        case .command: return "⌘"
        case .option:  return "⌥"
        case .control: return "⌃"
        }
    }

    // MARK: - Transcription Panel

    private var transcriptionPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionCard(label: "引擎选择") {
                radioRow(
                    selected: sttEngine == "local",
                    title: "本地 Whisper",
                    badge: "隐私优先", badgeColor: .green,
                    desc: "使用内置 Whisper 模型，无需网络，数据不离设备"
                ) { sttEngine = "local"; sttValidationStatus = .idle; isSttKeyVisible = false }
                rowDivider()
                radioRow(
                    selected: sttEngine == "deepgram",
                    title: "Deepgram",
                    badge: "云端", badgeColor: .blue,
                    desc: "高精度云端识别，响应更快，需要 API Key"
                ) { sttEngine = "deepgram"; sttValidationStatus = .idle; isSttKeyVisible = false }
                rowDivider()
                radioRow(
                    selected: sttEngine == "openai_whisper",
                    title: "OpenAI Whisper",
                    badge: "云端", badgeColor: .blue,
                    desc: "兼容 OpenAI 接口，支持中转站，可自定义模型"
                ) { sttEngine = "openai_whisper"; sttValidationStatus = .idle; isSttKeyVisible = false }
            }

            if sttEngine == "deepgram" {
                sectionCard(label: "Deepgram 配置") {
                    VStack(alignment: .leading, spacing: 8) {
                        labelText("API Key")
                        apiKeyField(
                            key: $deepgramKey,
                            placeholder: "dg_...",
                            isVisible: $isSttKeyVisible,
                            validationStatus: sttValidationStatus,
                            isValidating: isSttValidating,
                            onValidate: validateSttKey,
                            onKeyChanged: { sttValidationStatus = .idle }
                        )
                    }
                    .padding(14)
                }
            }

            if sttEngine == "openai_whisper" {
                sectionCard(label: "OpenAI Whisper 配置") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            labelText("API Base URL")
                            GlassTextField(text: $openaiWhisperBaseURL, placeholder: "https://api.openai.com")
                                .onChange(of: openaiWhisperBaseURL) { _ in sttValidationStatus = .idle }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            labelText("API Key")
                            apiKeyField(
                                key: $openaiWhisperKey,
                                placeholder: "sk-...",
                                isVisible: $isSttKeyVisible,
                                validationStatus: sttValidationStatus,
                                isValidating: isSttValidating,
                                onValidate: validateOpenAIWhisperKey,
                                onKeyChanged: { sttValidationStatus = .idle }
                            )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            labelText("模型名称")
                            GlassTextField(text: $openaiWhisperModel, placeholder: "whisper-1")
                            Text("支持 whisper-1、whisper-large-v3 等 OpenAI 兼容模型")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func radioRow(selected: Bool, title: String, badge: String, badgeColor: Color, desc: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            radioDot(checked: selected)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.92))
                    pillBadge(badge, color: badgeColor)
                }
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    // MARK: - AI Panel

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionCard(label: "转写优化") {
                rowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用大模型优化转写结果")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.92))
                        Text(selectedProvider != .none
                             ? "语音转写后，AI 自动润色标点和措辞"
                             : "关闭时直接输出原始转写结果")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    Spacer()
                    GlassToggle(isOn: isLlmEnabled)
                }
            }

            if selectedProvider != .none {
                sectionCard(label: "模型提供商") {
                    let providers = LLMProvider.allCases.filter { $0 != .none }
                    ForEach(Array(zip(providers.indices, providers)), id: \.1.rawValue) { index, provider in
                        HStack(spacing: 11) {
                            radioDot(checked: selectedProvider == provider)
                            Text(provider.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.92))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProviderRaw = provider.rawValue
                            llmValidationStatus = .idle
                            isLlmKeyVisible = false
                        }
                        if index < providers.count - 1 { rowDivider() }
                    }
                }

                if selectedProvider == .minimax {
                    sectionCard(label: "MiniMax Base URL") {
                        VStack(alignment: .leading, spacing: 6) {
                            labelText("国内版: https://api.minimax.chat")
                            labelText("国际版: https://api.minimaxi.chat")
                            GlassTextField(text: $minimaxBaseURL, placeholder: "https://api.minimax.chat")
                                .onChange(of: minimaxBaseURL) { _ in llmValidationStatus = .idle }
                        }
                        .padding(14)
                    }
                }

                sectionCard(label: "\(selectedProvider.displayName) API Key") {
                    apiKeyField(
                        key: currentLlmKey,
                        placeholder: selectedProvider.keyPlaceholder,
                        isVisible: $isLlmKeyVisible,
                        validationStatus: llmValidationStatus,
                        isValidating: isLlmValidating,
                        onValidate: validateLlmKey,
                        onKeyChanged: { llmValidationStatus = .idle }
                    )
                    .padding(14)
                }
            }
        }
    }

    // MARK: - Dictionary Panel

    private var dictionaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCard(label: "自定义词典") {
                ForEach(Array(zip(dictEntries.indices, dictEntries)), id: \.1.id) { index, entry in
                    entryRow(
                        leading: entry.phrase,
                        arrow: entry.replacements.isEmpty ? nil : "←",
                        trailing: entry.replacements.joined(separator: ", "),
                        monospaced: false
                    ) {
                        UserDictionary.shared.deleteEntry(id: entry.id)
                        dictEntries = UserDictionary.shared.allEntries
                    }
                    if index < dictEntries.count - 1 { rowDivider() }
                }

                if dictEntries.isEmpty {
                    Text("暂无词条")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(14)
                }

                addRow {
                    GlassTextField(text: $newDictPhrase, placeholder: "正确词汇")
                        .frame(width: 120)
                    GlassTextField(text: $newDictReplacements, placeholder: "误识形式（空格分隔，可选）")
                    GlassPrimaryButton(title: "添加", enabled: !newDictPhrase.trimmingCharacters(in: .whitespaces).isEmpty) {
                        let phrase = newDictPhrase.trimmingCharacters(in: .whitespaces)
                        guard !phrase.isEmpty else { return }
                        let reps = newDictReplacements.split(separator: " ").map(String.init)
                        UserDictionary.shared.addEntry(phrase: phrase, replacements: reps)
                        dictEntries = UserDictionary.shared.allEntries
                        newDictPhrase = ""
                        newDictReplacements = ""
                    }
                }
            }

            Text("添加专有名词，提高 Whisper 识别准确率。可填写常见误识形式帮助纠正。")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Snippets Panel

    private var snippetsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCard(label: "快捷语片段") {
                ForEach(Array(zip(snippetEntries.indices, snippetEntries)), id: \.1.id) { index, snippet in
                    entryRow(
                        leading: snippet.trigger,
                        arrow: "→",
                        trailing: snippet.expansion,
                        monospaced: snippet.expansion.contains("{{")
                    ) {
                        SnippetManager.shared.deleteSnippet(id: snippet.id)
                        snippetEntries = SnippetManager.shared.allSnippets
                    }
                    if index < snippetEntries.count - 1 { rowDivider() }
                }

                if snippetEntries.isEmpty {
                    Text("暂无片段")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(14)
                }

                addRow {
                    GlassTextField(text: $newSnippetTrigger, placeholder: "触发词")
                        .frame(width: 120)
                    GlassTextField(text: $newSnippetExpansion, placeholder: "展开文本")
                    GlassPrimaryButton(
                        title: "添加",
                        enabled: !newSnippetTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                            && !newSnippetExpansion.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        let trig = newSnippetTrigger.trimmingCharacters(in: .whitespaces)
                        let exp = newSnippetExpansion.trimmingCharacters(in: .whitespaces)
                        guard !trig.isEmpty, !exp.isEmpty else { return }
                        SnippetManager.shared.addSnippet(trigger: trig, expansion: exp)
                        snippetEntries = SnippetManager.shared.allSnippets
                        newSnippetTrigger = ""
                        newSnippetExpansion = ""
                    }
                }
            }

            HStack(spacing: 0) {
                Text("支持变量：")
                codeChip("{{clipboard}}")
                Text("、").padding(.horizontal, 1)
                codeChip("{{date}}")
                Text("、").padding(.horizontal, 1)
                codeChip("{{time}}")
            }
            .font(.system(size: 11))
            .foregroundColor(Color.white.opacity(0.4))
            .padding(.horizontal, 4)
        }
    }

    private func codeChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }

    // MARK: - Section card / row helpers

    private func sectionCard<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundColor(Color.white.opacity(0.45))
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func rowContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 46)
    }

    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color.white.opacity(0.6))
    }

    private func radioDot(checked: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? Color(red: 74/255, green: 154/255, blue: 1) : Color.white.opacity(0.3), lineWidth: 1.5)
            if checked {
                Circle()
                    .fill(Color(red: 74/255, green: 154/255, blue: 1))
                    .padding(2)
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 16, height: 16)
        .shadow(color: checked ? Color(red: 74/255, green: 154/255, blue: 1).opacity(0.5) : .clear, radius: 8)
    }

    private func pillBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .foregroundColor(color.lighter(by: 0.20))
            .background(color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func keycap(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? .white : Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [
                                        Color(red: 74/255, green: 154/255, blue: 1).opacity(0.45),
                                        Color(red: 36/255, green: 118/255, blue: 238/255).opacity(0.45)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                ))
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color(red: 120/255, green: 180/255, blue: 1).opacity(0.6), lineWidth: 0.5)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.clear],
                                        startPoint: .top, endPoint: .center
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.clear],
                                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                                    )
                                )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .shadow(color: selected
                ? Color(red: 74/255, green: 154/255, blue: 1).opacity(0.35)
                : .black.opacity(0.30),
                radius: selected ? 12 : 1,
                y: selected ? 0 : 1)
    }

    // MARK: - Entry / add rows

    private func entryRow(leading: String, arrow: String?, trailing: String, monospaced: Bool, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(leading)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            if let arrow = arrow {
                Text(arrow)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.3))
                Text(trailing)
                    .font(.system(size: monospaced ? 11 : 12,
                                  design: monospaced ? .monospaced : .default))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
            DeleteIconButton(action: onDelete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func addRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - API key field

    private func apiKeyField(
        key: Binding<String>,
        placeholder: String,
        isVisible: Binding<Bool>,
        validationStatus: ValidationStatus,
        isValidating: Bool,
        onValidate: @escaping () -> Void,
        onKeyChanged: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                GlassTextField(
                    text: key,
                    placeholder: placeholder,
                    isSecure: !isVisible.wrappedValue,
                    monospaced: true
                )
                .onChange(of: key.wrappedValue) { _ in onKeyChanged() }

                IconButton(systemName: isVisible.wrappedValue ? "eye.slash" : "eye") {
                    isVisible.wrappedValue.toggle()
                }
                GlassButton(
                    title: isValidating ? "验证中…" : "验证",
                    enabled: !key.wrappedValue.isEmpty && !isValidating,
                    action: onValidate
                )
            }

            switch validationStatus {
            case .idle:
                EmptyView()
            case .valid:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Key 有效")
                }
                .font(.system(size: 11))
                .foregroundColor(Color(red: 108/255, green: 224/255, blue: 136/255))
            case .invalid(let msg):
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(msg)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundColor(Color(red: 1, green: 122/255, blue: 110/255))
            }
        }
    }

    // MARK: - Validation actions

    private func validateSttKey() {
        let key = deepgramKey
        guard !key.isEmpty else { return }
        isSttValidating = true
        sttValidationStatus = .idle
        DeepgramTranscriber.validateKey(key: key) { isValid, errorMsg in
            DispatchQueue.main.async {
                isSttValidating = false
                sttValidationStatus = isValid ? .valid : .invalid(errorMsg ?? "验证失败")
            }
        }
    }

    private func validateOpenAIWhisperKey() {
        let key = openaiWhisperKey
        guard !key.isEmpty else { return }
        isSttValidating = true
        sttValidationStatus = .idle
        OpenAIWhisperTranscriber.validateKey(key: key) { isValid, errorMsg in
            DispatchQueue.main.async {
                isSttValidating = false
                sttValidationStatus = isValid ? .valid : .invalid(errorMsg ?? "验证失败")
            }
        }
    }

    private func validateLlmKey() {
        let provider = selectedProvider
        let key = currentLlmKey.wrappedValue
        guard !key.isEmpty else { return }
        isLlmValidating = true
        llmValidationStatus = .idle
        TextOptimizer.shared.validateKey(provider: provider, key: key) { isValid, errorMsg in
            DispatchQueue.main.async {
                isLlmValidating = false
                llmValidationStatus = isValid ? .valid : .invalid(errorMsg ?? "验证失败")
            }
        }
    }
}

// MARK: - Validation Status

private enum ValidationStatus {
    case idle, valid, invalid(String)
}

// MARK: - Glass Toggle (custom, matching design)

private struct GlassToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 52/255, green: 208/255, blue: 88/255),
                                         Color(red: 40/255, green: 176/255, blue: 72/255)],
                                startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.white.opacity(0.15))
                    )
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isOn ? [Color.white.opacity(0.3), Color.clear] : [Color.clear, Color.black.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.1), radius: 0, x: 0, y: -0.5)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .shadow(color: isOn ? Color(red: 52/255, green: 200/255, blue: 89/255).opacity(0.35) : .black.opacity(0.2), radius: isOn ? 12 : 0, y: isOn ? 0 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Text Field

private struct GlassTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var monospaced: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        let font: Font = monospaced
            ? .system(size: 11, design: .monospaced)
            : .system(size: 12)

        Group {
            if isSecure {
                SecureField("", text: $text, prompt: prompt)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(font)
            } else {
                TextField("", text: $text, prompt: prompt)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(font)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    focused
                        ? Color(red: 0, green: 122/255, blue: 1).opacity(0.6)
                        : Color.white.opacity(0.10),
                    lineWidth: focused ? 1 : 0.5
                )
        )
        .shadow(color: focused ? Color(red: 0, green: 122/255, blue: 1).opacity(0.18) : .clear, radius: 3)
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(Color.white.opacity(0.30))
    }
}

// MARK: - Buttons

private struct GlassButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                )
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct GlassPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 74/255, green: 154/255, blue: 1),
                                    Color(red: 36/255, green: 118/255, blue: 238/255)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                    }
                )
                .shadow(color: Color(red: 0, green: 80/255, blue: 200/255).opacity(0.4), radius: 4, y: 1)
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DeleteIconButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(hover ? Color(red: 1, green: 122/255, blue: 110/255) : Color.white.opacity(0.3))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover ? Color(red: 1, green: 80/255, blue: 80/255).opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Color helper

private extension Color {
    func lighter(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        let amt = CGFloat(amount)
        return Color(
            red: Double(min(r + amt, 1)),
            green: Double(min(g + amt, 1)),
            blue: Double(min(b + amt, 1))
        )
    }
}
