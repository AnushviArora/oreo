import Cocoa
import AVFoundation

// Personal desktop client: the user's key stays in memory for this launch only.
final class VoiceSession: NSObject {
    var changed: ((String) -> Void)?
    var idle: (() -> Void)?
    var contextProvider: (() -> String)?
    var toolHandler: ((String, [String: Any]) -> String)?
    var autoStart = false
    var key = ""
    var lastError: String?
    var socket: URLSessionWebSocketTask?
    var ready = false
    var listening = false
    var meterTimer: Timer?
    var speechDetected = false
    var lastSpeechTime: TimeInterval = 0
    var loudestPower: Float = -160
    var recording = false
    var busy = false
    var recorder: AVAudioRecorder?
    private lazy var playbackEngine = AVAudioEngine()
    private lazy var playbackNode = AVAudioPlayerNode()
    private var playbackFormat: AVAudioFormat?
    private var playbackConfigured = false
    private var pendingPlaybackBuffers = 0
    private var responseFinished = false
    private var playbackStarted = false
    var timer: Timer?
    private var generation = UUID()
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("voicebubble-\(UUID().uuidString).wav")

    func connect() {
        disconnect()
        lastError = nil
        changed?("Connecting…")
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        receive(generation)
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self = self, !self.ready else { return }
            self.fail("Connection timed out. Check internet access and API billing.")
        }
    }
    func send(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event), let text = String(data: data, encoding: .utf8) else { return }
        let current = generation
        socket?.send(.string(text)) { [weak self] error in
            if error != nil { DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                self.transportFailed()
            } }
        }
    }
    func receive(_ current: UUID) {
        socket?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, current == self.generation else { return }
                switch result {
                case .failure: self.transportFailed()
                case .success(let message):
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let value): data = value
                    @unknown default: return
                    }
                    if let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { self.handle(event) }
                    if self.socket != nil { self.receive(current) }
                }
            }
        }
    }
    func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "session.created":
            let format: [String: Any] = ["type": "audio/pcm", "rate": 24000]
            let input: [String: Any] = ["format": format, "turn_detection": NSNull()]
            let tools: [[String: Any]] = [
                ["type": "function", "name": "remember_memory", "description": "Save one personal detail only when Anushvi explicitly asks Oreo to remember it for future conversations.", "parameters": ["type": "object", "properties": ["fact": ["type": "string"]], "required": ["fact"], "additionalProperties": false]],
                ["type": "function", "name": "forget_memory", "description": "Delete locally saved memories matching a phrase when Anushvi explicitly asks Oreo to forget them.", "parameters": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"], "additionalProperties": false]],
                ["type": "function", "name": "list_memories", "description": "List the personal details Oreo has saved locally when Anushvi asks what Oreo remembers.", "parameters": ["type": "object", "properties": [:], "additionalProperties": false]],
                ["type": "function", "name": "open_application", "description": "Open an approved application or Gmail on this Mac only when Anushvi explicitly asks.", "parameters": ["type": "object", "properties": ["application": ["type": "string", "description": "The app name, such as Safari, Gmail, Spotify, Notes, Finder, Word, or Zoom."]], "required": ["application"], "additionalProperties": false]],
                ["type": "function", "name": "set_system_volume", "description": "Set this Mac's speaker volume only when Anushvi explicitly asks.", "parameters": ["type": "object", "properties": ["level": ["type": "integer", "minimum": 0, "maximum": 100]], "required": ["level"], "additionalProperties": false]],
                ["type": "function", "name": "search_web", "description": "Open Safari and search the web when Anushvi explicitly asks to search, look up, or find something online.", "parameters": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"], "additionalProperties": false]],
                ["type": "function", "name": "play_youtube", "description": "Open Safari, search YouTube, and play a matching numbered result when Anushvi explicitly asks to play something on YouTube or on her laptop.", "parameters": ["type": "object", "properties": ["query": ["type": "string", "description": "Song, artist, video, or topic to play."], "result_number": ["type": "integer", "minimum": 1, "maximum": 20, "description": "Requested result position; use 1 when unspecified."]], "required": ["query"], "additionalProperties": false]],
                ["type": "function", "name": "play_youtube_result", "description": "Play a numbered video from the YouTube search results already visible in Safari. Use this for follow-ups such as ‘play the second video’ without running a new search.", "parameters": ["type": "object", "properties": ["result_number": ["type": "integer", "minimum": 1, "maximum": 20]], "required": ["result_number"], "additionalProperties": false]],
                ["type": "function", "name": "open_gmail_compose", "description": "Open Gmail's Compose screen in Safari when Anushvi asks to compose, write, or start a new email, even if she has not provided any email details yet. Preserve and display any pending draft details.", "parameters": ["type": "object", "properties": [:], "additionalProperties": false]],
                ["type": "function", "name": "update_gmail_draft", "description": "Create or update a Gmail draft in Safari. The user may dictate the body, recipient, and subject in separate turns and any order. Include only fields supplied in the current turn; omitted fields are preserved locally. This tool fills the compose screen but never sends.", "parameters": ["type": "object", "properties": ["recipient": ["type": "string", "description": "Recipient email address exactly as spoken or spelled."], "subject": ["type": "string"], "body": ["type": "string", "description": "The message text to place in the email body."]], "additionalProperties": false]],
                ["type": "function", "name": "clear_gmail_draft", "description": "Clear Oreo's pending Gmail recipient, subject, and body when Anushvi explicitly asks to cancel or start over.", "parameters": ["type": "object", "properties": [:], "additionalProperties": false]]
            ]
            let memories = contextProvider?() ?? "Oreo has no saved personal memories yet."
            let instructions = """
            Your name is Oreo. You are Anushvi's friendly, sassy, funny AI voice assistant. For ordinary conversation, answer immediately in one or two short natural sentences. Match the language the user uses. Be honest that you are AI. Use a memory tool only when Anushvi explicitly asks you to remember, forget, or list saved details. Use a Mac-control or browser tool only when she explicitly asks you to open an app, change volume, search online, play something, or draft an email. When she says “play” a song or video on her laptop, use play_youtube. If YouTube results are already open and she then says “the second video,” “number three,” or similar, use play_youtube_result on the visible results without searching again. For Gmail, always use open_gmail_compose when she asks to open, click, or start Compose without supplying details. Use update_gmail_draft whenever she provides a message body, subject, or recipient; preserve fields from earlier turns by omitting them in later tool calls. Never send an email, click Send, or claim the message was sent. Never claim an action succeeded until its tool result says it succeeded. Do not invent abilities beyond the supplied tools.

            \(memories)
            """
            let configuration: [String: Any] = [
                "type": "realtime", "output_modalities": ["audio"],
                "reasoning": ["effort": "minimal"],
                "instructions": instructions,
                "tools": tools, "tool_choice": "auto",
                "audio": ["input": input, "output": ["format": format, "voice": "marin"]]
            ]
            send(["type": "session.update", "session": configuration])
        case "session.updated":
            ready = true; timer?.invalidate(); changed?("Ready · click to start conversation")
            if autoStart { autoStart = false; toggle() }
        case "input_audio_buffer.committed":
            resetPlaybackState()
            send(["type": "response.create"])
        case "response.output_audio.delta":
            if let encoded = event["delta"] as? String, let bytes = Data(base64Encoded: encoded) {
                queueAudio(bytes)
            }
        case "response.done":
            if let response = event["response"] as? [String: Any], response["status"] as? String == "failed" {
                let details = response["status_details"] as? [String: Any]
                serviceFailed(details?["error"] as? [String: Any] ?? [:]); return
            }
            if let response = event["response"] as? [String: Any], handleToolCalls(response) { return }
            responseFinished = true
            finishPlaybackIfReady()
        case "error":
            serviceFailed(event["error"] as? [String: Any] ?? event)
        default: break
        }
    }
    @discardableResult private func handleToolCalls(_ response: [String: Any]) -> Bool {
        guard let output = response["output"] as? [[String: Any]] else { return false }
        let calls = output.filter { ($0["type"] as? String) == "function_call" }
        guard !calls.isEmpty else { return false }
        for call in calls {
            let name = call["name"] as? String ?? ""
            let callID = call["call_id"] as? String ?? ""
            let raw = call["arguments"] as? String ?? "{}"
            let arguments = ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]) ?? [:]
            let result = toolHandler?(name, arguments) ?? "{\"ok\":false,\"message\":\"Local tools are unavailable.\"}"
            send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": result]])
        }
        changed?("Thinking…")
        send(["type": "response.create"])
        return true
    }
    func toggle() {
        if listening { disconnect(); return }
        guard !busy else { return }
        if !ready { connect(); return }
        let current = generation
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self = self, current == self.generation else { return }
                guard allowed else { self.changed?("Allow microphone access in System Settings"); return }
                self.listening = true
                self.beginRecording()
            }
        }
    }
    func beginRecording() {
        do {
            recorder = try AVAudioRecorder(url: recordingURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            recorder?.isMeteringEnabled = true
            speechDetected = false
            lastSpeechTime = 0
            loudestPower = -160
            guard recorder?.record() == true else { throw NSError(domain: "Microphone", code: 1) }
            recording = true; changed?("Listening · click to stop")
            timer?.invalidate()
            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let now = recorder.currentTime
                let average = recorder.averagePower(forChannel: 0)
                let peak = recorder.peakPower(forChannel: 0)
                self.loudestPower = max(self.loudestPower, average, peak)
                if average > -52 || peak > -44 {
                    self.speechDetected = true
                    self.lastSpeechTime = now
                }
                if self.speechDetected && now - self.lastSpeechTime >= 0.75 {
                    self.finishRecording()
                } else if !self.speechDetected && now >= 2.5 && self.loudestPower > -60 {
                    // Quiet, short phrases can sit below the normal speech threshold.
                    self.speechDetected = true
                    self.lastSpeechTime = now - 0.75
                    self.finishRecording()
                } else if !self.speechDetected && now >= 4 {
                    // Some Mac microphones report unusable meter values even while
                    // recording valid audio. Always submit one short turn instead
                    // of leaving Oreo stuck in Listening.
                    self.finishRecording()
                } else if self.speechDetected && now >= 12 {
                    self.finishRecording()
                } else if !self.speechDetected && now >= 30 {
                    self.disconnect()
                    self.idle?()
                } else if now >= 60 {
                    if self.speechDetected { self.finishRecording() }
                    else {
                        self.meterTimer?.invalidate()
                        recorder.stop()
                        self.recorder = nil
                        self.beginRecording()
                    }
                }
            }
        } catch { listening = false; changed?("Could not start microphone") }
    }
    func finishRecording() {
        guard recording else { return }
        meterTimer?.invalidate(); meterTimer = nil
        let duration = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; recording = false; timer?.invalidate()
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        guard duration >= 0.15, let wav = try? Data(contentsOf: recordingURL), let pcm = Self.pcmData(wav) else {
            if listening { beginRecording() }
            return
        }
        busy = true; changed?("Thinking…")
        send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
        send(["type": "input_audio_buffer.commit"])
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in self?.fail("Response timed out. Click to reconnect.") }
    }
    static func pcmData(_ wav: Data) -> Data? {
        guard wav.count >= 12, String(data: wav.prefix(4), encoding: .ascii) == "RIFF" else { return nil }
        var offset = 12
        while offset + 8 <= wav.count {
            let count = (0..<4).reduce(0) { $0 | Int(wav[offset+4+$1]) << (8*$1) }
            guard count <= wav.count-offset-8 else { return nil }
            if String(data: wav[offset..<offset+4], encoding: .ascii) == "data" { return wav.subdata(in: offset+8..<offset+8+count) }
            offset += 8+count+(count%2)
        }
        return nil
    }
    static func wave(_ pcm: Data) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(Data(value.utf8)) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(pcm.count+36)); text("WAVEfmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(24000)); number(UInt32(48000))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }
    static func pcmBuffer(from pcm: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let byteCount = pcm.count - (pcm.count % MemoryLayout<Int16>.size)
        let frames = AVAudioFrameCount(byteCount / MemoryLayout<Int16>.size)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let offset = frame * 2
            let bits = UInt16(pcm[offset]) | (UInt16(pcm[offset + 1]) << 8)
            channel[frame] = Float(Int16(bitPattern: bits)) / 32_768
        }
        return buffer
    }
    private func preparePlayback() -> Bool {
        if playbackFormat == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) else { return false }
            playbackFormat = format
            playbackEngine.attach(playbackNode)
            playbackEngine.connect(playbackNode, to: playbackEngine.mainMixerNode, format: format)
            playbackConfigured = true
        }
        if !playbackEngine.isRunning {
            do { try playbackEngine.start() }
            catch { return false }
        }
        return true
    }
    private func queueAudio(_ pcm: Data) {
        timer?.invalidate()
        guard preparePlayback(), let format = playbackFormat,
              let buffer = Self.pcmBuffer(from: pcm, format: format) else { return }
        pendingPlaybackBuffers += 1
        playbackNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingPlaybackBuffers = max(0, self.pendingPlaybackBuffers - 1)
                self.finishPlaybackIfReady()
            }
        }
        if !playbackStarted {
            playbackStarted = true
            playbackNode.play()
            changed?("Speaking · click to stop")
        }
    }
    private func resetPlaybackState() {
        if playbackConfigured { playbackNode.stop() }
        pendingPlaybackBuffers = 0
        responseFinished = false
        playbackStarted = false
    }
    private func finishPlaybackIfReady() {
        guard responseFinished, pendingPlaybackBuffers == 0 else { return }
        responseFinished = false
        playbackStarted = false
        busy = false
        if listening { beginRecording() }
    }
    static func safeDetail(_ value: String, key: String) -> String {
        var result = value
        if !key.isEmpty { result = result.replacingOccurrences(of: key, with: "[key hidden]") }
        result = result.replacingOccurrences(of: "sk-[A-Za-z0-9_.*-]+", with: "[key hidden]", options: .regularExpression)
        return String(result.prefix(1200))
    }
    func serviceFailed(_ error: [String: Any]) {
        let code = error["code"] as? String ?? ""
        let type = error["type"] as? String ?? ""
        let detail = Self.safeDetail(error["message"] as? String ?? "The service did not supply a description.", key: key)
        let message: String
        if code == "invalid_api_key" || type == "authentication_error" {
            key = ""
            message = "API key rejected. Choose Change API key and enter the new key."
        } else if code == "insufficient_quota" || code == "billing_hard_limit_reached" {
            message = "API credit or billing limit reached. Check API billing separately from ChatGPT."
        } else if code == "model_not_found" {
            message = "The selected voice model is unavailable to this account."
        } else if code == "rate_limit_exceeded" {
            message = "API rate limit reached. Wait briefly before retrying."
        } else if code == "permission_denied" {
            message = "This API key does not have permission to use the voice service."
        } else {
            message = "The voice service rejected a request. Details appear below."
        }
        fail(message + "\n\n" + detail)
    }
    func transportFailed() {
        let status = (socket?.response as? HTTPURLResponse)?.statusCode
        switch status {
        case 401:
            key = ""; fail("API key rejected. Choose Change API key and enter the new key.")
        case 403: fail("Voice access was denied. Check this key's project permissions and account access.")
        case 404: fail("The selected voice model or endpoint is unavailable to this account.")
        case 429: fail("API quota or rate limit reached. Check API billing and retry later.")
        default: fail("The voice connection closed. Check your internet connection, or replace the key if it was entered incorrectly.")
        }
    }
    func fail(_ message: String) {
        disconnect()
        lastError = message
        changed?("Connection issue · click for details")
    }
    func disconnect() {
        listening = false
        meterTimer?.invalidate(); meterTimer = nil
        generation = UUID(); timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        resetPlaybackState()
        if playbackConfigured { playbackEngine.stop() }
        try? FileManager.default.removeItem(at: recordingURL)
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        ready = false; recording = false; busy = false
        changed?("Disconnected · microphone off")
    }
}
