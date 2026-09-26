#if DEBUG && targetEnvironment(simulator)
import Foundation
import MuralCore

/// Sample content for native simulator captures. Never loaded on a physical device.
@MainActor enum ScreenshotPreview {
    enum Screen: String { case greeting, conversation, themes, words }
    static var screen: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--preview"),
              let argument = arguments.first(where: { $0.hasPrefix("--screenshot=") }) else { return nil }
        return Screen(rawValue: String(argument.dropFirst("--screenshot=".count)))
    }
    static var tab: Int { screen == .themes ? 1 : screen == .words ? 2 : 0 }

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
                mini.voiceModelID = VoiceModel.realtimeMini.rawValue; mini.voiceCost = entry.mini; mini.voiceSeconds = 900
                store.save(mini)
            }
        }
    }
    static func seedWords(_ store: LearningStore) {
        let samples: [(lemma: String, meaning: String, form: String, quote: String, days: [Int])] = [
            ("마시다", "to drink", "마셔요", "오늘은 커피를 마셔요.", [9, 4, 0]),
            ("약속", "plan, appointment", "약속", "친구하고 약속이 있어요.", [0]),
            ("만나다", "to meet", "만나요", "토요일에 만나요.", [3, 0]),
            ("산책하다", "to take a walk", "산책해요", "동네를 산책해요.", [9, 4, 0])
        ]
        for (index, sample) in samples.enumerated() {
            for (visit, day) in sample.days.enumerated() {
                let date = Date().addingTimeInterval(-Double(day) * 86400 - Double(index) * 60)
                let context = visit.isMultiple(of: 2) ? "coffee" : "weekend"
                var record = SessionRecord(languageID: "ko", themeID: context)
                record.startedAt = date; record.endedAt = date.addingTimeInterval(60)
                record.append(Fragment(speaker: .user, text: sample.quote, startMS: 0, endMS: 3000, receivedAt: date))
                let passage = record.passages[0]
                record.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey,
                    outcome: .success, suggestedLevel: 1, nextGoal: "일상 계획에 대해 이야기하기.", capability: "",
                    words: [WordProposal(lemma: sample.lemma, meaning: sample.meaning, form: sample.form,
                        kind: .independent, confidence: 0.95, sourceIDs: passage.fragments.map(\.id), quote: sample.quote, language: "ko")],
                    createdAt: date, context: context)]
                store.save(record)
            }
        }
    }
}
#endif
