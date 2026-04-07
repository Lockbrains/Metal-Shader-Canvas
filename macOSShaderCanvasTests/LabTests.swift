import Testing
import Foundation
@testable import macOSShaderCanvas

// MARK: - LabActionType Tests

struct LabActionTypeTests {

    @Test func allCasesRoundTrip() throws {
        let allCases: [LabActionType] = [
            .updateDesignDoc, .updateProjectDoc, .updateDocumentSection,
            .addParameter, .addConstraint, .suggestParamChange, .logIteration
        ]
        for actionType in allCases {
            let data = try JSONEncoder().encode(actionType)
            let decoded = try JSONDecoder().decode(LabActionType.self, from: data)
            #expect(decoded == actionType)
        }
    }

    @Test func rawValueMapping() {
        #expect(LabActionType.updateDesignDoc.rawValue == "updateDesignDoc")
        #expect(LabActionType.updateProjectDoc.rawValue == "updateProjectDoc")
        #expect(LabActionType.updateDocumentSection.rawValue == "updateDocumentSection")
        #expect(LabActionType.addParameter.rawValue == "addParameter")
        #expect(LabActionType.addConstraint.rawValue == "addConstraint")
        #expect(LabActionType.suggestParamChange.rawValue == "suggestParamChange")
        #expect(LabActionType.logIteration.rawValue == "logIteration")
    }
}

// MARK: - DocumentSection Tests (legacy support)

struct DocumentSectionTests {

    @Test func allCasesRoundTrip() throws {
        let allCases: [DocumentSection] = [.title, .visualGoal, .referenceAnalysis, .technicalApproach]
        for section in allCases {
            let data = try JSONEncoder().encode(section)
            let decoded = try JSONDecoder().decode(DocumentSection.self, from: data)
            #expect(decoded == section)
        }
    }

    @Test func rawValueMapping() {
        #expect(DocumentSection.title.rawValue == "title")
        #expect(DocumentSection.visualGoal.rawValue == "visualGoal")
        #expect(DocumentSection.referenceAnalysis.rawValue == "referenceAnalysis")
        #expect(DocumentSection.technicalApproach.rawValue == "technicalApproach")
    }
}

// MARK: - DesignDocument Tests

struct DesignDocumentTests {

    @Test func defaultInit() {
        let doc = DesignDocument()
        #expect(doc.markdown == "")
        #expect(doc.isEmpty)
    }

    @Test func initWithContent() {
        let doc = DesignDocument(markdown: "# My Design\n\nSome plan here.")
        #expect(!doc.isEmpty)
        #expect(doc.markdown.contains("My Design"))
    }

    @Test func isEmptyIgnoresWhitespace() {
        let doc = DesignDocument(markdown: "   \n\n  ")
        #expect(doc.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let original = DesignDocument(markdown: "# Design\n\n## Goals\n- Look cool")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DesignDocument.self, from: data)
        #expect(decoded.markdown == original.markdown)
    }
}

// MARK: - LabAction Tests

struct LabActionTests {

    @Test func decodeUpdateDesignDoc() throws {
        let json = """
        {
            "type": "updateDesignDoc",
            "content": "## Analysis\\n\\nThe reference uses SDF blending."
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .updateDesignDoc)
        #expect(action.content?.contains("SDF blending") == true)
    }

    @Test func decodeUpdateProjectDoc() throws {
        let json = """
        {
            "type": "updateProjectDoc",
            "content": "# Final Documentation\\n\\nThis shader implements glass refraction."
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .updateProjectDoc)
        #expect(action.content?.contains("Final Documentation") == true)
    }

    @Test func decodeLegacyUpdateDocumentSection() throws {
        let json = """
        {
            "type": "updateDocumentSection",
            "section": "visualGoal",
            "content": "Create a fluid glass refraction effect"
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .updateDocumentSection)
        #expect(action.section == .visualGoal)
        #expect(action.content == "Create a fluid glass refraction effect")
    }

    @Test func decodeAddParameter() throws {
        let json = """
        {
            "type": "addParameter",
            "paramName": "_refraction",
            "paramType": "float",
            "paramPurpose": "Controls refraction strength",
            "paramDefault": [0.5],
            "paramMin": 0.0,
            "paramMax": 2.0
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .addParameter)
        #expect(action.paramName == "_refraction")
        #expect(action.paramType == "float")
        #expect(action.paramPurpose == "Controls refraction strength")
        #expect(action.paramDefault == [0.5])
        #expect(action.paramMin == 0.0)
        #expect(action.paramMax == 2.0)
    }

    @Test func decodeAddConstraint() throws {
        let json = """
        {
            "type": "addConstraint",
            "constraint": "Must run at 60fps on M1"
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .addConstraint)
        #expect(action.constraint == "Must run at 60fps on M1")
    }

    @Test func decodeSuggestParamChange() throws {
        let json = """
        {
            "type": "suggestParamChange",
            "paramChanges": { "_speed": [1.5], "_intensity": [0.8, 0.3] },
            "changeRationale": "Smoother animation with lower intensity"
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .suggestParamChange)
        #expect(action.paramChanges?["_speed"] == [1.5])
        #expect(action.paramChanges?["_intensity"] == [0.8, 0.3])
        #expect(action.changeRationale == "Smoother animation with lower intensity")
    }

