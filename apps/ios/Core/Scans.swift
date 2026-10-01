import Foundation

/// A picture or PDF read once and kept as text, so every later conversation or test is built
/// from what was already read instead of sending the file again. The file itself is never
/// kept: only what Mural read from it and a small thumbnail to recognise it by.
public struct ScannedFile: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case picture, pdf }
    public var id = UUID()
    public var languageID: String
    public var name: String
    public var kind: Kind
    /// What was sent, such as "PDF · 3 pages", in the interface language.
    public var detail: String
    public var createdAt = Date()
    public var study: PictureStudy
    /// A small JPEG to recognise the scan by. Optional so a scan without one still decodes.
    public var thumbnail: Data?
    public var practices: [SavedPractice] = []
    /// The content-free session that carries this scan's token usage, so Spending still counts
    /// it after the scan is deleted.
    public var usageSessionID: UUID?

    public static let maximumNameLength = 80
    public static let maximumThumbnailBytes = 60_000
    public static let maximumPractices = 50

    public init(languageID: String, name: String, kind: Kind, detail: String, study: PictureStudy, thumbnail: Data? = nil, usageSessionID: UUID? = nil) {
        self.languageID = languageID; self.name = Self.cleanName(name) ?? "A scan"; self.kind = kind
        self.detail = String(detail.prefix(80)); self.study = study; self.thumbnail = thumbnail; self.usageSessionID = usageSessionID
    }

    /// A usable name, or `nil` when there is nothing left of it after trimming.
    public static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumNameLength))
    }

    /// Renames, and ignores a blank name rather than leaving the scan without one.
    public mutating func rename(_ name: String) { if let clean = Self.cleanName(name) { self.name = clean } }

    public func practice(id: UUID) -> SavedPractice? { practices.first { $0.id == id } }

    public mutating func add(_ practice: SavedPractice) {
        practices.append(practice)
        if practices.count > Self.maximumPractices { practices.removeFirst(practices.count - Self.maximumPractices) }
    }
    public mutating func renamePractice(_ id: UUID, to name: String) {
        guard let index = practices.firstIndex(where: { $0.id == id }), let clean = Self.cleanName(name) else { return }
        practices[index].name = clean
    }
    public mutating func removePractice(_ id: UUID) { practices.removeAll { $0.id == id } }
    public mutating func recordAttempt(_ attempt: TestAttempt, practiceID: UUID) {
        guard let index = practices.firstIndex(where: { $0.id == practiceID }) else { return }
        practices[index].attempts.append(attempt)
        if practices[index].attempts.count > SavedPractice.maximumAttempts {
            practices[index].attempts.removeFirst(practices[index].attempts.count - SavedPractice.maximumAttempts)
        }
    }

    /// A default name that says what the practice is and tells repeats apart.
    public func suggestedName(for activity: PictureActivity, level: GuidanceLevel) -> String {
        let base = "\(activity.title) · \(level.title)"
        let taken = Set(practices.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    func isValid(validDate: (Date) -> Bool) -> Bool {
        LanguageRegistry.module(for: languageID) != nil && study.languageID == languageID
            && Self.cleanName(name) == name && validDate(createdAt)
            && (thumbnail?.count ?? 0) <= Self.maximumThumbnailBytes
            && study.targetText.count <= PictureStudy.maximumTargetText && study.vocabulary.count <= PictureStudy.maximumTerms
            && study.summary.count <= 800 && study.situation.count <= 600 && study.title.count <= 80
            && practices.count <= Self.maximumPractices && Set(practices.map(\.id)).count == practices.count
            && practices.allSatisfy { $0.isValid(validDate: validDate) }
    }
}

/// A conversation or written test set up from a scan and kept for another go. A conversation
/// keeps its level and pace; a test keeps its questions, so retaking it sends nothing to build it.
public struct SavedPractice: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var activity: PictureActivity
    public var createdAt = Date()
    /// Stored as raw values, like `Preferences`, so an unknown value falls back instead of
    /// failing to decode.
    public var levelID: String
    public var paceID: String?
    public var questions: [TestQuestion] = []
    public var attempts: [TestAttempt] = []

    public static let maximumAttempts = 100
    public static let maximumQuestions = 10

    public init(name: String, activity: PictureActivity, level: GuidanceLevel, pace: SpeechPace? = nil, questions: [TestQuestion] = []) {
        self.name = ScannedFile.cleanName(name) ?? activity.title; self.activity = activity
        levelID = level.rawValue; paceID = pace?.rawValue; self.questions = Array(questions.prefix(Self.maximumQuestions))
    }

    public var level: GuidanceLevel { GuidanceLevel(rawValue: levelID) ?? .inAtTheDeepEnd }
    public var pace: SpeechPace? { paceID.flatMap(SpeechPace.init(rawValue:)) }
    public var test: PictureTest { PictureTest(questions: questions) }
    public var best: TestAttempt? { attempts.max { $0.score < $1.score } }

    func isValid(validDate: (Date) -> Bool) -> Bool {
        ScannedFile.cleanName(name) == name && validDate(createdAt)
            && questions.count <= Self.maximumQuestions && attempts.count <= Self.maximumAttempts
            && (activity == .writtenTest) != questions.isEmpty
            && Set(questions.map(\.id)).count == questions.count
            && attempts.allSatisfy { validDate($0.takenAt) && $0.score.isFinite && $0.score >= 0 && $0.score <= Double($0.total) && $0.total >= 0 }
    }
}

public struct TestAttempt: Codable, Sendable, Equatable {
    public var takenAt = Date()
    public var score: Double
    public var total: Int
    public init(score: Double, total: Int, takenAt: Date = .now) { self.score = score; self.total = total; self.takenAt = takenAt }
}

extension SessionRecord {
    /// The theme ID of a session that only carries the token usage of scans and tests. It has no
    /// transcript and no scanned content, and Past conversations does not list it.
    public static let usageThemeID = "mural.usage.scan"
    public var isUsageOnly: Bool { themeID == Self.usageThemeID }
}
