import XCTest
@testable import MuralCore

/// Keeping what was read from a picture or PDF, so it is read once and practised many times.
final class ScanTests: XCTestCase {
    private func scan(_ language: LanguageModule, name: String = "Menu") -> ScannedFile {
        let study = PictureStudy.validated(.init(title: "Menu", summary: "A menu.", targetText: language.greeting,
                                                 vocabulary: [PictureTerm(text: language.greetingWord, meaning: "hello")], situation: "A café."),
                                           language: language, meaningLanguage: "English")
        return ScannedFile(languageID: language.id, name: name, kind: .picture, detail: "Picture", study: study, thumbnail: Data(count: 100))
    }
    private func written(_ language: LanguageModule) -> [TestQuestion] {
        [TestQuestion(kind: .written, prompt: "Say hello", passage: language.greeting, options: [], answer: language.greetingWord, explanation: "")]
    }

    func testAScanAndItsPracticeSurviveABackupInEveryLanguage() throws {
        for language in LanguageRegistry.all {
            var file = scan(language)
            file.add(SavedPractice(name: "Talk", activity: .conversation, level: .startingOut, pace: .slow))
            let test = SavedPractice(name: "Test", activity: .writtenTest, level: .findingMyFeet, questions: written(language))
            file.add(test)
            file.recordAttempt(TestAttempt(score: 0.5, total: 1), practiceID: test.id)
            var archive = Archive(); archive.preferences.learningLanguageID = language.id; archive.scans = [file]
            let decoded = try Archive.decode(archive.encoded())
            let kept = try XCTUnwrap(decoded.scannedFiles.first)
            XCTAssertEqual(kept.study.targetText, language.greeting, language.id)
            XCTAssertEqual(kept.practices.map(\.activity), [.conversation, .writtenTest])
            XCTAssertEqual(kept.practices[0].pace, .slow)
            XCTAssertEqual(kept.practices[1].questions.first?.answer, language.greetingWord)
            XCTAssertEqual(kept.practices[1].attempts, [file.practices[1].attempts[0]])
        }
    }

    func testABackupWrittenBeforeScansStillDecodes() throws {
        let old = try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "sessions": [], "preferences": try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences()))])
        XCTAssertTrue(try Archive.decode(old).scannedFiles.isEmpty)
    }

    func testImportAddsNewScansOnce() throws {
        let language = LanguageRegistry.all[0]
        var mine = Archive(); mine.scans = [scan(language, name: "Mine")]
        var theirs = Archive(); theirs.scans = [mine.scannedFiles[0], scan(language, name: "Theirs")]
        let merged = try mine.merging(theirs)
        XCTAssertEqual(merged.scannedFiles.map(\.name), ["Mine", "Theirs"])
    }

    func testAnOversizedThumbnailOrAMismatchedLanguageIsRejected() throws {
        let language = LanguageRegistry.all[0], other = LanguageRegistry.all[1]
        var big = scan(language); big.thumbnail = Data(count: ScannedFile.maximumThumbnailBytes + 1)
        var archive = Archive(); archive.scans = [big]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        var mismatched = scan(language); mismatched.languageID = other.id
        archive.scans = [mismatched]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }

    func testATestWithoutQuestionsOrAConversationWithThemIsRejected() throws {
        let language = LanguageRegistry.all[0]
        var file = scan(language)
        file.add(SavedPractice(name: "Empty", activity: .writtenTest, level: .findingMyFeet))
        var archive = Archive(); archive.scans = [file]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }

    func testRenamingIgnoresABlankNameAndTrimsTheRest() {
        var file = scan(LanguageRegistry.all[0])
        file.rename("   ")
        XCTAssertEqual(file.name, "Menu")
        file.rename("  Lunch menu  ")
        XCTAssertEqual(file.name, "Lunch menu")
        file.rename(String(repeating: "a", count: 200))
        XCTAssertEqual(file.name.count, ScannedFile.maximumNameLength)
        let practice = SavedPractice(name: "Talk", activity: .conversation, level: .startingOut)
        file.add(practice)
        file.renamePractice(practice.id, to: "")
        XCTAssertEqual(file.practice(id: practice.id)?.name, "Talk")
        file.renamePractice(practice.id, to: "Ordering")
        XCTAssertEqual(file.practice(id: practice.id)?.name, "Ordering")
        file.removePractice(practice.id)
        XCTAssertNil(file.practice(id: practice.id))
    }

    func testSuggestedNamesTellRepeatsApart() {
        let language = LanguageRegistry.all[0]
        var file = scan(language)
        let first = file.suggestedName(for: .writtenTest, level: .startingOut)
        file.add(SavedPractice(name: first, activity: .writtenTest, level: .startingOut, questions: written(language)))
        let second = file.suggestedName(for: .writtenTest, level: .startingOut)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.hasPrefix(first))
        XCTAssertEqual(file.suggestedName(for: .conversation, level: .startingOut), "\(PictureActivity.conversation.title) · \(GuidanceLevel.startingOut.title)")
    }

    func testAttemptsAreBoundedAndTheBestIsKnown() {
        let language = LanguageRegistry.all[0]
        var file = scan(language)
        let test = SavedPractice(name: "Test", activity: .writtenTest, level: .startingOut, questions: written(language))
        file.add(test)
        for index in 0..<(SavedPractice.maximumAttempts + 5) {
            file.recordAttempt(TestAttempt(score: index == 3 ? 1 : 0, total: 1), practiceID: test.id)
        }
        XCTAssertEqual(file.practice(id: test.id)?.attempts.count, SavedPractice.maximumAttempts)
        XCTAssertEqual(file.practice(id: test.id)?.best?.score, 0)
        file.recordAttempt(TestAttempt(score: 1, total: 1), practiceID: test.id)
        XCTAssertEqual(file.practice(id: test.id)?.best?.score, 1)
    }

    func testAnUnknownStoredLevelFallsBackInsteadOfFailing() {
        var practice = SavedPractice(name: "Talk", activity: .conversation, level: .startingOut, pace: .slow)
        practice.levelID = "future-level"; practice.paceID = "future-pace"
        XCTAssertEqual(practice.level, .inAtTheDeepEnd)
        XCTAssertNil(practice.pace)
    }

    func testAUsageRecordCarriesNoContent() {
        var record = SessionRecord(languageID: LanguageRegistry.all[0].id, themeID: SessionRecord.usageThemeID, title: "Scan")
        record.inputTokens = 10
        XCTAssertTrue(record.isUsageOnly)
        XCTAssertTrue(record.fragments.isEmpty && record.topics.isEmpty)
        XCTAssertFalse(SessionRecord(languageID: LanguageRegistry.all[0].id).isUsageOnly)
    }
}
