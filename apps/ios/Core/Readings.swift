import Foundation

public struct ReadingToken: Equatable, Sendable {
    public let text: String
    public let reading: String?
    public init(text: String, reading: String?) {
        self.text = text
        self.reading = reading
    }
}

/// Optional pronunciation help for scripts a learner cannot yet sound out.
/// Readings come from the system's word dictionary and are never learning evidence.
public enum Readings {
    /// Splits text on the locale's word boundaries, attaching a Latin reading to each
    /// word that needs one. Punctuation, spacing and unrecognized characters are
    /// returned exactly as supplied.
    public static func tokens(_ text: String, locale: String) -> [ReadingToken] {
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        let tokenizer = CFStringTokenizerCreate(nil, text as CFString,
            CFRange(location: 0, length: source.length), kCFStringTokenizerUnitWord,
            CFLocaleCreate(nil, CFLocaleIdentifier(locale as CFString)))!
        var result: [ReadingToken] = []
        var cursor = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location >= cursor, range.length > 0, range.location + range.length <= source.length else { continue }
            if range.location > cursor {
                result.append(.init(text: source.substring(with: NSRange(location: cursor, length: range.location - cursor)), reading: nil))
            }
            let word = source.substring(with: NSRange(location: range.location, length: range.length))
            var transcription: String?
            if needsReading(word), let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                let normalized = latin.lowercased().precomposedStringWithCanonicalMapping
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty && !needsReading(normalized) { transcription = normalized }
            }
            if let spoken = spokenExceptions[word] { transcription = spoken }
            result.append(.init(text: word, reading: transcription))
            cursor = range.location + range.length
        }
        if cursor < source.length {
            result.append(.init(text: source.substring(from: cursor), reading: nil))
        }
        return result
    }

    /// A separate reading aid; source text and learning evidence are never replaced.
    public static func reading(_ text: String, locale: String) -> String? {
        let parts = tokens(text, locale: locale)
        guard parts.contains(where: { $0.reading != nil }) else { return nil }
        var result = ""
        for part in parts {
            let value = part.reading ?? part.text
            if let last = result.last, let first = value.first,
               (last.isLetter || last.isNumber), (first.isLetter || first.isNumber) {
                result.append(" ")
            }
            result.append(value)
        }
        return result
    }

    /// The system transcription spells kana as written. For a few very common
    /// Japanese words the spelling and the pronunciation differ: the particles は, を
    /// and へ, and two fixed greetings that end in a particle. Everything else keeps
    /// the dictionary reading, which is a sounding-out aid rather than a pronunciation
    /// guide: kanji with more than one reading, long vowels and pitch accent still
    /// need a listening check.
    private static let spokenExceptions = [
        "は": "wa", "を": "o", "へ": "e",
        "こんにちは": "konnichiwa", "こんばんは": "konbanwa"
    ]

    /// Reading help applies to scripts that do not map to sound letter by letter:
    /// Han characters, and the Japanese kana written alongside them.
    static func needsReading(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x20000...0x2FA1F, 0x30000...0x3347F,
                 0x3040...0x309F, 0x30A0...0x30FF: true
            default: false
            }
        }
    }
}

public struct CaptionSegment: Equatable, Sendable {
    public let text: String
    public let lookup: String?
}

public enum CaptionWords {
    /// Keeps every source character, linking individual words rather than whole
    /// sentences. Scripts written without spaces are split by the module's locale.
    public static func segments(_ text: String, languageID: String) -> [CaptionSegment] {
        if let locale = LanguageRegistry.module(for: languageID)?.wordSegmentationLocale {
            return Readings.tokens(text, locale: locale).map {
                CaptionSegment(text: $0.text, lookup: $0.text.contains(where: \.isLetter) ? $0.text : nil)
            }
        }
        var result: [CaptionSegment] = []
        var run = ""
        for character in text {
            if let last = run.last, last.isWhitespace != character.isWhitespace {
                result.append(segment(run)); run = ""
            }
            run.append(character)
        }
        if !run.isEmpty { result.append(segment(run)) }
        return result
    }

    private static func segment(_ text: String) -> CaptionSegment {
        let word = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return CaptionSegment(text: text, lookup: word.contains(where: \.isLetter) ? word : nil)
    }
}
