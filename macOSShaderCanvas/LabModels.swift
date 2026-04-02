//
//  LabModels.swift
//  macOSShaderCanvas
//
//  Data models for Lab mode — the AI-collaborative shader development workflow.
//
//  Lab mode extends Canvas with:
//  - Reference collection (images, videos, GIFs, text)
//  - Phased collaborative AI discussion
//  - Co-authored project documents
//  - Parameter snapshots with "engineering haptics"
//  - Adversarial generation versioning
//

import Foundation

// MARK: - Lab Phase

/// Workflow stages in Lab mode. The phases are sequential but allow
/// backward navigation (e.g. returning to Q&A after implementation).
enum LabPhase: String, Codable, CaseIterable, Identifiable {
    case referenceInput   = "References"
    case analysis         = "Analysis"
    case documentDrafting = "Document"
    case implementation   = "Implementation"
    case tuning           = "Tuning"
    case adversarial      = "Adversarial"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .referenceInput:   return "photo.on.rectangle.angled"
        case .analysis:         return "sparkle.magnifyingglass"
        case .documentDrafting: return "doc.text"
        case .implementation:   return "hammer"
        case .tuning:           return "slider.horizontal.3"
        case .adversarial:      return "arrow.triangle.2.circlepath"
        }
    }

    var displayName: String {
        switch self {
        case .referenceInput:   return String(localized: "Reference Input")
        case .analysis:         return String(localized: "Collaborative Analysis")
        case .documentDrafting: return String(localized: "Project Document")
        case .implementation:   return String(localized: "Implementation")
        case .tuning:           return String(localized: "Parameter Tuning")
        case .adversarial:      return String(localized: "Adversarial Generation")
        }
    }

    var phaseIndex: Int {
        switch self {
        case .referenceInput:   return 0
        case .analysis:         return 1
        case .documentDrafting: return 2
        case .implementation:   return 3
        case .tuning:           return 4
        case .adversarial:      return 5
        }
    }
}

// MARK: - Reference Item

/// A single reference asset provided by the user for AI analysis.
enum ReferenceType: String, Codable {
    case image
    case video
    case gif
    case text
}

struct ReferenceItem: Identifiable, Codable {
    let id: UUID
    var type: ReferenceType
    var annotation: String
    var dateAdded: Date

    /// Raw file data for image/video/gif types. nil for text-only references.
    var mediaData: Data?
    /// JPEG thumbnail for quick display (generated on import).
    var thumbnailData: Data?
    /// Original filename if imported from a file.
    var originalFilename: String?
    /// Text content for `.text` type references or extended descriptions.
    var textContent: String?

    init(id: UUID = UUID(), type: ReferenceType, annotation: String = "",
         mediaData: Data? = nil, thumbnailData: Data? = nil,
         originalFilename: String? = nil, textContent: String? = nil) {
        self.id = id
        self.type = type
        self.annotation = annotation
        self.dateAdded = Date()
        self.mediaData = mediaData
        self.thumbnailData = thumbnailData
        self.originalFilename = originalFilename
        self.textContent = textContent
    }
}

// MARK: - Project Document

/// A parameter specification within the project document, defined before
/// implementation to guide the AI's shader generation.
struct ParamSpec: Identifiable, Codable {
    let id: UUID
    var name: String
    var purpose: String
    var type: ParamType
    var suggestedDefault: [Float]
    var suggestedMin: Float?
    var suggestedMax: Float?

    init(id: UUID = UUID(), name: String, purpose: String, type: ParamType = .float,
         suggestedDefault: [Float] = [1.0], suggestedMin: Float? = nil, suggestedMax: Float? = nil) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.type = type
        self.suggestedDefault = suggestedDefault
        self.suggestedMin = suggestedMin
        self.suggestedMax = suggestedMax
    }
}

/// A single iteration entry recording a decision point during adversarial generation.
struct IterationEntry: Identifiable, Codable {
    let id: UUID
    var date: Date
    var description: String
    var decision: String
    /// "accepted", "rejected", "modified"
    var outcome: String
    var snapshotID: UUID?

    init(id: UUID = UUID(), description: String, decision: String,
         outcome: String = "pending", snapshotID: UUID? = nil) {
        self.id = id
        self.date = Date()
        self.description = description
        self.decision = decision
        self.outcome = outcome
        self.snapshotID = snapshotID
    }
}

/// Final project documentation — technical specs, implementation details,
/// parameter documentation for migration/handoff. Pure markdown with
/// supplementary structured data for backward compatibility.
struct ProjectDocument: Codable {
    var markdown: String
    var lastModified: Date

    // Legacy structured fields — kept for backward compatibility with saved files.
    // New content goes into `markdown` directly.
    var title: String
    var visualGoal: String
    var referenceAnalysis: String
    var technicalApproach: String
    var parameterDesign: [ParamSpec]
    var iterationLog: [IterationEntry]
    var constraints: [String]

