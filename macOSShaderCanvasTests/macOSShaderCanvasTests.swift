//
//  macOSShaderCanvasTests.swift
//  macOSShaderCanvasTests
//

import Testing
import Foundation
@testable import macOSShaderCanvas

// MARK: - AgentActionType Tests

struct AgentActionTypeTests {

    @Test func allCasesRoundTrip() throws {
        let allCases: [AgentActionType] = [
            .addLayer, .modifyLayer,
            .addObject2D, .modifyObject2D,
            .setSharedShader2D, .setObjectShader2D
        ]
        for actionType in allCases {
            let data = try JSONEncoder().encode(actionType)
            let decoded = try JSONDecoder().decode(AgentActionType.self, from: data)
            #expect(decoded == actionType)
        }
    }

    @Test func rawValueMapping() {
        #expect(AgentActionType.addLayer.rawValue == "addLayer")
        #expect(AgentActionType.modifyLayer.rawValue == "modifyLayer")
        #expect(AgentActionType.addObject2D.rawValue == "addObject2D")
        #expect(AgentActionType.modifyObject2D.rawValue == "modifyObject2D")
        #expect(AgentActionType.setSharedShader2D.rawValue == "setSharedShader2D")
        #expect(AgentActionType.setObjectShader2D.rawValue == "setObjectShader2D")
    }
}

// MARK: - AgentAction Tests

struct AgentActionTests {

    @Test func addLayerAction3D() throws {
        let json = """
        {
            "type": "addLayer",
            "category": "fragment",
            "name": "Lambert Shading",
            "code": "fragment float4 fragment_main(VertexOut in [[stage_in]]) { return float4(1,0,0,1); }"
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .addLayer)
        #expect(action.category == "fragment")
        #expect(action.name == "Lambert Shading")
        #expect(action.code.contains("fragment_main"))
        #expect(action.shaderCategory == .fragment)
        #expect(action.targetLayerName == nil)
        #expect(action.shapeType == nil)
    }

    @Test func modifyLayerAction3D() throws {
        let json = """
        {
            "type": "modifyLayer",
            "category": "vertex",
            "name": "Wave Deformation v2",
            "code": "vertex VertexOut vertex_main(VertexIn in [[stage_in]]) { VertexOut out; return out; }",
            "targetLayerName": "Wave Deformation"
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .modifyLayer)
        #expect(action.shaderCategory == .vertex)
        #expect(action.targetLayerName == "Wave Deformation")
    }

    @Test func addObject2DAction() throws {
        let json = """
        {
            "type": "addObject2D",
            "name": "Play Button",
            "shapeType": "Circle",
            "posX": 0.0,
            "posY": -0.3,
            "scaleW": 0.25,
            "scaleH": 0.25,
            "rotation": 0.0,
            "cornerRadius": 0.0
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .addObject2D)
        #expect(action.name == "Play Button")
        #expect(action.shape2DType == .circle)
        #expect(action.posX == 0.0)
        #expect(action.posY == -0.3)
        #expect(action.scaleW == 0.25)
        #expect(action.scaleH == 0.25)
        #expect(action.rotation == 0.0)
        #expect(action.cornerRadius == 0.0)
    }

    @Test func modifyObject2DAction() throws {
        let json = """
        {
            "type": "modifyObject2D",
            "targetObjectName": "Card",
            "name": "Card Updated",
            "shapeType": "Rounded Rect",
            "posX": 0.1,
            "scaleW": 0.6
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .modifyObject2D)
        #expect(action.targetObjectName == "Card")
        #expect(action.name == "Card Updated")
        #expect(action.shape2DType == .roundedRectangle)
        #expect(action.posX == 0.1)
        #expect(action.posY == nil)
        #expect(action.scaleW == 0.6)
        #expect(action.scaleH == nil)
    }

