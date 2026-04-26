import SwiftUI
import Carbon

enum RecordingState: Equatable {
    case recording
}

class OverlayViewModel: ObservableObject {
    @Published var state: RecordingState = .recording
    @Published var levelHistory: [Float] = Array(repeating: 0, count: 15)
    @Published var partialText: String = ""
    @Published var isThinking: Bool = false
    @Published var micNotificationText: String? = nil
    @Published var networkWarningText: String? = nil
    var showPartialText: Bool = true
    private(set) var peakLevel: Float = 0
    private(set) var recordingStartTime: CFAbsoluteTime = 0

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    func updateAudioLevel(_ newLevel: Float) {
        levelHistory.removeFirst()
        levelHistory.append(newLevel)
        if newLevel > peakLevel { peakLevel = newLevel }
    }

    func resetAudio() {
        levelHistory = Array(repeating: 0, count: 15)
        peakLevel = 0
        recordingStartTime = CFAbsoluteTimeGetCurrent()
    }
}

// MARK: - Hotkey Notification

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("com.sayit.hotkeyChanged")
}

// MARK: - Trigger Key

enum TriggerKey: String, CaseIterable, Identifiable {
    case fn = "fn"
    case command = "command"
    case option = "option"
    case control = "control"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn:      return "Fn (🌐)"
        case .command: return "Command (⌘)"
        case .option:  return "Option (⌥)"
        case .control: return "Control (⌃)"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn:      return .function
        case .command: return .command
        case .option:  return .option
        case .control: return .control
        }
    }

    static var current: TriggerKey {
        let raw = UserDefaults.standard.string(forKey: "triggerKey") ?? "fn"
        return TriggerKey(rawValue: raw) ?? .fn
    }
}

// MARK: - Speech Language

enum SpeechLanguage: String, CaseIterable, Identifiable {
    case auto_detect = "auto"
    case chinese     = "zh"
    case english     = "en"
    case japanese    = "ja"
    case korean      = "ko"
    case french      = "fr"
    case german      = "de"
    case spanish     = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto_detect: return "自动检测"
        case .chinese:     return "中文"
        case .english:     return "English"
        case .japanese:    return "日本語"
        case .korean:      return "한국어"
        case .french:      return "Français"
        case .german:      return "Deutsch"
        case .spanish:     return "Español"
        }
    }

    /// Deepgram API 使用的语言代码
    var deepgramCode: String {
        switch self {
        case .auto_detect: return "multi" // Deepgram 多语言模式
        case .chinese:     return "zh-CN"
        case .english:     return "en-US"
        case .japanese:    return "ja"
        case .korean:      return "ko"
        case .french:      return "fr"
        case .german:      return "de"
        case .spanish:     return "es"
        }
    }

    /// whisper.cpp 使用的语言代码
    var whisperCode: String { rawValue }

    static var current: SpeechLanguage {
        let raw = UserDefaults.standard.string(forKey: "speechLanguage") ?? "auto"
        return SpeechLanguage(rawValue: raw) ?? .auto_detect
    }
}

// MARK: - Overlay Position

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottomCenter  = "bottom_center"
    case nearCursor    = "near_cursor"
    case lastPosition  = "last_position"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottomCenter: return "屏幕底部居中"
        case .nearCursor:   return "跟随鼠标"
        case .lastPosition: return "记住上次位置"
        }
    }

    static var current: OverlayPosition {
        let raw = UserDefaults.standard.string(forKey: "overlayPosition") ?? "bottom_center"
        return OverlayPosition(rawValue: raw) ?? .bottomCenter
    }
}
