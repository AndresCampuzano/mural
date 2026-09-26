import XCTest
@testable import MuralCore

final class VoiceTests: XCTestCase {
    func testTheEstimateUsesARecordedCostWhenThereIsOneAndOpenTimeOtherwise() {
        var live = SessionRecord(languageID: "ko"); live.voiceSeconds = 120
        XCTAssertEqual(live.estimatedVoiceCost, 0.10, accuracy: 1e-9)
        XCTAssertEqual(live.voiceModel, VoicePricing.liveModel)
        var recorded = SessionRecord(languageID: "ko"); recorded.voiceSeconds = 120; recorded.voiceCost = 0.03
        recorded.voiceModelID = "gpt-realtime-2.1-mini"
        XCTAssertEqual(recorded.estimatedVoiceCost, 0.03, accuracy: 1e-9)
        XCTAssertEqual(recorded.voiceModel, "gpt-realtime-2.1-mini")
        recorded.voiceCost = .nan
        XCTAssertEqual(recorded.estimatedVoiceCost, 0.10, accuracy: 1e-9)
    }

    /// Sessions and preferences written while a second voice was offered still decode, and keep
    /// their recorded model and cost, now that the choice is gone.
    func testBackupsFromWhenASecondVoiceWasOfferedStillDecode() throws {
        var archive = Archive()
        var session = SessionRecord(languageID: "ko")
        session.voiceModelID = "gpt-realtime-2.1-mini"; session.voiceCost = 0.0123
        archive.sessions = [session]
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any])
        preferences["voiceModelID"] = "gpt-realtime-2.1-mini"
        root["preferences"] = preferences
        let restored = try Archive.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(restored.sessions.first?.voiceModel, "gpt-realtime-2.1-mini")
        XCTAssertEqual(restored.sessions.first?.voiceCost, 0.0123)
    }
}