    @Test func setSharedShader2DAction() throws {
        let json = """
        {
            "type": "setSharedShader2D",
            "category": "distortion",
            "code": "float2 distort_main(float2 p, float2 uv, Uniforms u) { return p; }"
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .setSharedShader2D)
        #expect(action.category == "distortion")
        #expect(action.code.contains("distort_main"))
        #expect(action.name == "Untitled")
    }

    @Test func setObjectShader2DAction() throws {
        let json = """
        {
            "type": "setObjectShader2D",
            "category": "fragment",
            "targetObjectName": "Badge",
            "code": "fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) { return float4(1,0,0,1); }"
        }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .setObjectShader2D)
        #expect(action.category == "fragment")
        #expect(action.targetObjectName == "Badge")
    }

    @Test func shaderCategoryMapping() {
        let vertex = AgentAction(type: .addLayer, category: "vertex", name: "V", code: "")
        let fragment = AgentAction(type: .addLayer, category: "Fragment", name: "F", code: "")
        let fullscreen = AgentAction(type: .addLayer, category: "FULLSCREEN", name: "PP", code: "")
        let distortion = AgentAction(type: .setSharedShader2D, category: "distortion", name: "", code: "")
        let unknown = AgentAction(type: .addLayer, category: "compute", name: "C", code: "")

        #expect(vertex.shaderCategory == .vertex)
        #expect(fragment.shaderCategory == .fragment)
        #expect(fullscreen.shaderCategory == .fullscreen)
        #expect(distortion.shaderCategory == nil)
        #expect(unknown.shaderCategory == nil)
    }

    @Test func shape2DTypeMapping() {
        let rect = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "Rectangle")
        let rounded = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "Rounded Rect")
        let circle = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "Circle")
        let capsule = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "Capsule")
        let none = AgentAction(type: .addObject2D, category: "", name: "", code: "")

        #expect(rect.shape2DType == .rectangle)
        #expect(rounded.shape2DType == .roundedRectangle)
        #expect(circle.shape2DType == .circle)
        #expect(capsule.shape2DType == .capsule)
        #expect(none.shape2DType == nil)
    }

    @Test func shape2DTypeCaseInsensitive() {
        let upper = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "CIRCLE")
        let lower = AgentAction(type: .addObject2D, category: "", name: "", code: "", shapeType: "circle")
        #expect(upper.shape2DType == .circle)
        #expect(lower.shape2DType == .circle)
    }

    @Test func actionRoundTrip() throws {
        let original = AgentAction(
            type: .addObject2D, category: "fragment", name: "Test",
            code: "some code", shapeType: "Circle",
            posX: 0.1, posY: -0.2, scaleW: 0.3, scaleH: 0.4,
            rotation: 1.5, cornerRadius: 0.1, targetObjectName: "Target"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentAction.self, from: data)
        #expect(decoded.type == original.type)
        #expect(decoded.category == original.category)
        #expect(decoded.name == original.name)
        #expect(decoded.code == original.code)
        #expect(decoded.shapeType == original.shapeType)
        #expect(decoded.posX == original.posX)
        #expect(decoded.posY == original.posY)
        #expect(decoded.scaleW == original.scaleW)
        #expect(decoded.scaleH == original.scaleH)
        #expect(decoded.rotation == original.rotation)
        #expect(decoded.cornerRadius == original.cornerRadius)
        #expect(decoded.targetObjectName == original.targetObjectName)
    }

    @Test func optionalFieldsDefaultToNil() throws {
        let json = """
        { "type": "addLayer", "category": "fullscreen", "name": "PP", "code": "x" }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.targetLayerName == nil)
        #expect(action.shapeType == nil)
        #expect(action.posX == nil)
        #expect(action.posY == nil)
        #expect(action.scaleW == nil)
        #expect(action.scaleH == nil)
        #expect(action.rotation == nil)
        #expect(action.cornerRadius == nil)
        #expect(action.targetObjectName == nil)
    }

    @Test func minimalFieldsDecodeGracefully() throws {
        let json = """
        { "type": "setSharedShader2D" }
        """
        let action = try JSONDecoder().decode(AgentAction.self, from: json.data(using: .utf8)!)
        #expect(action.type == .setSharedShader2D)
        #expect(action.category == "")
        #expect(action.name == "Untitled")
        #expect(action.code == "")
    }
}

// MARK: - AgentResponse Tests

struct AgentResponseTests {

    @Test func successfulResponseWithActions() throws {
        let json = """
        {
            "canFulfill": true,
            "explanation": "Added a Lambert shader.",
            "actions": [
                {
                    "type": "addLayer",
                    "category": "fragment",
                    "name": "Lambert",
                    "code": "fragment float4 fragment_main(VertexOut in [[stage_in]]) { return float4(1); }"
                }
            ],
            "barriers": null
        }
        """
        let response = try JSONDecoder().decode(AgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.canFulfill == true)
        #expect(response.explanation == "Added a Lambert shader.")
        #expect(response.actions.count == 1)
        #expect(response.actions[0].type == .addLayer)
        #expect(response.barriers == nil)
    }

    @Test func failedResponseWithBarriers() throws {
        let json = """
        {
            "canFulfill": false,
            "explanation": "Cannot add shadow mapping.",
            "actions": [],
            "barriers": ["Requires depth pass", "Not available in current pipeline"]
        }
        """
        let response = try JSONDecoder().decode(AgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.canFulfill == false)
        #expect(response.actions.isEmpty)
        #expect(response.barriers?.count == 2)
        #expect(response.barriers?[0] == "Requires depth pass")
    }

    @Test func plainTextFallback() {
        let response = AgentResponse.plainText("Hello, how can I help?")
        #expect(response.canFulfill == true)
        #expect(response.explanation == "Hello, how can I help?")
        #expect(response.actions.isEmpty)
        #expect(response.barriers == nil)
    }

    @Test func missingFieldsDefaultGracefully() throws {
        let json = """
        { "explanation": "Test" }
        """
        let response = try JSONDecoder().decode(AgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.canFulfill == true)
        #expect(response.explanation == "Test")
        #expect(response.actions.isEmpty)
        #expect(response.barriers == nil)
    }

    @Test func emptyObjectDecodes() throws {
        let json = "{}"
        let response = try JSONDecoder().decode(AgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.canFulfill == true)
        #expect(response.explanation == "")
        #expect(response.actions.isEmpty)
    }

    @Test func responseWith2DActions() throws {
        let json = """
        {
            "canFulfill": true,
            "explanation": "Created a UI card.",
            "actions": [
                {
                    "type": "addObject2D",
                    "name": "Card",
                    "shapeType": "Rounded Rect",
                    "posX": 0.0,
                    "posY": 0.0,
                    "scaleW": 0.6,
                    "scaleH": 0.4,
                    "cornerRadius": 0.1
                },
                {
                    "type": "setSharedShader2D",
                    "category": "fragment",
                    "code": "fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) { return float4(0.2, 0.4, 0.8, 1.0); }"
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(AgentResponse.self, from: json.data(using: .utf8)!)
        #expect(response.canFulfill == true)
        #expect(response.actions.count == 2)
        #expect(response.actions[0].type == .addObject2D)
        #expect(response.actions[0].shape2DType == .roundedRectangle)
        #expect(response.actions[1].type == .setSharedShader2D)
    }

    @Test func roundTripEncoding() throws {
        let original = AgentResponse(
            canFulfill: true,
            explanation: "Test round trip",
            actions: [
                AgentAction(type: .addObject2D, category: "", name: "Obj", code: "",
                           shapeType: "Circle", posX: 0.5, posY: -0.5)
            ],
            barriers: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentResponse.self, from: data)
        #expect(decoded.canFulfill == original.canFulfill)
        #expect(decoded.explanation == original.explanation)
        #expect(decoded.actions.count == 1)
        #expect(decoded.actions[0].name == "Obj")
    }
}

// MARK: - AIService Parsing Tests

struct AIServiceParsingTests {

    @Test func parseCleanJSON() async throws {
        let json = """
        {
            "canFulfill": true,
            "explanation": "Here is a shader",
            "actions": [
                { "type": "addLayer", "category": "fragment", "name": "Red", "code": "return float4(1,0,0,1);" }
            ]
        }
        """
        let response = try await AIService.shared.parseAgentResponse(from: json)
        #expect(response.canFulfill == true)
        #expect(response.actions.count == 1)
        #expect(response.actions[0].name == "Red")
    }

    @Test func parseJSONWithMarkdownFences() async throws {
        let json = """
        ```json
        {
            "canFulfill": true,
            "explanation": "Done",
            "actions": []
        }
        ```
        """
        let response = try await AIService.shared.parseAgentResponse(from: json)
        #expect(response.canFulfill == true)
        #expect(response.explanation == "Done")
    }

    @Test func parseJSONWithSurroundingText() async throws {
        let text = """
        Here is my response:
        {
            "canFulfill": false,
            "explanation": "Cannot do that",
            "actions": [],
            "barriers": ["Not supported"]
        }
        Some trailing text.
        """
        let response = try await AIService.shared.parseAgentResponse(from: text)
        #expect(response.canFulfill == false)
        #expect(response.barriers?.count == 1)
    }

    @Test func parseJSONWithNestedBraces() async throws {
        let json = """
        {
            "canFulfill": true,
            "explanation": "Added shader with braces in code",
            "actions": [
                {
                    "type": "addLayer",
                    "category": "fragment",
                    "name": "Test",
                    "code": "fragment float4 fragment_main(VertexOut in [[stage_in]]) { float x = 1.0; if (x > 0) { return float4(x, 0, 0, 1); } return float4(0); }"
                }
            ]
        }
        """
        let response = try await AIService.shared.parseAgentResponse(from: json)
        #expect(response.actions.count == 1)
        #expect(response.actions[0].code.contains("if (x > 0)"))
    }

    @Test func parseInvalidJSONThrows() async {
        let invalid = "This is not JSON at all"
        do {
            _ = try await AIService.shared.parseAgentResponse(from: invalid)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is AIError)
        }
    }

    @Test func parse2DActionsFromJSON() async throws {
        let json = """
        {
            "canFulfill": true,
            "explanation": "Created objects",
            "actions": [
                {
                    "type": "addObject2D",
                    "name": "Header",
                    "shapeType": "Rounded Rect",
                    "posX": 0.0, "posY": 0.3,
                    "scaleW": 0.8, "scaleH": 0.15,
                    "cornerRadius": 0.08
                },
                {
                    "type": "setSharedShader2D",
                    "category": "fragment",
                    "code": "fragment float4 fragment_main(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) { return float4(in.texCoord, 0.5, 1.0); }"
                },
                {
                    "type": "setObjectShader2D",
                    "category": "distortion",
                    "targetObjectName": "Header",
                    "code": "float2 distort_main(float2 p, float2 uv, Uniforms u) { p.y += sin(uv.x * 10.0 + u.time) * 0.01; return p; }"
                }
            ]
        }
        """
        let response = try await AIService.shared.parseAgentResponse(from: json)
        #expect(response.actions.count == 3)
        #expect(response.actions[0].type == .addObject2D)
        #expect(response.actions[0].posY == 0.3)
        #expect(response.actions[1].type == .setSharedShader2D)
        #expect(response.actions[2].type == .setObjectShader2D)
        #expect(response.actions[2].targetObjectName == "Header")
    }
}

// MARK: - DataFlowConfig Tests

struct DataFlowConfigTests {

    @Test func defaultConfig() {
        let config = DataFlowConfig()
        #expect(config.normalEnabled == true)
        #expect(config.uvEnabled == true)
        #expect(config.timeEnabled == true)
        #expect(config.worldPositionEnabled == false)
        #expect(config.worldNormalEnabled == false)
        #expect(config.viewDirectionEnabled == false)
    }

    @Test func dependencyResolutionWorldNormalRequiresNormal() {
        var config = DataFlowConfig()
        config.worldNormalEnabled = true
        config.normalEnabled = false
        config.resolveDependencies()
        #expect(config.normalEnabled == true)
    }

    @Test func dependencyResolutionViewDirRequiresWorldPos() {
        var config = DataFlowConfig()
        config.viewDirectionEnabled = true
        config.worldPositionEnabled = false
        config.resolveDependencies()
        #expect(config.worldPositionEnabled == true)
    }

    @Test func dependencyResolutionDisablingNormalDisablesWorldNormal() {
        var config = DataFlowConfig()
        config.worldNormalEnabled = true
        config.normalEnabled = false
        config.resolveDependencies()
        #expect(config.normalEnabled == true)

        config.normalEnabled = false
        config.worldNormalEnabled = false
        config.resolveDependencies()
        #expect(config.worldNormalEnabled == false)
    }

    @Test func dependencyResolutionReEnablesPrerequisite() {
        var config = DataFlowConfig()
        config.viewDirectionEnabled = true
        config.worldPositionEnabled = true
        config.resolveDependencies()
        #expect(config.viewDirectionEnabled == true)

        config.worldPositionEnabled = false
        config.resolveDependencies()
        // resolveDependencies re-enables worldPosition because viewDirection needs it
        #expect(config.worldPositionEnabled == true)
        #expect(config.viewDirectionEnabled == true)
    }

    @Test func dependencyDisablingDependentFirstAllowsPrereqOff() {
        var config = DataFlowConfig()
        config.viewDirectionEnabled = true
        config.worldPositionEnabled = true
        config.resolveDependencies()

        config.viewDirectionEnabled = false
        config.worldPositionEnabled = false
        config.resolveDependencies()
        #expect(config.worldPositionEnabled == false)
        #expect(config.viewDirectionEnabled == false)
    }

    @Test func codableRoundTrip() throws {
        var config = DataFlowConfig()
        config.worldPositionEnabled = true
        config.viewDirectionEnabled = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DataFlowConfig.self, from: data)
        #expect(decoded == config)
    }
}

