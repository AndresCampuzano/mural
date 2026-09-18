import Foundation

extension LanguageModule {
    public static let japanese = LanguageModule(
        id: "ja", name: "Japanese", nativeName: "日本語", variety: "Standard Japanese", locale: "ja-JP",
        greeting: "こんにちは！", greetingWord: "こんにちは",
        speechGuidance: "Use clear, natural Standard Japanese as spoken in Tokyo. Speak in the polite です/ます style by default, and move to plain form only when the learner has clearly established that register. Treat long vowels, small っ, pitch accent and particle choice as meaningful when they affect understanding. Accept valid regional accents and vocabulary without treating a regional difference or a non-native accent alone as an error. Do not imitate a regional caricature.",
        writingGuidance: "Use a natural mix of kanji, hiragana and katakana with standard modern punctuation, and no spaces between words. Do not append romaji, furigana or translations to ordinary spoken replies; the app supplies reading help separately. Explain kanji readings, particles and politeness briefly in Japanese when asked.",
        lemmaGuidance: "Give verbs and adjectives in dictionary form, for example 食べる, する and 高い, and keep する compounds such as 勉強する whole. Give nouns without attached particles, but keep the exact observed form and quote as spoken, including particles such as は, が and を. Preserve the script as written, including kanji, kana and any learner-written romaji. Never write a lemma in romaji. Do not infer pitch accent or pronunciation accuracy from a transcript alone.",
        teachingFocus: [
            "Greetings, introductions and short useful chunks such as ...です and ...をください.",
            "Everyday questions, は and が, counters and numbers, and present and future in です/ます.",
            "Connected stories, the past tense, て-form sequences, and familiar everyday situations.",
            "Reasons and opinions with から and ので, giving and receiving, and comfortable movement between polite and plain forms.",
            "Nuance, keigo for respect and humility, conditionals, and register suited to the listener.",
            "Flexible advanced discussion with precise, idiomatic Japanese and natural control of politeness."
        ],
        topicPlaceholder: "Food, travel, films, everyday life…",
        lookupUnavailableReply: "今はそれを確認できませんでした。よければ、その話題について一般的なことから話しませんか。",
        themeOverrides: [
            "coffee": .init("coffee", "コーヒーでも", "Something warm, please", "cup.and.saucer", "Everyday", "Meet in a neighbourhood café in Japan. Order a drink together and chat, following the learner's interests.", 0),
            "groceries": .init("groceries", "買い物へ", "Find something good", "basket", "Everyday", "Shop at a Japanese market or supermarket. Practise counters, quantities, prices and polite questions. Respect regional food vocabulary.", 2),
            "travel": .init("travel", "次の駅は", "A ticket to somewhere", "tram", "Everyday", "Plan a trip in Japan. Discuss trains, directions and tickets without inventing current schedules.", 1),
            "restaurant": .init("restaurant", "いただきます", "Stay for dessert", "wineglass", "Everyday", "Share a meal at a Japanese restaurant. Practise ordering, preferences and polite problem-solving.", 0),
            "cabin": .init("cabin", "週末の小旅行", "A change of scene", "mountain.2", "Local life", "Plan an imagined weekend away in Japan. Choose a city, coast or mountain together and discuss practical plans.", 2),
            "traditions": .init("traditions", "日々の習慣", "Small customs, big stories", "flag", "Local life", "Talk about everyday customs, seasons and family routines in Japanese. Compare the learner's experience without treating any culture as uniform.", 2)
        ],
        wordSegmentationLocale: "ja_JP", readingAidName: "romaji"
    )
}