    init(markdown: String = "",
         title: String = "Untitled Shader Project",
         visualGoal: String = "",
         referenceAnalysis: String = "",
         technicalApproach: String = "",
         parameterDesign: [ParamSpec] = [],
         iterationLog: [IterationEntry] = [],
         constraints: [String] = []) {
        self.markdown = markdown
        self.lastModified = Date()
        self.title = title
        self.visualGoal = visualGoal
        self.referenceAnalysis = referenceAnalysis
        self.technicalApproach = technicalApproach
        self.parameterDesign = parameterDesign
        self.iterationLog = iterationLog
        self.constraints = constraints
    }

    var isEmpty: Bool {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && visualGoal.isEmpty && referenceAnalysis.isEmpty
        && technicalApproach.isEmpty && parameterDesign.isEmpty
    }

    /// Migrates legacy structured fields into a markdown string.
    /// Called once when loading old documents that have structured data but no markdown.
    mutating func migrateToMarkdown() {
        guard markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let hasLegacy = !visualGoal.isEmpty || !referenceAnalysis.isEmpty
            || !technicalApproach.isEmpty || !parameterDesign.isEmpty
        guard hasLegacy else { return }

        var md = "# \(title)\n\n"
        if !visualGoal.isEmpty {
            md += "## Visual Goal\n\n\(visualGoal)\n\n"
        }
        if !referenceAnalysis.isEmpty {
            md += "## Reference Analysis\n\n\(referenceAnalysis)\n\n"
        }
        if !technicalApproach.isEmpty {
            md += "## Technical Approach\n\n\(technicalApproach)\n\n"
        }
        if !parameterDesign.isEmpty {
            md += "## Parameters\n\n"
            md += "| Name | Type | Purpose | Default | Range |\n"
            md += "|------|------|---------|---------|-------|\n"
            for p in parameterDesign {
                let def = p.suggestedDefault.map { String(format: "%.2f", $0) }.joined(separator: ", ")
                let range: String
                if let mn = p.suggestedMin, let mx = p.suggestedMax {
                    range = "\(String(format: "%.2f", mn))–\(String(format: "%.2f", mx))"
                } else {
                    range = "—"
                }
                md += "| \(p.name) | \(p.type.rawValue) | \(p.purpose) | \(def) | \(range) |\n"
            }
            md += "\n"
        }
        if !constraints.isEmpty {
            md += "## Constraints\n\n"
            for c in constraints { md += "- \(c)\n" }
            md += "\n"
        }
        if !iterationLog.isEmpty {
            md += "## Iteration Log\n\n"
            for entry in iterationLog {
                md += "- **\(entry.decision)**: \(entry.description) (\(entry.outcome))\n"
            }
            md += "\n"
        }
        markdown = md
        lastModified = Date()
    }
}

// MARK: - Parameter Snapshot

/// A frozen snapshot of all parameter values + render capture at a point in time.
/// Used by the engineering haptics system to enable timeline browsing and A/B comparison.
struct ParameterSnapshot: Identifiable, Codable {
    let id: UUID
    var date: Date
    var paramValues: [String: [Float]]
    /// JPEG render capture at the time of snapshot.
    var renderCapture: Data?
    var aiComment: String?
    var label: String?
    /// The shader code hash at the time of snapshot, to detect code-level changes.
    var codeHash: String?

    init(id: UUID = UUID(), paramValues: [String: [Float]],
         renderCapture: Data? = nil, aiComment: String? = nil,
         label: String? = nil, codeHash: String? = nil) {
        self.id = id
        self.date = Date()
        self.paramValues = paramValues
        self.renderCapture = renderCapture
        self.aiComment = aiComment
        self.label = label
        self.codeHash = codeHash
    }
}

// MARK: - Adversarial Proposal

/// A proposal from the AI during adversarial generation, containing
/// alternative code and/or parameter changes for human review.
struct AdversarialProposal: Identifiable, Codable {
    let id: UUID
    var date: Date
    var description: String
    var rationale: String
    /// Proposed code changes keyed by layer name. nil values mean no change.
    var codeChanges: [String: String]?
    /// Proposed parameter value changes. nil values mean no change.
    var paramChanges: [String: [Float]]?
    var outcome: ProposalOutcome

    init(id: UUID = UUID(), description: String, rationale: String,
         codeChanges: [String: String]? = nil, paramChanges: [String: [Float]]? = nil,
         outcome: ProposalOutcome = .pending) {
        self.id = id
        self.date = Date()
        self.description = description
        self.rationale = rationale
        self.codeChanges = codeChanges
        self.paramChanges = paramChanges
        self.outcome = outcome
    }
}

