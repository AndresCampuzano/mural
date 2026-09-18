import Foundation

/// How much of the conversation the learner wants in a language they already read, and how
/// quickly Mural speaks. The learner chooses both. Neither changes what `LearningEngine`
/// accepts as evidence: support makes production *assisted*, never independent.
public enum GuidanceLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Mostly the learner's own language. Target phrases arrive one at a time, with their meaning.
    case startingOut = "starting-out"
    /// Target language first, with a few words of support when something is new.
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
            "Simple \(language.name), with a few words of \(meaningLanguage) when something is new."
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
    /// did not ask for that language in the first place.
    public var expectsTargetLanguageThroughout: Bool { self != .startingOut }
}

/// How quickly Mural speaks, as a multiple of the model's normal rate.
///
/// The provider applies this to the generated audio after the fact, so it changes playback
/// rate rather than how the model composes speech; `TeachingPolicy` asks for matching pacing
/// in words as well. Accepted range is 0.25–1.5, and the value can only change between turns,
/// so Mural sets it when a conversation starts.
/// https://developers.openai.com/api/reference/resources/realtime/client-events
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
