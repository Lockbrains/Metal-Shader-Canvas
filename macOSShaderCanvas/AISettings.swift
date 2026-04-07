//
//  AISettings.swift
//  macOSShaderCanvas
//
//  Data models and settings UI for AI provider configuration.
//
//  CONTENTS:
//  ─────────
//  1. AIProvider enum   — Supported AI providers (OpenAI, Anthropic, Gemini)
//  2. AISettings class  — Observable settings persisted to UserDefaults
//  3. ChatMessage struct — A single message in the AI chat conversation
//  4. AISettingsView    — Settings sheet for configuring API keys and models
//
//  PERSISTENCE:
//  ────────────
//  All settings are stored in UserDefaults with "ai_" prefixed keys.
//  Each property's `didSet` observer writes the new value immediately.
//  This means settings are persisted without explicit save/load calls.
//
//  SECURITY NOTE:
//  ──────────────
//  API keys are stored in UserDefaults (plaintext). For a production app,
//  consider using Keychain Services for secure credential storage.
//

import Foundation
import SwiftUI

// MARK: - AI Provider

/// The supported AI service providers.
///
/// Each provider has:
/// - A default model (used on first launch)
/// - A list of available models (shown in the settings picker)
/// - Different API endpoints and authentication mechanisms
nonisolated enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"

    var id: String { rawValue }

    /// The recommended default model for this provider.
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4.1"
        case .anthropic: return "claude-sonnet-4-6-20260217"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    /// All models available for selection in the settings UI.
    /// Updated: Feb 2026.
    ///
    /// OpenAI: GPT-5.2 is the latest frontier model (Dec 2025). GPT-4.1 remains
    ///         the smartest non-reasoning model and is the default for shader assistance.
    /// Anthropic: Claude Sonnet 4.6 (Feb 2026) and Opus 4.6 (Feb 2026) are the latest.
    /// Gemini: 3.x series are in preview; 2.5 series remains the stable default.
    var availableModels: [String] {
        switch self {
        case .openai: return ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-5.2", "gpt-5-mini", "gpt-5-nano", "gpt-4o", "gpt-4o-mini", "o4-mini"]
        case .anthropic: return ["claude-sonnet-4-6-20260217", "claude-opus-4-6-20260205", "claude-sonnet-4-20250514", "claude-4-opus-20250514", "claude-3-5-haiku-20241022"]
        case .gemini: return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-3.1-pro-preview", "gemini-3-flash-preview"]
        }
    }
}

// MARK: - Persisted Settings

/// Observable settings object that stores AI provider configuration.
///
/// Uses the `@Observable` macro (Swift 5.9+) for automatic SwiftUI observation.
/// Each property writes to UserDefaults on change via `didSet`, ensuring
/// settings survive app restarts without explicit serialization.
@Observable
class AISettings {
    var selectedProvider: AIProvider {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_provider") }
    }
    var openAIKey: String {
        didSet { UserDefaults.standard.set(openAIKey, forKey: "ai_openai_key") }
    }
    var anthropicKey: String {
        didSet { UserDefaults.standard.set(anthropicKey, forKey: "ai_anthropic_key") }
    }
    var geminiKey: String {
        didSet { UserDefaults.standard.set(geminiKey, forKey: "ai_gemini_key") }
    }
    var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: "ai_openai_model") }
    }
    var anthropicModel: String {
        didSet { UserDefaults.standard.set(anthropicModel, forKey: "ai_anthropic_model") }
    }
    var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "ai_gemini_model") }
    }

    /// Returns the API key for the currently selected provider.
    var currentKey: String {
        switch selectedProvider {
        case .openai: return openAIKey
        case .anthropic: return anthropicKey
        case .gemini: return geminiKey
        }
    }

    /// Returns the model name for the currently selected provider.
    var currentModel: String {
        switch selectedProvider {
        case .openai: return openAIModel
        case .anthropic: return anthropicModel
        case .gemini: return geminiModel
        }
    }

    /// Whether the current provider has a non-empty API key.
    var isConfigured: Bool { !currentKey.isEmpty }

    /// Loads all settings from UserDefaults, falling back to defaults for missing values.
    init() {
        let d = UserDefaults.standard
        self.selectedProvider = AIProvider(rawValue: d.string(forKey: "ai_provider") ?? "") ?? .openai
        self.openAIKey = d.string(forKey: "ai_openai_key") ?? ""
        self.anthropicKey = d.string(forKey: "ai_anthropic_key") ?? ""
        self.geminiKey = d.string(forKey: "ai_gemini_key") ?? ""
        self.openAIModel = d.string(forKey: "ai_openai_model") ?? AIProvider.openai.defaultModel
        self.anthropicModel = d.string(forKey: "ai_anthropic_model") ?? AIProvider.anthropic.defaultModel
        self.geminiModel = d.string(forKey: "ai_gemini_model") ?? AIProvider.gemini.defaultModel
    }
}

