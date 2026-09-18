import XCTest

final class MuralUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let footer = app.buttons["onboarding-continue"].frame
            if element.isHittable && element.frame.minY >= 110 && element.frame.maxY < footer.minY - 16 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func checkNewOnboarding(id: String, greeting: String, romaji: String? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let choice = app.buttons["onboarding-language-\(id)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        reveal(choice, in: app)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Language selection - \(id)"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, greeting)
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
        if let romaji {
            XCTAssertEqual(app.staticTexts.matching(identifier: "reading-text").count, 1)
            XCTAssertEqual(app.staticTexts["reading-text"].label, romaji)
            app.buttons["reading-toggle"].tap()
            XCTAssertTrue(app.staticTexts["reading-text"].waitForNonExistence(timeout: 3))
            app.buttons["reading-toggle"].tap()
            XCTAssertTrue(app.staticTexts["reading-text"].waitForExistence(timeout: 3))
        } else {
            XCTAssertFalse(app.buttons["reading-toggle"].exists)
        }
    }

    func testKoreanOnboardingHasNoReadingAid() { checkNewOnboarding(id: "ko", greeting: "안녕하세요!") }
    func testJapaneseOnboardingWithOptionalRomaji() { checkNewOnboarding(id: "ja", greeting: "こんにちは！", romaji: "konnichiwa！") }

    func testJapaneseSelectionAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let choice = app.buttons["onboarding-language-ja"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        reveal(choice, in: app)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        let privacy = app.descendants(matching: .any).matching(identifier: "onboarding-privacy-policy").firstMatch
        reveal(privacy, in: app)
        XCTAssertTrue(app.staticTexts["onboarding-ai-consent"].exists)
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Japanese onboarding - largest accessibility text"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "こんにちは！")
    }

    func testSettingsThemesWordsAndReturnToKorean() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Japanese · Standard Japanese"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "こんにちは！")
        XCTAssertEqual(app.staticTexts["reading-text"].label, "konnichiwa！")
        app.tabBars.buttons["Themes"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "コーヒーでも")).firstMatch.exists)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Little by little · Japanese")).firstMatch.exists)
        app.tabBars.buttons["Talk"].tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Korean · Seoul standard"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
        XCTAssertFalse(app.buttons["reading-toggle"].exists)
    }

    func testSimplifiedChineseMeaningsAreAvailableInOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Chinese (Simplified)"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "你好！")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["meaning-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "你好！")
    }

    func testJapaneseTranscriptRetainsSourceTextAndRomajiAfterReset() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ended-conversation", "--preview-language=ja"]
        app.launch()
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "コーヒーが好きです。")
        XCTAssertEqual(app.staticTexts.matching(identifier: "reading-text").firstMatch.label, "kōhī ga suki desu。")
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["コーヒーが好きです。"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "reading-text").firstMatch.label, "kōhī ga suki desu。")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Japanese transcript and romaji"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["Done"].tap()
        app.buttons["new-conversation"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "こんにちは！")
        app.tabBars.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "コーヒーでも")).firstMatch.exists)
    }

    private func launch(ended: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--preview"] + (ended ? ["--ended-conversation"] : [])
        app.launch(); return app
    }
    func testGreetingAndMeaningToggle() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
        app.buttons["Hide meaning subtitles"].tap()
        XCTAssertFalse(app.staticTexts["meaning-caption"].exists)
        app.buttons["Show meaning subtitles"].tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
    }
    func testThemeSurvivesNavigationToWords() {
        let app = launch()
        app.tabBars.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "커피 한잔")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["커피 한잔?"].exists)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["Your words."].exists)
        app.tabBars.buttons["Talk"].tap()
        XCTAssertTrue(app.staticTexts["커피 한잔?"].exists)
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
    }
    func testSettingsOfferSecureKeyEntryAndBackups() {
        let app = launch()
        app.buttons["Settings"].tap()
        if app.buttons["managed-account-settings"].exists {
            app.buttons["managed-account-settings"].tap()
            XCTAssertTrue(app.staticTexts["managed-sign-in-agreement"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["managed-google-sign-in"].isHittable || app.buttons["managed-apple-sign-in"].isHittable)
            XCTAssertFalse(app.staticTexts["managedAccountMessage"].exists)
            XCTAssertFalse(app.buttons["Buy credits"].exists)
            let accountScreen = XCTAttachment(screenshot: app.screenshot())
            accountScreen.name = "Configured account signup"; accountScreen.lifetime = .keepAlways; add(accountScreen)
            app.navigationBars["Account"].buttons.element(boundBy: 0).tap()
        }
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
        app.buttons["advanced-api-key"].tap()
        if !app.secureTextFields["api-key"].exists { app.swipeUp() }
        XCTAssertTrue(app.secureTextFields["api-key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].exists)
    }

    func testSettingsKeepLicensesInNoticesWithoutTransportDetails() {
        let app = launch()
        app.buttons["Settings"].tap()
        for _ in 0..<6 {
            if app.buttons["Open-source notices"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Open-source notices"].isHittable)
        XCTAssertFalse(app.staticTexts["WebRTC distribution by stasel, BSD 3-Clause. WebRTC includes third-party open-source components."].exists)
        XCTAssertFalse(app.links["WebRTC licenses"].exists)
        app.buttons["Open-source notices"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Google WebRTC")).firstMatch.waitForExistence(timeout: 5))
    }

    func testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user"]
        app.launch()
        XCTAssertTrue(app.buttons["start-conversation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-language-ko"].exists)
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-decline"].tap()
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ai-consent-title"].exists)
        XCTAssertFalse(app.buttons["onboarding-language-ko"].exists)
    }

    func testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-language-ja"].waitForExistence(timeout: 10))
        let languageScreen = XCTAttachment(screenshot: app.screenshot())
        languageScreen.name = "Onboarding - language"; languageScreen.lifetime = .keepAlways; add(languageScreen)
        app.buttons["onboarding-language-ja"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onboarding-ai-consent"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding-privacy-policy").firstMatch.exists)
        XCTAssertEqual(app.buttons["onboarding-continue"].label, "Agree and continue")
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        let meaningScreen = XCTAttachment(screenshot: app.screenshot())
        meaningScreen.name = "Onboarding - meanings and consent"; meaningScreen.lifetime = .keepAlways; add(meaningScreen)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "こんにちは！")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
    }

    func testAnExplicitSubtitleChoiceSurvivesChangingTheLearningLanguage() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-language-ja"].waitForExistence(timeout: 10))
        app.buttons["onboarding-language-ja"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        app.buttons["onboarding-back"].tap()
        app.buttons["onboarding-language-ko"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
    }

    func testLanguageSwitchUpdatesGreetingThemesAndWords() {
        let app = launch()
        app.tabBars.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "커피 한잔")).firstMatch.tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Japanese · Standard Japanese"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "こんにちは！")
        XCTAssertTrue(app.staticTexts["A little everyday Japanese"].exists)
        app.tabBars.buttons["Themes"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "コーヒーでも")).firstMatch.exists)
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Little by little · Japanese")).firstMatch.exists)
        app.tabBars.buttons["Talk"].tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Korean · Seoul standard"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
    }

    func testMeaningLabelWorksAfterEndingAndManualResetKeepsHistory() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-conversation"].isHittable)
        XCTAssertTrue(app.buttons["start-conversation"].isHittable)
        XCTAssertTrue(app.buttons["Conversation transcript"].isHittable)
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        app.buttons["Hide meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        XCTAssertFalse(app.staticTexts["meaning-caption"].exists)
        app.buttons["Show meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        app.buttons["new-conversation"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
        XCTAssertEqual(app.staticTexts["microphone-status"].label, "Microphone off")
        XCTAssertFalse(app.staticTexts["커피 한잔?"].exists)
        app.tabBars.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "커피 한잔")).firstMatch.exists)
    }

    func testEndedConversationAutomaticallyReturnsToGreeting() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "저는 커피를 좋아해요.")
        let ready = NSPredicate(format: "label == %@", "Ready when you are")
        expectation(for: ready, evaluatedWith: app.staticTexts["conversation-status"])
        waitForExpectations(timeout: 18)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
        XCTAssertFalse(app.buttons["new-conversation"].exists)
    }

    func testOpenTranscriptRemainsReadableAfterAutomaticReset() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 5))
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["I like coffee."].exists)
        let delay = expectation(description: "Allow the 15-second reset to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { delay.fulfill() }
        waitForExpectations(timeout: 18)
        XCTAssertTrue(app.staticTexts["저는 커피를 좋아해요."].exists)
        XCTAssertTrue(app.staticTexts["I like coffee."].exists)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "안녕하세요!")
    }
}
