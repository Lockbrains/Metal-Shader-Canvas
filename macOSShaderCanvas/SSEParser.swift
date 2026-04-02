//
//  SSEParser.swift
//  macOSShaderCanvas
//
//  Server-Sent Events (SSE) parser and streaming infrastructure for AI providers.
//
//  Provides a unified streaming interface across OpenAI, Anthropic, and Gemini.
//  Each provider uses URLSession.bytes(for:) to receive incremental SSE events,
//  which are parsed into StreamChunk values delivered via AsyncStream.
//

import Foundation

// MARK: - SSE Line Parser

nonisolated struct SSEEvent: Sendable {
    var event: String?
    var data: String = ""
}

/// Parses a stream of bytes into SSE events, handling `event:` and `data:` prefixes.
///
/// Gemini's SSE data lines may contain literal newlines inside JSON string values
/// (e.g. AI-generated markdown with `\n`). `URLSession.bytes.lines` splits on ALL
/// newlines, producing continuation lines that lack any SSE prefix. These are
/// appended to the current data buffer to reconstruct the full JSON payload.
nonisolated struct SSELineParser: Sendable {
    private var currentEvent: SSEEvent = SSEEvent()

    mutating func feedLine(_ line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if !currentEvent.data.isEmpty {
                let event = currentEvent
                currentEvent = SSEEvent()
                return event
            }
            return nil
        }

        if trimmed.hasPrefix(":") {
            // SSE comment — ignore
        } else if trimmed.hasPrefix("event:") {
            currentEvent.event = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("data:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if !currentEvent.data.isEmpty { currentEvent.data += "\n" }
            currentEvent.data += payload
        } else if !currentEvent.data.isEmpty {
            // Continuation: literal newline inside an SSE data payload (common with Gemini).
            // Append to the current data buffer to reconstruct the full JSON.
            currentEvent.data += "\n" + trimmed
        }

        return nil
    }
}

// MARK: - Provider Delta Parsers

nonisolated func parseOpenAIDelta(_ data: String) -> String? {
    guard data != "[DONE]",
          let jsonData = data.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let delta = choices.first?["delta"] as? [String: Any],
          let content = delta["content"] as? String
    else { return nil }
    return content
}

nonisolated func parseAnthropicDelta(_ data: String, event: String?) -> String? {
    guard event == "content_block_delta",
          let jsonData = data.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let delta = json["delta"] as? [String: Any],
          let text = delta["text"] as? String
    else { return nil }
    return text
}

nonisolated func parseGeminiChunk(_ data: String) -> String? {
    guard let jsonData = data.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let content = candidates.first?["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let text = parts.first?["text"] as? String
    else { return nil }
    return text
}

/// Gemini sends literal newline bytes (0x0A) inside JSON "text" values instead of
/// the JSON escape sequence `\n`. After SSE line reassembly, the data string has
/// literal newlines that make JSONSerialization reject it. Replacing 0x0A → `\n`
/// (and 0x0D → `\r`) restores valid JSON. JSONSerialization then decodes the escape
/// sequences back to actual newline/CR characters in the parsed string, so the
/// extracted text is correct.
nonisolated func parseGeminiChunkSanitized(_ data: String) -> String? {
    let sanitized = data
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
    return parseGeminiChunk(sanitized)
}

// MARK: - Captured Settings (actor-safe snapshot)

/// Value-type snapshot of AISettings, captured on MainActor before crossing into
/// the AIService actor. This avoids accessing @Observable properties across actor
/// boundaries, which causes silent failures under strict concurrency.
nonisolated struct CapturedAISettings: Sendable {
    let provider: AIProvider
    let apiKey: String
    let model: String
}

extension AISettings {
    /// Creates a Sendable snapshot of the currently-selected provider's config.
    @MainActor
    var captured: CapturedAISettings {
        CapturedAISettings(provider: selectedProvider, apiKey: currentKey, model: currentModel)
    }
}

// MARK: - Streaming Session

nonisolated(unsafe) private let streamingSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 600
    return URLSession(configuration: config)
}()

