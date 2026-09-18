import Foundation

/// A phrase the learner chose to keep, with the meaning it had when they kept it.
///
/// This list is a notebook, not evidence. Saving a phrase says the learner wants to see it
/// again; it says nothing about whether they can produce it, so `LearningEngine` never reads
/// this and no recall bar comes from it.
public struct SavedPhrase: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let languageID: String
    public var text: String
    /// Empty until the meaning arrives, so saving never waits on the network.
    public var meaning: String
    public var meaningLanguage: String
    /// The line it was taken from, kept so the phrase can be read in context later.
    public var source: String
    public var savedAt = Date()
    public init(languageID: String, text: String, meaning: String = "", meaningLanguage: String, source: String = "") {
        self.languageID = languageID
        self.text = String(text.prefix(SavedPhrase.maximumLength))
        self.meaning = String(meaning.prefix(300))
        self.meaningLanguage = meaningLanguage
        self.source = String(source.prefix(500))
    }
    public static let maximumLength = 200
    /// Matching is by language and text, so the same phrase is never kept twice.
    public var key: String { languageID + "|" + SavedPhrase.normalize(text) }
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Finds the target-language phrases inside a line that may also carry the learner's own
/// language, so they can be offered for saving.
public enum Phrases {
    /// Kept small deliberately: the chooser sits under a caption on a phone screen.
    public static let maximumPerLine = 6

    public static func candidates(in text: String, language: LanguageModule) -> [String] {
        guard !language.scriptRanges.isEmpty else { return [] }
        var found: [String] = []
        var seen = Set<String>()
        var run = ""
        var pending = ""

        func end() {
            let phrase = trimmed(run)
            run = ""; pending = ""
            guard !phrase.isEmpty, phrase.contains(where: { belongs($0, to: language) }),
                  seen.insert(SavedPhrase.normalize(phrase)).inserted else { return }
            found.append(String(phrase.prefix(SavedPhrase.maximumLength)))
        }

        for character in text {
            if belongs(character, to: language) {
                // A space between two target words belongs to the phrase; one before the
                // learner's own language does not, which is why it waits here first.
                run += pending; pending = ""
                run.append(character)
            } else if character.isWhitespace, !run.isEmpty {
                pending.append(character)
            } else {
                end()
            }
        }
        end()
        return Array(found.prefix(maximumPerLine))
    }

    /// True when any scalar of the character sits in the module's own script.
    static func belongs(_ character: Character, to language: LanguageModule) -> Bool {
        character.unicodeScalars.contains { scalar in
            language.scriptRanges.contains { $0.contains(scalar.value) }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
