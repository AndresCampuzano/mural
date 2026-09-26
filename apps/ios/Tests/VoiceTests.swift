import XCTest
@testable import MuralCore

final class VoiceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    func testAnUnsetOrUnknownVoiceModelFallsBackToTheOriginal() throws {
        var preferences = Preferences()
        XCTAssertEqual(preferences.voiceModel, .live)
        preferences.voiceModelID = "no-such-model"
        XCTAssertEqual(preferences.voiceModel, .live)
        preferences.voiceModelID = VoiceModel.realtimeMini.rawValue
        XCTAssertEqual(preferences.voiceModel, .realtimeMini)
    }

    func testABackupWrittenBeforeTheVoiceChoiceStillDecodesAndTheChoiceSurvivesARoundTrip() throws {
        var archive = Archive()
        archive.preferences.voiceModelID = VoiceModel.realtimeMini.rawValue
        var session = SessionRecord(languageID: "ko")
        session.voiceModelID = VoiceModel.realtimeMini.rawValue; session.voiceCost = 0.0123
        archive.sessions = [session]
        let restored = try Archive.decode(archive.encoded())
        XCTAssertEqual(restored.preferences.voiceModel, .realtimeMini)
        XCTAssertEqual(restored.sessions.first?.voiceCost, 0.0123)

        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any]); preferences.removeValue(forKey: "voiceModelID")
        var sessions = try XCTUnwrap(root["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "voiceModelID"); sessions[0].removeValue(forKey: "voiceCost")
        root["preferences"] = preferences; root["sessions"] = sessions
        let old = try Archive.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(old.preferences.voiceModel, .live)
        XCTAssertNil(old.sessions.first?.voiceCost)
    }

    func testTheEstimateUsesTokenCostWhenRecordedAndOpenTimeOtherwise() {
        var live = SessionRecord(languageID: "ko"); live.voiceSeconds = 120
        XCTAssertEqual(live.estimatedVoiceCost, 0.10, accuracy: 1e-9)
        var mini = SessionRecord(languageID: "ko"); mini.voiceSeconds = 120; mini.voiceCost = 0.03
        XCTAssertEqual(mini.estimatedVoiceCost, 0.03, accuracy: 1e-9)
        mini.voiceCost = .nan
        XCTAssertEqual(mini.estimatedVoiceCost, 0.10, accuracy: 1e-9)
    }

    func testUsageIsPricedWithCachedTokensAtTheCachedRate() throws {
        let cached: [String: Any] = ["text_tokens": 1500, "audio_tokens": 400]
        let input: [String: Any] = ["text_tokens": 2000, "audio_tokens": 1000, "cached_tokens_details": cached]
        let output: [String: Any] = ["text_tokens": 100, "audio_tokens": 600]
        let usage = try XCTUnwrap(RealtimeUsage(["input_token_details": input, "output_token_details": output]))
        // Each term is written out on its own: a single long literal expression is slow enough
        // to type-check that the CI compiler gives up on it.
        let textIn: Double = 500 * VoicePricing.miniTextInput
        let cachedTextIn: Double = 1500 * VoicePricing.miniCachedTextInput
        let audioIn: Double = 600 * VoicePricing.miniAudioInput
        let cachedAudioIn: Double = 400 * VoicePricing.miniCachedAudioInput
        let textOut: Double = 100 * VoicePricing.miniTextOutput
        let audioOut: Double = 600 * VoicePricing.miniAudioOutput
        var total: Double = textIn
        total += cachedTextIn; total += audioIn; total += cachedAudioIn; total += textOut; total += audioOut
        let expected = total / 1_000_000
        XCTAssertEqual(usage.miniCost, expected, accuracy: 1e-12)
        XCTAssertNil(RealtimeUsage("not usage"))
        // Cached counts larger than the totals cannot produce a negative charge.
        let odd = try XCTUnwrap(RealtimeUsage(["input_token_details": ["audio_tokens": 10, "cached_tokens_details": ["audio_tokens": 50]]]))
        XCTAssertGreaterThanOrEqual(odd.miniCost, 0)
    }

    func testTheSessionAsksForTranscriptsPatientTurnTakingTheHelperAndThePace() throws {
        let session = RealtimeBridge.session(model: .realtimeMini, instructions: "Be kind.", speed: 0.8)
        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2.1-mini")
        XCTAssertEqual(session["instructions"] as? String, "Be kind.")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        XCTAssertEqual((input["transcription"] as? [String: Any])?["model"] as? String, VoiceModel.learnerTranscriptionModel)
        let turns = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turns["type"] as? String, "semantic_vad"); XCTAssertEqual(turns["eagerness"] as? String, "low")
        XCTAssertEqual((audio["output"] as? [String: Any])?["speed"] as? Double, 0.8)
        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, RealtimeBridge.helperTool)
        XCTAssertNil((RealtimeBridge.session(model: .realtimeMini, instructions: "", speed: nil)["audio"] as? [String: Any])
            .flatMap { ($0["output"] as? [String: Any])?["speed"] })
    }

    func testAnInstructionBecomesASystemItemAndAResponse() {
        var bridge = RealtimeBridge(startedAt: start)
        let sent = bridge.outbound(["type": "session.instructions.append", "event_id": "a", "content": "Greet.", RealtimeBridge.respondKey: true])
        XCTAssertEqual(sent.map { $0["type"] as? String }, ["conversation.item.create", "response.create"])
        XCTAssertEqual(sent[0]["event_id"] as? String, "a")
        let item = sent[0]["item"] as? [String: Any]
        XCTAssertEqual(item?["role"] as? String, "system")
        XCTAssertEqual(((item?["content"] as? [[String: Any]])?.first)?["text"] as? String, "Greet.")
        // Context for the model is added without asking it to speak.
        XCTAssertEqual(bridge.outbound(["type": "session.thinking.append", "event_id": "b", "content": "Note."]).map { $0["type"] as? String },
                       ["conversation.item.create"])
    }

    func testAResponseAskedForDuringAnotherWaitsForItToFinish() {
        var bridge = RealtimeBridge(startedAt: start)
        _ = bridge.outbound(["type": "session.instructions.append", "event_id": "a", "content": "One.", RealtimeBridge.respondKey: true])
        _ = bridge.inbound(["type": "response.created"])
        let second = bridge.outbound(["type": "session.instructions.append", "event_id": "b", "content": "Two.", RealtimeBridge.respondKey: true])
        XCTAssertEqual(second.map { $0["type"] as? String }, ["conversation.item.create"])
        let done = bridge.inbound(["type": "response.done", "response": [:]], now: at(5))
        XCTAssertEqual(done.send.map { $0["event_id"] as? String }, ["b-response"])
        XCTAssertTrue(bridge.inbound(["type": "response.done", "response": [:]], now: at(6)).send.isEmpty)
    }

    /// The model can start a response on its own when the learner stops speaking, so a request
    /// sent at the same moment is rejected; it must be retried, not reported.
    func testAResponseRejectedBecauseTheModelStartedOneIsRetriedAfterIt() {
        var bridge = RealtimeBridge(startedAt: start)
        _ = bridge.outbound(["type": "session.instructions.append", "event_id": "a", "content": "Help.", RealtimeBridge.respondKey: true])
        let rejected = bridge.inbound(["type": "error", "error": ["code": RealtimeBridge.activeResponseError, "event_id": "a-response"]])
        XCTAssertTrue(rejected.emit.isEmpty)
        let done = bridge.inbound(["type": "response.done", "response": [:]], now: at(3))
        XCTAssertEqual(done.send.map { $0["event_id"] as? String }, ["a-response"])
        let other = bridge.inbound(["type": "error", "error": ["code": "invalid_value", "event_id": "x", "message": "Bad."]])
        XCTAssertEqual((other.emit.first?["error"] as? [String: Any])?["client_event_id"] as? String, "x")
    }

    func testADelegatedAnswerReturnsAsTheFunctionOutputAndATypedReplyIsSpokenAsWritten() {
        var bridge = RealtimeBridge(startedAt: start)
        let call = bridge.inbound(["type": "response.function_call_arguments.done", "call_id": "call_1", "name": RealtimeBridge.helperTool, "arguments": "{}"])
        XCTAssertEqual(call.emit.first?["type"] as? String, "session.delegation.created")
        XCTAssertEqual((call.emit.first?["delegation"] as? [String: Any])?["id"] as? String, "call_1")
        XCTAssertTrue(bridge.inbound(["type": "response.function_call_arguments.done", "call_id": "c", "name": "other"]).emit.isEmpty)
        _ = bridge.inbound(["type": "response.done", "response": [:]])
        let answer = bridge.outbound(["type": "session.commentary.append", "event_id": "d", "delegation_id": "call_1", "content": "Answer."])
        XCTAssertEqual((answer.first?["item"] as? [String: Any])?["type"] as? String, "function_call_output")
        XCTAssertEqual((answer.first?["item"] as? [String: Any])?["call_id"] as? String, "call_1")
        _ = bridge.inbound(["type": "response.done", "response": [:]])
        let typed = bridge.outbound(["type": "session.commentary.append", "event_id": "e", "delegation_id": NSNull(), "content": "좋아요!"])
        XCTAssertEqual(typed.map { $0["type"] as? String }, ["response.create"])
        XCTAssertTrue(((typed.first?["response"] as? [String: Any])?["instructions"] as? String ?? "").contains("좋아요!"))
    }

    func testTranscriptsCarryWallClockOffsetsAndTheLearnersSpeechKeepsItsOwnTiming() {
        var bridge = RealtimeBridge(startedAt: start)
        XCTAssertEqual(bridge.inbound(["type": "session.created", "session": ["id": "sess_1"]]).emit.first?["type"] as? String, "session.started")
        _ = bridge.inbound(["type": "input_audio_buffer.speech_started", "item_id": "u1"], now: at(2))
        _ = bridge.inbound(["type": "input_audio_buffer.speech_stopped", "item_id": "u1"], now: at(5))
        let reply = bridge.inbound(["type": "response.output_audio_transcript.delta", "delta": "네, ", "event_id": "o1"], now: at(5.5)).emit
        XCTAssertEqual(reply.first?["start_ms"] as? Int, 5500)
        // The learner's transcript arrives after the reply has begun, but keeps the time they spoke.
        let heard = bridge.inbound(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": " 안녕하세요 "], now: at(6)).emit
        XCTAssertEqual(heard.first?["type"] as? String, "session.input_transcript.delta")
        XCTAssertEqual(heard.first?["delta"] as? String, "안녕하세요")
        XCTAssertEqual(heard.first?["start_ms"] as? Int, 2000); XCTAssertEqual(heard.first?["end_ms"] as? Int, 5000)
        XCTAssertTrue(bridge.inbound(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u2", "transcript": "  "]).emit.isEmpty)
    }

    func testCostAddsTranscriptionAndEveryResponseAndIsReportedOnClose() {
        var bridge = RealtimeBridge(startedAt: start)
        _ = bridge.inbound(["type": "input_audio_buffer.speech_started", "item_id": "u1"], now: at(0))
        _ = bridge.inbound(["type": "input_audio_buffer.speech_stopped", "item_id": "u1"], now: at(60))
        XCTAssertEqual(bridge.cost, VoicePricing.transcriptionPerMinute, accuracy: 1e-12)
        let done = bridge.inbound(["type": "response.done", "response": ["usage": ["output_token_details": ["audio_tokens": 1_000_000]]]], now: at(61)).emit
        XCTAssertEqual(bridge.cost, VoicePricing.transcriptionPerMinute + VoicePricing.miniAudioOutput, accuracy: 1e-9)
        XCTAssertEqual(done.first { $0["type"] as? String == "session.usage.updated" }.flatMap { ($0["usage"] as? [String: Any])?["seconds"] as? Double }, 61)
        let closed = bridge.closed(now: at(90))
        XCTAssertEqual(closed.last?["type"] as? String, "session.closed")
        XCTAssertEqual(closed.first?["cost"] as? Double ?? 0, bridge.cost, accuracy: 1e-12)
    }

    func testMutingClearsHalfHeardSpeechAndClosingSendsNothing() {
        var bridge = RealtimeBridge(startedAt: start)
        XCTAssertEqual(bridge.outbound(["type": "session.input_audio.mute", "event_id": "m"]).first?["type"] as? String, "input_audio_buffer.clear")
        XCTAssertTrue(bridge.outbound(["type": "session.input_audio.unmute"]).isEmpty)
        XCTAssertTrue(bridge.outbound(["type": "session.close"]).isEmpty)
    }

    /// Guidance such as a language redirect or a level change only shapes the next turn. If it
    /// asked for a reply, a reply that drifted would be redirected, drift again and be redirected
    /// again, and Mural would never stop talking.
    func testGuidanceIsAddedWithoutMakingTheModelSpeak() {
        var bridge = RealtimeBridge(startedAt: start)
        let quiet = bridge.outbound(["type": "session.instructions.append", "event_id": "r", "content": "Return to the target language."])
        XCTAssertEqual(quiet.map { $0["type"] as? String }, ["conversation.item.create"])
        let unflagged = bridge.outbound(["type": "session.instructions.append", "event_id": "s", "content": "Slower.", RealtimeBridge.respondKey: false])
        XCTAssertEqual(unflagged.count, 1)
        XCTAssertTrue(bridge.inbound(["type": "response.done", "response": [:]]).send.isEmpty)
    }

    /// Requests made while a reply runs never pile up into a run of replies: only the newest waits.
    func testOnlyTheNewestWaitingReplyIsKept() {
        var bridge = RealtimeBridge(startedAt: start)
        _ = bridge.outbound(["type": "session.instructions.append", "event_id": "a", "content": "1", RealtimeBridge.respondKey: true])
        for id in ["b", "c", "d"] {
            _ = bridge.outbound(["type": "session.instructions.append", "event_id": id, "content": id, RealtimeBridge.respondKey: true])
        }
        XCTAssertEqual(bridge.inbound(["type": "response.done", "response": [:]]).send.map { $0["event_id"] as? String }, ["d-response"])
        XCTAssertTrue(bridge.inbound(["type": "response.done", "response": [:]]).send.isEmpty)
    }

    /// Recorded in the simulator: the model's first words came back through the microphone about a
    /// second after it began, were transcribed as the learner, and interrupted it, eleven times in
    /// 36 seconds. The microphone is closed while its audio plays and cleared as it stops.
    func testTheMicrophoneClosesWhileTheModelSpeaksAndItsTailIsDiscarded() {
        var bridge = RealtimeBridge(startedAt: start)
        XCTAssertNil(bridge.microphone)
        XCTAssertTrue(bridge.inbound(["type": "output_audio_buffer.started", "response_id": "r1"]).send.isEmpty)
        XCTAssertEqual(bridge.microphone, .close)
        bridge.microphone = nil
        let stopped = bridge.inbound(["type": "output_audio_buffer.stopped", "response_id": "r1"])
        XCTAssertEqual(bridge.microphone, .open)
        XCTAssertEqual(stopped.send.map { $0["type"] as? String }, ["input_audio_buffer.clear"])
        bridge.microphone = nil
        _ = bridge.inbound(["type": "output_audio_buffer.started"]); bridge.microphone = nil
        _ = bridge.inbound(["type": "output_audio_buffer.cleared"])
        XCTAssertEqual(bridge.microphone, .open)
    }
}
