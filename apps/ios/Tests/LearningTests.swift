import XCTest
@testable import MuralCore

final class LearningTests: XCTestCase {
    func fixture(day: Double = 0, theme: String = "walk", supported: Bool = false, kind: EvidenceKind = .independent) -> SessionRecord {
        let date = Date(timeIntervalSince1970: 1_780_000_000 + day * 86400)
        var s = SessionRecord(themeID: theme)
        s.startedAt = date
        s.append(Fragment(id: UUID().uuidString, speaker: .user, text: "저는 숲에 갔어요.", startMS: 1000, endMS: 2000, receivedAt: date, meaningVisible: supported))
        let p = s.passages[0]
        s.assessments = [Assessment(passageID: p.id, revisionKey: p.revisionKey, outcome: .success, suggestedLevel: 2, nextGoal: "더 이야기해 주세요.", capability: "Describes a past outing", words: [WordProposal(lemma: "가다", meaning: "to go", form: "갔어요", kind: kind, confidence: 0.95, sourceIDs: p.fragments.map(\.id), quote: "저는 숲에 갔어요.")], createdAt: date, context: theme)]
        return s
    }
    func testDuplicateProviderEventsDoNotChangeTranscript() {
        var s = SessionRecord()
        let f = Fragment(id: "same", speaker: .user, text: "안녕", startMS: 0, endMS: 100)
        s.append(f); s.append(f)
        XCTAssertEqual(s.fragments.count, 1)
    }
    func testConcatenationPreservesExactProviderWhitespace() {
        let f = [Fragment(id: "a", speaker: .assistant, text: "오늘", startMS: 0, endMS: 100), Fragment(id: "b", speaker: .assistant, text: " 뭐 했어요?", startMS: 100, endMS: 400)]
        XCTAssertEqual(Transcript.passages(f).first?.text, "오늘 뭐 했어요?")
    }
    /// Appending skips the passage rebuild when nothing it protects can have changed. The
    /// guarantee is that recorded evidence still disappears the moment its own passage is
    /// rewritten, and that Mural's own speech never quietly takes evidence away.
    func testMuralsOwnSpeechNeverInvalidatesTheLearnersEvidence() {
        for module in LanguageRegistry.all {
            var session = fixture()
            let before = session.assessments
            session.append(Fragment(speaker: .assistant, text: module.greeting, startMS: 2100, endMS: 2600))
            session.append(Fragment(speaker: .assistant, text: module.greeting, startMS: 2600, endMS: 3000))
            XCTAssertEqual(session.assessments.map(\.revisionKey), before.map(\.revisionKey), module.id)
            XCTAssertEqual(session.passages.count, 2, module.id)
            XCTAssertNotNil(LearningEngine.validate(session.assessments[0], session: session), module.id)
            // The learner speaking into the same passage still invalidates it.
            session.append(Fragment(speaker: .user, text: " 아마도", startMS: 2200, endMS: 2400))
            XCTAssertEqual(session.assessments.count, 0, module.id)
        }
    }
    /// The copy kept on the device is rewritten on every change, so it is encoded compactly.
    /// Exports stay readable, and both decode to the same learning record.
    func testCompactAndReadableEncodingsCarryTheSameRecord() throws {
        var archive = Archive()
        archive.sessions = LanguageRegistry.all.map { fixtureFor($0.id) }
        let readable = try archive.encoded()
        let compact = try archive.encoded(pretty: false)
        XCTAssertLessThan(compact.count, readable.count)
        let fromReadable = try Archive.decode(readable), fromCompact = try Archive.decode(compact)
        XCTAssertEqual(fromCompact.sessions.map(\.id), fromReadable.sessions.map(\.id))
        XCTAssertEqual(fromCompact.sessions.map { $0.passages.map(\.text) }, fromReadable.sessions.map { $0.passages.map(\.text) })
        XCTAssertEqual(fromCompact.sessions.flatMap { $0.assessments.flatMap { $0.words.map(\.key) } },
                       fromReadable.sessions.flatMap { $0.assessments.flatMap { $0.words.map(\.key) } })
    }
    private func fixtureFor(_ languageID: String) -> SessionRecord {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let text = LanguageRegistry.module(for: languageID)?.greeting ?? ""
        var session = SessionRecord(languageID: languageID, themeID: "walk")
        session.startedAt = date
        session.append(Fragment(speaker: .user, text: text, startMS: 1000, endMS: 2000, receivedAt: date))
        return session
    }
    func testLateFragmentsRebuildEarlierPassageAndInvalidateEvidence() {
        var s = fixture()
        s.append(Fragment(id: "late", speaker: .user, text: " 아마도", startMS: 2100, endMS: 2500))
        XCTAssertEqual(s.assessments.count, 0)
        XCTAssertEqual(s.passages.count, 1)
    }
    func testOverlappingSpeakersRemainSeparate() {
        let fragments = [Fragment(speaker: .assistant, text: "안녕", startMS: 0, endMS: 500), Fragment(speaker: .user, text: "여보세요", startMS: 100, endMS: 400), Fragment(speaker: .assistant, text: "!", startMS: 500, endMS: 600)]
        let p = Transcript.passages(fragments)
        XCTAssertEqual(p.count, 2); XCTAssertEqual(p[0].text, "안녕!"); XCTAssertEqual(p[1].text, "여보세요")
    }
    func testVisibleMeaningCannotAwardIndependentRecall() {
        let s = fixture(supported: true)
        let valid = LearningEngine.validate(s.assessments[0], session: s)
        XCTAssertEqual(valid?.words[0].kind, .assisted)
        XCTAssertEqual(LearningEngine.project([s]).words[0].independentCount, 0)
    }
    func testImmediateImitationIsAssisted() {
        var s = fixture()
        s.fragments.insert(Fragment(speaker: .assistant, text: "숲에 갔어요?", startMS: 0, endMS: 500), at: 0)
        XCTAssertEqual(LearningEngine.validate(s.assessments[0], session: s)?.words[0].kind, .assisted)
    }
    func testEnglishCannotAwardKoreanProduction() {
        var s = fixture(); s.assessments[0].words[0].language = "en"
        XCTAssertEqual(LearningEngine.validate(s.assessments[0], session: s)?.words.count, 0)
    }
    func testTypingCannotAwardIndependentSpokenRecall() {
        var s = fixture(); s.fragments[0].typed = true
        XCTAssertEqual(LearningEngine.validate(s.assessments[0], session: s)?.words[0].kind, .assisted)
    }
    func testFabricatedSourceAndQuotesAreRejected() {
        var s = fixture(); s.assessments[0].words[0].sourceIDs = ["invented"]
        XCTAssertEqual(LearningEngine.validate(s.assessments[0], session: s)?.words.count, 0)
        s = fixture(); s.assessments[0].words[0].quote = "저는 날 수 있어요."
        XCTAssertEqual(LearningEngine.validate(s.assessments[0], session: s)?.words.count, 0)
    }
    func testDuplicateAssessmentsNeverDoubleCredit() {
        var s = fixture(); s.assessments += s.assessments
        let projection = LearningEngine.project([s], now: s.startedAt)
        XCTAssertEqual(projection.words[0].independentCount, 1)
        XCTAssertEqual(projection.observationCount, 1)
    }
    func testDuplicateWordProposalsNeverDoubleCredit() {
        var s = fixture(); s.assessments[0].words += s.assessments[0].words
        XCTAssertEqual(LearningEngine.project([s], now: s.startedAt).words[0].independentCount, 1)
    }
    func testSteadyRequiresSpacingAndDifferentContexts() {
        let first = fixture(), second = fixture(day: 2), third = fixture(day: 8, theme: "dinner")
        let p = LearningEngine.project([first, second, third], now: third.startedAt)
        XCTAssertEqual(p.words[0].bars, 3)
        let sameContext = LearningEngine.project([first, second, fixture(day: 8)], now: third.startedAt)
        XCTAssertEqual(sameContext.words[0].bars, 2)
        let massed = LearningEngine.project([first, fixture(day: 0.01), fixture(day: 0.02)], now: first.startedAt)
        XCTAssertLessThanOrEqual(massed.words[0].bars, 2)
    }
    func testStrengthFadesAndLapsesLowerIt() {
        let sessions = [fixture(), fixture(day: 2), fixture(day: 8, theme: "dinner")]
        let projected = LearningEngine.project(sessions, now: sessions.last!.startedAt.addingTimeInterval(30 * 86400))
        XCTAssertEqual(projected.words[0].bars, 2)
        let lapse = fixture(day: 9, kind: .lapse)
        XCTAssertEqual(LearningEngine.project(sessions + [lapse], now: lapse.startedAt).words[0].bars, 1)
    }
    func testCorrectedTranscriptRevokesEvidence() {
        var s = fixture(); s.correctFragment(id: s.fragments[0].id, text: "I went for a walk.")
        XCTAssertTrue(s.assessments.isEmpty)
        XCTAssertTrue(LearningEngine.project([s]).words.isEmpty)
    }
    func testArchiveRoundTripAndVersionGuard() throws {
        var archive = Archive(); archive.sessions = [fixture()]
        let decoded = try Archive.decode(archive.encoded())
        XCTAssertEqual(decoded.sessions.count, 1)
        archive.schemaVersion = 99
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }
    func testDuplicateSessionImportRejected() throws {
        var archive = Archive(); let s = fixture(); archive.sessions = [s,s]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }
    func testArchiveRejectsNumbersThatCanCrashTheInterface() throws {
        var archive = Archive(); archive.sessions = [fixture()]
        archive.sessions[0].voiceSeconds = 1e308
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        archive.sessions[0].voiceSeconds = 0
        archive.sessions[0].searchCalls = Int.max
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        archive.sessions[0].searchCalls = 0
        archive.sessions[0].fragments[0].revision = Int.max
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        archive.sessions[0].fragments[0].revision = 0
        archive.sessions[0].inputTokens = -1
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
        archive.sessions[0].inputTokens = 0
        archive.sessions[0].assessments[0].createdAt = Date(timeIntervalSinceReferenceDate: 1e308)
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }
    func testImportFileReadRejectsOversizedAndNonFileInputs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = try Archive().encoded()
        try expected.write(to: url)
        XCTAssertEqual(try Archive.readImportData(from: url), expected)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(Archive.maximumEncodedBytes) + 1)
        try file.close()
        XCTAssertThrowsError(try Archive.readImportData(from: url)) { XCTAssertEqual($0 as? ArchiveError, .tooLarge) }
        XCTAssertThrowsError(try Archive.readImportData(from: URL(string: "https://example.test/backup.json")!))
        XCTAssertThrowsError(try Archive.readImportData(from: FileManager.default.temporaryDirectory))
    }
    func testImportMergeCannotPersistAnArchiveThatFailsOnRelaunch() throws {
        var original = Archive(), incoming = Archive()
        original.sessions = (0..<10_000).map { _ in SessionRecord() }
        incoming.sessions = [SessionRecord()]
        XCTAssertThrowsError(try original.merging(incoming)) { XCTAssertEqual($0 as? ArchiveError, .tooLarge) }
        XCTAssertEqual(original.sessions.count, 10_000)
        incoming.sessions = [original.sessions[0]]
        XCTAssertEqual(try original.merging(incoming).sessions.count, 10_000)
        original.sessions = [SessionRecord(title: String(repeating: "a", count: Archive.maximumEncodedBytes / 2))]
        incoming.sessions = [SessionRecord(title: String(repeating: "b", count: Archive.maximumEncodedBytes / 2))]
        XCTAssertNoThrow(try Archive.decode(original.encoded()))
        XCTAssertNoThrow(try Archive.decode(incoming.encoded()))
        XCTAssertThrowsError(try original.merging(incoming)) { XCTAssertEqual($0 as? ArchiveError, .tooLarge) }
        XCTAssertEqual(original.sessions.count, 1)
    }
    func testImportMergePreservesLocalPreferencesAndValidatesNewEvidence() throws {
        var original = Archive(), incoming = Archive()
        original.preferences.meaningLanguage = "Spanish"
        original.preferences.aiConsentVersion = 1
        incoming.preferences.meaningLanguage = "English"
        var invalidEvidence = fixture()
        invalidEvidence.assessments[0].revisionKey = "changed"
        incoming.sessions = [invalidEvidence]
        let merged = try original.merging(incoming)
        XCTAssertEqual(merged.preferences.meaningLanguage, "Spanish")
        XCTAssertEqual(merged.preferences.aiConsentVersion, 1)
        XCTAssertTrue(merged.sessions[0].assessments.isEmpty)
        XCTAssertEqual(try Archive.decode(merged.encoded()).sessions.count, 1)
    }
    func testSourceLinksRejectNonHTTPSAndCredentials() {
        XCTAssertNil(SourceLink(title: "bad", url: "javascript:alert(1)").safeURL)
        XCTAssertNil(SourceLink(title: "bad", url: "https://user@example.com/page").safeURL)
        XCTAssertNotNil(SourceLink(title: "good", url: "https://www.nrk.no/").safeURL)
    }
    func testTwentyFourDistinctThemes() { XCTAssertEqual(Set(LanguageModule.korean.themes.map(\.id)).count, 24) }
}