// MARK: - Streaming Service Extension

extension AIService {

    /// Streams an agent chat response, delivering tokens as they arrive.
    ///
    /// All settings values are captured eagerly (before entering the actor-isolated Task)
    /// to avoid cross-actor access to @Observable properties.
    func streamAgentChat(
        messages: [ChatMessage], context: String, dataFlowDescription: String,
        canvasMode: CanvasMode = .threeDimensional, captured: CapturedAISettings,
        imageData: Data? = nil
    ) -> AsyncStream<StreamChunk> {
        let systemPrompt = canvasMode.is2D
            ? build2DSystemPrompt(context: context, dataFlowDescription: dataFlowDescription)
            : build3DSystemPrompt(context: context, dataFlowDescription: dataFlowDescription)
        switch captured.provider {
        case .openai:   return streamOpenAI(system: systemPrompt, messages: messages, captured: captured, imageData: imageData)
        case .anthropic: return streamAnthropic(system: systemPrompt, messages: messages, captured: captured, imageData: imageData)
        case .gemini:   return streamGemini(system: systemPrompt, messages: messages, captured: captured, imageData: imageData)
        }
    }

    // MARK: - OpenAI Streaming

    /// Uses `nonisolated` so the internal Task runs on the global executor,
    /// not the AIService actor — preventing scheduling deadlocks with the consumer.
    nonisolated func streamOpenAI(system: String, messages: [ChatMessage], captured: CapturedAISettings, imageData: Data?) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        let msgs = Self.buildOpenAIMessages(system: system, messages: messages, imageData: imageData)
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "messages": msgs,
                        "max_tokens": 4096, "stream": true
                    ] as [String: Any])

                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseOpenAIDelta(event.data) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Anthropic Streaming

    nonisolated func streamAnthropic(system: String, messages: [ChatMessage], captured: CapturedAISettings, imageData: Data?) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        let msgs = Self.buildAnthropicMessages(messages: messages, imageData: imageData)
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "max_tokens": 4096,
                        "system": system, "messages": msgs, "stream": true
                    ] as [String: Any])

                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseAnthropicDelta(event.data, event: event.event) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Gemini Streaming

    nonisolated func streamGemini(system: String, messages: [ChatMessage], captured: CapturedAISettings, imageData: Data?) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        let contents = Self.buildGeminiContents(messages: messages, imageData: imageData)
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "contents": contents,
                        "systemInstruction": ["parts": [["text": system]]]
                    ] as [String: Any])

                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseGeminiChunk(event.data) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Lab Chat Streaming

    /// Streams a Lab chat response with a custom system prompt.
    /// Returns an AsyncStream of text deltas. The accumulated text should be parsed
    /// as LabAgentResponse JSON when the stream completes.
    nonisolated func streamLabChat(
        system: String, messages: [ChatMessage], captured: CapturedAISettings,
        imageData: Data?, additionalImages: [Data] = []
    ) -> AsyncStream<StreamChunk> {
        switch captured.provider {
        case .openai:
            return streamOpenAILab(system: system, messages: messages, captured: captured, imageData: imageData, additionalImages: additionalImages)
        case .anthropic:
            return streamAnthropicLab(system: system, messages: messages, captured: captured, imageData: imageData, additionalImages: additionalImages)
        case .gemini:
            return streamGeminiLab(system: system, messages: messages, captured: captured, imageData: imageData, additionalImages: additionalImages)
        }
    }

    private nonisolated func streamOpenAILab(
        system: String, messages: [ChatMessage], captured: CapturedAISettings,
        imageData: Data?, additionalImages: [Data]
    ) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser {
                var contentArray: [[String: Any]] = [["type": "text", "text": m.content]]
                if let img = imageData {
                    contentArray.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img.base64EncodedString())", "detail": "low"]])
                }
                for extra in additionalImages {
                    contentArray.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(extra.base64EncodedString())", "detail": "low"]])
                }
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "messages": msgs,
                        "max_tokens": 8192, "stream": true
                    ] as [String: Any])
                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseOpenAIDelta(event.data) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    private nonisolated func streamAnthropicLab(
        system: String, messages: [ChatMessage], captured: CapturedAISettings,
        imageData: Data?, additionalImages: [Data]
    ) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        var msgs: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser {
                var contentArray: [[String: Any]] = []
                if let img = imageData {
                    contentArray.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": img.base64EncodedString()]])
                }
                for extra in additionalImages {
                    contentArray.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": extra.base64EncodedString()]])
                }
                contentArray.append(["type": "text", "text": m.content])
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "max_tokens": 8192,
                        "system": system, "messages": msgs, "stream": true
                    ] as [String: Any])
                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseAnthropicDelta(event.data, event: event.event) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    private nonisolated func streamGeminiLab(
        system: String, messages: [ChatMessage], captured: CapturedAISettings,
        imageData: Data?, additionalImages: [Data]
    ) -> AsyncStream<StreamChunk> {
        let apiKey = captured.apiKey
        let model = captured.model
        var contents: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "model"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser {
                var parts: [[String: Any]] = [["text": m.content]]
                if let img = imageData {
                    parts.append(["inlineData": ["mimeType": "image/jpeg", "data": img.base64EncodedString()]])
                }
                for extra in additionalImages {
                    parts.append(["inlineData": ["mimeType": "image/jpeg", "data": extra.base64EncodedString()]])
                }
                contents.append(["role": role, "parts": parts])
            } else {
                contents.append(["role": role, "parts": [["text": m.content]]])
            }
        }
        return AsyncStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "contents": contents,
                        "systemInstruction": ["parts": [["text": system]]]
                    ] as [String: Any])
                    let (bytes, resp) = try await streamingSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(StreamChunk(type: .content, delta: "[Stream error: HTTP \(code)]"))
                        continuation.finish(); return
                    }
                    var parser = SSELineParser()
                    for try await line in bytes.lines {
                        if let event = parser.feedLine(line),
                           let text = parseGeminiChunk(event.data) {
                            continuation.yield(StreamChunk(type: .content, delta: text))
                        }
                    }
                } catch {
                    continuation.yield(StreamChunk(type: .content, delta: "[Stream error: \(error.localizedDescription)]"))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Message Builders (nonisolated helpers)

    /// Pre-builds the OpenAI messages array outside the Task closure to avoid
    /// capturing non-Sendable ChatMessage across isolation boundaries.
    private nonisolated static func buildOpenAIMessages(system: String, messages: [ChatMessage], imageData: Data?) -> [[String: Any]] {
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let contentArray: [[String: Any]] = [
                    ["type": "text", "text": m.content],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "low"]]
                ]
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        return msgs
    }

    private nonisolated static func buildAnthropicMessages(messages: [ChatMessage], imageData: Data?) -> [[String: Any]] {
        var msgs: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "assistant"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let contentArray: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                    ["type": "text", "text": m.content]
                ]
                msgs.append(["role": role, "content": contentArray])
            } else {
                msgs.append(["role": role, "content": m.content])
            }
        }
        return msgs
    }

    private nonisolated static func buildGeminiContents(messages: [ChatMessage], imageData: Data?) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == .user ? "user" : "model"
            let isLastUser = (m.role == .user && i == messages.count - 1)
            if isLastUser, let img = imageData {
                let b64 = img.base64EncodedString()
                let parts: [[String: Any]] = [
                    ["text": m.content],
                    ["inlineData": ["mimeType": "image/jpeg", "data": b64]]
                ]
                contents.append(["role": role, "parts": parts])
            } else {
                contents.append(["role": role, "parts": [["text": m.content]]])
            }
        }
        return contents
    }
}