// MARK: - DataFlow2DConfig Tests

struct DataFlow2DConfigTests {

    @Test func defaultConfig() {
        let config = DataFlow2DConfig()
        #expect(config.timeEnabled == true)
        #expect(config.mouseEnabled == false)
        #expect(config.objectPositionEnabled == false)
        #expect(config.screenUVEnabled == false)
    }

    @Test func codableRoundTrip() throws {
        var config = DataFlow2DConfig()
        config.mouseEnabled = true
        config.screenUVEnabled = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DataFlow2DConfig.self, from: data)
        #expect(decoded == config)
    }
}

// MARK: - Object2D Tests

struct Object2DTests {

    @Test func defaultInit() {
        let obj = Object2D()
        #expect(obj.name == "Object")
        #expect(obj.shapeType == .roundedRectangle)
        #expect(obj.posX == 0)
        #expect(obj.posY == 0)
        #expect(obj.scaleW == 0.5)
        #expect(obj.scaleH == 0.5)
        #expect(obj.rotation == 0)
        #expect(obj.cornerRadius == 0.15)
        #expect(obj.customVertexCode == nil)
        #expect(obj.customFragmentCode == nil)
    }

    @Test func customInit() {
        let obj = Object2D(
            name: "Button", shapeType: .capsule,
            posX: 0.2, posY: -0.3, scaleW: 0.4, scaleH: 0.2,
            rotation: 0.5, cornerRadius: 0.3,
            customVertexCode: "distort code",
            customFragmentCode: "frag code"
        )
        #expect(obj.name == "Button")
        #expect(obj.shapeType == .capsule)
        #expect(obj.posX == 0.2)
        #expect(obj.customVertexCode == "distort code")
        #expect(obj.customFragmentCode == "frag code")
    }

