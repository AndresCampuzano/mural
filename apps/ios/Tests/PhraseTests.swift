import XCTest
@testable import MuralCore

/// Finding target-language phrases inside a mixed line, and keeping them without touching
/// the learning record.
final class PhraseTests: XCTestCase {
    func testEveryModuleDeclaresItsOwnScript() {
        for language in LanguageRegistry.all {
            XCTAssertFalse(language.scriptRanges.isEmpty, language.id)
            XCTAssertTrue(language.scriptRanges.allSatisfy { $0.lowerBound <= $0.upperBound }, language.id)
            XCTAssertTrue(Phrases.candidates(in: language.greeting, language: language).contains(language.greetingWord), language.id)
        }
    }

    func testTheTaughtPhrasesAreFoundInsideAnExplanation() {
        let korean = Phrases.candidates(in: "For saying goodbye you say 안녕히 가세요, and for saying hello, 안녕하세요.", language: .korean)
        XCTAssertEqual(korean, ["안녕히 가세요", "안녕하세요"])
        let japanese = Phrases.candidates(in: "To say goodbye, さようなら. To say hello, こんにちは!", language: .japanese)
        XCTAssertEqual(japanese, ["さようなら", "こんにちは"])
    }

    func testSpacesInsideAPhraseAreKeptAndSpacesBesideEnglishAreNot() {
        XCTAssertEqual(Phrases.candidates(in: "Order it with 커피 한 잔 주세요 please", language: .korean), ["커피 한 잔 주세요"])
        XCTAssertEqual(Phrases.candidates(in: "Say 네 for yes", language: .korean), ["네"])
    }

    func testQuotesSentenceEndingsAndTrailingPunctuationAreNotPartOfThePhrase() {
        XCTAssertEqual(Phrases.candidates(in: "Try ‘안녕하세요’ first.", language: .korean), ["안녕하세요"])
        XCTAssertEqual(Phrases.candidates(in: "こんにちは。おげんきですか。", language: .japanese), ["こんにちは", "おげんきですか"])
    }

    func testTheOtherModulesScriptIsNotOfferedAsAFind() {
        XCTAssertTrue(Phrases.candidates(in: "안녕하세요", language: .japanese).isEmpty)
        XCTAssertTrue(Phrases.candidates(in: "Nothing but English here.", language: .korean).isEmpty)
        XCTAssertTrue(Phrases.candidates(in: "", language: .korean).isEmpty)
        // Japanese and Korean do not share a block, so a Korean line offers nothing in Japanese.
        XCTAssertEqual(Phrases.candidates(in: "ひらがな and 안녕", language: .japanese), ["ひらがな"])
    }

    func testRepeatedPhrasesAreOfferedOnceAndTheListIsBounded() {
        XCTAssertEqual(Phrases.candidates(in: "안녕하세요! Again: 안녕하세요.", language: .korean), ["안녕하세요"])
        let many = (1...10).map { "Phrase \($0) is 안녕\($0)." }.joined(separator: " ")
        XCTAssertLessThanOrEqual(Phrases.candidates(in: many, language: .korean).count, Phrases.maximumPerLine)
    }

    func testAPhraseIsTruncatedRatherThanStoredUnbounded() {
        let long = String(repeating: "가", count: SavedPhrase.maximumLength + 50)
        XCTAssertEqual(Phrases.candidates(in: long, language: .korean).first?.count, SavedPhrase.maximumLength)
        let phrase = SavedPhrase(languageID: "ko", text: long, meaning: String(repeating: "x", count: 400), meaningLanguage: "English")
        XCTAssertEqual(phrase.text.count, SavedPhrase.maximumLength)
        XCTAssertEqual(phrase.meaning.count, 300)
    }

    func testTheSamePhraseIsNeverKeptTwiceAndLanguagesStaySeparate() {
        let first = SavedPhrase(languageID: "ko", text: " 안녕하세요 ", meaningLanguage: "English")
        let second = SavedPhrase(languageID: "ko", text: "안녕하세요", meaningLanguage: "Spanish")
        let japanese = SavedPhrase(languageID: "ja", text: "안녕하세요", meaningLanguage: "English")
        XCTAssertEqual(first.key, second.key)
        XCTAssertNotEqual(first.key, japanese.key)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAnArchiveWithoutSavedPhrasesStillDecodes() throws {
        var archive = Archive()
        archive.preferences.hasOnboarded = true
        let data = try archive.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("savedPhrases"))
        XCTAssertTrue(try Archive.decode(data).phrases.isEmpty)
    }

    func testSavedPhrasesSurviveExportAndImportInBothModules() throws {
        var archive = Archive()
        archive.savedPhrases = [SavedPhrase(languageID: "ko", text: "안녕하세요", meaning: "hello", meaningLanguage: "English", source: "Say 안녕하세요."),
                                SavedPhrase(languageID: "ja", text: "こんにちは", meaning: "hello", meaningLanguage: "English")]
        let restored = try Archive.decode(archive.encoded())
        XCTAssertEqual(restored.phrases.map(\.text), ["안녕하세요", "こんにちは"])
        XCTAssertEqual(restored.phrases.map(\.meaning), ["hello", "hello"])
        XCTAssertEqual(restored.phrases.first?.source, "Say 안녕하세요.")
    }

    func testAnUnreadablePhraseIsRejectedRatherThanStored() throws {
        for phrase in [SavedPhrase(languageID: "ko", text: "   ", meaningLanguage: "English"),
                       SavedPhrase(languageID: "nb", text: "hei", meaningLanguage: "English")] {
            var archive = Archive()
            archive.savedPhrases = [phrase]
            XCTAssertThrowsError(try Archive.decode(archive.encoded()), phrase.languageID)
        }
        var duplicated = Archive()
        let phrase = SavedPhrase(languageID: "ko", text: "안녕하세요", meaningLanguage: "English")
        duplicated.savedPhrases = [phrase, phrase]
        XCTAssertThrowsError(try Archive.decode(duplicated.encoded()))
    }

    func testImportingABackupAddsOnlyPhrasesTheDeviceDoesNotHave() throws {
        var local = Archive()
        local.savedPhrases = [SavedPhrase(languageID: "ko", text: "안녕하세요", meaning: "hello", meaningLanguage: "English")]
        var incoming = Archive()
        incoming.savedPhrases = [SavedPhrase(languageID: "ko", text: "안녕하세요", meaning: "hi there", meaningLanguage: "Spanish"),
                                 SavedPhrase(languageID: "ko", text: "감사합니다", meaning: "thank you", meaningLanguage: "English")]
        let merged = try local.merging(incoming)
        XCTAssertEqual(merged.phrases.map(\.text), ["안녕하세요", "감사합니다"])
        XCTAssertEqual(merged.phrases.first?.meaning, "hello")
    }

    /// Keeping a phrase says the learner wants to see it again, never that they produced it.
    func testKeepingAPhraseCreatesNoLearningEvidence() throws {
        var archive = Archive()
        archive.savedPhrases = [SavedPhrase(languageID: "ko", text: "안녕하세요", meaning: "hello", meaningLanguage: "English")]
        let restored = try Archive.decode(archive.encoded())
        let learner = LearningEngine.project(restored.sessions, languageID: "ko")
        XCTAssertTrue(learner.words.isEmpty)
        XCTAssertEqual(learner.observationCount, 0)
        XCTAssertEqual(learner.challenge, 0)
    }
}