    @Test func decodeLogIteration() throws {
        let json = """
        {
            "type": "logIteration",
            "iterationDescription": "Adjusted SDF blend radius",
            "iterationDecision": "Increased smoothMin k to 4.0",
            "iterationOutcome": "Better glass edge softness"
        }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .logIteration)
        #expect(action.iterationDescription == "Adjusted SDF blend radius")
        #expect(action.iterationDecision == "Increased smoothMin k to 4.0")
        #expect(action.iterationOutcome == "Better glass edge softness")
    }

    @Test func displaySummaryUpdateDesignDoc() throws {
        let json = """
        { "type": "updateDesignDoc", "content": "## Plan" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Update Design Doc")
    }

    @Test func displaySummaryUpdateProjectDoc() throws {
        let json = """
        { "type": "updateProjectDoc", "content": "## Docs" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Update Project Doc")
    }

    @Test func displaySummaryLegacyUpdateSection() throws {
        let json = """
        { "type": "updateDocumentSection", "section": "title", "content": "Glass Shader" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Update title")
    }

    @Test func displaySummaryAddParam() throws {
        let json = """
        { "type": "addParameter", "paramName": "_glow" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Add param: _glow")
    }

    @Test func displaySummaryAddConstraint() throws {
        let json = """
        { "type": "addConstraint", "constraint": "test" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Add constraint")
    }

    @Test func displaySummarySuggestChange() throws {
        let json = """
        { "type": "suggestParamChange", "paramChanges": { "_a": [1], "_b": [2] } }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary.hasPrefix("Suggest: "))
        #expect(action.displaySummary.contains("_a") || action.displaySummary.contains("_b"))
    }

    @Test func displaySummaryLogIteration() throws {
        let json = """
        { "type": "logIteration" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.displaySummary == "Log iteration")
    }

    @Test func roundTripEncoding() throws {
        let json = """
        {
            "type": "addParameter",
            "paramName": "_test",
            "paramType": "color",
            "paramPurpose": "Tint color",
            "paramDefault": [1.0, 0.5, 0.2],
            "paramMin": 0.0,
            "paramMax": 1.0
        }
        """
        let original = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LabAction.self, from: encoded)
        #expect(decoded.type == original.type)
        #expect(decoded.paramName == original.paramName)
        #expect(decoded.paramType == original.paramType)
        #expect(decoded.paramDefault == original.paramDefault)
    }

    @Test func missingOptionalFieldsDecodeAsNil() throws {
        let json = """
        { "type": "updateDesignDoc" }
        """
        let action = try JSONDecoder().decode(LabAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .updateDesignDoc)
        #expect(action.content == nil)
        #expect(action.paramName == nil)
        #expect(action.paramChanges == nil)
        #expect(action.constraint == nil)
        #expect(action.iterationDescription == nil)
    }
}

// MARK: - LabAgentResponse Tests

struct LabAgentResponseTests {

    @Test func responseWithDesignDocUpdate() throws {
        let json = """
        {
            "explanation": "I've analyzed the reference and started the design doc.",
            "labActions": [
                {
                    "type": "updateDesignDoc",
                    "content": "## Reference Analysis\\n\\nThe reference shows organic glass surfaces."
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.explanation.contains("design doc"))
        #expect(response.labActions.count == 1)
        #expect(response.labActions[0].type == .updateDesignDoc)
    }

    @Test func responseWithProjectDocUpdate() throws {
        let json = """
        {
            "explanation": "Project documentation is ready.",
            "labActions": [
                {
                    "type": "updateProjectDoc",
                    "content": "# Glass Shader Project\\n\\nFinal implementation docs."
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.labActions[0].type == .updateProjectDoc)
    }

    @Test func responseWithBothDocUpdates() throws {
        let json = """
        {
            "explanation": "Updated both documents.",
            "labActions": [
                { "type": "updateDesignDoc", "content": "Design plan update" },
                { "type": "updateProjectDoc", "content": "Project docs update" },
                { "type": "addParameter", "paramName": "_speed", "paramType": "float", "paramDefault": [1.0] }
            ]
        }
        """
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.labActions.count == 3)
        #expect(response.labActions[0].type == .updateDesignDoc)
        #expect(response.labActions[1].type == .updateProjectDoc)
        #expect(response.labActions[2].type == .addParameter)
    }

    @Test func responseWithAgentActions() throws {
        let json = """
        {
            "explanation": "Added a layer.",
            "labActions": [],
            "agentActions": [
                { "type": "addLayer", "category": "fragment", "name": "Test", "code": "return float4(1);" }
            ]
        }
        """
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.labActions.isEmpty)
        #expect(response.agentActions?.count == 1)
        #expect(response.agentActions?[0].type == .addLayer)
    }

    @Test func plainTextFactory() {
        let response = LabAgentResponse.plainText("Hello, let's design a shader!")
        #expect(response.explanation == "Hello, let's design a shader!")
        #expect(response.labActions.isEmpty)
        #expect(response.agentActions == nil)
    }

    @Test func emptyJSONDecodes() throws {
        let json = "{}"
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.explanation == "")
        #expect(response.labActions.isEmpty)
        #expect(response.agentActions == nil)
    }

    @Test func missingFieldsDefaultGracefully() throws {
        let json = """
        { "explanation": "Just text" }
        """
        let response = try JSONDecoder().decode(LabAgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.explanation == "Just text")
        #expect(response.labActions.isEmpty)
        #expect(response.agentActions == nil)
    }

    @Test func roundTripEncoding() throws {
        let original = LabAgentResponse(
            explanation: "Test round trip",
            labActions: [LabAction(type: .addConstraint, constraint: "60fps")],
            agentActions: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LabAgentResponse.self, from: data)
        #expect(decoded.explanation == original.explanation)
        #expect(decoded.labActions.count == 1)
        #expect(decoded.labActions[0].constraint == "60fps")
    }
}

// MARK: - LabAIFlow.extractJSON Tests

struct ExtractJSONTests {

    @Test func cleanJSON() {
        let input = """
        { "explanation": "Hello", "labActions": [] }
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("explanation"))
    }

    @Test func markdownFencedJSON() {
        let input = """
        ```json
        { "explanation": "Fenced", "labActions": [] }
        ```
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("Fenced"))
    }

