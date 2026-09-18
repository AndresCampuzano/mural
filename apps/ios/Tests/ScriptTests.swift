import XCTest
@testable import MuralCore

/// Korean is written with spaces and sounds out letter by letter; Japanese is written
/// without spaces and needs both word segmentation and an optional reading.
final class ScriptTests: XCTestCase {
    func testKoreanNeedsNoSegmentationLocaleOrReadingAid() {
        let korean = LanguageModule.korean
        XCTAssertNil(korean.wordSegmentationLocale)
        XCTAssertNil(korean.readingAidName)
    }

    func testJapaneseDeclaresSegmentationAndRomaji() {
        let japanese = LanguageModule.japanese
        XCTAssertEqual(japanese.wordSegmentationLocale, "ja_JP")
        XCTAssertEqual(japanese.readingAidName, "romaji")
    }

    func testJapaneseReadingsUseDictionaryWordsAndSpokenParticles() {
        for (text, expected) in [("こんにちは", "konnichiwa"), ("こんにちは！", "konnichiwa！"), ("東京", "toukyou"),
                                 ("コーヒーを飲みます。", "kōhī o nomi masu。"),
                                 ("今日は天気がいいですね。", "kyou wa tenki ga ii desu ne。")] {
            XCTAssertEqual(Readings.reading(text, locale: "ja_JP"), expected, text)
        }
        XCTAssertEqual(Readings.reading(LanguageModule.japanese.greeting, locale: "ja_JP"), "konnichiwa！")
    }

    func testTextWithoutJapaneseScriptHasNoReading() {
        for text in ["", "Hello, Mural 2026! ☕️", "12345"] {
            XCTAssertNil(Readings.reading(text, locale: "ja_JP"), text)
        }
    }

    func testJapaneseSegmentationPreservesEveryCharacterAndLinksWords() {
        for text in ["", "こんにちは！", "  コーヒーを飲みます。\n", "日本語とEnglish", "今日は天気がいいですね。"] {
            XCTAssertEqual(Readings.tokens(text, locale: "ja_JP").map(\.text).joined(), text, text)
            XCTAssertEqual(CaptionWords.segments(text, languageID: "ja").map(\.text).joined(), text, text)
        }
        let links = CaptionWords.segments("コーヒーを飲みます。", languageID: "ja").compactMap(\.lookup)
        XCTAssertTrue(links.contains("コーヒー"))
        XCTAssertTrue(links.contains("飲み"))
        XCTAssertFalse(links.contains(where: { $0.contains("。") }))
    }

    func testKoreanWordLinksSplitOnSpacesAndDropPunctuation() {
        for (text, expected) in [("저는 커피를 마셔요.", ["저는", "커피를", "마셔요"]),
                                 ("  안녕하세요!\n오늘 어땠어요?  ", ["안녕하세요", "오늘", "어땠어요"])] {
            let segments = CaptionWords.segments(text, languageID: "ko")
            XCTAssertEqual(segments.map(\.text).joined(), text)
            XCTAssertEqual(segments.compactMap(\.lookup), expected)
        }
    }

    func testAnUnknownLanguageFallsBackToWhitespaceSegmentation() {
        let segments = CaptionWords.segments("hello there", languageID: "zz")
        XCTAssertEqual(segments.map(\.text).joined(), "hello there")
        XCTAssertEqual(segments.compactMap(\.lookup), ["hello", "there"])
    }

    func testScriptAndRegionalDetectorIDsDoNotCauseRedirectLoops() {
        for detected in ["ja", "ja-JP", "ja_JP", "JA"] {
            XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: .japanese, detectedLanguageID: detected, confidence: 0.99))
        }
        for detected in ["ko", "ko-KR", "KO-KR"] {
            XCTAssertFalse(TeachingPolicy.shouldRedirectSpeech(language: .korean, detectedLanguageID: detected, confidence: 0.99))
        }
        XCTAssertTrue(TeachingPolicy.shouldRedirectSpeech(language: .japanese, detectedLanguageID: "zh-Hans", confidence: 0.99))
        XCTAssertTrue(TeachingPolicy.shouldRedirectSpeech(language: .korean, detectedLanguageID: "kox", confidence: 0.99))
    }

    func testSupportedAndTypedPracticeCannotBecomeIndependentRecall() {
        let samples = [("ko", "커피를 마셔요.", "마시다", "마셔요"), ("ja", "コーヒーを飲みます。", "飲む", "飲みます")]
        for (id, text, lemma, form) in samples {
            for (supported, typed) in [(true, false), (false, true), (true, true)] {
                var record = SessionRecord(languageID: id, themeID: "coffee")
                record.append(Fragment(speaker: .user, text: text, startMS: 0, endMS: 3000, meaningVisible: supported, typed: typed))
                let passage = record.passages[0]
                record.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey, outcome: .success,
                    suggestedLevel: 3, nextGoal: "Goal for \(id)", capability: "Describes a familiar action",
                    words: [WordProposal(lemma: lemma, meaning: "to drink", form: form, kind: .independent, confidence: 0.95,
                        sourceIDs: passage.fragments.map(\.id), quote: text, language: id)])]
                XCTAssertEqual(LearningEngine.validate(record.assessments[0], session: record)?.words.first?.kind, .assisted, id)
                XCTAssertEqual(LearningEngine.project([record], languageID: id).words.first?.independentCount, 0, id)
            }
        }
    }
}