    @Test func codableRoundTrip() throws {
        let obj = Object2D(name: "Card", shapeType: .circle, posX: 0.1, posY: -0.2)
        let data = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(Object2D.self, from: data)
        #expect(decoded.name == "Card")
        #expect(decoded.shapeType == .circle)
        #expect(decoded.posX == 0.1)
        #expect(decoded.posY == -0.2)
        #expect(decoded.cornerRadius == 0.15)
    }

    @Test func decodingMissingCornerRadiusDefaultsTo015() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "Legacy",
            "shapeType": "Rectangle",
            "posX": 0.0, "posY": 0.0,
            "scaleW": 0.5, "scaleH": 0.5,
            "rotation": 0.0
        }
        """
        let decoded = try JSONDecoder().decode(Object2D.self, from: json.data(using: .utf8)!)
        #expect(decoded.cornerRadius == 0.15)
    }
}

// MARK: - Shape2DType Tests

struct Shape2DTypeTests {

    @Test func allCasesExist() {
        #expect(Shape2DType.allCases.count == 4)
    }

    @Test func quadAspects() {
        #expect(Shape2DType.rectangle.quadAspect == 1.6)
        #expect(Shape2DType.roundedRectangle.quadAspect == 1.6)
        #expect(Shape2DType.circle.quadAspect == 1.0)
        #expect(Shape2DType.capsule.quadAspect == 2.5)
    }

    @Test func icons() {
        #expect(Shape2DType.rectangle.icon == "rectangle.fill")
        #expect(Shape2DType.circle.icon == "circle.fill")
    }

    @Test func codableRoundTrip() throws {
        for shape in Shape2DType.allCases {
            let data = try JSONEncoder().encode(shape)
            let decoded = try JSONDecoder().decode(Shape2DType.self, from: data)
            #expect(decoded == shape)
        }
    }
}

// MARK: - CanvasDocument Tests

struct CanvasDocumentTests {

    @Test func roundTrip3D() throws {
        let doc = CanvasDocument(
            name: "Test 3D",
            mode: .threeDimensional,
            meshType: .sphere,
            shaders: [
                ActiveShader(category: .fragment, name: "Lambert", code: "test code")
            ],
            dataFlow: DataFlowConfig(),
            paramValues: ["_intensity": [0.5]]
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(CanvasDocument.self, from: data)
        #expect(decoded.name == "Test 3D")
        #expect(decoded.mode == .threeDimensional)
        #expect(decoded.shaders.count == 1)
        #expect(decoded.shaders[0].name == "Lambert")
        #expect(decoded.paramValues["_intensity"] == [0.5])
        #expect(decoded.objects2D == nil)
    }

    @Test func roundTrip2D() throws {
        let objects = [
            Object2D(name: "Card", shapeType: .roundedRectangle),
            Object2D(name: "Button", shapeType: .capsule, posY: -0.3)
        ]
        let doc = CanvasDocument(
            name: "Test 2D",
            mode: .twoDimensional,
            meshType: .sphere,
            shape2DType: .circle,
            shaders: [
                ActiveShader(category: .fullscreen, name: "Bloom", code: "pp code")
            ],
            objects2D: objects,
            sharedVertexCode2D: "distort code",
            sharedFragmentCode2D: "frag code"
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(CanvasDocument.self, from: data)
        #expect(decoded.name == "Test 2D")
        #expect(decoded.mode == .twoDimensional)
        #expect(decoded.objects2D?.count == 2)
        #expect(decoded.objects2D?[0].name == "Card")
        #expect(decoded.objects2D?[1].posY == -0.3)
        #expect(decoded.sharedVertexCode2D == "distort code")
        #expect(decoded.sharedFragmentCode2D == "frag code")
        #expect(decoded.shape2DType == .circle)
    }

    @Test func decodingLegacyDocumentMissingModeDefaultsTo3D() throws {
        let json = """
        {
            "name": "Old File",
            "meshType": { "type": "sphere" },
            "shaders": []
        }
        """
        let decoded = try JSONDecoder().decode(CanvasDocument.self, from: json.data(using: .utf8)!)
        #expect(decoded.mode == .threeDimensional)
        #expect(decoded.dataFlow2D == DataFlow2DConfig())
        #expect(decoded.objects2D == nil)
        #expect(decoded.shape2DType == .roundedRectangle)
    }
}

// MARK: - ActiveShader Tests

struct ActiveShaderTests {

    @Test func initAndCodable() throws {
        let shader = ActiveShader(category: .vertex, name: "Wave", code: "vertex code here")
        let data = try JSONEncoder().encode(shader)
        let decoded = try JSONDecoder().decode(ActiveShader.self, from: data)
        #expect(decoded.category == .vertex)
        #expect(decoded.name == "Wave")
        #expect(decoded.code == "vertex code here")
        #expect(decoded.id == shader.id)
    }
}

// MARK: - ShaderSnippets Tests

struct ShaderSnippetsTests {

    // MARK: 3D Header Generation

    @Test func generateSharedHeaderContainsVertexIn() {
        let header = ShaderSnippets.generateSharedHeader(config: DataFlowConfig())
        #expect(header.contains("struct VertexIn"))
        #expect(header.contains("struct VertexOut"))
        #expect(header.contains("struct Uniforms"))
        #expect(header.contains("positionOS"))
        #expect(header.contains("#include <metal_stdlib>"))
    }

    @Test func generateSharedHeaderRespectsConfig() {
        var config = DataFlowConfig()
        config.normalEnabled = false
        config.uvEnabled = false
        let header = ShaderSnippets.generateSharedHeader(config: config)
        #expect(!header.contains("normalOS [[attribute(1)]]"))
        #expect(!header.contains("uv [[attribute(2)]]"))
    }

    @Test func generateSharedHeaderWorldFields() {
        var config = DataFlowConfig()
        config.worldPositionEnabled = true
        config.worldNormalEnabled = true
        config.viewDirectionEnabled = true
        let header = ShaderSnippets.generateSharedHeader(config: config)
        #expect(header.contains("positionWS"))
        #expect(header.contains("normalWS"))
        #expect(header.contains("viewDirWS"))
    }

    // MARK: Default Vertex Shader

    @Test func defaultVertexShaderContainsEntry() {
        let vs = ShaderSnippets.generateDefaultVertexShader(config: DataFlowConfig())
        #expect(vs.contains("vertex VertexOut vertex_main"))
        #expect(vs.contains("mvpMatrix"))
    }

    @Test func defaultVertexShaderWorldPosition() {
        var config = DataFlowConfig()
        config.worldPositionEnabled = true
        let vs = ShaderSnippets.generateDefaultVertexShader(config: config)
        #expect(vs.contains("positionWS"))
        #expect(vs.contains("modelMatrix"))
    }

    // MARK: Vertex Demo

    @Test func vertexDemoContainsDeformation() {
        let demo = ShaderSnippets.generateVertexDemo(config: DataFlowConfig())
        #expect(demo.contains("vertex VertexOut vertex_main"))
        #expect(demo.contains("displacement"))
    }

    // MARK: 2D Header Generation

    @Test func generateSharedHeader2DDefault() {
        let header = ShaderSnippets.generateSharedHeader2D()
        #expect(header.contains("struct VertexOut"))
        #expect(header.contains("struct Uniforms"))
        #expect(header.contains("struct Transform2D"))
        #expect(header.contains("texCoord"))
        #expect(header.contains("shapeAspect"))
        #expect(header.contains("cornerRadius"))
        #expect(header.contains("time"))
        let vertexOutRange = header.range(of: "struct VertexOut")!
        let uniformsRange = header.range(of: "struct Uniforms")!
        let vertexOutBlock = String(header[vertexOutRange.lowerBound..<uniformsRange.lowerBound])
        #expect(!vertexOutBlock.contains("mouse"), "VertexOut should not have 'mouse' with default config")
    }

    @Test func generateSharedHeader2DAllFieldsEnabled() {
        var config = DataFlow2DConfig()
        config.timeEnabled = true
        config.mouseEnabled = true
        config.objectPositionEnabled = true
        config.screenUVEnabled = true
        let header = ShaderSnippets.generateSharedHeader2D(config: config)
        #expect(header.contains("time"))
        #expect(header.contains("mouse"))
        #expect(header.contains("objectPosition"))
        #expect(header.contains("screenUV"))
    }

    @Test func generateSharedHeader2DTimeDisabled() {
        var config = DataFlow2DConfig()
        config.timeEnabled = false
        let header = ShaderSnippets.generateSharedHeader2D(config: config)
        let vertexOutRange = header.range(of: "struct VertexOut")!
        let uniformsRange = header.range(of: "struct Uniforms")!
        let vertexOutBlock = String(header[vertexOutRange.lowerBound..<uniformsRange.lowerBound])
        #expect(!vertexOutBlock.contains("float  time;"))
    }

    // MARK: SDF Functions

    @Test func sdfFunctionForAllShapes() {
        for shape in Shape2DType.allCases {
            let sdf = ShaderSnippets.sdfFunction(for: shape)
            #expect(!sdf.isEmpty)
            #expect(sdf.contains("uv"))
        }
    }

    @Test func sdfRectangleUsesAbsAndMax() {
        let sdf = ShaderSnippets.sdfFunction(for: .rectangle)
        #expect(sdf.contains("abs(q)"))
    }

    @Test func sdfCircleUsesLength() {
        let sdf = ShaderSnippets.sdfFunction(for: .circle)
        #expect(sdf.contains("length(q)"))
    }

    // MARK: 2D Vertex Wrapper

    @Test func generate2DVertexWrapperContainsEntry() {
        let wrapper = ShaderSnippets.generate2DVertexWrapper(shape: .roundedRectangle)
        #expect(wrapper.contains("vertex VertexOut vertex_main"))
        #expect(wrapper.contains("distort_main"))
        #expect(wrapper.contains("transform.objectScale"))
        #expect(wrapper.contains("transform.canvasZoom"))
    }

    @Test func generate2DVertexWrapperRespectsConfig() {
        var config = DataFlow2DConfig()
        config.mouseEnabled = true
        config.screenUVEnabled = true
        let wrapper = ShaderSnippets.generate2DVertexWrapper(shape: .circle, config: config)
        #expect(wrapper.contains("out.mouse"))
        #expect(wrapper.contains("out.screenUV"))
    }

    @Test func generate2DVertexWrapperWithoutOptionalFields() {
        var config = DataFlow2DConfig()
        config.timeEnabled = false
        config.mouseEnabled = false
        config.objectPositionEnabled = false
        config.screenUVEnabled = false
        let wrapper = ShaderSnippets.generate2DVertexWrapper(shape: .capsule, config: config)
        #expect(!wrapper.contains("out.time"))
        #expect(!wrapper.contains("out.mouse"))
        #expect(!wrapper.contains("out.objectPosition"))
        #expect(!wrapper.contains("out.screenUV"))
    }

    // MARK: Fragment SDF Wrapping

    @Test func wrapFragmentWithSDFRenamesEntry() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]]) {
            return float4(1, 0, 0, 1);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .circle, hasParams: false)
        #expect(wrapped.contains("_user_fragment"))
        #expect(wrapped.contains("_sdf_shape"))
        #expect(wrapped.contains("smoothstep"))
        #expect(wrapped.contains("fragment float4 fragment_main"))
    }

    @Test func wrapFragmentWithSDFParamsVariant() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      constant Params &params [[buffer(2)]]) {
            return float4(1);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .roundedRectangle, hasParams: true)
        #expect(wrapped.contains("constant Params &params"))
        #expect(wrapped.contains("_user_fragment(in, uniforms, params)"))
    }

    @Test func wrapFragmentWithSDFNoParams() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]]) {
            return float4(0);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .capsule, hasParams: false)
        #expect(wrapped.contains("_user_fragment(in, uniforms)"))
        #expect(!wrapped.contains("Params"))
    }

    @Test func wrapFragmentWithSDFAlwaysDecaresBgTexture() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]]) {
            return float4(1);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .circle, hasParams: false)
        #expect(wrapped.contains("texture2d<float> bgTexture [[texture(0)]]"))
        #expect(wrapped.contains("_user_fragment(in, uniforms)"))
        #expect(!wrapped.contains("_user_fragment(in, uniforms, bgTexture)"))
    }

    @Test func wrapFragmentWithSDFForwardsBgTextureWhenUsed() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      texture2d<float> bgTexture [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            float2 screenUV = float2(in.position.xy) / uniforms.resolution;
            float4 bg = bgTexture.sample(s, screenUV);
            return mix(bg, float4(1, 0, 0, 1), 0.5);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .roundedRectangle, hasParams: false)
        #expect(wrapped.contains("_user_fragment(in, uniforms, bgTexture)"))
        #expect(wrapped.contains("texture2d<float> bgTexture [[texture(0)]]"))
        #expect(!wrapped.contains("[[texture(0)]] )"))
    }

    @Test func wrapFragmentWithSDFBgTextureAndParams() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      constant Params &params [[buffer(2)]],
                                      texture2d<float> bgTexture [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            float4 bg = bgTexture.sample(s, in.texCoord);
            return bg * params._tint;
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .circle, hasParams: true)
        #expect(wrapped.contains("_user_fragment(in, uniforms, params, bgTexture)"))
        #expect(wrapped.contains("constant Params &params [[buffer(2)]]"))
        #expect(wrapped.contains("texture2d<float> bgTexture [[texture(0)]]"))
    }

    @Test func wrapFragmentWithSDFStripsTextureAttribute() {
        let userCode = """
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      texture2d<float> bgTexture [[texture(0)]]) {
            return float4(1);
        }
        """
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(userCode: userCode, shape: .capsule, hasParams: false)
        let userFnRange = wrapped.range(of: "_user_fragment(")!
        let userFnPart = String(wrapped[userFnRange.lowerBound...])
        let closingParen = userFnPart.firstIndex(of: "{")!
        let signature = String(userFnPart[...closingParen])
        #expect(!signature.contains("[[texture(0)]]"))
    }

    // MARK: Static Shader Strings

    @Test func distortion2DDemoContainsDistortMain() {
        #expect(ShaderSnippets.distortion2DDemo.contains("distort_main"))
    }

    @Test func distortion2DTemplateIsIdentity() {
        #expect(ShaderSnippets.distortion2DTemplate.contains("return position"))
    }

    @Test func fragment2DDemoContainsFragmentMain() {
        #expect(ShaderSnippets.fragment2DDemo.contains("fragment_main"))
    }

    @Test func fragment2DTemplateContainsFragmentMain() {
        #expect(ShaderSnippets.fragment2DTemplate.contains("fragment_main"))
    }

    @Test func gridShaderIsSelfContained() {
        let grid = ShaderSnippets.gridShader
        #expect(grid.contains("#include <metal_stdlib>"))
        #expect(grid.contains("vertex VertexOut vertex_main"))
        #expect(grid.contains("fragment float4 fragment_main"))
    }

    @Test func blitShaderExists() {
        #expect(!ShaderSnippets.blitShader.isEmpty)
        #expect(ShaderSnippets.blitShader.contains("fragment_main"))
    }

    @Test func defaultFragmentExists() {
        #expect(!ShaderSnippets.defaultFragment.isEmpty)
        #expect(ShaderSnippets.defaultFragment.contains("fragment_main"))
    }

    @Test func fragmentDemoExists() {
        #expect(!ShaderSnippets.fragmentDemo.isEmpty)
    }

    @Test func fullscreenDemoIsSelfContained() {
        let fs = ShaderSnippets.fullscreenDemo
        #expect(fs.contains("#include <metal_stdlib>"))
        #expect(fs.contains("vertex VertexOut vertex_main"))
        #expect(fs.contains("fragment float4 fragment_main"))
    }

    // MARK: @param Parsing

    @Test func parseParamsFloat() {
        let code = """
        // @param _speed float 2.0 0.0 10.0
        fragment float4 fragment_main(VertexOut in [[stage_in]]) { return float4(1); }
        """
        let params = ShaderSnippets.parseParams(from: code)
        #expect(params.count == 1)
        #expect(params[0].name == "_speed")
        #expect(params[0].type == .float)
        #expect(params[0].defaultValue == [2.0])
        #expect(params[0].minValue == 0.0)
        #expect(params[0].maxValue == 10.0)
    }

    @Test func parseParamsColor() {
        let code = """
        // @param _tint color 1.0 0.5 0.2
        """
        let params = ShaderSnippets.parseParams(from: code)
        #expect(params.count == 1)
        #expect(params[0].name == "_tint")
        #expect(params[0].type == .color)
        #expect(params[0].defaultValue == [1.0, 0.5, 0.2])
    }

    @Test func parseParamsMultiple() {
        let code = """
        // @param _speed float 2.0 0.0 10.0
        // @param _color color 1.0 0.5 0.2
        // @param _offset float2 0.0 0.0
        """
        let params = ShaderSnippets.parseParams(from: code)
        #expect(params.count == 3)
        #expect(params[0].name == "_speed")
        #expect(params[1].name == "_color")
        #expect(params[2].name == "_offset")
        #expect(params[2].type == .float2)
    }

    @Test func parseParamsNoParams() {
        let code = "fragment float4 fragment_main(VertexOut in [[stage_in]]) { return float4(1); }"
        let params = ShaderSnippets.parseParams(from: code)
        #expect(params.isEmpty)
    }
}

// MARK: - MeshType Tests

struct MeshTypeTests {

    @Test func sphereRoundTrip() throws {
        let data = try JSONEncoder().encode(MeshType.sphere)
        let decoded = try JSONDecoder().decode(MeshType.self, from: data)
        #expect(decoded == .sphere)
    }

    @Test func cubeRoundTrip() throws {
        let data = try JSONEncoder().encode(MeshType.cube)
        let decoded = try JSONDecoder().decode(MeshType.self, from: data)
        #expect(decoded == .cube)
    }

    @Test func unknownTypeDefaultsToSphere() throws {
        let json = """
        { "type": "pyramid" }
        """
        let decoded = try JSONDecoder().decode(MeshType.self, from: json.data(using: .utf8)!)
        #expect(decoded == .sphere)
    }

    @Test func customWithMissingFileFallsToSphere() throws {
        let json = """
        { "type": "custom", "path": "/nonexistent/model.usdz" }
        """
        let decoded = try JSONDecoder().decode(MeshType.self, from: json.data(using: .utf8)!)
        #expect(decoded == .sphere)
    }
}

// MARK: - CanvasMode Tests

struct CanvasModeTests {

    @Test func rawValues() {
        #expect(CanvasMode.twoDimensional.rawValue == "2D")
        #expect(CanvasMode.threeDimensional.rawValue == "3D")
        #expect(CanvasMode.twoDimensionalLab.rawValue == "2D Lab")
        #expect(CanvasMode.threeDimensionalLab.rawValue == "3D Lab")
    }

    @Test func allCases() {
        #expect(CanvasMode.allCases.count == 4)
    }

    @Test func labAndDimensionHelpers() {
        #expect(CanvasMode.twoDimensional.is2D)
        #expect(!CanvasMode.twoDimensional.isLab)
        #expect(CanvasMode.twoDimensionalLab.is2D)
        #expect(CanvasMode.twoDimensionalLab.isLab)
        #expect(CanvasMode.threeDimensional.is3D)
        #expect(!CanvasMode.threeDimensional.isLab)
        #expect(CanvasMode.threeDimensionalLab.is3D)
        #expect(CanvasMode.threeDimensionalLab.isLab)
    }

    @Test func codableRoundTrip() throws {
        for mode in CanvasMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(CanvasMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - ShaderCategory Tests

struct ShaderCategoryTests {

    @Test func allCases() {
        #expect(ShaderCategory.allCases.count == 3)
    }

    @Test func ordering() {
        let categories = ShaderCategory.allCases
        #expect(categories.contains(.vertex))
        #expect(categories.contains(.fragment))
        #expect(categories.contains(.fullscreen))
    }

    @Test func icons() {
        #expect(ShaderCategory.vertex.icon == "move.3d")
        #expect(ShaderCategory.fragment.icon == "paintbrush.fill")
        #expect(ShaderCategory.fullscreen.icon == "display")
    }
}

// MARK: - ParamType Tests

struct ParamTypeTests {

    @Test func componentCounts() {
        #expect(ParamType.float.componentCount == 1)
        #expect(ParamType.float2.componentCount == 2)
        #expect(ParamType.float3.componentCount == 3)
        #expect(ParamType.color.componentCount == 3)
        #expect(ParamType.float4.componentCount == 4)
    }
}

// MARK: - AIError Tests

struct AIErrorTests {

    @Test func notConfiguredDescription() {
        let error = AIError.notConfigured
        #expect(error.errorDescription?.contains("No API key") == true)
    }

    @Test func apiErrorDescription() {
        let error = AIError.apiError(provider: "OpenAI", status: 401, message: "Unauthorized")
        #expect(error.errorDescription?.contains("OpenAI") == true)
        #expect(error.errorDescription?.contains("401") == true)
    }

    @Test func invalidResponseDescription() {
        let error = AIError.invalidResponse("bad format")
        #expect(error.errorDescription?.contains("bad format") == true)
    }
}
