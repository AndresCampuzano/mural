import Foundation

/// A target language's content and teaching policy. IDs are stable storage keys.
public struct LanguageModule: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nativeName: String
    public let variety: String
    public let locale: String
    public let greeting: String
    public let greetingWord: String
    public let speechGuidance: String
    public let writingGuidance: String
    public let lemmaGuidance: String
    public let teachingFocus: [String]
    public let topicPlaceholder: String
    public let lookupUnavailableReply: String
    public let themeOverrides: [String: ConversationTheme]
    /// Locale used to find word boundaries in a script written without spaces.
    /// `nil` splits on whitespace, which is correct for Hangul and for Latin scripts.
    public var wordSegmentationLocale: String? = nil
    /// Name of the optional reading aid offered under target text, such as "romaji".
    /// `nil` hides the control entirely.
    public var readingAidName: String? = nil
    /// Unicode ranges this language's own script occupies, used to find its phrases inside a
    /// sentence that also carries the learner's own language. A module written in the same
    /// script as the learner reads — Latin beside English, say — cannot be separated this way
    /// and needs a different strategy before it is registered.
    public var scriptRanges: [ClosedRange<UInt32>] = []

    public var themes: [ConversationTheme] {
        ConversationTheme.shared.map { themeOverrides[$0.id] ?? $0 }
    }
    public var defaultTitle: String { "A little \(name)" }
    public var talkTitle: String { "A little everyday \(name)" }
    public var settingsTitle: String { "\(name) · \(variety)" }
}

public enum LanguageRegistry {
    public static let defaultID = "ko"
    public static let all: [LanguageModule] = [.korean, .japanese]
    public static func module(for id: String) -> LanguageModule? { all.first { $0.id == id } }
}

public enum MeaningLanguages {
    public static let all = ["English", "Spanish", "French", "German", "Portuguese", "Italian", "Chinese (Simplified)", "Polish", "Arabic", "Ukrainian"]
    public static func greeting(in language: String) -> String {
        ["English": "Hi!", "French": "Salut !", "German": "Hallo!", "Spanish": "¡Hola!", "Portuguese": "Olá!", "Italian": "Ciao!", "Chinese (Simplified)": "你好！", "Chinese": "你好！", "Polish": "Cześć!", "Arabic": "مرحبًا!", "Ukrainian": "Привіт!"][language] ?? "Hi!"
    }
}
