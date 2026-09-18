import XCTest
@testable import MuralCore

final class LanguageTests: XCTestCase {
    private static let samples = [
        "ko": (text: "커피를 마셔요.", lemma: "마시다", meaning: "to drink", form: "마셔요"),
        "ja": (text: "コーヒーを飲みます。", lemma: "飲む", meaning: "to drink", form: "飲みます")
    ]

    func testExistingArchivesRequireConsentAndAcceptedVersionRoundTrips() throws {
        var archive = Archive()
        archive.preferences.hasOnboarded = true
        let legacy = try Archive.decode(archive.encoded())
        XCTAssertTrue(legacy.preferences.hasOnboarded)
        XCTAssertNil(legacy.preferences.aiConsentVersion)
        archive.preferences.aiConsentVersion = 1
        XCTAssertEqual(try Archive.decode(archive.encoded()).preferences.aiConsentVersion, 1)
    }

    private func evidence(languageID: String, day: Int = 0, supported: Bool = false) -> SessionRecord {
        let sample = Self.samples[languageID] ?? Self.samples["ko"]!
        let date = Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86400)
        var session = SessionRecord(languageID: languageID, themeID: "coffee")
        session.startedAt = date
        session.append(Fragment(speaker: .user, text: sample.text, startMS: 1000, endMS: 2000, receivedAt: date, meaningVisible: supported))
        let passage = session.passages[0]
        session.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey, outcome: .success,
            suggestedLevel: 3, nextGoal: "A goal for \(languageID)", capability: "Describes a familiar action",
            words: [WordProposal(lemma: sample.lemma, meaning: sample.meaning, form: sample.form, kind: .independent, confidence: 0.95,
                sourceIDs: passage.fragments.map(\.id), quote: sample.text, language: languageID)], createdAt: date)]
        return session
    }

    func testRegisteredModulesAreKoreanAndJapaneseOnly() {
        XCTAssertEqual(LanguageRegistry.all.map(\.id), ["ko", "ja"])
        XCTAssertEqual(LanguageRegistry.defaultID, "ko")
        XCTAssertNil(LanguageRegistry.module(for: "nb"))
        XCTAssertNil(LanguageRegistry.module(for: "es"))
        XCTAssertEqual(Preferences().learningLanguageID, "ko")
        for (id, locale, greeting, native) in [("ko", "ko-KR", "안녕하세요!", "한국어"), ("ja", "ja-JP", "こんにちは！", "日本語")] {
            XCTAssertEqual(LanguageRegistry.module(for: id)?.locale, locale)
            XCTAssertEqual(LanguageRegistry.module(for: id)?.greeting, greeting)
            XCTAssertEqual(LanguageRegistry.module(for: id)?.nativeName, native)
        }
        XCTAssertFalse(MeaningLanguages.all.contains("Norwegian"))
        XCTAssertEqual(MeaningLanguages.all.first, "English")
        XCTAssertEqual(MeaningLanguages.greeting(in: "English"), "Hi!")
    }

    func testProgressAndVocabularyStayWithinTheirLanguage() {
        let sessions = [evidence(languageID: "ko"), evidence(languageID: "ko", day: 2)]
        let korean = LearningEngine.project(sessions, languageID: "ko", now: sessions[1].startedAt)
        let japanese = LearningEngine.project(sessions, languageID: "ja", now: sessions[1].startedAt)
        XCTAssertEqual(korean.challenge, 1)
        XCTAssertEqual(korean.words.first?.bars, 2)
        XCTAssertEqual(japanese.challenge, 0)
        XCTAssertEqual(japanese.observationCount, 0)
        XCTAssertTrue(japanese.words.isEmpty)
        XCTAssertNotEqual(japanese.nextGoal, "A goal for ko")
    }

    func testHidingAWordDoesNotHideItInTheOtherLanguage() {
        let sessions = [evidence(languageID: "ja"), evidence(languageID: "ko")]
        let koreanID = sessions[1].assessments[0].words[0].key
        XCTAssertTrue(LearningEngine.project(sessions, languageID: "ko", hiddenWords: [koreanID]).words.isEmpty)
        XCTAssertEqual(LearningEngine.project(sessions, languageID: "ja", hiddenWords: [koreanID]).words.count, 1)
    }

    func testEvidenceInAnotherLanguageIsNeverCredited() {
        for kind in [EvidenceKind.independent, .assisted, .understanding, .exposure, .lapse] {
            var session = evidence(languageID: "ko")
            session.assessments[0].words[0].language = "ja"
            session.assessments[0].words[0].kind = kind
            XCTAssertTrue(LearningEngine.validate(session.assessments[0], session: session)!.words.isEmpty)
        }
    }

    func testKoreanWithMeaningSupportIsAssisted() {
        let session = evidence(languageID: "ko", supported: true)
        XCTAssertEqual(LearningEngine.validate(session.assessments[0], session: session)?.words.first?.kind, .assisted)
        XCTAssertEqual(LearningEngine.project([session], languageID: "ko").words.first?.independentCount, 0)
    }

    func testVersionOneMigrationAdoptsTheDefaultModuleAndKeepsHiddenWords() throws {
        var original = Archive()
        var session = evidence(languageID: "ko")
        session.topics = [TopicBrief(languageID: "ko", query: "weather", text: "오늘은 날씨가 좋아요.", sources: [])]
        original.sessions = [session]
        original.preferences.hiddenWords = [session.assessments[0].words[0].key]
        var legacy = try JSONSerialization.jsonObject(with: original.encoded()) as! [String: Any]
        legacy["schemaVersion"] = 1
        var preferences = legacy["preferences"] as! [String: Any]
        preferences.removeValue(forKey: "learningLanguageID")
        preferences["hiddenWords"] = ["마시다|to drink"]
        legacy["preferences"] = preferences
        var oldSession = (legacy["sessions"] as! [[String: Any]])[0]
        oldSession.removeValue(forKey: "languageID")
        var oldTopic = (oldSession["topics"] as! [[String: Any]])[0]
        oldTopic.removeValue(forKey: "languageID")
        oldSession["topics"] = [oldTopic]; legacy["sessions"] = [oldSession]
        let migrated = try Archive.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.preferences.learningLanguageID, "ko")
        XCTAssertEqual(migrated.preferences.hiddenWords, original.preferences.hiddenWords)
        XCTAssertEqual(migrated.sessions[0].id, session.id)
        XCTAssertEqual(migrated.sessions[0].fragments, session.fragments)
        XCTAssertEqual(migrated.sessions[0].topics[0].languageID, "ko")
        XCTAssertEqual(migrated.sessions[0].topics[0].text, session.topics[0].text)
        XCTAssertEqual(LearningEngine.project(migrated.sessions).words.first?.independentCount, 1)
        XCTAssertTrue(LearningEngine.project(migrated.sessions, hiddenWords: migrated.preferences.hiddenWords).words.isEmpty)
        XCTAssertEqual(try Archive.decode(migrated.encoded()).preferences.hiddenWords, original.preferences.hiddenWords)
    }

    func testBilingualArchiveRoundTripAndSelection() throws {
        var archive = Archive()
        archive.preferences.learningLanguageID = "ja"
        archive.sessions = [evidence(languageID: "ko"), evidence(languageID: "ja")]
        let restored = try Archive.decode(archive.encoded())
        XCTAssertEqual(restored.preferences.learningLanguageID, "ja")
        XCTAssertEqual(restored.sessions.map(\.languageID), ["ko", "ja"])
        XCTAssertEqual(LearningEngine.project(restored.sessions, languageID: "ja").words.count, 1)
    }

    func testVersionTwoRequiresExplicitSupportedLanguage() throws {
        var archive = Archive(); archive.sessions = [evidence(languageID: "ko")]
        var root = try JSONSerialization.jsonObject(with: archive.encoded()) as! [String: Any]
        var session = (root["sessions"] as! [[String: Any]])[0]
        session.removeValue(forKey: "languageID"); root["sessions"] = [session]
        XCTAssertThrowsError(try Archive.decode(JSONSerialization.data(withJSONObject: root)))
        archive.sessions = [SessionRecord(languageID: "not-installed")]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }

    func testAnArchiveFromARemovedModuleIsRejectedRatherThanCrashing() throws {
        var archive = Archive(); archive.sessions = [evidence(languageID: "ko")]
        var root = try JSONSerialization.jsonObject(with: archive.encoded()) as! [String: Any]
        var preferences = root["preferences"] as! [String: Any]
        preferences["learningLanguageID"] = "nb"
        root["preferences"] = preferences
        XCTAssertThrowsError(try Archive.decode(JSONSerialization.data(withJSONObject: root))) {
            XCTAssertEqual($0 as? ArchiveError, .unsupportedLanguage)
        }
    }

    func testTopicCannotBeAttachedToADifferentLanguage() throws {
        var archive = Archive(); var session = SessionRecord(languageID: "ko")
        session.topics = [TopicBrief(languageID: "ja", query: "food", text: "ごはん", sources: [])]
        archive.sessions = [session]
        XCTAssertThrowsError(try Archive.decode(archive.encoded()))
    }

    func testEveryModuleHasCompleteCurriculumAndStableThemeIDs() {
        XCTAssertEqual(Set(LanguageRegistry.all.map(\.id)).count, LanguageRegistry.all.count)
        for language in LanguageRegistry.all {
            XCTAssertEqual(language.teachingFocus.count, 6)
            XCTAssertTrue(language.teachingFocus.allSatisfy { !$0.isEmpty })
            XCTAssertEqual(Set(language.themes.map(\.id)), Set(ConversationTheme.shared.map(\.id)))
            XCTAssertTrue(language.themeOverrides.allSatisfy { $0.key == $0.value.id })
            XCTAssertFalse(language.speechGuidance.isEmpty)
            XCTAssertFalse(language.lemmaGuidance.isEmpty)
            XCTAssertFalse(language.lookupUnavailableReply.isEmpty)
        }
    }

    func testEachModuleDrivesEveryPromptWithoutLeakingTheOtherTarget() throws {
        for language in LanguageRegistry.all {
            let other = try XCTUnwrap(LanguageRegistry.all.first { $0.id != language.id })
            let learner = LearningEngine.project([], languageID: language.id)
            let voice = TeachingPolicy.voice(language: language, learner: learner, theme: language.themes[0], interests: "", meaningLanguage: "English")
            let assessment = TeachingPolicy.assessment(language: language)
            let prompts = [voice, assessment, TeachingPolicy.greeting(language: language), TeachingPolicy.help(language: language),
                TeachingPolicy.redirect(language: language), TeachingPolicy.translation(language: language, meaningLanguage: "English"),
                TeachingPolicy.delegation(language: language), TeachingPolicy.typedReply(language: language),
                TeachingPolicy.lookup(language: language, meaningLanguage: "English"), TeachingPolicy.currentTopic(language: language)]
            for prompt in prompts {
                XCTAssertTrue(prompt.contains(language.name), language.id)
                XCTAssertFalse(prompt.contains(other.name), language.id)
                XCTAssertFalse(prompt.contains("Norwegian"), language.id)
                XCTAssertFalse(prompt.contains("Spanish"), language.id)
            }
            XCTAssertTrue(voice.contains("Speak ONLY \(language.name)."))
            XCTAssertTrue(voice.contains(language.speechGuidance))
            XCTAssertTrue(voice.contains(language.writingGuidance))
            XCTAssertTrue(voice.contains("Meaning subtitles in English"))
            XCTAssertTrue(assessment.contains(language.lemmaGuidance))
            XCTAssertTrue(assessment.contains("Use language \(language.id) for target-language evidence"))
            XCTAssertTrue(TeachingPolicy.typedReply(language: language).contains("Reply only in \(language.name)"))
            XCTAssertTrue(TeachingPolicy.redirect(language: language).contains("continue ONLY in \(language.name)"))
        }
    }

    func testBothLanguagesKeepSeparateProgressAndGlossaryKeys() throws {
        var archive = Archive()
        archive.preferences.learningLanguageID = "ja"
        archive.sessions = ["ko", "ja"].flatMap { [evidence(languageID: $0), evidence(languageID: $0, day: 2)] }
        let restored = try Archive.decode(archive.encoded())
        let keys = ["ko", "ja"].compactMap { id -> String? in
            let learner = LearningEngine.project(restored.sessions, languageID: id, now: restored.sessions.last!.startedAt)
            XCTAssertEqual(learner.observationCount, 2, id)
            XCTAssertEqual(learner.words.count, 1, id)
            XCTAssertEqual(learner.words.first?.independentCount, 2, id)
            XCTAssertEqual(learner.words.first?.bars, 2, id)
            return learner.words.first?.id
        }
        XCTAssertEqual(Set(keys).count, 2)
    }

    func testNativeScriptEvidenceSurvivesExportImportExactly() throws {
        for (id, sample) in Self.samples {
            var archive = Archive()
            archive.preferences.learningLanguageID = id
            archive.sessions = [evidence(languageID: id)]
            let restored = try Archive.decode(archive.encoded())
            let record = restored.sessions[0]
            let word = try XCTUnwrap(LearningEngine.validate(record.assessments[0], session: record)?.words.first)
            XCTAssertEqual(word.lemma, sample.lemma)
            XCTAssertEqual(word.quote, sample.text)
            XCTAssertEqual(word.kind, .independent)
            XCTAssertEqual(record.passages[0].text, sample.text)
        }
    }

    func testLanguageRedirectUsesTheSelectedTargetInsteadOfAnEnglishBlacklist() {
        for language in LanguageRegistry.all {
            XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: language.id, confidence: 0.99))
            let otherID = language.id == "ko" ? "ja" : "ko"
            XCTAssertTrue(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: otherID, confidence: 0.99))
            XCTAssertTrue(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: "en", confidence: 0.99))
            for confidence in [0.0, 0.88, .nan, .infinity, 1.1] {
                XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: otherID, confidence: confidence))
            }
            XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: "und", confidence: 0.99))
            XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: language, detectedLanguageID: "", confidence: 0.99))
        }
    }
}