enum ProposalOutcome: String, Codable {
    case pending
    case accepted
    case rejected
    case partiallyAdopted = "partial"
}

// MARK: - Design Document

/// Collaborative design plan — records analysis, design thinking, and decisions
/// made during the conversation. Both AI and human can edit. Pure markdown.
struct DesignDocument: Codable {
    var markdown: String
    var lastModified: Date

    init(markdown: String = "", lastModified: Date = Date()) {
        self.markdown = markdown
        self.lastModified = lastModified
    }

    var isEmpty: Bool { markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Lab Action Types

/// Actions the Lab AI agent can perform beyond Canvas-level shader operations.
/// These drive document updates, parameter suggestions, and iteration tracking
/// so the agent actively writes into the project state instead of just chatting.
nonisolated enum LabActionType: String, Codable, Sendable {
    case updateDesignDoc
    case updateProjectDoc
    case updateDocumentSection // legacy — treated as updateDesignDoc
    case addParameter
    case addConstraint
    case suggestParamChange
    case logIteration
}

/// Which section of the ProjectDocument to update (legacy support).
nonisolated enum DocumentSection: String, Codable, Sendable {
    case title
    case visualGoal
    case referenceAnalysis
    case technicalApproach
}

/// A single Lab-level action parsed from the agent's structured JSON response.
nonisolated struct LabAction: Codable, Sendable {
    let type: LabActionType

    // updateDesignDoc / updateProjectDoc / updateDocumentSection
    var section: DocumentSection?
    var content: String?

    // addParameter
    var paramName: String?
    var paramType: String?
    var paramPurpose: String?
    var paramDefault: [Float]?
    var paramMin: Float?
    var paramMax: Float?

    // addConstraint
    var constraint: String?

    // suggestParamChange
    var paramChanges: [String: [Float]]?
    var changeRationale: String?

    // logIteration
    var iterationDescription: String?
    var iterationDecision: String?
    var iterationOutcome: String?

    var displaySummary: String {
        switch type {
        case .updateDesignDoc:
            return "Update Design Doc"
        case .updateProjectDoc:
            return "Update Project Doc"
        case .updateDocumentSection:
            return "Update \(section?.rawValue ?? "document")"
        case .addParameter:
            return "Add param: \(paramName ?? "?")"
        case .addConstraint:
            return "Add constraint"
        case .suggestParamChange:
            let keys = paramChanges?.keys.joined(separator: ", ") ?? "?"
            return "Suggest: \(keys)"
        case .logIteration:
            return "Log iteration"
        }
    }
}

/// Structured response from the Lab AI agent. Contains the natural-language
/// explanation shown in chat, plus optional Lab-level and Canvas-level actions
/// to execute against the project state.
nonisolated struct LabAgentResponse: Codable, Sendable {
    let explanation: String
    let labActions: [LabAction]
    let agentActions: [AgentAction]?

    static func plainText(_ text: String) -> LabAgentResponse {
        LabAgentResponse(explanation: text, labActions: [], agentActions: nil)
    }

    init(explanation: String, labActions: [LabAction] = [], agentActions: [AgentAction]? = nil) {
        self.explanation = explanation
        self.labActions = labActions
        self.agentActions = agentActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        labActions = try container.decodeIfPresent([LabAction].self, forKey: .labActions) ?? []
        agentActions = try container.decodeIfPresent([AgentAction].self, forKey: .agentActions)
    }
}

// MARK: - Lab Session

/// Persistent state for a Lab mode session, tracking the collaborative workflow
/// progress, parameter evolution, and adversarial generation history.
struct LabSession: Codable {
    var currentPhase: LabPhase
    var parameterSnapshots: [ParameterSnapshot]
    var adversarialProposals: [AdversarialProposal]
    /// Tracks which phases have been visited (allows non-linear navigation).
    var visitedPhases: Set<String>
    var createdDate: Date
    var lastModified: Date

    init(currentPhase: LabPhase = .referenceInput,
         parameterSnapshots: [ParameterSnapshot] = [],
         adversarialProposals: [AdversarialProposal] = [],
         visitedPhases: Set<String> = [LabPhase.referenceInput.rawValue]) {
        self.currentPhase = currentPhase
        self.parameterSnapshots = parameterSnapshots
        self.adversarialProposals = adversarialProposals
        self.visitedPhases = visitedPhases
        self.createdDate = Date()
        self.lastModified = Date()
    }

    mutating func advanceTo(_ phase: LabPhase) {
        currentPhase = phase
        visitedPhases.insert(phase.rawValue)
        lastModified = Date()
    }

    func hasVisited(_ phase: LabPhase) -> Bool {
        visitedPhases.contains(phase.rawValue)
    }
}