    @Test func markdownFenceWithoutLanguageTag() {
        let input = """
        ```
        { "explanation": "No lang tag", "labActions": [] }
        ```
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("No lang tag"))
    }

    @Test func jsonWithSurroundingText() {
        let input = """
        Here is my analysis:
        { "explanation": "Extracted", "labActions": [] }
        Hope this helps!
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("Extracted"))
    }

    @Test func nestedBracesInStringValues() {
        let input = """
        {
            "explanation": "Code with braces: if (x > 0) { return y; }",
            "labActions": []
        }
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        let data = result!.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(LabAgentResponse.self, from: data)
        #expect(decoded != nil)
        #expect(decoded?.explanation.contains("if (x > 0)") == true)
    }

    @Test func shaderCodeWithManyBraces() {
        let input = """
        {
            "explanation": "Shader added",
            "labActions": [
                {
                    "type": "updateDesignDoc",
                    "content": "fragment float4 f() { if (x) { for (int i=0; i<10; i++) { y += 1; } } return float4(1); }"
                }
            ]
        }
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        let data = result!.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(LabAgentResponse.self, from: data)
        #expect(decoded != nil)
        #expect(decoded?.labActions.count == 1)
    }

    @Test func noJSON() {
        let input = "This is plain text with no JSON at all"
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result == nil)
    }

    @Test func incompleteBraces() {
        let input = "{ \"explanation\": \"unclosed"
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result == nil)
    }

    @Test func escapedQuotesInString() {
        let input = """
        { "explanation": "He said \\"hello\\" to me", "labActions": [] }
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("hello"))
    }

    @Test func emptyObject() {
        let result = LabAIFlow.extractJSON(from: "{}")
        #expect(result == "{}")
    }

    @Test func multipleJSONObjectsExtractsFirst() {
        let input = """
        { "a": 1 }
        { "b": 2 }
        """
        let result = LabAIFlow.extractJSON(from: input)
        #expect(result != nil)
        #expect(result!.contains("\"a\""))
        #expect(!result!.contains("\"b\""))
    }
}

// MARK: - LabAIFlow.parseLabAgentResponse Tests

struct ParseLabAgentResponseTests {

    @Test func validResponseWithDesignDocAction() {
        let input = """
        {
            "explanation": "Updated the design doc with analysis.",
            "labActions": [
                { "type": "updateDesignDoc", "content": "## Reference Analysis\\nSDF blending detected" }
            ]
        }
        """
        let response = LabAIFlow.parseLabAgentResponse(from: input)
        #expect(response.explanation == "Updated the design doc with analysis.")
        #expect(response.labActions.count == 1)
        #expect(response.labActions[0].type == .updateDesignDoc)
    }

    @Test func jsonWithMarkdownFence() {
        let input = """
        ```json
        {
            "explanation": "Fenced response",
            "labActions": [
                { "type": "addConstraint", "constraint": "Must be performant" }
            ]
        }
        ```
        """
        let response = LabAIFlow.parseLabAgentResponse(from: input)
        #expect(response.explanation == "Fenced response")
        #expect(response.labActions.count == 1)
    }

    @Test func plainTextFallback() {
        let input = "This is just a regular chat message with no JSON."
        let response = LabAIFlow.parseLabAgentResponse(from: input)
        #expect(response.explanation == input)
        #expect(response.labActions.isEmpty)
    }

    @Test func invalidJSONFallsBackToPlainText() {
        let input = "{ broken json: ??? }"
        let response = LabAIFlow.parseLabAgentResponse(from: input)
        #expect(response.explanation == input)
        #expect(response.labActions.isEmpty)
    }

    @Test func emptyJSONObject() {
        let response = LabAIFlow.parseLabAgentResponse(from: "{}")
        #expect(response.explanation == "")
        #expect(response.labActions.isEmpty)
    }

    @Test func mixedDesignAndProjectDocActions() {
        let input = """
        {
            "explanation": "Comprehensive update to both documents.",
            "labActions": [
                { "type": "updateDesignDoc", "content": "## Design Plan\\nUse SDF approach" },
                { "type": "updateProjectDoc", "content": "# Project Docs\\nFinal implementation" },
                { "type": "addParameter", "paramName": "_refractionStrength", "paramType": "float", "paramPurpose": "Refraction", "paramDefault": [0.5], "paramMin": 0.0, "paramMax": 3.0 },
                { "type": "addConstraint", "constraint": "60fps on M1" }
            ]
        }
        """
        let response = LabAIFlow.parseLabAgentResponse(from: input)
        #expect(response.labActions.count == 4)
        #expect(response.labActions[0].type == .updateDesignDoc)
        #expect(response.labActions[1].type == .updateProjectDoc)
        #expect(response.labActions[2].type == .addParameter)
        #expect(response.labActions[3].type == .addConstraint)
    }
}

// MARK: - LabAIFlow.extractExplanationFromPartialJSON Tests

struct ExtractExplanationTests {

    @Test func completedExplanation() {
        let partial = """
        { "explanation": "Here is a complete explanation", "labActions": [
        """
        let result = LabAIFlow.extractExplanationFromPartialJSON(partial)
        #expect(result == "Here is a complete explanation")
    }

    @Test func incompleteExplanation() {
        let partial = """
        { "explanation": "This is still being stream
        """
        let result = LabAIFlow.extractExplanationFromPartialJSON(partial)
        #expect(result == "This is still being stream")
    }

    @Test func escapedNewlinesInExplanation() {
        let partial = """
        { "explanation": "Line one\\nLine two\\nLine three" }
        """
        let result = LabAIFlow.extractExplanationFromPartialJSON(partial)
        #expect(result.contains("\n"))
        #expect(result == "Line one\nLine two\nLine three")
    }

    @Test func escapedTabsAndQuotes() {
        let partial = """
        { "explanation": "Tab:\\there, Quote:\\"hi\\"" }
        """
        let result = LabAIFlow.extractExplanationFromPartialJSON(partial)
        #expect(result.contains("\t"))
        #expect(result.contains("\"hi\""))
    }

    @Test func nonJSONInput() {
        let input = "This is not JSON at all"
        let result = LabAIFlow.extractExplanationFromPartialJSON(input)
        #expect(result == input)
    }

    @Test func jsonWithNoExplanationField() {
        let input = "{ \"labActions\": [] }"
        let result = LabAIFlow.extractExplanationFromPartialJSON(input)
        #expect(result == "")
    }

    @Test func emptyExplanation() {
        let input = "{ \"explanation\": \"\" }"
        let result = LabAIFlow.extractExplanationFromPartialJSON(input)
        #expect(result == "")
    }

    @Test func explanationWithUnicode() {
        let input = "{ \"explanation\": \"这是中文测试，包含 emoji 🎨\" }"
        let result = LabAIFlow.extractExplanationFromPartialJSON(input)
        #expect(result.contains("中文"))
        #expect(result.contains("🎨"))
    }

    @Test func justOpenBrace() {
        let result = LabAIFlow.extractExplanationFromPartialJSON("{")
        #expect(result == "")
    }

    @Test func explanationKeyButNoColon() {
        let result = LabAIFlow.extractExplanationFromPartialJSON("{ \"explanation\"")
        #expect(result == "")
    }

    @Test func explanationKeyColonButNoQuote() {
        let result = LabAIFlow.extractExplanationFromPartialJSON("{ \"explanation\": 42 }")
        #expect(result == "")
    }
}

// MARK: - ProjectDocument Tests (markdown-based with legacy support)

struct ProjectDocumentTests {

    @Test func defaultInit() {
        let doc = ProjectDocument()
        #expect(doc.markdown == "")
        #expect(doc.title == "Untitled Shader Project")
        #expect(doc.isEmpty)
    }

    @Test func markdownBasedIsEmpty() {
        let doc = ProjectDocument(markdown: "# Project")
        #expect(!doc.isEmpty)
    }

    @Test func legacyFieldsStillWork() {
        var doc = ProjectDocument()
        doc.visualGoal = "Create glass effect"
        doc.referenceAnalysis = "SDF based"
        doc.technicalApproach = "Smooth min"
        #expect(!doc.isEmpty)
        #expect(doc.visualGoal == "Create glass effect")
    }

    @Test func migrateEmptyDocDoesNothing() {
        var doc = ProjectDocument()
        doc.migrateToMarkdown()
        #expect(doc.markdown == "")
    }

    @Test func migrateSkipsIfMarkdownExists() {
        var doc = ProjectDocument(markdown: "# Existing")
        doc.visualGoal = "Old goal"
        doc.migrateToMarkdown()
        #expect(doc.markdown == "# Existing")
    }

    @Test func migrateFromLegacyFields() {
        var doc = ProjectDocument(
            title: "Glass Shader",
            visualGoal: "Organic glass surfaces",
            referenceAnalysis: "SDF blending detected",
            technicalApproach: "Polynomial smooth min"
        )
        doc.parameterDesign.append(ParamSpec(
            name: "_refraction", purpose: "Strength",
            type: .float, suggestedDefault: [0.5],
            suggestedMin: 0.0, suggestedMax: 2.0
        ))
        doc.constraints.append("60fps on M1")
        doc.iterationLog.append(IterationEntry(
            description: "v1", decision: "Approve", outcome: "accepted"
        ))

        doc.migrateToMarkdown()

        #expect(doc.markdown.contains("# Glass Shader"))
        #expect(doc.markdown.contains("## Visual Goal"))
        #expect(doc.markdown.contains("Organic glass surfaces"))
        #expect(doc.markdown.contains("## Reference Analysis"))
        #expect(doc.markdown.contains("## Technical Approach"))
        #expect(doc.markdown.contains("## Parameters"))
        #expect(doc.markdown.contains("_refraction"))
        #expect(doc.markdown.contains("## Constraints"))
        #expect(doc.markdown.contains("60fps on M1"))
        #expect(doc.markdown.contains("## Iteration Log"))
        #expect(doc.markdown.contains("Approve"))
    }

    @Test func codableRoundTrip() throws {
        var doc = ProjectDocument(
            markdown: "# Test",
            title: "Test Project",
            visualGoal: "Create glow",
            referenceAnalysis: "Uses bloom",
            technicalApproach: "Gaussian blur"
        )
        doc.parameterDesign.append(ParamSpec(name: "_intensity", purpose: "Glow strength"))
        doc.constraints.append("Metal 2.0 only")
        doc.iterationLog.append(IterationEntry(description: "v1", decision: "Approve", outcome: "ok"))

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)
        #expect(decoded.markdown == "# Test")
        #expect(decoded.title == "Test Project")
        #expect(decoded.visualGoal == "Create glow")
        #expect(decoded.parameterDesign.count == 1)
        #expect(decoded.constraints.count == 1)
        #expect(decoded.iterationLog.count == 1)
    }

    @Test func addParameterDesign() {
        var doc = ProjectDocument()
        let param = ParamSpec(name: "_refraction", purpose: "Refraction strength",
                              type: .float, suggestedDefault: [0.5],
                              suggestedMin: 0.0, suggestedMax: 2.0)
        doc.parameterDesign.append(param)
        #expect(doc.parameterDesign.count == 1)
        #expect(doc.parameterDesign[0].name == "_refraction")
    }

    @Test func addConstraint() {
        var doc = ProjectDocument()
        doc.constraints.append("Must run at 60fps on M1")
        doc.constraints.append("Single-pass only")
        #expect(doc.constraints.count == 2)
    }

    @Test func logIteration() {
        var doc = ProjectDocument()
        let entry = IterationEntry(description: "Changed blend mode",
                                   decision: "Use additive blending",
                                   outcome: "improved")
        doc.iterationLog.append(entry)
        #expect(doc.iterationLog.count == 1)
    }
}

// MARK: - Dual-Document Action Execution Simulation

struct DualDocActionExecutionTests {

    @Test func updateDesignDocAppendsContent() {
        var designDoc = DesignDocument()
        var projectDoc = ProjectDocument()

        let action1 = LabAction(type: .updateDesignDoc, content: "## Analysis\nSDF-based approach")
        let action2 = LabAction(type: .updateDesignDoc, content: "## Parameters\n_refraction: float")

        applyAction(action1, designDoc: &designDoc, projectDoc: &projectDoc)
        applyAction(action2, designDoc: &designDoc, projectDoc: &projectDoc)

        #expect(designDoc.markdown.contains("## Analysis"))
        #expect(designDoc.markdown.contains("## Parameters"))
        #expect(designDoc.markdown.contains("\n\n"))
    }

    @Test func updateProjectDocAppendsContent() {
        var projectDoc = ProjectDocument()
        var designDoc = DesignDocument()

        let action = LabAction(type: .updateProjectDoc, content: "# Final Docs\nImplementation details.")
        applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc)

        #expect(projectDoc.markdown.contains("# Final Docs"))
    }

    @Test func legacyUpdateDocumentSectionGoesToDesignDoc() {
        var designDoc = DesignDocument()
        var projectDoc = ProjectDocument()

        let action = LabAction(type: .updateDocumentSection, section: .visualGoal, content: "Glass effect")
        applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc)

        #expect(designDoc.markdown.contains("Glass effect"))
        #expect(projectDoc.markdown.isEmpty)
    }

    @Test func mixedActionsApplyCorrectly() {
        var designDoc = DesignDocument()
        var projectDoc = ProjectDocument()
        var paramValues: [String: [Float]] = [:]

        let actions: [LabAction] = [
            LabAction(type: .updateDesignDoc, content: "## Plan\nUse SDF"),
            LabAction(type: .updateProjectDoc, content: "# Docs\nFinal spec"),
            LabAction(type: .addParameter, paramName: "_speed", paramType: "float",
                      paramPurpose: "Animation", paramDefault: [1.0], paramMin: 0.0, paramMax: 5.0),
            LabAction(type: .addConstraint, constraint: "60fps on M1"),
            LabAction(type: .suggestParamChange, paramChanges: ["_speed": [2.5]], changeRationale: "Faster"),
        ]

        for action in actions {
            applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc, paramValues: &paramValues)
        }

        #expect(designDoc.markdown.contains("SDF"))
        #expect(projectDoc.markdown.contains("Final spec"))
        #expect(projectDoc.parameterDesign.count == 1)
        #expect(projectDoc.constraints.contains("60fps on M1"))
        #expect(paramValues["_speed"] == [2.5])
    }

    private func applyAction(
        _ action: LabAction,
        designDoc: inout DesignDocument,
        projectDoc: inout ProjectDocument,
        paramValues: inout [String: [Float]]
    ) {
        switch action.type {
        case .updateDesignDoc, .updateDocumentSection:
            guard let content = action.content, !content.isEmpty else { return }
            if designDoc.markdown.isEmpty {
                designDoc.markdown = content
            } else {
                designDoc.markdown += "\n\n" + content
            }
            designDoc.lastModified = Date()

        case .updateProjectDoc:
            guard let content = action.content, !content.isEmpty else { return }
            if projectDoc.markdown.isEmpty {
                projectDoc.markdown = content
            } else {
                projectDoc.markdown += "\n\n" + content
            }
            projectDoc.lastModified = Date()

        case .addParameter:
            guard let name = action.paramName, !name.isEmpty else { return }
            let paramType = ParamType(rawValue: action.paramType ?? "float") ?? .float
            let defaults = action.paramDefault ?? [1.0]
            let spec = ParamSpec(
                name: name, purpose: action.paramPurpose ?? "",
                type: paramType, suggestedDefault: defaults,
                suggestedMin: action.paramMin, suggestedMax: action.paramMax
            )
            projectDoc.parameterDesign.append(spec)
            if paramValues[name] == nil {
                paramValues[name] = defaults
            }

        case .addConstraint:
            if let c = action.constraint, !c.isEmpty {
                projectDoc.constraints.append(c)
            }

        case .suggestParamChange:
            if let changes = action.paramChanges {
                for (key, val) in changes { paramValues[key] = val }
            }

        case .logIteration:
            let entry = IterationEntry(
                description: action.iterationDescription ?? "",
                decision: action.iterationDecision ?? "",
                outcome: action.iterationOutcome ?? "pending"
            )
            projectDoc.iterationLog.append(entry)
        }
    }

    @Test func addParameterInitializesParamValues() {
        var designDoc = DesignDocument()
        var projectDoc = ProjectDocument()
        var paramValues: [String: [Float]] = [:]

        let action = LabAction(type: .addParameter, paramName: "_speed",
                               paramType: "float", paramPurpose: "Animation speed",
                               paramDefault: [2.5], paramMin: 0.0, paramMax: 10.0)

        applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc, paramValues: &paramValues)

        #expect(projectDoc.parameterDesign.count == 1)
        #expect(projectDoc.parameterDesign[0].name == "_speed")
        #expect(paramValues["_speed"] == [2.5])
    }

    @Test func addParameterDoesNotOverwriteExistingValue() {
        var designDoc = DesignDocument()
        var projectDoc = ProjectDocument()
        var paramValues: [String: [Float]] = ["_speed": [5.0]]

        let action = LabAction(type: .addParameter, paramName: "_speed",
                               paramType: "float", paramDefault: [2.5])

        applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc, paramValues: &paramValues)

        #expect(paramValues["_speed"] == [5.0])
    }

    private func applyAction(
        _ action: LabAction,
        designDoc: inout DesignDocument,
        projectDoc: inout ProjectDocument
    ) {
        var pv: [String: [Float]] = [:]
        applyAction(action, designDoc: &designDoc, projectDoc: &projectDoc, paramValues: &pv)
    }
}

// MARK: - Unified Prompt Tests

struct UnifiedPromptTests {

    @Test func promptContainsAllActionTypes() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "test context")
        #expect(prompt.contains("updateDesignDoc"))
        #expect(prompt.contains("updateProjectDoc"))
        #expect(prompt.contains("addParameter"))
        #expect(prompt.contains("addConstraint"))
        #expect(prompt.contains("suggestParamChange"))
        #expect(prompt.contains("logIteration"))
    }

    @Test func promptIncludesContext() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "Mode: 3D Lab\nShader code here")
        #expect(prompt.contains("Mode: 3D Lab"))
        #expect(prompt.contains("Shader code here"))
    }

    @Test func promptIncludesPhaseHint() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", phaseHint: .tuning)
        #expect(prompt.contains("Parameter Tuning"))
        #expect(prompt.contains("WORKFLOW HINT"))
    }

    @Test func promptWithoutPhaseHintOmitsHintSection() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", phaseHint: nil)
        #expect(!prompt.contains("WORKFLOW HINT"))
    }

    @Test func promptIncludesDesignDocGuidelines() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx")
        #expect(prompt.contains("Design Doc"))
        #expect(prompt.contains("Project Doc"))
        #expect(prompt.contains("collaborative plan"))
        #expect(prompt.contains("final documentation"))
    }

    @Test func promptDoesNotMentionImplementationMode() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx")
        #expect(!prompt.contains("switch to Implementation"))
        #expect(!prompt.contains("Implementation mode"))
        #expect(!prompt.contains("Implementation Mode"))
    }

    @Test func promptIncludesAgentActions() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx")
        #expect(prompt.contains("agentActions"))
        #expect(prompt.contains("addLayer"))
        #expect(prompt.contains("modifyLayer"))
        #expect(prompt.contains("enableDataFlow"))
    }

    @Test func promptJsonFormatIncludesAgentActionsField() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx")
        #expect(prompt.contains("\"agentActions\""))
    }

    @Test func prompt3DIncludesShaderCodeRules() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .threeDimensionalLab)
        #expect(prompt.contains("METAL SHADER CODE RULES (3D MODE)"))
        #expect(prompt.contains("vertex VertexOut vertex_main"))
        #expect(prompt.contains("fragment float4 fragment_main"))
        #expect(prompt.contains("// @param"))
        #expect(prompt.contains("Uniforms"))
    }

    @Test func prompt2DIncludesShaderCodeRules() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .twoDimensionalLab)
        #expect(prompt.contains("METAL SHADER CODE RULES (2D MODE)"))
        #expect(prompt.contains("distort_main"))
        #expect(prompt.contains("bgTexture"))
        #expect(prompt.contains("addObject2D"))
        #expect(prompt.contains("setObjectShader2D"))
    }

    @Test func prompt2DIncludesCustomSDFGuidance() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .twoDimensionalLab)
        #expect(prompt.contains("CUSTOM SDF SHAPES"))
        #expect(prompt.contains("heart"))
        #expect(prompt.contains("star"))
    }

    @Test func prompt2DExplainsRenderingPipeline() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .twoDimensionalLab)
        #expect(prompt.contains("RENDERING PIPELINE"))
        #expect(prompt.contains("Fullscreen layers render AFTER all objects"))
        #expect(prompt.contains("inTexture"))
        #expect(prompt.contains("targetObjectName"))
    }

    @Test func prompt2DWarnsAboutFullscreenCovering() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .twoDimensionalLab)
        #expect(prompt.contains("HIDE all objects"))
        #expect(prompt.contains("NEVER output opaque procedural content"))
    }

    @Test func prompt3DIncludesCustomSDFGuidance() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", canvasMode: .threeDimensionalLab)
        #expect(prompt.contains("CUSTOM SDF SHAPES"))
    }

    @Test func promptIncludesDataFlowDescription() {
        let prompt = LabAIFlow.buildUnifiedPrompt(context: "ctx", dataFlowDescription: "time=ON mouse=OFF")
        #expect(prompt.contains("DATA FLOW CONFIGURATION"))
        #expect(prompt.contains("time=ON mouse=OFF"))
    }

    @Test func contextBuilderIncludesDesignDoc() {
        let designDoc = DesignDocument(markdown: "# My Design Plan\n\n## Goals\n- Look amazing")
        let ctx = LabAIFlow.buildLabContext(
            references: [], projectDocument: ProjectDocument(),
            designDoc: designDoc,
            activeShaders: [], canvasMode: .threeDimensionalLab,
            dataFlowConfig: DataFlowConfig(), dataFlow2DConfig: DataFlow2DConfig(),
            objects2D: [], sharedVertexCode2D: "", sharedFragmentCode2D: "",
            paramValues: [:], meshType: .sphere
        )
        #expect(ctx.contains("DESIGN DOCUMENT"))
        #expect(ctx.contains("My Design Plan"))
    }

    @Test func contextBuilderIncludesProjectDoc() {
        let projectDoc = ProjectDocument(markdown: "# Final Docs\n\nImplementation complete.")
        let ctx = LabAIFlow.buildLabContext(
            references: [], projectDocument: projectDoc,
            designDoc: DesignDocument(),
            activeShaders: [], canvasMode: .threeDimensionalLab,
            dataFlowConfig: DataFlowConfig(), dataFlow2DConfig: DataFlow2DConfig(),
            objects2D: [], sharedVertexCode2D: "", sharedFragmentCode2D: "",
            paramValues: [:], meshType: .sphere
        )
        #expect(ctx.contains("PROJECT DOCUMENT"))
        #expect(ctx.contains("Final Docs"))
    }

    @Test func contextBuilderAlwaysIncludesShaderCode() {
        let shader = ActiveShader(category: .fragment, name: "Glass", code: "float4 glass_code;")
        let ctx = LabAIFlow.buildLabContext(
            references: [], projectDocument: ProjectDocument(),
            designDoc: DesignDocument(),
            activeShaders: [shader], canvasMode: .threeDimensionalLab,
            dataFlowConfig: DataFlowConfig(), dataFlow2DConfig: DataFlow2DConfig(),
            objects2D: [], sharedVertexCode2D: "", sharedFragmentCode2D: "",
            paramValues: [:], meshType: .sphere
        )
        #expect(ctx.contains("glass_code"))
    }

    @Test func contextBuilderAlwaysIncludesParams() {
        let ctx = LabAIFlow.buildLabContext(
            references: [], projectDocument: ProjectDocument(),
            designDoc: DesignDocument(),
            activeShaders: [], canvasMode: .threeDimensionalLab,
            dataFlowConfig: DataFlowConfig(), dataFlow2DConfig: DataFlow2DConfig(),
            objects2D: [], sharedVertexCode2D: "", sharedFragmentCode2D: "",
            paramValues: ["_speed": [2.5]], meshType: .sphere
        )
        #expect(ctx.contains("_speed"))
        #expect(ctx.contains("2.500"))
    }

    @Test func contextBuilderIncludes2DObjects() {
        let obj = Object2D(name: "Glass Card", shapeType: .roundedRectangle,
                           posX: 0.0, posY: 0.0, scaleW: 0.5, scaleH: 0.3)
        let ctx = LabAIFlow.buildLabContext(
            references: [], projectDocument: ProjectDocument(),
            designDoc: DesignDocument(),
            activeShaders: [], canvasMode: .twoDimensionalLab,
            dataFlowConfig: DataFlowConfig(), dataFlow2DConfig: DataFlow2DConfig(),
            objects2D: [obj], sharedVertexCode2D: "", sharedFragmentCode2D: "",
            paramValues: [:], meshType: .sphere
        )
        #expect(ctx.contains("2D OBJECTS"))
        #expect(ctx.contains("Glass Card"))
        #expect(ctx.contains("Rounded Rect"))
    }
}

// MARK: - AdversarialProposal Tests

struct AdversarialProposalTests {

    @Test func basicInit() {
        let proposal = AdversarialProposal(description: "Use additive blending",
                                            rationale: "Brighter highlights")
        #expect(proposal.description == "Use additive blending")
        #expect(proposal.rationale == "Brighter highlights")
        #expect(proposal.codeChanges == nil)
        #expect(proposal.paramChanges == nil)
        #expect(proposal.outcome == .pending)
    }

    @Test func initWithCodeAndParamChanges() {
        let proposal = AdversarialProposal(
            description: "Modified fragment shader",
            rationale: "Better color accuracy",
            codeChanges: ["Lambert": "fragment float4 f() { return float4(1); }"],
            paramChanges: ["_intensity": [0.8]]
        )
        #expect(proposal.codeChanges?["Lambert"] != nil)
        #expect(proposal.paramChanges?["_intensity"] == [0.8])
    }

    @Test func codableRoundTrip() throws {
        let original = AdversarialProposal(
            description: "Alt approach", rationale: "Faster execution",
            codeChanges: ["Layer1": "code here"],
            paramChanges: ["_a": [1.0, 2.0]]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdversarialProposal.self, from: data)
        #expect(decoded.description == original.description)
        #expect(decoded.rationale == original.rationale)
        #expect(decoded.codeChanges?["Layer1"] == "code here")
        #expect(decoded.paramChanges?["_a"] == [1.0, 2.0])
        #expect(decoded.outcome == .pending)
    }

    @Test func outcomeValues() throws {
        for outcome in [ProposalOutcome.pending, .accepted, .rejected, .partiallyAdopted] {
            let data = try JSONEncoder().encode(outcome)
            let decoded = try JSONDecoder().decode(ProposalOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }
}

// MARK: - ParameterSnapshot Tests

struct ParameterSnapshotTests {

    @Test func basicInit() {
        let snapshot = ParameterSnapshot(paramValues: ["_speed": [1.5]])
        #expect(snapshot.paramValues["_speed"] == [1.5])
        #expect(snapshot.aiComment == nil)
        #expect(snapshot.renderCapture == nil)
        #expect(snapshot.label == nil)
    }

    @Test func initWithAIComment() {
        let snapshot = ParameterSnapshot(
            paramValues: ["_intensity": [0.8]],
            aiComment: "Good balance of brightness",
            label: "Sweet spot"
        )
        #expect(snapshot.aiComment == "Good balance of brightness")
        #expect(snapshot.label == "Sweet spot")
    }

    @Test func codableRoundTrip() throws {
        let original = ParameterSnapshot(
            paramValues: ["_a": [1.0], "_b": [0.5, 0.3]],
            aiComment: "Looks great",
            label: "Snapshot 1",
            codeHash: "abc123"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterSnapshot.self, from: data)
        #expect(decoded.paramValues == original.paramValues)
        #expect(decoded.aiComment == "Looks great")
        #expect(decoded.label == "Snapshot 1")
        #expect(decoded.codeHash == "abc123")
    }
}

// MARK: - ChatMessage Lab Extensions Tests

struct ChatMessageLabTests {

    @Test func executedLabActionsDefaultNil() {
        let msg = ChatMessage(role: .assistant, content: "Hello")
        #expect(msg.executedLabActions == nil)
    }

    @Test func executedLabActionsCanBeSet() {
        var msg = ChatMessage(role: .assistant, content: "Updated doc")
        let action = LabAction(type: .updateDesignDoc, content: "## New Plan")
        msg.executedLabActions = [action]
        #expect(msg.executedLabActions?.count == 1)
        #expect(msg.executedLabActions?[0].type == .updateDesignDoc)
    }

    @Test func executedLabActionsAlongsideExecutedActions() {
        var msg = ChatMessage(role: .assistant, content: "Both types")
        msg.executedActions = [AgentAction(type: .addLayer, category: "fragment", name: "Test", code: "code")]
        msg.executedLabActions = [LabAction(type: .addConstraint, constraint: "60fps")]
        #expect(msg.executedActions?.count == 1)
        #expect(msg.executedLabActions?.count == 1)
    }
}

// MARK: - LabAction Memberwise Init Tests

struct LabActionInitTests {

    @Test func updateDesignDocInit() {
        let action = LabAction(type: .updateDesignDoc, content: "## Design Notes")
        #expect(action.type == .updateDesignDoc)
        #expect(action.content == "## Design Notes")
    }

    @Test func updateProjectDocInit() {
        let action = LabAction(type: .updateProjectDoc, content: "# Project Documentation")
        #expect(action.type == .updateProjectDoc)
        #expect(action.content == "# Project Documentation")
    }

    @Test func addParameterInit() {
        let action = LabAction(type: .addParameter, paramName: "_speed", paramType: "float",
                               paramPurpose: "Animation speed", paramDefault: [2.0],
                               paramMin: 0.0, paramMax: 10.0)
        #expect(action.paramName == "_speed")
        #expect(action.paramDefault == [2.0])
        #expect(action.paramMin == 0.0)
        #expect(action.paramMax == 10.0)
    }

    @Test func suggestParamChangeInit() {
        let action = LabAction(type: .suggestParamChange,
                               paramChanges: ["_a": [1.0], "_b": [2.0, 3.0]],
                               changeRationale: "Better balance")
        #expect(action.paramChanges?.count == 2)
        #expect(action.changeRationale == "Better balance")
    }
}

// MARK: - LabSession Tests

struct LabSessionTests {

    @Test func defaultInit() {
        let session = LabSession()
        #expect(session.currentPhase == .referenceInput)
        #expect(session.parameterSnapshots.isEmpty)
        #expect(session.adversarialProposals.isEmpty)
        #expect(session.visitedPhases.contains(LabPhase.referenceInput.rawValue))
    }

    @Test func phaseProgression() {
        var session = LabSession()
        session.advanceTo(.analysis)
        session.advanceTo(.documentDrafting)
        #expect(session.currentPhase == .documentDrafting)
        #expect(session.visitedPhases.count == 3)
        #expect(session.hasVisited(.analysis))
        #expect(session.hasVisited(.documentDrafting))
    }

    @Test func snapshotTracking() {
        var session = LabSession()
        let snapshot = ParameterSnapshot(paramValues: ["_speed": [1.0]])
        session.parameterSnapshots.append(snapshot)
        #expect(session.parameterSnapshots.count == 1)
    }

    @Test func codableRoundTrip() throws {
        var session = LabSession()
        session.advanceTo(.implementation)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LabSession.self, from: data)
        #expect(decoded.currentPhase == .implementation)
        #expect(decoded.visitedPhases.contains(LabPhase.implementation.rawValue))
    }

    @Test func codableRoundTripWithChatMessages() throws {
        var session = LabSession()
        session.chatMessages = [
            ChatMessage(role: .user, content: "Create a shader"),
            ChatMessage(role: .assistant, content: "Here's a gradient shader",
                        executedActions: [
                            AgentAction(type: .addLayer, category: "fragment", name: "Gradient", code: "test")
                        ]),
            ChatMessage(role: .assistant, content: "Updated design doc",
                        executedLabActions: [
                            LabAction(type: .updateDesignDoc, content: "# Design")
                        ])
        ]
        session.parameterSnapshots = [
            ParameterSnapshot(paramValues: ["_speed": [1.5]], label: "Snapshot A")
        ]
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LabSession.self, from: data)
        #expect(decoded.chatMessages.count == 3)
        #expect(decoded.chatMessages[0].role == .user)
        #expect(decoded.chatMessages[0].content == "Create a shader")
        #expect(decoded.chatMessages[1].executedActions?.count == 1)
        #expect(decoded.chatMessages[2].executedLabActions?.count == 1)
        #expect(decoded.parameterSnapshots.count == 1)
    }
}

// MARK: - CanvasDocument Lab Round-Trip Tests

struct CanvasDocumentLabTests {

    @Test func roundTripLabWithAllFields() throws {
        var session = LabSession()
        session.advanceTo(.implementation)
        session.chatMessages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "World")
        ]
        let refs = [
            ReferenceItem(type: .text, annotation: "My ref", textContent: "Some description"),
            ReferenceItem(type: .image, annotation: "Image ref",
                          mediaData: Data([0x01, 0x02, 0x03]),
                          thumbnailData: Data([0x04, 0x05]))
        ]
        let projDoc = ProjectDocument(markdown: "# Project\n\nGoal: cool shader")
        let designDoc = DesignDocument(markdown: "# Design\n\n## Approach\nUse SDF")

        let doc = CanvasDocument(
            name: "Lab Test",
            mode: .twoDimensionalLab,
            meshType: .sphere,
            shaders: [ActiveShader(category: .fragment, name: "Main", code: "frag code")],
            paramValues: ["_speed": [2.0]],
            labSession: session,
            references: refs,
            projectDocument: projDoc,
            designDoc: designDoc
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("labSession"))
        #expect(json.contains("references"))
        #expect(json.contains("projectDocument"))
        #expect(json.contains("designDoc"))
        #expect(json.contains("chatMessages"))
        #expect(json.contains("My ref"))
        #expect(json.contains("cool shader"))
        #expect(json.contains("Use SDF"))

        let decoded = try JSONDecoder().decode(CanvasDocument.self, from: data)
        #expect(decoded.name == "Lab Test")
        #expect(decoded.mode == .twoDimensionalLab)

        #expect(decoded.labSession != nil)
        #expect(decoded.labSession!.chatMessages.count == 2)
        #expect(decoded.labSession!.chatMessages[0].content == "Hello")
        #expect(decoded.labSession!.currentPhase == .implementation)

        #expect(decoded.references != nil)
        #expect(decoded.references!.count == 2)
        #expect(decoded.references![0].annotation == "My ref")
        #expect(decoded.references![0].textContent == "Some description")
        #expect(decoded.references![1].mediaData == Data([0x01, 0x02, 0x03]))

        #expect(decoded.projectDocument != nil)
        #expect(decoded.projectDocument!.markdown.contains("cool shader"))

        #expect(decoded.designDoc != nil)
        #expect(decoded.designDoc!.markdown.contains("Use SDF"))
    }

    @Test func roundTripLabViaCanvasActions() throws {
        var session = LabSession()
        session.chatMessages = [
            ChatMessage(role: .user, content: "Test message")
        ]
        let refs = [ReferenceItem(type: .text, annotation: "Note", textContent: "Content")]
        let projDoc = ProjectDocument(markdown: "# Doc")
        let design = DesignDocument(markdown: "# Design")

        let doc = CanvasActions.buildDocument(
            name: "Lab Build", mode: .threeDimensionalLab, meshType: .sphere,
            shape2DType: .roundedRectangle,
            shaders: [], dataFlow: DataFlowConfig(), dataFlow2D: DataFlow2DConfig(),
            paramValues: [:], objects2D: [],
            sharedVertexCode2D: "", sharedFragmentCode2D: "",
            labSession: session,
            references: refs,
            projectDocument: projDoc,
            designDoc: design
        )

        #expect(doc.labSession != nil)
        #expect(doc.labSession!.chatMessages.count == 1)
        #expect(doc.references != nil)
        #expect(doc.references!.count == 1)
        #expect(doc.projectDocument != nil)
        #expect(doc.designDoc != nil)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(CanvasDocument.self, from: data)

        #expect(decoded.labSession != nil)
        #expect(decoded.labSession!.chatMessages.count == 1)
        #expect(decoded.labSession!.chatMessages[0].content == "Test message")
        #expect(decoded.references!.count == 1)
        #expect(decoded.references![0].textContent == "Content")
        #expect(decoded.projectDocument!.markdown == "# Doc")
        #expect(decoded.designDoc!.markdown == "# Design")
    }
}
