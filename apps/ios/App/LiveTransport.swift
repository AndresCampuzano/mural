import Foundation
import AVFoundation
import MuralCore
@preconcurrency import WebRTC

enum ConnectionState: Equatable { case idle, connecting, active, closing, ended, failed }

@MainActor final class LiveTransport: NSObject {
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var localTrack: RTCAudioTrack?
    private var meterTask: Task<Void, Never>?
    private var attempt = UUID()
    private(set) var started = false
    private(set) var isMuted = false
    /// False when the provider rejected the speaking pace and the session was created without it.
    private(set) var paceApplied = true
    private(set) var paceRejection: String?
    private var closing = false
    private var ownsAudioActivation = false
    private var lastInput = 0.0, lastOutput = 0.0
    private var reportedMuted = false
    /// Present while a token-billed voice model carries the call, translating its events into the
    /// session protocol the app speaks. Absent for gpt-live-1, which speaks that protocol itself.
    private var bridge: RealtimeBridge?
    /// True while the microphone is held closed because the model's own audio is playing.
    private var echoGuarded = false
    private var echoTask: Task<Void, Never>?
    private var outputQuietSince: Date?

    /// `speed` is the provider's playback multiple for generated speech. It is clamped to the
    /// documented 0.25–1.5 range and can only be set between turns, so Mural sends it once here.
    /// https://developers.openai.com/api/reference/resources/realtime/client-events
    func connect(api: APIClient, instructions: String, history: [[String: Any]], speed: Double = 1, model: VoiceModel = .live) async throws {
        disconnect()
        bridge = model == .live ? nil : RealtimeBridge(startedAt: .now)
        closing = false
        paceApplied = true; paceRejection = nil
        let token = UUID(); attempt = token
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw TransportError.microphone }
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
        // WebRTC reapplies this configuration when its audio unit starts.
        // Setting AVAudioSession alone loses the speaker preference at that point.
        let audioConfiguration = RTCAudioSessionConfiguration()
        audioConfiguration.category = AVAudioSession.Category.playAndRecord.rawValue
        audioConfiguration.mode = AVAudioSession.Mode.voiceChat.rawValue
        audioConfiguration.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        RTCAudioSessionConfiguration.setWebRTC(audioConfiguration)
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        do {
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: audioConfiguration.categoryOptions)
            try audio.setActive(true)
            ownsAudioActivation = true
            audio.unlockForConfiguration()
        } catch { audio.unlockForConfiguration(); throw error }
        RTCInitializeSSL()
        let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        self.factory = factory
        let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherOnce
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        guard let peer = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { throw TransportError.connection }
        self.peer = peer
        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["googEchoCancellation": "true", "googNoiseSuppression": "true", "googAutoGainControl": "true"]))
        let track = factory.audioTrack(with: source, trackId: "mural-microphone")
        localTrack = track; isMuted = false
        peer.add(track, streamIds: ["mural-audio"])
        let dataConfig = RTCDataChannelConfiguration(); dataConfig.isOrdered = true
        guard let channel = peer.dataChannel(forLabel: "oai-events", configuration: dataConfig) else { throw TransportError.connection }
        self.channel = channel; channel.delegate = self
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { c in
            peer.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"], optionalConstraints: nil)) { sdp, error in
                if let error { c.resume(throwing: error) } else if let sdp { c.resume(returning: sdp) } else { c.resume(throwing: TransportError.connection) }
            }
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in if let error { c.resume(throwing: error) } else { c.resume() } }
        }
        let deadline = Date().addingTimeInterval(10)
        while peer.iceGatheringState != .complete {
            try await Task.sleep(for: .milliseconds(100))
            guard attempt == token else { throw CancellationError() }
            guard Date() < deadline else { throw TransportError.timeout }
        }
        guard let sdp = peer.localDescription?.sdp else { throw TransportError.connection }
        let outputSpeed = speed.isFinite ? min(SpeechPace.range.upperBound, max(SpeechPace.range.lowerBound, speed)) : 1
        // A token-billed model answers with the SDP alone; its session is announced on the data channel.
        if model != .live {
            func call(withSpeed: Bool) async throws -> String {
                try await api.realtimeCall(sdp: sdp, session: RealtimeBridge.session(model: model, instructions: instructions, speed: withSpeed ? outputSpeed : nil))
            }
            let wantsSpeed = outputSpeed != 1
            let answer: String
            do { answer = try await call(withSpeed: wantsSpeed) }
            catch APIClient.APIError.http(400, let detail) where wantsSpeed {
                guard attempt == token else { throw CancellationError() }
                paceApplied = false; paceRejection = detail
                answer = try await call(withSpeed: false)
            }
            guard attempt == token else { throw CancellationError() }
            try await answerAndWait(peer: peer, sdp: answer, token: token)
            return
        }
        func createSession(withSpeed: Bool) async throws -> [String: Any] {
            var output: [String: Any] = ["voice": "marin"]
            if withSpeed { output["speed"] = outputSpeed }
            return try await api.post("live/sessions", body: [
                "session": ["model": "gpt-live-1", "instructions": instructions, "input": history,
                            "store": false, "delegation": ["type": "client"], "audio": ["output": output]],
                "transport": ["type": "webrtc", "sdp": sdp]
            ])
        }
        // A rejected create is never billed and never opened a session, so the one retry here is
        // safe. A pace this model will not accept must not cost the learner the conversation.
        let wantsSpeed = outputSpeed != 1
        let result: [String: Any]
        do { result = try await createSession(withSpeed: wantsSpeed) }
        catch APIClient.APIError.http(400, let detail) where wantsSpeed {
            guard attempt == token else { throw CancellationError() }
            paceApplied = false; paceRejection = detail
            result = try await createSession(withSpeed: false)
        }
        guard attempt == token else { throw CancellationError() }
        guard let transport = result["transport"] as? [String: Any], let answer = transport["sdp"] as? String else { throw TransportError.connection }
        if let session = result["session"] as? [String: Any] { onEvent?(["type": "mural.session.created", "session": session]) }
        try await answerAndWait(peer: peer, sdp: answer, token: token)
    }

    private func answerAndWait(peer: RTCPeerConnection, sdp answer: String, token: UUID) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
        let readyDeadline = Date().addingTimeInterval(20)
        while !started {
            try await Task.sleep(for: .milliseconds(100))
            guard attempt == token else { throw CancellationError() }
            guard Date() < readyDeadline else { throw TransportError.timeout }
        }
        startMetering()
    }

    @discardableResult func send(_ event: [String: Any]) -> Bool {
        guard bridge != nil else {
            var event = event; event.removeValue(forKey: RealtimeBridge.respondKey)
            return sendRaw(event)
        }
        guard let channel, channel.readyState == .open else { return false }
        // A command the bridge holds back until the current response ends is still accepted.
        return bridge!.outbound(event).allSatisfy { sendRaw($0) }
    }
    private func sendRaw(_ event: [String: Any]) -> Bool {
        guard let channel, channel.readyState == .open, let data = try? JSONSerialization.data(withJSONObject: event) else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    func mute(_ muted: Bool) {
        isMuted = muted; localTrack?.isEnabled = !muted && !echoGuarded
        _ = send(["type": muted ? "session.input_audio.mute" : "session.input_audio.unmute", "event_id": UUID().uuidString])
    }
    func close() {
        closing = true; localTrack?.isEnabled = false; isMuted = true
        _ = send(["type": "session.close", "event_id": UUID().uuidString])
        // The Realtime API has no close handshake: the call ends when the app disconnects, so the
        // closing report is made here, after the caller has finished starting its own close.
        if let bridge {
            let events = bridge.closed()
            Task { @MainActor [weak self] in events.forEach { self?.onEvent?($0) } }
        }
    }
    func disconnect() {
        attempt = UUID(); meterTask?.cancel(); meterTask = nil
        echoTask?.cancel(); echoTask = nil; echoGuarded = false; outputQuietSince = nil
        started = false; closing = true
        localTrack?.isEnabled = false; localTrack = nil
        channel?.delegate = nil; channel?.close(); channel = nil
        peer?.delegate = nil; peer?.close(); peer = nil; factory = nil
        if ownsAudioActivation {
            let audio = RTCAudioSession.sharedInstance(); audio.lockForConfiguration()
            try? audio.setActive(false); audio.unlockForConfiguration()
            ownsAudioActivation = false
        }
        lastInput = 0; lastOutput = 0; reportedMuted = false; onLevels?(0, 0)
        bridge = nil
    }
    /// Holds the microphone closed while a token-billed voice plays its own audio, which it would
    /// otherwise hear through the speaker and answer as if the learner had spoken. It reopens a
    /// moment after playback stops, so the room's echo has died away, and never stays closed
    /// longer than a single reply could last.
    private func guardEcho(_ closed: Bool) {
        echoTask?.cancel()
        if closed {
            echoGuarded = true; localTrack?.isEnabled = false
            echoTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                self?.guardEcho(false)
            }
        } else {
            echoTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, self.echoGuarded else { return }
                self.echoGuarded = false
                _ = self.sendRaw(["type": "input_audio_buffer.clear", "event_id": UUID().uuidString])
                self.localTrack?.isEnabled = !self.isMuted && !self.closing
            }
        }
    }
    /// A backstop for the playback events, which can arrive late: audio heard from the model
    /// closes the microphone, and 0.8 seconds of silence from it reopens it.
    private func followPlayback(_ level: Double) {
        if level > 0.02 {
            outputQuietSince = nil
            if !echoGuarded { guardEcho(true) }
        } else if echoGuarded {
            let quiet = outputQuietSince ?? .now; outputQuietSince = quiet
            if Date().timeIntervalSince(quiet) >= 0.8 { outputQuietSince = nil; guardEcho(false) }
        }
    }
    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let peer = self.peer else { return }
                peer.statistics { [weak self] report in
                    var input = 0.0, output = 0.0
                    for stat in report.statistics.values {
                        let level = (stat.values["audioLevel"] as? NSNumber)?.doubleValue ?? 0
                        if stat.type == "inbound-rtp" { output = max(output, level) }
                        if stat.type == "media-source" { input = max(input, level) }
                    }
                    Task { @MainActor [weak self] in
                        guard let self, self.started else { return }
                        let nextInput = self.lastInput * 0.35 + min(1, input * 4) * 0.65
                        let nextOutput = self.lastOutput * 0.35 + min(1, output * 4) * 0.65
                        // Every level reported redraws the orb. Building a statistics report and
                        // publishing a level that has settled costs a conversation's worth of work
                        // for a picture that does not change, so silence stops reporting.
                        let settled = abs(nextInput - self.lastInput) < 0.004 && abs(nextOutput - self.lastOutput) < 0.004
                            && self.isMuted == self.reportedMuted
                        self.lastInput = nextInput; self.lastOutput = nextOutput
                        if self.bridge != nil { self.followPlayback(output) }
                        guard !settled else { return }
                        self.reportedMuted = self.isMuted
                        self.onLevels?(self.isMuted ? 0 : self.lastInput, self.lastOutput)
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    enum TransportError: LocalizedError {
        case microphone, connection, timeout
        var errorDescription: String? {
            switch self {
            case .microphone: "Allow microphone access in iPhone Settings → Mural to start a conversation."
            case .connection: "The voice connection couldn’t be established. Check your connection and try again."
            case .timeout: "The voice connection took too long. Please try again."
            }
        }
    }
}

extension LiveTransport: RTCDataChannelDelegate, RTCPeerConnectionDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let closed = dataChannel.readyState == .closed
        Task { @MainActor [weak self] in
            guard let self, dataChannel === self.channel, closed, !self.closing else { return }
            self.onFailure?("The voice connection ended unexpectedly. Your conversation has been saved.")
        }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        Task { @MainActor [weak self] in
            guard let self, dataChannel === self.channel,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard self.bridge != nil else {
                if json["type"] as? String == "session.started" { self.started = true }
                self.onEvent?(json); return
            }
            let (emit, send) = self.bridge!.inbound(json)
            if let microphone = self.bridge!.microphone { self.bridge!.microphone = nil; self.guardEcho(microphone == .close) }
            send.forEach { _ = self.sendRaw($0) }
            for event in emit {
                if event["type"] as? String == "session.started" { self.started = true }
                self.onEvent?(event)
            }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peer, !self.closing else { return }
            if newState == .failed { self.onFailure?("The network connection was lost. Tap to start a new conversation.") }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
