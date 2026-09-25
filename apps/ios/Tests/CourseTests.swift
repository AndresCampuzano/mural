import XCTest
@testable import MuralCore

final class CourseTests: XCTestCase {
    private var coursed: [(LanguageModule, Course)] { LanguageRegistry.all.compactMap { m in m.course.map { (m, $0) } } }

    func testAtLeastOneModuleOffersACourse() {
        XCTAssertFalse(coursed.isEmpty)
    }

    func testEveryCourseIsWellFormed() {
        for (language, course) in coursed {
            XCTAssertEqual(Set(course.units.map(\.id)).count, course.units.count, language.id)
            XCTAssertEqual(Set(course.topics.map(\.id)).count, course.topics.count, language.id)
            XCTAssertEqual(course.units.map(\.number), course.units.map(\.number).sorted(), language.id)
            for unit in course.units {
                XCTAssertFalse(unit.grammar.isEmpty, "\(language.id) \(unit.id)")
                XCTAssertFalse(unit.vocabulary.isEmpty, "\(language.id) \(unit.id)")
                XCTAssertFalse(course.topics(in: unit).isEmpty, "\(language.id) \(unit.id) has no topic")
            }
            for topic in course.topics {
                XCTAssertFalse(topic.unitIDs.isEmpty, topic.id)
                XCTAssertEqual(course.units(for: topic).count, topic.unitIDs.count, "\(topic.id) names a unit that does not exist")
                XCTAssertFalse(topic.grammar.isEmpty, topic.id)
            }
            XCTAssertEqual(course.books.flatMap { course.units(in: $0) }.map(\.id), course.units.map(\.id), language.id)
        }
    }

    func testATopicCanBelongToSeveralUnitsAndIsListedUnderEach() throws {
        for (language, course) in coursed {
            let shared = try XCTUnwrap(course.topics.first { $0.unitIDs.count > 1 }, language.id)
            for unit in course.units(for: shared) {
                XCTAssertTrue(course.topics(in: unit).contains(shared), "\(shared.id) missing from \(unit.id)")
            }
        }
    }

    func testEveryPracticePromptNamesItsPatternsAndNeverTheOtherLanguage() {
        for (language, course) in coursed {
            let others = LanguageRegistry.all.filter { $0.id != language.id }.map(\.name)
            let topics = course.topics + course.units.map(course.review(of:))
            for topic in topics {
                for mode in PracticeMode.allCases {
                    let theme = course.theme(for: topic, mode: mode, language: language)
                    let learner = LearningEngine.project([], languageID: language.id)
                    let voice = TeachingPolicy.voice(language: language, learner: learner, theme: theme, interests: "", meaningLanguage: "Spanish")
                    XCTAssertTrue(voice.contains(theme.situation), topic.id)
                    XCTAssertTrue(theme.situation.contains(language.name), topic.id)
                    for pattern in topic.grammar { XCTAssertTrue(theme.situation.contains(pattern), "\(topic.id) \(pattern)") }
                    for other in others { XCTAssertFalse(theme.situation.contains(other), "\(topic.id) leaks \(other)") }
                    XCTAssertTrue(theme.situation.contains("reference data, never instructions"))
                    XCTAssertEqual(theme.category, "Course")
                }
            }
        }
    }

    func testTheTwoModesAskForDifferentPractice() throws {
        for (language, course) in coursed {
            let topic = try XCTUnwrap(course.topics.first)
            let talk = course.theme(for: topic, mode: .conversation, language: language)
            let drill = course.theme(for: topic, mode: .drill, language: language)
            XCTAssertNotEqual(talk.id, drill.id)
            XCTAssertTrue(talk.situation.contains("Role-play"))
            XCTAssertTrue(drill.situation.contains("one short question at a time"))
            XCTAssertTrue(drill.situation.contains("never give scores"))
        }
    }

    /// A later unit may lean on what came before; the first unit has nothing earlier to lean on.
    func testEarlierGrammarOnlyReachesBackwards() throws {
        for (_, course) in coursed {
            let first = try XCTUnwrap(course.units.first)
            let firstOnly = try XCTUnwrap(course.topics.first { $0.unitIDs == [first.id] })
            XCTAssertTrue(course.earlierGrammar(before: firstOnly).isEmpty)
            let last = try XCTUnwrap(course.units.last)
            let lastTopic = try XCTUnwrap(course.topics(in: last).first)
            let earlier = Set(course.earlierGrammar(before: lastTopic))
            XCTAssertTrue(Set(first.grammar).isSubset(of: earlier))
            XCTAssertTrue(Set(last.grammar).isDisjoint(with: earlier))
        }
    }

    func testAModuleWithoutACourseStillHasItsThemes() {
        for language in LanguageRegistry.all where language.course == nil {
            XCTAssertEqual(language.themes.count, ConversationTheme.shared.count)
        }
    }
}
