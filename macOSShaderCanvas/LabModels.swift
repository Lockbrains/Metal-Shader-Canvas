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

/// The co-authored project specification document.
/// AI and human collaboratively fill in sections during the Document phase.
struct ProjectDocument: Codable {
    var title: String
    var visualGoal: String
    var referenceAnalysis: String
    var technicalApproach: String
    var parameterDesign: [ParamSpec]
    var iterationLog: [IterationEntry]
    var constraints: [String]

    init(title: String = "Untitled Shader Project",
         visualGoal: String = "",
         referenceAnalysis: String = "",
         technicalApproach: String = "",
         parameterDesign: [ParamSpec] = [],
         iterationLog: [IterationEntry] = [],
         constraints: [String] = []) {
        self.title = title
        self.visualGoal = visualGoal
        self.referenceAnalysis = referenceAnalysis
        self.technicalApproach = technicalApproach
        self.parameterDesign = parameterDesign
        self.iterationLog = iterationLog
        self.constraints = constraints
    }

    var isEmpty: Bool {
        visualGoal.isEmpty && referenceAnalysis.isEmpty &&
        technicalApproach.isEmpty && parameterDesign.isEmpty
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
