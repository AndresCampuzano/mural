#if DEBUG && targetEnvironment(simulator)
import Foundation
import MuralCore

/// Sample content for native simulator captures. Never loaded on a physical device.
@MainActor enum ScreenshotPreview {
    enum Screen: String { case greeting, conversation, themes }
    static var screen: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--preview"),
              let argument = arguments.first(where: { $0.hasPrefix("--screenshot=") }) else { return nil }
        return Screen(rawValue: String(argument.dropFirst("--screenshot=".count)))
    }
    static var tab: Int { screen == .themes ? 1 : 0 }

    /// A scan with a saved test whose questions are all choices, so a test can be taken and
    /// marked without an API key. Built from the current module, so it works in every language.
    /// `RootView.init` can run again when the app's body is re-evaluated, so the seed is kept to
    /// once per launch; otherwise deleting the last scan would bring it straight back.
    private static var seededScan = false
    static func seedScan(_ store: LearningStore) {
        guard !seededScan else { return }
        seededScan = true
        let language = store.language
        let study = PictureStudy.validated(.init(title: "Café menu", summary: "A small café menu with drinks and prices.", targetText: language.greeting,
                                                 vocabulary: [PictureTerm(text: language.greetingWord, meaning: "hello")], situation: "Ordering at a café."),
                                           language: language, meaningLanguage: store.preferences.meaningLanguage)
        var scan = ScannedFile(languageID: language.id, name: "Café menu", kind: .picture, detail: "Picture", study: study)
        scan.add(SavedPractice(name: "Menu quiz", activity: .writtenTest, level: .startingOut, questions: [
            TestQuestion(kind: .choice, prompt: "What does this mean?", passage: language.greetingWord, options: ["hello", "goodbye"], answer: "hello", explanation: ""),
            TestQuestion(kind: .choice, prompt: "Which one is the greeting?", passage: "", options: [language.greetingWord, "—"], answer: language.greetingWord, explanation: "")
        ]))
        store.saveScan(scan)
    }

    /// Conversations over the last few months on both voice models, so Spending has bars to draw.
    static func seedSpending(_ store: LearningStore) {
        let calendar = Calendar.current
        let plan: [(monthsAgo: Int, minutes: Double, mini: Double)] = [(4, 38, 0), (3, 52, 0), (2, 61, 0), (1, 44, 0.31), (0, 12, 0.46)]
        for (index, entry) in plan.enumerated() {
            guard let date = calendar.date(byAdding: .month, value: -entry.monthsAgo, to: .now) else { continue }
            var live = SessionRecord(languageID: "ko"); live.startedAt = date; live.endedAt = date.addingTimeInterval(60)
            live.voiceSeconds = entry.minutes * 60; live.inputTokens = 40_000 * (index + 1); live.outputTokens = 9_000 * (index + 1)
            store.save(live)
            if entry.mini > 0 {
                var mini = SessionRecord(languageID: "ko"); mini.startedAt = date.addingTimeInterval(120); mini.endedAt = date.addingTimeInterval(180)
                mini.voiceModelID = "gpt-realtime-2.1-mini"; mini.voiceCost = entry.mini; mini.voiceSeconds = 900
                store.save(mini)
            }
        }
    }
}
#endif
