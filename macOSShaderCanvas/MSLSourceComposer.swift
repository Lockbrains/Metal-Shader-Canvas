//
//  MSLSourceComposer.swift
//  macOSShaderCanvas
//
//  Composes the full MSL source strings that MetalRenderer would compile,
//  mirroring its assembly logic in ShaderSnippets. Used by the read-only
//  Code Editor to display composed shader source and generate debug shaders.
//

import Foundation

// MARK: - Composed Shader Parts

struct MSLComposedShader {
    let headers: String
    let paramDefines: String
    let userFunction: String
    let systemWrapper: String

    var fullSource: String { headers + paramDefines + userFunction + systemWrapper }
}

// MARK: - MSLSourceComposer

struct MSLSourceComposer {

    // MARK: - DataFlow Headers (for DataFlow tab display)

    static func structDefinitions2D(config: DataFlow2DConfig) -> String {
        ShaderSnippets.generateSharedHeader2D(config: config)
    }

    static func structDefinitions3D(config: DataFlowConfig) -> String {
        ShaderSnippets.generateSharedHeader(config: config)
    }

    static func paramDefinesFor(codes: [String]) -> String {
        let params = parseUniqueParams(from: codes)
        return ShaderSnippets.generateParamHeader(params: params)
    }

    // MARK: - 2D Mode (Decomposed)

    static func decompose2DVertex(
        object: Object2D, sharedVS: String, config: DataFlow2DConfig
    ) -> MSLComposedShader {
        let userCode = object.customVertexCode ?? sharedVS
        let fsCode = object.customFragmentCode ?? ""
        let allParams = parseUniqueParams(from: [userCode, fsCode])
        let header = ShaderSnippets.generateSharedHeader2D(config: config)
        let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
        let stripped = ShaderSnippets.stripStructDefinitions(from: userCode)
        let injected = ShaderSnippets.inject2DVertexParamsBuffer(into: stripped, paramCount: allParams.count)
        let wrapper = ShaderSnippets.generate2DVertexWrapper(
            shape: object.shapeType, config: config, hasParams: !allParams.isEmpty
        )
        return MSLComposedShader(
            headers: header, paramDefines: paramHeader,
            userFunction: injected, systemWrapper: wrapper
        )
    }

    static func decompose2DFragment(
        object: Object2D, sharedFS: String, config: DataFlow2DConfig
    ) -> MSLComposedShader {
        let vsCode = object.customVertexCode ?? ""
        let fsCode = object.customFragmentCode ?? sharedFS
        let allParams = parseUniqueParams(from: [vsCode, fsCode])
        let header = ShaderSnippets.generateSharedHeader2D(config: config)
        let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
        let stripped = ShaderSnippets.stripStructDefinitions(from: fsCode)
        let sdfAccess = object.shapeLocked && object.customFragmentCode != nil
        let wrapped = ShaderSnippets.wrapFragmentWithSDF(
            userCode: stripped, shape: object.shapeType,
            hasParams: !allParams.isEmpty, sdfAccessEnabled: sdfAccess
        )

        let (userFunc, sysWrapper) = splitUserAndWrapper(from: wrapped, funcName: "_user_fragment")
        return MSLComposedShader(
            headers: header, paramDefines: paramHeader,
            userFunction: userFunc, systemWrapper: sysWrapper
        )
    }

    // MARK: - 3D Mode (Decomposed)

    static func decompose3DVertex(
        shaders: [ActiveShader], config: DataFlowConfig
    ) -> MSLComposedShader {
        let vertexShaders = shaders.filter { $0.category == .vertex }
        let fragmentShaders = shaders.filter { $0.category == .fragment }
        let vBody = vertexShaders.last?.code
            ?? ShaderSnippets.generateDefaultVertexShader(config: config)
        let allParams = parseUniqueParams(from:
            vertexShaders.map(\.code) + fragmentShaders.map(\.code))
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
        var source = ShaderSnippets.stripStructDefinitions(from: vBody)
        source = ShaderSnippets.injectParamsBuffer(into: source, paramCount: allParams.count)
        return MSLComposedShader(
            headers: header, paramDefines: paramHeader,
            userFunction: source, systemWrapper: ""
        )
    }

    static func decompose3DFragment(
        shaders: [ActiveShader], config: DataFlowConfig
    ) -> MSLComposedShader {
        let vertexShaders = shaders.filter { $0.category == .vertex }
        let fragmentShaders = shaders.filter { $0.category == .fragment }
        let fBody = fragmentShaders.last?.code ?? ShaderSnippets.defaultFragment
        let allParams = parseUniqueParams(from:
            vertexShaders.map(\.code) + fragmentShaders.map(\.code))
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let paramHeader = ShaderSnippets.generateParamHeader(params: allParams)
        var source = ShaderSnippets.stripStructDefinitions(from: fBody)
        source = ShaderSnippets.injectParamsBuffer(into: source, paramCount: allParams.count)
        return MSLComposedShader(
            headers: header, paramDefines: paramHeader,
            userFunction: source, systemWrapper: ""
        )
    }

    // MARK: - Fullscreen

    static func composeFullscreenSource(shader: ActiveShader) -> String {
        shader.code
    }

    // MARK: - Helpers

    static func parseUniqueParams(from codes: [String]) -> [ShaderParam] {
        var result: [ShaderParam] = []
        var seen = Set<String>()
        for code in codes {
            for p in ShaderSnippets.parseParams(from: code) {
                if seen.insert(p.name).inserted { result.append(p) }
            }
        }
        return result
    }

    /// Splits the wrapFragmentWithSDF output into user function portion
    /// and system wrapper portion (_sdf_shape + fragment_main).
    private static func splitUserAndWrapper(
        from code: String, funcName: String
    ) -> (userFunc: String, sysWrapper: String) {
        let lines = code.components(separatedBy: "\n")
        var funcEnd = lines.count
        var braceDepth = 0
        var inFunc = false
        var funcStarted = false

        for (i, line) in lines.enumerated() {
            if !inFunc && line.contains(funcName) {
                inFunc = true
            }
            if inFunc {
                for ch in line {
                    if ch == "{" { braceDepth += 1; funcStarted = true }
                    if ch == "}" { braceDepth -= 1 }
                }
                if funcStarted && braceDepth <= 0 {
                    funcEnd = i + 1
                    break
                }
            }
        }

        let userFunc = lines[0..<funcEnd].joined(separator: "\n") + "\n"
        let sysWrapper = funcEnd < lines.count
            ? lines[funcEnd...].joined(separator: "\n")
            : ""
        return (userFunc, sysWrapper)
    }
}
