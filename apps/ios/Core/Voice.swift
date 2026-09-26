import Foundation

/// Published list prices, in US dollars, used only for the estimates in Settings and Spending.
/// The provider's own dashboard is authoritative.
public enum VoicePricing {
    public static let asOf = "25 September 2026"
    /// The realtime voice, billed per second of open session, silence included.
    public static let liveModel = "gpt-live-1"
    public static let livePerMinute = 0.05
    /// The text model behind translation, assessment, lookups and typed replies, per million tokens.
    public static let textModel = "gpt-5.6-luna"
    public static let textInput = 0.20, textOutput = 0.75
}

extension SessionRecord {
    /// The voice cost this session is estimated at. A session recorded on the token-billed voice
    /// Mural briefly offered keeps the cost it recorded; every other session is priced by its
    /// open time.
    public var estimatedVoiceCost: Double {
        if let voiceCost, voiceCost.isFinite, voiceCost >= 0 { return voiceCost }
        return voiceSeconds / 60 * VoicePricing.livePerMinute
    }
    /// The voice model this session used: gpt-live-1 unless it recorded another.
    public var voiceModel: String { voiceModelID ?? VoicePricing.liveModel }
}
