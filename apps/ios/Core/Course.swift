import Foundation

/// A textbook syllabus a module can offer, so practice can follow the units a learner is
/// studying in class. Units are the sections; a topic can belong to several units, because a
/// real situation — buying clothes, say — draws on more than one lesson.
public struct Course: Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let units: [CourseUnit]
    public let topics: [CourseTopic]
    public init(id: String, title: String, detail: String, units: [CourseUnit], topics: [CourseTopic]) {
        self.id = id; self.title = title; self.detail = detail; self.units = units; self.topics = topics
    }

    public var books: [String] { units.map(\.book).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
    public func units(in book: String) -> [CourseUnit] { units.filter { $0.book == book } }
    public func unit(id: String) -> CourseUnit? { units.first { $0.id == id } }
    public func topics(in unit: CourseUnit) -> [CourseTopic] { topics.filter { $0.unitIDs.contains(unit.id) } }
    public func units(for topic: CourseTopic) -> [CourseUnit] { units.filter { topic.unitIDs.contains($0.id) } }

    /// Grammar from every unit before the latest one this topic draws on. Mural may lean on it
    /// freely, and should avoid grammar the course has not reached yet.
    public func earlierGrammar(before topic: CourseTopic) -> [String] {
        let latest = units(for: topic).map(\.number).max() ?? 0
        return units.filter { $0.number < latest && !topic.unitIDs.contains($0.id) }.flatMap(\.grammar)
    }

    /// A drill over everything a unit teaches, for revising a whole lesson rather than one situation.
    public func review(of unit: CourseUnit) -> CourseTopic {
        CourseTopic("review-\(unit.id)", "Unit \(unit.number) review", unit.meaning, "checklist", [unit.id],
                    "Revise everything this unit teaches, moving between its situations.", grammar: unit.grammar, vocabulary: [])
    }

    /// The conversation theme a topic becomes, so a course practice starts, is titled and is
    /// saved exactly like any other theme.
    public func theme(for topic: CourseTopic, mode: PracticeMode, language: LanguageModule) -> ConversationTheme {
        let colorIndex = (units(for: topic).first?.number ?? 0) % 4
        return ConversationTheme("course.\(id).\(topic.id).\(mode.rawValue)", topic.title, mode.title, topic.symbol, "Course",
                                 TeachingPolicy.coursePractice(topic, mode: mode, course: self, language: language), colorIndex)
    }
}

public struct CourseUnit: Identifiable, Hashable, Sendable {
    public let id: String
    public let number: Int
    public let book: String
    /// The unit's title as the book prints it, in the target language.
    public let title: String
    /// The title's meaning, for the English interface.
    public let meaning: String
    /// The vocabulary areas the unit covers, in English.
    public let vocabulary: [String]
    /// The grammar and expressions the unit teaches, written as the target language writes them.
    public let grammar: [String]
    public init(_ id: String, _ number: Int, _ book: String, _ title: String, _ meaning: String, vocabulary: [String], grammar: [String]) {
        self.id = id; self.number = number; self.book = book; self.title = title; self.meaning = meaning
        self.vocabulary = vocabulary; self.grammar = grammar
    }
}

public struct CourseTopic: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let unitIDs: [String]
    /// The scene, in English, as prompt text for the model.
    public let situation: String
    /// The grammar this topic should give the learner reasons to use.
    public let grammar: [String]
    /// Target-language words worth bringing into the practice.
    public let vocabulary: [String]
    public init(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ unitIDs: [String], _ situation: String,
                grammar: [String], vocabulary: [String]) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.unitIDs = unitIDs
        self.situation = situation; self.grammar = grammar; self.vocabulary = vocabulary
    }
}

public enum PracticeMode: String, CaseIterable, Sendable {
    /// A role-play in which the situation gives natural reasons to use the unit's grammar.
    case conversation
    /// Short questions, one at a time, each built to be answered with a target pattern.
    case drill

    public var title: String {
        switch self {
        case .conversation: "Talk it through"
        case .drill: "Quick questions"
        }
    }
    public var symbol: String {
        switch self {
        case .conversation: "waveform"
        case .drill: "questionmark.bubble"
        }
    }
}
