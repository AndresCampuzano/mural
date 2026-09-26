import Foundation

/// Translates between the conversation protocol the app speaks — gpt-live-1's session events —
/// and the Realtime API used by token-billed voice models, so the rest of the app behaves the
/// same whichever voice carries the conversation.
///
/// The app sends `session.instructions.append`, `session.thinking.append` and
/// `session.commentary.append`, and expects `session.started`, transcript deltas with
/// millisecond offsets, `session.delegation.created`, `session.usage.updated` and
/// `session.closed`. The Realtime API has none of these, so each is built from its nearest
/// equivalent. Offsets are measured from `startedAt` on the wall clock, the same base the app
/// uses for typed replies.
public struct RealtimeBridge {
    /// The function the model calls to hand a request to the app, which answers it with a
    /// Responses call and returns the reply as the function's output.
    public static let helperTool = "ask_mural_helper"
    public static let activeResponseError = "conversation_already_has_active_response"
    /// Set on an app command that should make the model speak now. Removed before anything
    /// reaches gpt-live-1, which has no such field.
    public static let respondKey = "mural_respond"

    /// What the transport should do with the microphone. A token-billed voice does not cancel
    /// its own echo, so it hears itself through the speaker, takes that for the learner and
    /// answers itself without end; the microphone is closed while its audio plays.
    public enum Microphone: Equatable { case close, open }

    public let startedAt: Date
    public private(set) var cost = 0.0
    private var responseActive = false
    private var queued: [[String: Any]] = []
    private var sentResponses: [String: [String: Any]] = [:]
    private var speechStarted: [String: Date] = [:]
    private var speechStopped: [String: Date] = [:]
    /// The latest microphone change, read and cleared by the transport after each event.
    public var microphone: Microphone?

    public init(startedAt: Date) { self.startedAt = startedAt }

    /// The `session` field of the call request.
    public static func session(model: VoiceModel, instructions: String, speed: Double?) -> [String: Any] {
        var output: [String: Any] = ["voice": "marin"]
        if let speed { output["speed"] = speed }
        return [
            "type": "realtime", "model": model.rawValue, "instructions": instructions, "output_modalities": ["audio"],
            "audio": [
                "input": [
                    "transcription": ["model": VoiceModel.learnerTranscriptionModel],
                    // Learners pause mid-sentence to find a word; the least eager setting waits longest
                    // before deciding they have finished.
                    "turn_detection": ["type": "semantic_vad", "eagerness": "low", "create_response": true, "interrupt_response": true],
                    "noise_reduction": ["type": "near_field"]
                ],
                "output": output
            ],
            "tools": [[
                "type": "function", "name": helperTool,
                "description": "Hand a request to Mural's helper instead of guessing: current events, facts that need checking, a web lookup, or a detailed explanation. The helper's answer comes back as this function's output; speak it to the learner naturally.",
                "parameters": ["type": "object", "properties": ["request": ["type": "string", "description": "What the learner wants, briefly."]], "required": ["request"]]
            ]],
            "tool_choice": "auto"
        ]
    }

    /// Provider events for one app command. May be empty, and a response request is held back
    /// while another response is still running.
    public mutating func outbound(_ event: [String: Any]) -> [[String: Any]] {
        guard let type = event["type"] as? String else { return [] }
        let id = event["event_id"] as? String ?? UUID().uuidString
        let content = event["content"] as? String ?? ""
        switch type {
        case "session.instructions.append":
            // Guidance for the next turn is only added; asking for a reply to every instruction
            // would make the model speak each time the app adjusts it.
            guard event[Self.respondKey] as? Bool == true else { return [Self.systemItem(content, id: id)] }
            return [Self.systemItem(content, id: id)] + request(["type": "response.create", "event_id": id + "-response"])
        case "session.thinking.append":
            return [Self.systemItem(content, id: id)]
        case "session.commentary.append":
            if let call = event["delegation_id"] as? String, !call.isEmpty {
                let output: [String: Any] = ["type": "conversation.item.create", "event_id": id,
                                             "item": ["type": "function_call_output", "call_id": call, "output": content]]
                return [output] + request(["type": "response.create", "event_id": id + "-response"])
            }
            // A reply the app composed, such as the answer to a typed message, to be spoken as written.
            return request(["type": "response.create", "event_id": id, "response": [
                "instructions": "Say the following to the learner, as written, then stop and listen. It is your own reply, not a quotation:\n\(content)"
            ]])
        case "session.input_audio.mute":
            return [["type": "input_audio_buffer.clear", "event_id": id]]
        default:
            // Unmuting needs no event: the microphone track is simply re-enabled. Closing is
            // handled by the transport, which ends the call.
            return []
        }
    }