// MARK: - Chat Message

/// A single message in the AI chat conversation.
///
/// Each message has a role (user/assistant/system), content text,
/// and a timestamp. The UUID enables SwiftUI list identification.
nonisolated struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var executedActions: [AgentAction]? = nil
    var executedLabActions: [LabAction]? = nil
    var barriers: [String]? = nil
    var thinking: String? = nil
    var plan: AgentPlan? = nil
    var renderSnapshot: Data? = nil
    var userImage: Data? = nil

    nonisolated enum MessageRole: String, Codable, Sendable { case user, assistant, system }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
        case executedActions, executedLabActions, barriers, thinking, plan
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, executedActions: [AgentAction]? = nil,
         executedLabActions: [LabAction]? = nil, barriers: [String]? = nil,
         thinking: String? = nil, plan: AgentPlan? = nil,
         renderSnapshot: Data? = nil, userImage: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.executedActions = executedActions
        self.executedLabActions = executedLabActions
        self.barriers = barriers
        self.thinking = thinking
        self.plan = plan
        self.renderSnapshot = renderSnapshot
        self.userImage = userImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        executedActions = try container.decodeIfPresent([AgentAction].self, forKey: .executedActions)
        executedLabActions = try container.decodeIfPresent([LabAction].self, forKey: .executedLabActions)
        barriers = try container.decodeIfPresent([String].self, forKey: .barriers)
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        plan = try container.decodeIfPresent(AgentPlan.self, forKey: .plan)
        renderSnapshot = nil
        userImage = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(executedActions, forKey: .executedActions)
        try container.encodeIfPresent(executedLabActions, forKey: .executedLabActions)
        try container.encodeIfPresent(barriers, forKey: .barriers)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(plan, forKey: .plan)
    }
}

// MARK: - AI Settings View

/// A modal settings sheet for configuring AI provider API keys and model selection.
///
/// Displays three provider sections (OpenAI, Anthropic, Gemini) with:
/// - A secure text field for the API key
/// - A model picker showing available models
/// - Visual opacity dimming for non-selected providers
/// - A status indicator showing whether the current provider is configured
struct AISettingsView: View {
    @Bindable var settings: AISettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("AI Settings").font(.title2.bold())

            // Provider selection (segmented control).
            Picker("Provider", selection: $settings.selectedProvider) {
                ForEach(AIProvider.allCases) { p in Text(verbatim: p.rawValue).tag(p) }
            }.pickerStyle(.segmented)

            // OpenAI configuration.
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    keyField("OpenAI API Key", key: $settings.openAIKey)
                    modelPicker($settings.openAIModel, provider: .openai)
                }.padding(8)
            } label: { Label("OpenAI", systemImage: "brain.head.profile") }
            .opacity(settings.selectedProvider == .openai ? 1 : 0.5)

            // Anthropic configuration.
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    keyField("Anthropic API Key", key: $settings.anthropicKey)
                    modelPicker($settings.anthropicModel, provider: .anthropic)
                }.padding(8)
            } label: { Label("Anthropic", systemImage: "sparkle") }
            .opacity(settings.selectedProvider == .anthropic ? 1 : 0.5)

            // Gemini configuration.
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    keyField("Gemini API Key", key: $settings.geminiKey)
                    modelPicker($settings.geminiModel, provider: .gemini)
                }.padding(8)
            } label: { Label("Gemini", systemImage: "wand.and.stars") }
            .opacity(settings.selectedProvider == .gemini ? 1 : 0.5)

            // Status indicator and dismiss button.
            HStack {
                if settings.isConfigured {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                } else {
                    Label("Enter an API key for the selected provider", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480)
    }

    /// A labeled secure text field for API key entry.
    private func keyField(_ label: String, key: Binding<String>) -> some View {
        HStack { Text(label).frame(width: 140, alignment: .leading); SecureField("sk-...", text: key).textFieldStyle(.roundedBorder) }
    }

    /// A labeled model picker for the given provider.
    private func modelPicker(_ sel: Binding<String>, provider: AIProvider) -> some View {
        HStack { Text("Model").frame(width: 140, alignment: .leading); Picker("", selection: sel) { ForEach(provider.availableModels, id: \.self) { Text(verbatim: $0).tag($0) } } }
    }
}
