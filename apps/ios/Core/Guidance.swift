import Foundation

/// How much of the conversation the learner wants in a language they already read, and how
/// quickly Mural speaks. The learner chooses both. Neither changes what `LearningEngine`
/// accepts as evidence: support makes production *assisted*, never independent.
public enum GuidanceLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Mostly the learner's own language. Target phrases arrive one at a time, with their meaning.
    case startingOut = "starting-out"
    /// Target language for questions, examples and replies; explanations in the learner's own language.
    case findingMyFeet = "finding-my-feet"
    /// Target language only. This is how Mural behaved before levels existed.
    case inAtTheDeepEnd = "deep-end"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .startingOut: "Starting out"
        case .findingMyFeet: "Finding my feet"
        case .inAtTheDeepEnd: "In at the deep end"
        }
    }

    /// A single line for the chooser, in the interface language.
    public func detail(language: LanguageModule, meaningLanguage: String) -> String {
        switch self {
        case .startingOut:
            "Mural speaks \(meaningLanguage) and teaches \(language.name) one short phrase at a time."
        case .findingMyFeet:
            "Mural asks and answers in simple \(language.name), and explains things in \(meaningLanguage)."
        case .inAtTheDeepEnd:
            "\(language.name) only, at a natural pace."
        }
    }

    /// Where the pace starts for this level. An explicit choice in Settings overrides it.
    public var pace: SpeechPace {
        switch self {
        case .startingOut: .slow
        case .findingMyFeet: .gentle
        case .inAtTheDeepEnd: .natural
        }
    }

    /// Detecting another language in Mural's own speech only means drift when the level
    /// did not ask for that language in the first place. Below the deep end, explanations are
    /// meant to arrive in the learner's own language.
    public var expectsTargetLanguageThroughout: Bool { self == .inAtTheDeepEnd }

    /// The language Mural explains grammar, meaning and corrections in. Teachers of beginners
    /// keep the target language for interaction and explain in the learner's own language, so an
    /// explanation is never harder to follow than the question it leads to.
    public func explanationLanguage(language: LanguageModule, meaningLanguage: String) -> String {
        self == .inAtTheDeepEnd ? language.name : meaningLanguage
    }

    /// The highest stage of a module's `teachingFocus` Mural reaches for at this level. The
    /// assessed challenge can rise with evidence, but a learner who asked for support should not
    /// meet grammar from far beyond it.
    public var maximumChallenge: Int {
        switch self {
        case .startingOut: 1
        case .findingMyFeet: 2
        case .inAtTheDeepEnd: 5
        }
    }
}

/// How quickly Mural speaks.
///
/// GPT-Live has no speed setting for its voice, so the conversation pace is an instruction
/// (`TeachingPolicy`) and the model decides how well it follows it. `speed` is kept as the
/// stored form of the choice, so older backups still decode, and sets the rate of the system
/// voice that reads scans aloud. It stays within 0.25–1.5.
public enum SpeechPace: String, Codable, CaseIterable, Sendable, Identifiable {
    case slow, gentle, natural, brisk

    public var id: String { rawValue }
    public static let range: ClosedRange<Double> = 0.25...1.5

    public var speed: Double {
        switch self {
        case .slow: 0.7
        case .gentle: 0.85
        case .natural: 1.0
        case .brisk: 1.15
        }
    }

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .gentle: "Gentle"
        case .natural: "Natural"
        case .brisk: "Brisk"
        }
    }

    public static func nearest(to speed: Double) -> SpeechPace {
        guard speed.isFinite else { return .natural }
        return allCases.min { abs($0.speed - speed) < abs($1.speed - speed) } ?? .natural
    }
}
