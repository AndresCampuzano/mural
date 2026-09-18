import Foundation

extension LanguageModule {
    public static let korean = LanguageModule(
        id: "ko", name: "Korean", nativeName: "한국어", variety: "Seoul standard", locale: "ko-KR",
        greeting: "안녕하세요!", greetingWord: "안녕하세요",
        speechGuidance: "Use clear, natural Standard Korean as spoken in Seoul. Speak in the polite 해요체 style by default. Move to 합니다체 or 반말 only when the learner has clearly established that register, and explain the change briefly in Korean. Treat tense, aspirated and plain consonant contrasts, final consonants (받침) and the sound changes of connected speech as meaningful when they affect understanding. Accept valid regional accents and vocabulary without treating a regional difference or a non-native accent alone as an error. Do not imitate a regional caricature.",
        writingGuidance: "Use natural Hangul with standard modern spacing (띄어쓰기) and punctuation. Do not append romanization, furigana-style glosses or translations to ordinary spoken replies; the app supplies reading help separately. Explain Hangul letters, 받침 and sound changes briefly in Korean when asked.",
        lemmaGuidance: "Give verbs and adjectives in dictionary form ending in -다, for example 먹다, 예쁘다 and 공부하다, keeping 하다 compounds whole. Give nouns without attached particles, but keep the exact observed form and quote as spoken, including particles such as 은/는, 이/가 and 을/를. Preserve Hangul exactly and never write a lemma in romanization. Do not infer pronunciation accuracy from a transcript alone.",
        teachingFocus: [
            "Greetings, introductions and short useful chunks such as 저는 ...이에요 and ...주세요.",
            "Everyday questions, topic and subject particles, numbers and counters, and present-tense 해요체.",
            "Connected stories, the past tense with -았/었-, intention with -(으)ㄹ 거예요, and familiar situations.",
            "Reasons and opinions with -아서/어서 and -(으)니까, natural connectives, and comfortable movement between speech levels.",
            "Nuance, subject honorifics with -시-, indirect quotation, conditionals and register suited to the listener.",
            "Flexible advanced discussion with precise, idiomatic Korean and natural control of speech level."
        ],
        topicPlaceholder: "Food, travel, music, daily life in Korea…",
        lookupUnavailableReply: "지금은 그걸 확인할 수 없었어요. 괜찮으시면 그 주제에 대해 전반적으로 이야기해 볼까요?",
        themeOverrides: [
            "coffee": .init("coffee", "커피 한잔?", "Something warm, please", "cup.and.saucer", "Everyday", "Meet in a neighbourhood café in Korea. Order a drink together and chat, following the learner's interests.", 0),
            "groceries": .init("groceries", "시장에서", "Find something good", "basket", "Everyday", "Shop at a Korean market or supermarket. Practise counters, quantities, prices and polite questions. Respect regional food vocabulary.", 2),
            "travel": .init("travel", "다음 역은", "A ticket to somewhere", "tram", "Everyday", "Plan a trip in Korea. Discuss subways, trains, directions and tickets without inventing current schedules.", 1),
            "restaurant": .init("restaurant", "같이 먹어요", "Stay for one more", "wineglass", "Everyday", "Share a meal at a Korean restaurant. Practise ordering, sharing dishes and 반찬, and polite problem-solving.", 0),
            "cabin": .init("cabin", "주말 여행", "A change of scene", "mountain.2", "Local life", "Plan an imagined weekend away in Korea. Choose a city, coast or mountain together and discuss practical plans.", 2),
            "traditions": .init("traditions", "일상 속 문화", "Small customs, big stories", "flag", "Local life", "Talk about everyday customs, holidays and family routines in Korean. Compare the learner's experience without treating any culture as uniform.", 2)
        ],
        // Hangul syllables and jamo, including the compatibility and extended blocks.
        scriptRanges: [0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xD7B0...0xD7FF]
    )
}
