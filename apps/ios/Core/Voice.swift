import Foundation

/// The provider model that carries the spoken conversation. Stored by raw value, so the IDs are
/// the provider's own model names and must not change.
public enum VoiceModel: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Billed per second of open session, including silence.
    case live = "gpt-live-1"
    /// Billed per audio and text token actually processed, so pauses cost almost nothing.
    case realtimeMini = "gpt-realtime-2.1-mini"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .live: "GPT-Live 1"
        case .realtimeMini: "GPT-Realtime 2.1 mini"
        }
    }
    public var detail: String {
        switch self {
        case .live: "The original voice. Billed for every minute a conversation is open."
        case .realtimeMini: "Experimental and usually cheaper: billed only for speech, not pauses. A smaller model, so teaching may be less careful, and Mural cannot be interrupted mid-sentence: the microphone rests while it speaks so it does not hear itself."
        }
    }
    /// Transcripts of the learner's speech come from a separate model on the token-billed voice.
    public static let learnerTranscriptionModel = "gpt-4o-mini-transcribe"
}

/// Published list prices, in US dollars, used only for the estimate in Settings. The provider's
/// own dashboard is authoritative.
public enum VoicePricing {
    public static let asOf = "25 September 2026"
    public static let livePerMinute = 0.05
    /// gpt-4o-mini-transcribe, charged on the learner's speech.
    public static let transcriptionPerMinute = 0.003
    /// gpt-realtime-2.1-mini, per million tokens.
    public static let miniTextInput = 0.60, miniCachedTextInput = 0.06, miniTextOutput = 2.40
    public static let miniAudioInput = 10.0, miniCachedAudioInput = 0.30, miniAudioOutput = 20.0
    /// The text model behind translation, assessment, lookups and typed replies, per million tokens.
    public static let textModel = "gpt-5.6-luna"
    public static let textInput = 0.20, textOutput = 0.75
}

/// Token usage from one completed response on a token-billed voice model.
public struct RealtimeUsage: Equatable, Sendable {
    public var textInput = 0, cachedTextInput = 0
    public var audioInput = 0, cachedAudioInput = 0
    public var textOutput = 0, audioOutput = 0
    public init() {}

    /// Reads `response.usage` from a `response.done` event. Returns nil for anything that is not
    /// a usage object, so a malformed event can never be counted.
    public init?(_ usage: Any?) {
        guard let usage = usage as? [String: Any] else { return nil }
        let input = usage["input_token_details"] as? [String: Any] ?? [:]
        let cached = input["cached_tokens_details"] as? [String: Any] ?? [:]
        let output = usage["output_token_details"] as? [String: Any] ?? [:]
        func count(_ values: [String: Any], _ key: String) -> Int { max(0, (values[key] as? NSNumber)?.intValue ?? 0) }
        textInput = count(input, "text_tokens"); audioInput = count(input, "audio_tokens")
        cachedTextInput = min(textInput, count(cached, "text_tokens")); cachedAudioInput = min(audioInput, count(cached, "audio_tokens"))
        textOutput = count(output, "text_tokens"); audioOutput = count(output, "audio_tokens")
    }

    /// Cost at the mini model's list prices. Cached tokens are part of the input counts, so they
    /// are billed at the cached rate and removed from the full-price count.
    public var miniCost: Double {
        let perToken = 1.0 / 1_000_000
        return (Double(textInput - cachedTextInput) * VoicePricing.miniTextInput
            + Double(cachedTextInput) * VoicePricing.miniCachedTextInput
            + Double(audioInput - cachedAudioInput) * VoicePricing.miniAudioInput
            + Double(cachedAudioInput) * VoicePricing.miniCachedAudioInput
            + Double(textOutput) * VoicePricing.miniTextOutput
            + Double(audioOutput) * VoicePricing.miniAudioOutput) * perToken
    }
}

extension SessionRecord {
    /// The voice cost this session is estimated at: the recorded token cost when the session
    /// used a token-billed model, otherwise its open time at the per-minute price.
    public var estimatedVoiceCost: Double {
        if let voiceCost, voiceCost.isFinite, voiceCost >= 0 { return voiceCost }
        return voiceSeconds / 60 * VoicePricing.livePerMinute
    }
}
