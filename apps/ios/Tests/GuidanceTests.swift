import XCTest
@testable import MuralCore

/// The learner's chosen level and speaking pace: what they change in the prompts, and what
/// they are not allowed to change in the learning record.
final class GuidanceTests: XCTestCase {
    private let meaning = "English"

    private func voice(_ level: GuidanceLevel, language: LanguageModule = .korean, pace: SpeechPace = .natural) -> String {
        TeachingPolicy.voice(language: language, learner: LearningEngine.project([], languageID: language.id),
                             theme: nil, interests: "", meaningLanguage: meaning, level: level, pace: pace)
    }

    func testAnArchiveWithoutALevelKeepsTheOriginalTargetOnlyBehaviour() throws {
        var archive = Archive()
        archive.preferences.hasOnboarded = true
        let data = try archive.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("guidanceLevelID"))
        XCTAssertFalse(text.contains("speechSpeed"))
        let restored = try Archive.decode(data)
        XCTAssertEqual(restored.preferences.guidanceLevel, .inAtTheDeepEnd)
        XCTAssertEqual(restored.preferences.speed, 1)
        XCTAssertEqual(restored.preferences.pace, .natural)
    }

    func testAChosenLevelAndPaceSurviveExportAndImport() throws {
        var archive = Archive()
        archive.preferences.guidanceLevelID = GuidanceLevel.startingOut.rawValue
        archive.preferences.speechSpeed = SpeechPace.slow.speed
        let restored = try Archive.decode(archive.encoded())
        XCTAssertEqual(restored.preferences.guidanceLevel, .startingOut)
        XCTAssertEqual(restored.preferences.pace, .slow)
        XCTAssertEqual(restored.preferences.speed, 0.7)
    }

    func testAnUnsetPaceFollowsTheLevelUntilTheLearnerChoosesOne() {
        var preferences = Preferences()
        for level in GuidanceLevel.allCases {
            preferences.guidanceLevelID = level.rawValue
            XCTAssertNil(preferences.speechSpeed)
            XCTAssertEqual(preferences.pace, level.pace, level.rawValue)
            XCTAssertEqual(preferences.speed, level.pace.speed, level.rawValue)
        }
        preferences.speechSpeed = SpeechPace.brisk.speed
        preferences.guidanceLevelID = GuidanceLevel.startingOut.rawValue
        XCTAssertEqual(preferences.pace, .brisk)
    }

    func testAnUnknownLevelFallsBackInsteadOfRejectingTheBackup() throws {
        var archive = Archive()
        archive.preferences.guidanceLevelID = "shouting-in-the-street"
        let restored = try Archive.decode(archive.encoded())
        XCTAssertEqual(restored.preferences.guidanceLevel, .inAtTheDeepEnd)
    }

    func testAStoredSpeedOutsideTheProviderRangeIsRejected() throws {
        for speed in [2.0, 0.1, -1] {
            var archive = Archive()
            archive.preferences.speechSpeed = speed
            let data = try archive.encoded()
            XCTAssertThrowsError(try Archive.decode(data), "\(speed)") { error in
                XCTAssertEqual((error as? ArchiveError)?.errorDescription, ArchiveError.invalid.errorDescription)
            }
        }
        // JSON cannot carry a non-finite number, so one can only arrive in memory. It falls back.
        var infinite = Preferences()
        infinite.speechSpeed = .nan
        XCTAssertEqual(infinite.speed, GuidanceLevel.inAtTheDeepEnd.pace.speed)
        infinite.speechSpeed = .infinity
        XCTAssertEqual(infinite.speed, GuidanceLevel.inAtTheDeepEnd.pace.speed)
        for pace in SpeechPace.allCases {
            var archive = Archive()
            archive.preferences.speechSpeed = pace.speed
            XCTAssertEqual(try Archive.decode(archive.encoded()).preferences.pace, pace)
        }
    }

    func testEveryPaceStaysInsideTheDocumentedProviderRange() {
        for pace in SpeechPace.allCases {
            XCTAssertTrue(SpeechPace.range.contains(pace.speed), pace.rawValue)
            XCTAssertEqual(SpeechPace.nearest(to: pace.speed), pace)
        }
        XCTAssertEqual(SpeechPace.nearest(to: 0.71), .slow)
        XCTAssertEqual(SpeechPace.nearest(to: 5), .brisk)
        XCTAssertEqual(SpeechPace.nearest(to: .nan), .natural)
        XCTAssertEqual(GuidanceLevel.startingOut.pace, .slow)
        XCTAssertEqual(GuidanceLevel.inAtTheDeepEnd.pace, .natural)
    }

    func testTheDeepEndKeepsTheTargetOnlyPromptsUnchanged() {
        for language in LanguageRegistry.all {
            XCTAssertTrue(voice(.inAtTheDeepEnd, language: language).contains("Speak ONLY \(language.name)."))
            XCTAssertTrue(TeachingPolicy.greeting(language: language, level: .inAtTheDeepEnd, meaningLanguage: meaning)
                .contains("All speech must be in \(language.name)."))
            XCTAssertTrue(TeachingPolicy.typedReply(language: language, level: .inAtTheDeepEnd, meaningLanguage: meaning)
                .contains("Reply only in \(language.name)"))
            XCTAssertTrue(TeachingPolicy.delegation(language: language, level: .inAtTheDeepEnd, meaningLanguage: meaning)
                .contains("ONLY in \(language.name)"))
            // The defaulted argument is the same prompt, so untouched call sites keep their behaviour.
            XCTAssertEqual(TeachingPolicy.greeting(language: language), TeachingPolicy.greeting(language: language, level: .inAtTheDeepEnd))
            XCTAssertEqual(TeachingPolicy.redirect(language: language), TeachingPolicy.redirect(language: language, level: .inAtTheDeepEnd))
        }
    }

    func testStartingOutAsksForTheLearnersOwnLanguageAndShortTaughtPhrases() {
        for language in LanguageRegistry.all {
            let prompt = voice(.startingOut, language: language)
            XCTAssertFalse(prompt.contains("Speak ONLY \(language.name)."), language.id)
            XCTAssertTrue(prompt.contains("Speak mainly in \(meaning)"), language.id)
            XCTAssertTrue(prompt.contains("one useful expression"), language.id)
            XCTAssertTrue(prompt.contains(language.speechGuidance), language.id)
            XCTAssertTrue(prompt.contains(language.writingGuidance), language.id)
            XCTAssertTrue(TeachingPolicy.greeting(language: language, level: .startingOut, meaningLanguage: meaning)
                .contains("Greet the learner in \(meaning)"), language.id)
            XCTAssertTrue(TeachingPolicy.typedReply(language: language, level: .startingOut, meaningLanguage: meaning)
                .contains("Reply in \(meaning)"), language.id)
        }
    }

    /// The opener follows the chosen theme and a randomly picked way in, instead of always
    /// teaching the same greeting.
    func testTheOpenerFollowsTheThemeAndVariesInsteadOfAlwaysTeachingHello() {
        for language in LanguageRegistry.all {
            let other = LanguageRegistry.all.first { $0.id != language.id }!.name
            let themes = language.themes.prefix(3) + (language.course.map { c in c.topics.prefix(2).map { c.theme(for: $0, mode: .drill, language: language) } } ?? [])
            for level in GuidanceLevel.allCases {
                XCTAssertFalse(voice(level, language: language).contains("phrase is \(language.greeting)"), "\(language.id) \(level)")
                for theme in themes {
                    let openers = TeachingPolicy.openingAngles.indices.map {
                        TeachingPolicy.greeting(language: language, level: level, meaningLanguage: meaning, theme: theme, angle: $0)
                    }
                    XCTAssertEqual(Set(openers).count, TeachingPolicy.openingAngles.count, "\(language.id) \(theme.id)")
                    for opener in openers {
                        XCTAssertTrue(opener.contains(theme.situation), "\(language.id) \(theme.id)")
                        XCTAssertFalse(opener.contains("teach ‘\(language.greeting)’"), "\(language.id) \(theme.id)")
                        XCTAssertFalse(opener.contains(other), "\(language.id) \(theme.id)")
                    }
                }
                let free = TeachingPolicy.greeting(language: language, level: level, meaningLanguage: meaning)
                XCTAssertTrue(free.contains("No situation is chosen"), language.id)
            }
        }
    }

    func testFindingMyFeetAsksInTheTargetLanguageAndExplainsInTheLearnersOwn() {
        for language in LanguageRegistry.all {
            for meaning in ["English", "Spanish"] {
                let prompt = TeachingPolicy.voice(language: language, learner: LearnerState(challenge: 0, observationCount: 0, nextGoal: "", capabilities: [], words: []),
                                                  theme: nil, interests: "", meaningLanguage: meaning, level: .findingMyFeet)
                let label = "\(language.id) \(meaning)"
                XCTAssertTrue(prompt.contains("Use \(language.name) for the conversation itself"), label)
                XCTAssertTrue(prompt.contains("cannot follow explanations in \(language.name). Explain in \(meaning)"), label)
                XCTAssertTrue(prompt.contains("a very brief explanation in \(meaning)"), "corrections are explained in \(meaning): \(label)")
                XCTAssertTrue(prompt.contains("never be harder than your questions"), label)
                XCTAssertFalse(prompt.contains("Speak ONLY \(language.name)."), label)
                XCTAssertTrue(TeachingPolicy.delegation(language: language, level: .findingMyFeet, meaningLanguage: meaning).contains("Explain in \(meaning)"), label)
                XCTAssertTrue(TeachingPolicy.typedReply(language: language, level: .findingMyFeet, meaningLanguage: meaning).contains("explain it in \(meaning)"), label)
                XCTAssertTrue(TeachingPolicy.redirect(language: language, level: .findingMyFeet, meaningLanguage: meaning)
                    .contains("explanations stay brief and in \(meaning)"), label)
            }
        }
    }

    func testOnlyTheDeepEndExplainsInTheTargetLanguageAndThenMoreSimply() {
        for language in LanguageRegistry.all {
            XCTAssertEqual(GuidanceLevel.inAtTheDeepEnd.explanationLanguage(language: language, meaningLanguage: "Polish"), language.name)
            XCTAssertEqual(GuidanceLevel.findingMyFeet.explanationLanguage(language: language, meaningLanguage: "Polish"), "Polish")
            XCTAssertEqual(GuidanceLevel.startingOut.explanationLanguage(language: language, meaningLanguage: "Polish"), "Polish")
            let deep = voice(.inAtTheDeepEnd, language: language)
            XCTAssertTrue(deep.contains("use simpler \(language.name) than the thing you are explaining"), language.id)
            XCTAssertTrue(deep.contains("never answer confusion with a longer explanation"), language.id)
        }
    }

    func testTheChosenLevelCapsHowHardTheTeachingFocusGets() {
        let advanced = LearnerState(challenge: 5, observationCount: 20, nextGoal: "", capabilities: [], words: [])
        for language in LanguageRegistry.all {
            for level in GuidanceLevel.allCases {
                let prompt = TeachingPolicy.voice(language: language, learner: advanced, theme: nil, interests: "", meaningLanguage: meaning, level: level)
                let stage = TeachingPolicy.focusStage(advanced, level: level)
                XCTAssertEqual(stage, min(5, level.maximumChallenge))
                XCTAssertTrue(prompt.contains("Language-specific focus: \(language.teachingFocus[stage])"), "\(language.id) \(level.rawValue)")
            }
            XCTAssertFalse(TeachingPolicy.voice(language: language, learner: advanced, theme: nil, interests: "", meaningLanguage: meaning, level: .findingMyFeet)
                .contains(language.teachingFocus[5]), "advanced grammar stays out of a supported level: \(language.id)")
        }
        XCTAssertLessThan(GuidanceLevel.startingOut.maximumChallenge, GuidanceLevel.findingMyFeet.maximumChallenge)
        XCTAssertEqual(TeachingPolicy.focusStage(LearnerState(challenge: -3, observationCount: 0, nextGoal: "", capabilities: [], words: []), level: .inAtTheDeepEnd), 0)
    }

    /// GPT-Live has no speed setting, so the pace exists only as words in the prompt.
    func testThePaceIsAskedForInWords() {
        XCTAssertTrue(voice(.startingOut, pace: .slow).contains("Speak slowly."))
        XCTAssertTrue(voice(.findingMyFeet, pace: .gentle).contains("a little more slowly than usual"))
        XCTAssertTrue(voice(.inAtTheDeepEnd, pace: .natural).contains("natural, unhurried pace"))
        XCTAssertTrue(voice(.inAtTheDeepEnd, pace: .brisk).contains("natural, lively pace"))
    }

    /// A pace chosen during a conversation is sent as the same rule the opening prompt carries,
    /// and names no language, so it reads the same in every module.
    func testAPaceChangeMidConversationCarriesTheSameRuleForEveryModule() {
        let names = LanguageRegistry.all.map(\.name)
        for pace in SpeechPace.allCases {
            let change = TeachingPolicy.paceChange(pace)
            XCTAssertTrue(change.hasPrefix("The learner has just changed how quickly they want you to speak. From now on: "), pace.rawValue)
            let rule = String(change.dropFirst("The learner has just changed how quickly they want you to speak. From now on: ".count))
            for language in LanguageRegistry.all {
                XCTAssertTrue(voice(.inAtTheDeepEnd, language: language, pace: pace).contains(rule), "\(language.id) \(pace.rawValue)")
            }
            for name in names { XCTAssertFalse(change.contains(name), "\(pace.rawValue) \(name)") }
        }
    }

    func testEveryLevelKeepsTheOtherModuleOutOfItsPrompts() throws {
        for language in LanguageRegistry.all {
            let other = try XCTUnwrap(LanguageRegistry.all.first { $0.id != language.id })
            for level in GuidanceLevel.allCases {
                let prompts = [voice(level, language: language),
                               TeachingPolicy.greeting(language: language, level: level, meaningLanguage: meaning),
                               TeachingPolicy.redirect(language: language, level: level, meaningLanguage: meaning),
                               TeachingPolicy.typedReply(language: language, level: level, meaningLanguage: meaning),
                               TeachingPolicy.delegation(language: language, level: level, meaningLanguage: meaning),
                               TeachingPolicy.levelChange(language: language, level: level, meaningLanguage: meaning)]
                for prompt in prompts {
                    XCTAssertTrue(prompt.contains(language.name), "\(language.id) \(level.rawValue)")
                    XCTAssertFalse(prompt.contains(other.name), "\(language.id) \(level.rawValue)")
                }
            }
        }
    }

    func testOnlyTheDeepEndExpectsMuralToStayInTheTargetLanguage() {
        // Below the deep end, explanations arrive in the learner's own language on purpose, so the
        // drift check must not pull Mural back mid-explanation.
        XCTAssertFalse(GuidanceLevel.startingOut.expectsTargetLanguageThroughout)
        XCTAssertFalse(GuidanceLevel.findingMyFeet.expectsTargetLanguageThroughout)
        XCTAssertTrue(GuidanceLevel.inAtTheDeepEnd.expectsTargetLanguageThroughout)
    }

    func testTheChooserDescribesEveryModuleInTheLearnersOwnSubtitleLanguage() throws {
        for language in LanguageRegistry.all {
            let other = try XCTUnwrap(LanguageRegistry.all.first { $0.id != language.id })
            for level in GuidanceLevel.allCases {
                let detail = level.detail(language: language, meaningLanguage: "Spanish")
                let label = "\(language.id) \(level.rawValue)"
                XCTAssertFalse(detail.isEmpty, label)
                XCTAssertFalse(level.title.isEmpty, label)
                XCTAssertTrue(detail.contains(language.name), label)
                XCTAssertFalse(detail.contains(other.name), label)
                XCTAssertEqual(detail.contains("Spanish"), level != .inAtTheDeepEnd, label)
            }
        }
        XCTAssertEqual(GuidanceLevel.allCases.map(\.title), ["Starting out", "Finding my feet", "In at the deep end"])
        XCTAssertEqual(GuidanceLevel.startingOut.detail(language: .japanese, meaningLanguage: "English"),
                       "Mural speaks English and teaches Japanese one short phrase at a time.")
        XCTAssertEqual(GuidanceLevel.inAtTheDeepEnd.detail(language: .japanese, meaningLanguage: "English"),
                       "Japanese only, at a natural pace.")
    }

    /// The level is a teaching choice. In either module it must not make a phrase the learner
    /// has just heard look like recall.
    func testABeginnerRepeatingMuralsPhraseIsAssistedNotIndependent() throws {
        for language in LanguageRegistry.all {
            let greeting = language.greetingWord
            var session = SessionRecord(languageID: language.id, themeID: "coffee")
            session.append(Fragment(speaker: .assistant, text: "\(greeting) means hello. Try saying \(greeting).", startMS: 0, endMS: 4000))
            session.append(Fragment(speaker: .user, text: greeting, startMS: 5000, endMS: 6000))
            let passage = try XCTUnwrap(session.passages.last { $0.speaker == .user })
            session.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey, outcome: .success,
                suggestedLevel: 1, nextGoal: "Greet and give a name", capability: "Greets someone",
                words: [WordProposal(lemma: greeting, meaning: "hello", form: greeting, kind: .independent, confidence: 0.99,
                    sourceIDs: passage.fragments.map(\.id), quote: greeting, language: language.id)])]
            let validated = try XCTUnwrap(LearningEngine.validate(session.assessments[0], session: session))
            XCTAssertEqual(validated.words.first?.kind, .assisted, language.id)
            let learner = LearningEngine.project([session], languageID: language.id)
            XCTAssertEqual(learner.words.first?.independentCount, 0, language.id)
            XCTAssertEqual(learner.words.first?.bars, 0, language.id)
        }
    }
}
