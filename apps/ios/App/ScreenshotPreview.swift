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