    /// App events for one provider event, and any provider events it frees to be sent.
    public mutating func inbound(_ event: [String: Any], now: Date = .now) -> (emit: [[String: Any]], send: [[String: Any]]) {
        guard let type = event["type"] as? String else { return ([], []) }
        switch type {
        case "output_audio_buffer.started":
            microphone = .close
            return ([], [])
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            microphone = .open
            // Anything captured as playback ended is the tail of the model's own voice.
            return ([], [["type": "input_audio_buffer.clear", "event_id": UUID().uuidString]])
        case "session.created":
            let id = (event["session"] as? [String: Any])?["id"] as? String
            return ([["type": "session.started", "session": ["id": id as Any]]], [])
        case "input_audio_buffer.speech_started":
            if let item = event["item_id"] as? String { speechStarted[item] = now }
            return ([], [])
        case "input_audio_buffer.speech_stopped":
            guard let item = event["item_id"] as? String else { return ([], []) }
            speechStopped[item] = now
            let spoken = max(0, now.timeIntervalSince(speechStarted[item] ?? now))
            cost += spoken / 60 * VoicePricing.transcriptionPerMinute
            return ([costEvent], [])
        case "conversation.item.input_audio_transcription.completed":
            guard let item = event["item_id"] as? String else { return ([], []) }
            let text = (event["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let start = speechStarted.removeValue(forKey: item), end = speechStopped.removeValue(forKey: item)
            guard !text.isEmpty else { return ([], []) }
            let endMS = milliseconds(end ?? now)
            let startMS = min(endMS, milliseconds(start ?? now.addingTimeInterval(-1)))
            return ([["type": "session.input_transcript.delta", "event_id": "input-" + item, "delta": text,
                      "start_ms": startMS, "end_ms": endMS]], [])
        case "response.output_audio_transcript.delta":
            let delta = event["delta"] as? String ?? (event["delta"] as? [String: Any])?["transcript"] as? String ?? ""
            guard !delta.isEmpty else { return ([], []) }
            let at = milliseconds(now)
            return ([["type": "session.output_transcript.delta", "event_id": event["event_id"] as? String ?? UUID().uuidString,
                      "delta": delta, "start_ms": at, "end_ms": at]], [])
        case "response.created":
            responseActive = true
            return ([], [])
        case "response.function_call_arguments.done":
            guard let call = event["call_id"] as? String, event["name"] as? String == Self.helperTool else { return ([], []) }
            return ([["type": "session.delegation.created", "delegation": ["id": call, "target": "client"]]], [])
        case "response.done":
            responseActive = false
            let response = event["response"] as? [String: Any]
            if let usage = RealtimeUsage(response?["usage"]) { cost += usage.miniCost }
            var send: [[String: Any]] = []
            if !queued.isEmpty { send = [queued.removeFirst()]; responseActive = true }
            return ([costEvent, usageEvent(now)], send)
        case "error":
            let details = event["error"] as? [String: Any] ?? [:]
            let client = details["event_id"] as? String
            // A response asked for while the model had already started one on its own is not a
            // failure: it waits for that one to finish.
            if details["code"] as? String == Self.activeResponseError, let client, let body = sentResponses[client] {
                if queued.isEmpty { queued = [body] }
                responseActive = true
                return ([], [])
            }
            return ([["type": "error", "error": ["client_event_id": client as Any, "message": details["message"] as Any]]], [])
        default:
            return ([], [])
        }
    }

    /// The app waits for `session.closed` to know the conversation ended cleanly.
    public func closed(now: Date = .now) -> [[String: Any]] {
        [costEvent, ["type": "session.closed", "reason": "Client closed", "usage": ["seconds": max(0, now.timeIntervalSince(startedAt))]]]
    }

    private mutating func request(_ body: [String: Any]) -> [[String: Any]] {
        if let id = body["event_id"] as? String { sentResponses[id] = body }
        // One waiting reply at most: a newer request replaces an older one, so requests can never
        // pile up into a run of replies nobody asked for.
        guard !responseActive else { queued = [body]; return [] }
        responseActive = true
        return [body]
    }
    private static func systemItem(_ text: String, id: String) -> [String: Any] {
        ["type": "conversation.item.create", "event_id": id,
         "item": ["type": "message", "role": "system", "content": [["type": "input_text", "text": text]]]]
    }
    private var costEvent: [String: Any] { ["type": "mural.voice.cost", "cost": cost] }
    private func usageEvent(_ now: Date) -> [String: Any] {
        ["type": "session.usage.updated", "usage": ["seconds": max(0, now.timeIntervalSince(startedAt))]]
    }
    private func milliseconds(_ date: Date) -> Int { max(0, Int(date.timeIntervalSince(startedAt) * 1000)) }
}
