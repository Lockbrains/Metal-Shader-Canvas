//
//  ShaderSnippets.swift
//  macOSShaderCanvas
//
//  A centralized repository of all Metal Shading Language (MSL) source code
//  used throughout the application.
//
//  ARCHITECTURE (Data Flow system):
//  ─────────────────────────────────
//  Mesh shaders (vertex + fragment) share auto-generated struct definitions
//  (VertexIn, VertexOut, Uniforms) produced by generateSharedHeader(config:).
//  The header is prepended to user code at compile time by MetalRenderer.
//  Shader templates/presets contain only function bodies — no struct definitions.
//
//  Fullscreen (PP) shaders are self-contained and unaffected by Data Flow.
//
//  NAMING CONVENTION (OS/WS):
//  ──────────────────────────
//  positionOS / normalOS  — object space (VertexIn)
//  positionWS / normalWS  — world space  (VertexOut)
//  viewDirWS              — world space  (VertexOut)
//  Backward compat: #define normal normalOS / #define texCoord uv
//

import Foundation

/// Central repository for all Metal Shading Language source code strings
/// and Data Flow header generation logic.
struct ShaderSnippets {

    // MARK: - Data Flow Header Generation

    /// Generates the shared MSL header (VertexIn, VertexOut, Uniforms)
    /// based on the current Data Flow configuration.
    ///
    /// This header is prepended to ALL mesh shader source code before compilation.
    /// Fullscreen shaders are NOT affected.
    static func generateSharedHeader(config: DataFlowConfig) -> String {
        var header = """
        #include <metal_stdlib>
        using namespace metal;
        
        // Backward compatibility with old naming convention
        #define normal normalOS
        #define texCoord uv
        #define modelViewProjectionMatrix mvpMatrix
        
        struct VertexIn {
            float3 positionOS [[attribute(0)]];
        """
        if config.normalEnabled { header += "\n    float3 normalOS [[attribute(1)]];" }
        if config.uvEnabled     { header += "\n    float2 uv [[attribute(2)]];" }
        header += "\n};\n\nstruct VertexOut {\n    float4 position [[position]];"
        if config.normalEnabled         { header += "\n    float3 normalOS;" }
        if config.uvEnabled             { header += "\n    float2 uv;" }
        if config.timeEnabled           { header += "\n    float time;" }
        if config.worldPositionEnabled  { header += "\n    float3 positionWS;" }
        if config.worldNormalEnabled    { header += "\n    float3 normalWS;" }
        if config.viewDirectionEnabled  { header += "\n    float3 viewDirWS;" }
        header += """
        
        };

        struct Uniforms {
            float4x4 mvpMatrix;
            float4x4 modelMatrix;
            float4x4 normalMatrix;
            float4   cameraPosition;
            float    time;
            float    mouseX;
            float    mouseY;
            float    _pad2;
        };

        """
        return header
    }

    /// Generates a complete default vertex shader function based on the
    /// current Data Flow configuration. Used when no user Vertex Shader layer exists.
    static func generateDefaultVertexShader(config: DataFlowConfig) -> String {
        var fn = """
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.mvpMatrix * float4(in.positionOS, 1.0);
        """
        if config.normalEnabled { fn += "\n    out.normalOS = in.normalOS;" }
        if config.uvEnabled     { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled   { fn += "\n    out.time = uniforms.time;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(in.positionOS, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(in.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    /// Generates the vertex shader template shown when a user creates a new
    /// Vertex Shader layer. Includes all standard field assignments for the
    /// current Data Flow config, with a marked area for user deformation code.
    static func generateVertexDemo(config: DataFlowConfig) -> String {
        var fn = """
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            float3 pos = in.positionOS;
            
            // === Your deformation logic here ===
            float displacement = sin(pos.x * 5.0 + uniforms.time * 3.0) * 0.15 +
                                 cos(pos.z * 5.0 + uniforms.time * 3.0) * 0.15;
            pos.y += displacement;
            
            // === Standard assignments (managed by Data Flow) ===
            out.position = uniforms.mvpMatrix * float4(pos, 1.0);
        """
        if config.normalEnabled {
            fn += """
            
                // Estimate the deformed normal
                float3 newNormal = in.normalOS;
                newNormal.x -= cos(pos.x * 5.0 + uniforms.time * 3.0) * 0.15 * 5.0;
                newNormal.z -= -sin(pos.z * 5.0 + uniforms.time * 3.0) * 0.15 * 5.0;
                out.normalOS = normalize(newNormal);
            """
        }
        if config.uvEnabled     { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled   { fn += "\n    out.time = uniforms.time;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(out.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    /// Generates the educational vertex shader template (shown on reset).
    static func generateVertexTemplate(config: DataFlowConfig) -> String {
        var fn = """
        // ============================================================
        // VERTEX SHADER
        // ============================================================
        // VertexIn, VertexOut, and Uniforms are auto-managed by Data Flow.
        // You can see which fields are available in the Data Flow panel.
        //
        // Your job: transform vertex positions and pass data to the fragment shader.
        // Try modifying `pos` before the MVP transform to deform the mesh!
        // ============================================================

        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            float3 pos = in.positionOS;

            // === Your deformation here ===
            // Example: pos.y += sin(pos.x * 5.0 + uniforms.time) * 0.2;

            out.position = uniforms.mvpMatrix * float4(pos, 1.0);
        """
        if config.normalEnabled { fn += "\n    out.normalOS = in.normalOS;" }
        if config.uvEnabled     { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled   { fn += "\n    out.time = uniforms.time;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(in.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    /// Generates a clean struct-only preview for the Data Flow panel.
    /// Omits #include, using namespace, #define, and padding fields.
    static func generateStructPreview(config: DataFlowConfig) -> String {
        var preview = "struct VertexIn {\n    float3 positionOS [[attribute(0)]];"
        if config.normalEnabled { preview += "\n    float3 normalOS [[attribute(1)]];" }
        if config.uvEnabled     { preview += "\n    float2 uv [[attribute(2)]];" }
        preview += "\n};\n\nstruct VertexOut {\n    float4 position [[position]];"
        if config.normalEnabled         { preview += "\n    float3 normalOS;" }
        if config.uvEnabled             { preview += "\n    float2 uv;" }
        if config.timeEnabled           { preview += "\n    float time;" }
        if config.worldPositionEnabled  { preview += "\n    float3 positionWS;" }
        if config.worldNormalEnabled    { preview += "\n    float3 normalWS;" }
        if config.viewDirectionEnabled  { preview += "\n    float3 viewDirWS;" }
        preview += "\n};\n\nstruct Uniforms {\n    float4x4 mvpMatrix;"
        preview += "\n    float4x4 modelMatrix;"
        preview += "\n    float4x4 normalMatrix;"
        preview += "\n    float4   cameraPosition;"
        preview += "\n    float    time;"
        preview += "\n    float    mouseX;"
        preview += "\n    float    mouseY;\n};"
        return preview
    }
    
    /// Generates a clean struct-only preview for the 2D Data Flow panel.
    static func generateStructPreview2D(config: DataFlow2DConfig) -> String {
        var preview = "struct VertexOut {\n    float4 position [[position]];"
        preview += "\n    float2 texCoord;"
        preview += "\n    float  shapeAspect;"
        preview += "\n    float  cornerRadius;"
        if config.timeEnabled           { preview += "\n    float  time;" }
        if config.mouseEnabled           { preview += "\n    float2 mouse;" }
        if config.objectPositionEnabled  { preview += "\n    float2 objectPosition;" }
        if config.screenUVEnabled        { preview += "\n    float2 screenUV;" }
        preview += "\n};\n\nstruct Uniforms {\n    float2 resolution;"
        preview += "\n    float  time;"
        preview += "\n    float  mouseX;"
        preview += "\n    float  mouseY;\n};"
        return preview
    }

    // MARK: - User Parameter System (@param)
    
    /// Parses `// @param` directives from shader source code.
    ///
    /// Supported syntax:
    /// ```
    /// // @param speed float 1.0 0.0 10.0     → slider (default, min, max)
    /// // @param speed float 1.0               → input field (default only)
    /// // @param baseColor color 1.0 0.5 0.2   → color picker
    /// // @param dir float3 0.0 1.0 0.0        → 3-component input
    /// // @param offset float2 0.0 0.0         → 2-component input
    /// ```
    static func parseParams(from code: String) -> [ShaderParam] {
        var params: [ShaderParam] = []
        let pattern = #"//\s*@param\s+(\w+)\s+(float[234]?|color)\s+(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return params }
        
        let nsCode = code as NSString
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
        
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let name = nsCode.substring(with: match.range(at: 1))
            let typeStr = nsCode.substring(with: match.range(at: 2))
            let valuesStr = nsCode.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            
            guard let type = ParamType(rawValue: typeStr == "color" ? "color" : typeStr) else { continue }
            
            let numbers = valuesStr.split(separator: " ").compactMap { Float($0) }
            guard !numbers.isEmpty else { continue }
            
            var defaultValue: [Float]
            var minValue: Float? = nil
            var maxValue: Float? = nil
            
            if type == .float && numbers.count >= 3 {
                defaultValue = [numbers[0]]
                minValue = numbers[1]
                maxValue = numbers[2]
            } else {
                defaultValue = Array(numbers.prefix(type.componentCount))
                while defaultValue.count < type.componentCount {
                    defaultValue.append(0)
                }
            }
            
            params.append(ShaderParam(name: name, type: type, defaultValue: defaultValue, minValue: minValue, maxValue: maxValue))
        }
        return params
    }
    
    /// Generates MSL #define directives that map parameter names to buffer slots.
    ///
    /// The param buffer is a flat `float *` array at buffer index 2.
    /// Each parameter is mapped via #define to its offset(s) in the array.
    static func generateParamHeader(params: [ShaderParam]) -> String {
        guard !params.isEmpty else { return "" }
        var header = "\n// === User Parameters (buffer index 2) ===\n"
        var offset = 0
        for param in params {
            switch param.type.componentCount {
            case 1:
                header += "#define \(param.name) (params[\(offset)])\n"
            case 2:
                header += "#define \(param.name) float2(params[\(offset)], params[\(offset+1)])\n"
            case 3:
                header += "#define \(param.name) float3(params[\(offset)], params[\(offset+1)], params[\(offset+2)])\n"
            case 4:
                header += "#define \(param.name) float4(params[\(offset)], params[\(offset+1)], params[\(offset+2)], params[\(offset+3)])\n"
            default:
                break
            }
            offset += param.type.componentCount
        }
        header += "// === End User Parameters ===\n\n"
        return header
    }
    
    /// Injects `constant float *params [[buffer(2)]]` into vertex_main and
    /// fragment_main function signatures when user params are present.
    static func injectParamsBuffer(into code: String, paramCount: Int) -> String {
        guard paramCount > 0 else { return code }
        var result = code
        let injection = ",\n                             constant float *params [[buffer(2)]]"
        // Use lazy [\s\S]*? to correctly skip nested parens inside [[buffer(N)]],
        // anchoring on the `) {` that closes the function signature.
        let pattern = #"((vertex_main|fragment_main)\s*\([\s\S]*?)\)\s*\{"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                let fullRange = match.range
                let innerRange = match.range(at: 1)
                let inner = nsResult.substring(with: innerRange)
                if inner.contains("buffer(2)") { continue }
                let replacement = inner + injection + ") {"
                result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }
        return result
    }
    
    /// Injects `constant float *params` into the 2D distort_main function signature.
    /// Unlike fragment shaders which use [[buffer(2)]], distort_main is a regular function
    /// called by the system vertex_main, so we just add a plain parameter.
    static func inject2DVertexParamsBuffer(into code: String, paramCount: Int) -> String {
        guard paramCount > 0 else { return code }
        let pattern = #"(distort_main\s*\([\s\S]*?)(Uniforms\s+uniforms)\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return code }
        let nsCode = code as NSString
        guard let match = regex.firstMatch(in: code, range: NSRange(location: 0, length: nsCode.length)) else { return code }
        if nsCode.substring(with: match.range).contains("params") { return code }
        let replacement = nsCode.substring(with: match.range(at: 1)) +
                          nsCode.substring(with: match.range(at: 2)) +
                          ", constant float *params)"
        return nsCode.replacingCharacters(in: match.range, with: replacement)
    }

    /// Packs current parameter values into a flat float array for GPU upload.
    /// When `scopeKey` is provided, tries `scopeKey/paramName` first, then
    /// falls back to `paramName` for backward compatibility.
    static func packParamBuffer(params: [ShaderParam], values: [String: [Float]], scopeKey: String = "") -> [Float] {
        var buffer: [Float] = []
        for param in params {
            let vals: [Float]
            if !scopeKey.isEmpty, let scoped = values["\(scopeKey)/\(param.name)"] {
                vals = scoped
            } else {
                vals = values[param.name] ?? param.defaultValue
            }
            for i in 0..<param.type.componentCount {
                buffer.append(i < vals.count ? vals[i] : 0)
            }
        }
        return buffer
    }

    /// Strips VertexIn/VertexOut/Uniforms struct definitions and
    /// #include/using directives from user shader code, so the
    /// auto-generated Data Flow header can be prepended without conflicts.
    static func stripStructDefinitions(from code: String) -> String {
        var result = code
        let structPattern = #"struct\s+(VertexIn|VertexOut|Uniforms)\s*\{[^}]*\}\s*;?"#
        if let regex = try? NSRegularExpression(pattern: structPattern, options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        let linePatterns = [
            #"^\s*#include\s+<metal_stdlib>\s*$"#,
            #"^\s*using\s+namespace\s+metal\s*;\s*$"#,
        ]
        for pattern in linePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result
    }

    // MARK: - Default Shaders (Fallbacks)

    /// Default fragment shader: basic directional lighting.
    /// Used when no user fragment shader layer is active.
    /// Struct definitions are omitted — the shared header is prepended at compile time.
    static let defaultFragment = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
        float intensity = max(0.2, dot(in.normalOS, lightDir));
        return float4(float3(0.5) * intensity, 1.0);
    }
    """

    /// Blit shader: renders a fullscreen triangle that samples from a texture.
    /// Used for two purposes:
    /// 1. Final pass: copies the composited result to the screen drawable
    /// 2. Background: draws the user's background image behind the mesh
    ///
    /// The fullscreen triangle technique uses 3 vertices to cover the entire
    /// screen without needing a quad (4 vertices + 2 triangles). The triangle
    /// extends beyond the viewport and is clipped by the GPU automatically.
    static let blitShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        // Flip Y since Metal texture coordinates are top-left
        out.texCoord.y = 1.0 - out.texCoord.y;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        return inTexture.sample(s, in.texCoord);
    }
    """

    // MARK: - Demo Shaders (New Layer Defaults)

    /// Demo fragment shader: time-animated rainbow colors with directional lighting.
    /// Applied when the user creates a new Fragment Layer.
    /// Struct definitions omitted — shared header is prepended at compile time.
    static let fragmentDemo = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float r = 0.5 + 0.5 * cos(in.time + in.normalOS.x * 5.0);
        float g = 0.5 + 0.5 * cos(in.time + in.normalOS.y * 5.0 + 2.0);
        float b = 0.5 + 0.5 * cos(in.time + in.normalOS.z * 5.0 + 4.0);
        
        float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
        float intensity = max(0.3, dot(in.normalOS, lightDir));
        
        return float4(float3(r, g, b) * intensity, 1.0);
    }
    """

    /// Demo fullscreen shader: psychedelic concentric ripple effect.
    /// Applied when the user creates a new Fullscreen (Post-Processing) Layer.
    static let fullscreenDemo = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        // Generate a fullscreen triangle covering the screen
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        // Flip Y to sample the previous pass texture correctly
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        
        float2 uv = in.texCoord;
        
        // Read the output from the previous pass
        float4 baseColor = inTexture.sample(s, uv);
        
        float d = length(uv - 0.5);
        
        // Psychedelic concentric ripple effect as a filter
        float c = sin(d * 40.0 - in.time * 5.0) * 0.5 + 0.5;
        
        // Overlaid color variation
        float r = sin(uv.x * 10.0 + in.time) * 0.5 + 0.5;
        float g = cos(uv.y * 10.0 - in.time) * 0.5 + 0.5;
        
        float4 effectColor = float4(c * r, c * g, 1.0 - c, 1.0);
        
        // Blend the original image with the fullscreen effect
        return mix(baseColor, effectColor, 0.4);
    }
    """

    /// Demo vertex shader is now generated dynamically by generateVertexDemo(config:)
    /// to match the current Data Flow configuration.

    // MARK: - Shading Model Presets (Fragment Shader)

    /// Names of all available fragment shader presets.
    /// Displayed as buttons in the ShaderEditorView preset bar.
    static let shadingModelNames = [
        "Lambert", "Half Lambert", "NdotL", "Phong", "Blinn-Phong",
        "Fresnel", "Rim Light", "Cel/Toon", "Gooch", "Minnaert"
    ]

    /// Looks up a fragment shader preset by name.
    /// Returns nil if the name doesn't match any preset.
    static func shadingModel(named name: String) -> String? {
        switch name {
        case "Lambert":      return lambertShading
        case "Half Lambert":  return halfLambertShading
        case "NdotL":        return ndotlShading
        case "Phong":        return phongShading
        case "Blinn-Phong":  return blinnPhongShading
        case "Fresnel":      return fresnelShading
        case "Rim Light":    return rimLightShading
        case "Cel/Toon":     return celShading
        case "Gooch":        return goochShading
        case "Minnaert":     return minnaertShading
        default: return nil
        }
    }

    static let lambertShading = """
    // Lambert Diffuse — the simplest physically-based diffuse model.
    // Intensity = max(0, dot(N, L))
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        
        float3 baseColor = float3(0.8, 0.3, 0.2);
        float diffuse = max(0.0, dot(N, L));
        float ambient = 0.1;
        
        float3 color = baseColor * (ambient + diffuse);
        return float4(color, 1.0);
    }
    """

    static let halfLambertShading = """
    // Half Lambert — Valve's technique from Half-Life.
    // Wraps lighting around the object to avoid harsh dark areas.
    // HalfLambert = (dot(N,L) * 0.5 + 0.5)^2
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        
        float3 baseColor = float3(0.7, 0.5, 0.3);
        float halfLambert = dot(N, L) * 0.5 + 0.5;
        halfLambert *= halfLambert;
        
        float3 color = baseColor * halfLambert;
        return float4(color, 1.0);
    }
    """

    static let ndotlShading = """
    // N dot L — raw dot product visualization.
    // Shows how light angle affects surface brightness.
    // Useful as a building block for more complex models.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(sin(in.time), 1.0, cos(in.time)));
        
        float NdotL = dot(N, L);
        
        // Visualize: red = facing light, blue = facing away
        float3 color = mix(float3(0.1, 0.1, 0.6),
                           float3(1.0, 0.3, 0.1),
                           NdotL * 0.5 + 0.5);
        return float4(color, 1.0);
    }
    """

    static let phongShading = """
    // Phong Reflection Model — ambient + diffuse + specular.
    // Specular uses the reflection vector: R = reflect(-L, N)
    // Shininess exponent controls highlight tightness.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 R = reflect(-L, N);
        
        float3 baseColor = float3(0.2, 0.5, 0.8);
        float ambient = 0.1;
        float diffuse = max(0.0, dot(N, L));
        float specular = pow(max(0.0, dot(R, V)), 32.0);
        
        float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
        return float4(color, 1.0);
    }
    """

    static let blinnPhongShading = """
    // Blinn-Phong — more efficient than Phong, used widely in real-time.
    // Uses the half vector H = normalize(L + V) instead of reflection.
    // Specular = pow(max(0, dot(N, H)), shininess)
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 H = normalize(L + V);
        
        float3 baseColor = float3(0.3, 0.6, 0.9);
        float ambient = 0.1;
        float diffuse = max(0.0, dot(N, L));
        float specular = pow(max(0.0, dot(N, H)), 64.0);
        
        float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
        return float4(color, 1.0);
    }
    """

    static let fresnelShading = """
    // Fresnel Effect — surfaces facing away from camera appear brighter.
    // Approximation: fresnel = pow(1 - dot(N, V), exponent)
    // Used in glass, water, energy shields, rim highlights, etc.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        
        float fresnel = pow(1.0 - max(0.0, dot(N, V)), 3.0);
        float diffuse = max(0.0, dot(N, L));
        
        float3 baseColor = float3(0.1, 0.1, 0.2);
        float3 rimColor = float3(0.3, 0.6, 1.0);
        
        float3 color = baseColor * (0.1 + diffuse) + rimColor * fresnel;
        return float4(color, 1.0);
    }
    """

    static let rimLightShading = """
    // Rim Lighting — highlights the silhouette edges of the object.
    // Combines diffuse with a fresnel-based rim term.
    // Great for character outlines, hologram effects, atmosphere.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        
        float diffuse = max(0.0, dot(N, L));
        float rim = 1.0 - max(0.0, dot(N, V));
        rim = pow(rim, 2.5);
        
        float3 baseColor = float3(0.4, 0.2, 0.6) * (0.15 + diffuse);
        float3 rimColor = float3(1.0, 0.5, 0.8) * rim;
        
        return float4(baseColor + rimColor, 1.0);
    }
    """

    static let celShading = """
    // Cel / Toon Shading — quantizes light into discrete bands.
    // Creates a cartoon / anime look with hard light transitions.
    // Adjust the step thresholds to control the number of bands.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        
        float NdotL = dot(N, L);
        
        // Quantize into 3 bands
        float toon;
        if (NdotL > 0.6)       toon = 1.0;
        else if (NdotL > 0.2)  toon = 0.6;
        else if (NdotL > -0.1) toon = 0.35;
        else                    toon = 0.15;
        
        float3 baseColor = float3(0.9, 0.4, 0.3);
        
        // Rim outline
        float rim = 1.0 - max(0.0, dot(N, V));
        float outline = step(0.65, rim);
        
        float3 color = baseColor * toon * (1.0 - outline * 0.7);
        return float4(color, 1.0);
    }
    """

    static let goochShading = """
    // Gooch Shading — warm/cool non-photorealistic model.
    // Replaces dark shadows with cool blue and bright areas with warm yellow.
    // Originally designed for technical illustration rendering.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        
        float3 baseColor = float3(0.6, 0.3, 0.2);
        float3 coolColor = float3(0.0, 0.0, 0.55) + 0.25 * baseColor;
        float3 warmColor = float3(0.55, 0.45, 0.0) + 0.25 * baseColor;
        
        float t = (dot(N, L) + 1.0) * 0.5;
        float3 color = mix(coolColor, warmColor, t);
        
        // Add subtle specular highlight
        float3 R = reflect(-L, N);
        float specular = pow(max(0.0, dot(R, V)), 24.0);
        color += float3(1.0) * specular * 0.5;
        
        return float4(color, 1.0);
    }
    """

    static let minnaertShading = """
    // Minnaert Shading — models the limb-darkening effect.
    // Originally developed for rendering the Moon's surface.
    // Controls how edges darken relative to the view angle.
    // 'darkness' parameter: 1.0 = Lambert, >1.0 = darker edges.
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        
        float NdotL = max(0.0, dot(N, L));
        float NdotV = max(0.0, dot(N, V));
        float darkness = 1.5;
        
        float minnaert = NdotL * pow(NdotL * NdotV, darkness - 1.0);
        
        float3 baseColor = float3(0.75, 0.7, 0.6);
        float3 color = baseColor * (0.05 + minnaert);
        return float4(color, 1.0);
    }
    """

    // MARK: - Educational Templates (shown after reset)

    /// Vertex template is now generated dynamically by generateVertexTemplate(config:)
    /// to match the current Data Flow configuration.

    /// Educational fragment shader template.
    /// Struct definitions are omitted — the shared header is prepended at compile time.
    static let fragmentTemplate = """
    // ============================================================
    // FRAGMENT SHADER
    // ============================================================
    // VertexOut fields are managed by the Data Flow panel.
    // Available fields depend on your configuration (e.g. normalOS, uv, time, positionWS...).
    //
    // Common techniques: lighting, texturing, color effects,
    // cel shading, rim lighting, fresnel, etc.
    // ============================================================

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {

        // Basic directional lighting example:
        // float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
        // float diffuse = max(0.2, dot(in.normalOS, lightDir));
        // return float4(float3(diffuse), 1.0);

        return float4(1.0, 1.0, 1.0, 1.0);
    }
    """

    /// Educational post-processing shader template with extensive inline comments.
    static let fullscreenTemplate = """
    // ============================================================
    // POST-PROCESSING SHADER TEMPLATE
    // ============================================================
    // A fullscreen (post-processing) shader applies effects to
    // the entire rendered image AFTER the mesh has been drawn.
    //
    // It reads the previous frame via `inTexture`, processes it,
    // and outputs a new color. Multiple post-processing shaders
    // are chained together (ping-pong rendering).
    //
    // Common effects: blur, bloom, vignette, color grading,
    // chromatic aberration, edge detection, pixelation, etc.
    // ============================================================

    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;   // UV in range [0,1], covering the full screen
        float time;        // Animation time from CPU
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    // --- Fullscreen Triangle Vertex Shader ---
    // Generates a single triangle that covers the entire screen.
    // This is a standard technique — you usually don't need to modify this.
    // [[vertex_id]] gives the index of the current vertex (0, 1, or 2).
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;  // Flip Y for Metal's coordinate system
        out.time = uniforms.time;
        return out;
    }

    // --- Post-Processing Fragment Shader ---
    // [[texture(0)]] = the rendered scene (or output of previous post-process pass)
    // Sample it with `inTexture.sample(sampler, uv)` to read pixel colors.
    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.texCoord;

        // Read the base color from the previous pass
        float4 baseColor = inTexture.sample(s, uv);

        // --- Your effect goes here! ---
        // Example — grayscale:
        //   float gray = dot(baseColor.rgb, float3(0.299, 0.587, 0.114));
        //   return float4(float3(gray), 1.0);
        //
        // Example — vignette:
        //   float d = length(uv - 0.5);
        //   float vignette = smoothstep(0.7, 0.3, d);
        //   return baseColor * vignette;

        return baseColor;
    }
    """

    // MARK: - Post Processing Presets (Fullscreen Shader)

    /// Names of all available post-processing presets.
    static let ppPresetNames = [
        "Bloom", "Gaussian Blur", "HSV Adjustment", "Tone Mapping", "Edge Detection"
    ]

    /// Looks up a post-processing preset by name.
    static func ppPreset(named name: String) -> String? {
        switch name {
        case "Bloom":            return ppBloom
        case "Gaussian Blur":    return ppGaussianBlur
        case "HSV Adjustment":   return ppHSVAdjustment
        case "Tone Mapping":     return ppToneMapping
        case "Edge Detection":   return ppEdgeDetection
        default: return nil
        }
    }

    static let ppBloom = """
    // @param _threshold float 0.6 0.0 1.0
    // @param _knee float 0.3 0.0 1.0
    // @param _bloomIntensity float 0.7 0.0 2.0
    // @param _blurRadius float 2.0 0.5 6.0
    // Bloom — soft-threshold extraction + Gaussian blur + additive blend.
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float2 uv = in.texCoord;
        float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());

        float4 baseColor = inTexture.sample(s, uv);

        const int HALF = 6;
        float gw[7] = { 0.1964, 0.1748, 0.1226, 0.0677, 0.0294, 0.0101, 0.0027 };

        float4 bloom = float4(0.0);
        float wSum = 0.0;

        for (int dy = -HALF; dy <= HALF; dy++) {
            float wy = gw[abs(dy)];
            for (int dx = -HALF; dx <= HALF; dx++) {
                if (abs(dx) + abs(dy) > HALF + 2) continue;
                float wx = gw[abs(dx)];
                float w = wx * wy;

                float2 offset = float2(float(dx), float(dy)) * texelSize * _blurRadius;
                float4 sc = inTexture.sample(s, uv + offset);
                float lum = dot(sc.rgb, float3(0.2126, 0.7152, 0.0722));

                float bright = smoothstep(_threshold - _knee, _threshold + _knee, lum);

                bloom += sc * bright * w;
                wSum += w;
            }
        }

        bloom /= wSum;

        return baseColor + bloom * _bloomIntensity;
    }
    """

    static let ppGaussianBlur = """
    // @param _blurScale float 2.0 0.5 8.0
    // Gaussian Blur — proper 2D Gaussian kernel.
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float2 uv = in.texCoord;
        float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());

        const int HALF = 6;
        float w[7] = { 0.1964, 0.1748, 0.1226, 0.0677, 0.0294, 0.0101, 0.0027 };

        float4 color = float4(0.0);
        float totalW = 0.0;
        for (int dy = -HALF; dy <= HALF; dy++) {
            float wy = w[abs(dy)];
            for (int dx = -HALF; dx <= HALF; dx++) {
                if (abs(dx) + abs(dy) > HALF + 2) continue;
                float wx = w[abs(dx)];
                float weight = wx * wy;
                float2 offset = float2(float(dx), float(dy)) * texelSize * _blurScale;
                color += inTexture.sample(s, uv + offset) * weight;
                totalW += weight;
            }
        }

        return color / totalW;
    }
    """

    static let ppHSVAdjustment = """
    // @param _hueShift float 0.05 0.0 1.0
    // @param _saturation float 1.3 0.0 3.0
    // @param _brightness float 1.05 0.0 2.0
    // HSV Adjustment — converts RGB to HSV, adjusts hue/saturation/value, converts back.
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    float3 rgb2hsv(float3 c) {
        float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
        float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
    }

    float3 hsv2rgb(float3 c) {
        float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
        float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float4 baseColor = inTexture.sample(s, in.texCoord);

        float3 hsv = rgb2hsv(baseColor.rgb);
        hsv.x = fract(hsv.x + _hueShift);
        hsv.y = clamp(hsv.y * _saturation, 0.0, 1.0);
        hsv.z = clamp(hsv.z * _brightness, 0.0, 1.0);
        float3 rgb = hsv2rgb(hsv);

        return float4(rgb, baseColor.a);
    }
    """

    static let ppToneMapping = """
    // @param _exposure float 1.5 0.1 5.0
    // @param _gamma float 0.455 0.1 2.0
    // @param _vignetteOuter float 0.8 0.3 1.5
    // @param _vignetteInner float 0.35 0.0 1.0
    // Tone Mapping — ACES filmic curve + gamma correction + vignette.
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    float3 acesFilm(float3 x) {
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float4 baseColor = inTexture.sample(s, in.texCoord);

        float3 hdr = baseColor.rgb * _exposure;
        float3 mapped = acesFilm(hdr);
        mapped = pow(mapped, float3(_gamma));

        float d = length(in.texCoord - 0.5);
        float vignette = smoothstep(_vignetteOuter, _vignetteInner, d);
        mapped *= vignette;

        return float4(mapped, 1.0);
    }
    """

    static let ppEdgeDetection = """
    // @param _edgeThreshold float 0.15 0.0 1.0
    // @param _edgeStrength float 0.85 0.0 1.0
    // @param _edgeColor color 1.0 0.9 0.7
    // Edge Detection — Sobel operator for outlines and stylized rendering.
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
        float mouseX;
        float mouseY;
        float _pad;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    float luminance(float3 c) {
        return dot(c, float3(0.2126, 0.7152, 0.0722));
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float2 uv = in.texCoord;
        float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());

        float tl = luminance(inTexture.sample(s, uv + float2(-1, -1) * texelSize).rgb);
        float tm = luminance(inTexture.sample(s, uv + float2( 0, -1) * texelSize).rgb);
        float tr = luminance(inTexture.sample(s, uv + float2( 1, -1) * texelSize).rgb);
        float ml = luminance(inTexture.sample(s, uv + float2(-1,  0) * texelSize).rgb);
        float mr = luminance(inTexture.sample(s, uv + float2( 1,  0) * texelSize).rgb);
        float bl = luminance(inTexture.sample(s, uv + float2(-1,  1) * texelSize).rgb);
        float bm = luminance(inTexture.sample(s, uv + float2( 0,  1) * texelSize).rgb);
        float br = luminance(inTexture.sample(s, uv + float2( 1,  1) * texelSize).rgb);

        float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
        float gy = -tl - 2.0*tm - tr + bl + 2.0*bm + br;

        float edge = sqrt(gx*gx + gy*gy);
        edge = smoothstep(_edgeThreshold, _edgeThreshold + 0.1, edge);

        float4 baseColor = inTexture.sample(s, uv);
        float3 result = mix(baseColor.rgb, _edgeColor, edge * _edgeStrength);

        return float4(result, 1.0);
    }
    """

    // MARK: - 2D Canvas Mode

    /// MSL header for 2D canvas shaders.
    /// Generates VertexOut dynamically based on DataFlow2DConfig, plus fixed
    /// Uniforms and Transform2D structs.
    static func generateSharedHeader2D(config: DataFlow2DConfig = DataFlow2DConfig()) -> String {
        var header = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
            float  shapeAspect;
            float  cornerRadius;
        """
        if config.timeEnabled           { header += "\n    float  time;" }
        if config.mouseEnabled           { header += "\n    float2 mouse;" }
        if config.objectPositionEnabled  { header += "\n    float2 objectPosition;" }
        if config.screenUVEnabled        { header += "\n    float2 screenUV;" }
        header += """

        };

        struct Uniforms {
            float2 resolution;
            float  time;
            float  mouseX;
            float  mouseY;
            float  _pad;
        };

        struct Transform2D {
            float2 objectOffset;
            float2 objectScale;
            float2 canvasPan;
            float  canvasZoom;
            float  objectRotation;
            float  cornerRadius;
        };

        """
        return header
    }

    /// Grid background shader for 2D canvas mode (Unity-style graph view grid).
    static let gridShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct Uniforms {
        float2 resolution;
        float  time;
        float  mouseX;
        float  mouseY;
        float  _pad;
    };

    struct Transform2D {
        float2 objectOffset;
        float2 objectScale;
        float2 canvasPan;
        float  canvasZoom;
        float  objectRotation;
        float  cornerRadius;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Transform2D &transform [[buffer(3)]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        float2 uv = positions[vertexID] * 0.5 + 0.5;
        uv.y = 1.0 - uv.y;
        // Apply inverse camera so the grid scrolls with pan/zoom
        uv = (uv - 0.5) / transform.canvasZoom + 0.5 + transform.canvasPan * 0.5;
        out.texCoord = uv;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
        float2 uv = in.texCoord;
        float aspect = uniforms.resolution.x / uniforms.resolution.y;
        float2 coord = float2(uv.x * aspect, uv.y) * 50.0;

        float2 grid = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
        float minorLine = min(grid.x, grid.y);

        float2 majorCoord = coord / 5.0;
        float2 majorGrid = abs(fract(majorCoord - 0.5) - 0.5) / fwidth(majorCoord);
        float majorLine = min(majorGrid.x, majorGrid.y);

        float3 bg = float3(0.118, 0.118, 0.137);
        float3 minorColor = float3(0.196, 0.196, 0.220);
        float3 majorColor = float3(0.275, 0.275, 0.314);

        float3 color = bg;
        color = mix(minorColor, color, clamp(minorLine, 0.0, 1.0));
        color = mix(majorColor, color, clamp(majorLine, 0.0, 1.0));
        return float4(color, 1.0);
    }
    """

    /// Returns the SDF function body for a given 2D shape.
    /// All SDFs operate in aspect-corrected space so that curved features
    /// (rounded corners, circles) remain circular on screen regardless of
    /// the quad's width/height ratio or per-object scaleW/scaleH.
    /// The `aspect` parameter is the runtime screen-space aspect ratio.
    static func sdfFunction(for shape: Shape2DType) -> String {
        switch shape {
        case .rectangle:
            return """
                float2 q = (uv - 0.5) * float2(aspect, 1.0);
                float2 d = abs(q) - float2(aspect * 0.5, 0.5);
                return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
            """
        case .roundedRectangle:
            return """
                float2 q = (uv - 0.5) * float2(aspect, 1.0);
                float2 hs = float2(aspect * 0.5, 0.5);
                float r = clamp(cornerR, 0.001, min(hs.x, hs.y));
                float2 d = abs(q) - (hs - r);
                float2 c = max(d, 0.0) / r;
                float2 c2 = c * c;
                float2 c4 = c2 * c2;
                float lp = sqrt(sqrt(c4.x + c4.y));
                return (lp - 1.0) * r + min(max(d.x, d.y), 0.0);
            """
        case .circle:
            return """
                float2 q = (uv - 0.5) * float2(aspect, 1.0);
                float minHalf = min(aspect * 0.5, 0.5);
                return length(q) - minHalf;
            """
        case .capsule:
            return """
                float2 p = uv - 0.5;
                float2 q = float2(p.x * aspect, p.y);
                float halfLen = max(0.0, aspect * 0.5 - 0.5);
                q.x = max(abs(q.x) - halfLen, 0.0);
                return length(q) - 0.5;
            """
        }
    }

    /// Generates the system vertex_main that calls the user's `distort_main`
    /// and then applies object transform + canvas camera.
    /// Populates Data Flow fields based on the 2D config.
    static func generate2DVertexWrapper(shape: Shape2DType, config: DataFlow2DConfig = DataFlow2DConfig(), hasParams: Bool = false) -> String {
        let sa = shape.quadAspect
        let paramsArg = hasParams ? ",\n                                     constant float *params [[buffer(2)]]" : ""
        let paramsForward = hasParams ? ", params" : ""
        var fn = """
        vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                     constant Uniforms &uniforms [[buffer(1)]]\(paramsArg),
                                     constant Transform2D &transform [[buffer(3)]]) {
            float halfW = 0.5 * \(sa);
            float2 localPositions[6] = {
                float2(-halfW, -0.5), float2( halfW, -0.5), float2(-halfW,  0.5),
                float2(-halfW,  0.5), float2( halfW, -0.5), float2( halfW,  0.5)
            };
            float2 uvs[6] = {
                float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0)
            };

            float2 localPos = localPositions[vertexID];
            float2 uv = uvs[vertexID];

            float2 distorted = distort_main(localPos, uv, uniforms\(paramsForward));

            float2 pos = distorted * transform.objectScale;

            float viewAspect = uniforms.resolution.x / uniforms.resolution.y;
            pos.x *= viewAspect;
            float c = cos(transform.objectRotation);
            float s = sin(transform.objectRotation);
            pos = float2(pos.x * c - pos.y * s, pos.x * s + pos.y * c);
            pos.x /= viewAspect;

            pos += transform.objectOffset;

            pos = (pos - transform.canvasPan) * transform.canvasZoom;

            VertexOut out;
            out.position = float4(pos, 0.0, 1.0);
            out.texCoord = uv;
            out.shapeAspect = \(sa) * transform.objectScale.x / transform.objectScale.y
                             * viewAspect;
            out.cornerRadius = transform.cornerRadius;
        """
        if config.timeEnabled {
            fn += "\n        out.time = uniforms.time;"
        }
        if config.mouseEnabled {
            fn += "\n        out.mouse = float2(uniforms.mouseX, uniforms.mouseY);"
        }
        if config.objectPositionEnabled {
            fn += "\n        out.objectPosition = transform.objectOffset;"
        }
        if config.screenUVEnabled {
            fn += "\n        out.screenUV = pos * 0.5 + 0.5;"
            fn += "\n        out.screenUV.y = 1.0 - out.screenUV.y;"
        }
        fn += "\n        return out;\n    }\n"
        return fn
    }

    /// Wraps the user's fragment_main with SDF shape masking.
    /// The user's function is renamed to `_user_fragment` (a regular function)
    /// and a new entry-point `fragment_main` calls it, then applies the SDF alpha mask.
    ///
    /// If the user's code references `bgTexture`, the background texture is passed
    /// through to `_user_fragment` so it can sample the canvas behind the object.
    ///
    /// When `sdfAccessEnabled` is true, `_sdf_shape()` is defined **before** the
    /// user's code so it can be called from `_user_fragment`. This is gated behind
    /// the shape-lock feature: the object's shape must be locked before the AI can
    /// generate code that references `_sdf_shape()`.
    static func wrapFragmentWithSDF(userCode: String, shape: Shape2DType, hasParams: Bool, sdfAccessEnabled: Bool = false) -> String {
        let usesBgTexture = userCode.contains("bgTexture")

        var code = userCode
        if let regex = try? NSRegularExpression(
            pattern: #"fragment\s+(float4|half4)\s+fragment_main\s*\("#,
            options: []
        ) {
            let range = NSRange(code.startIndex..., in: code)
            code = regex.stringByReplacingMatches(in: code, range: range,
                                                   withTemplate: "$1 _user_fragment(")
        }
        code = code
            .replacingOccurrences(of: "[[stage_in]]", with: "")
            .replacingOccurrences(of: "[[buffer(1)]]", with: "")
            .replacingOccurrences(of: "[[buffer(2)]]", with: "")
            .replacingOccurrences(of: "[[texture(0)]]", with: "")

        // Inject params as the LAST parameter of _user_fragment so the call
        // argument order is always: (in, uniforms, [bgTexture], params).
        // This avoids a type-mismatch when the AI's code declares bgTexture
        // before the injected params buffer.
        if hasParams,
           let funcRegex = try? NSRegularExpression(pattern: #"(_user_fragment\s*\([^)]*)"#) {
            let nsCode = code as NSString
            if let match = funcRegex.firstMatch(in: code, range: NSRange(location: 0, length: nsCode.length)) {
                let captured = nsCode.substring(with: match.range(at: 1))
                if !captured.contains("params") {
                    code = nsCode.replacingCharacters(
                        in: match.range(at: 1),
                        with: captured + ", constant float *params"
                    )
                }
            }
        }

        let sdfBody = sdfFunction(for: shape)
        let sdfFunc = """

        float _sdf_shape(float2 uv, float aspect, float cornerR) {
            \(sdfBody)
        }

        """

        if sdfAccessEnabled {
            code = sdfFunc + code
        } else {
            code += sdfFunc
        }

        // Build the wrapper's parameter list and the call arguments.
        // bgTexture is always declared (since the renderer always binds it),
        // but only forwarded to _user_fragment if the user's code references it.
        // Call order MUST match _user_fragment's declaration:
        //   (in, uniforms, [bgTexture], [params])
        var wrapperParams = "VertexOut in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]"
        var callArgs = "in, uniforms"
        if usesBgTexture {
            callArgs += ", bgTexture"
        }
        if hasParams {
            wrapperParams += ", constant float *params [[buffer(2)]]"
            callArgs += ", params"
        }
        wrapperParams += ", texture2d<float> bgTexture [[texture(0)]]"

        code += """
            fragment float4 fragment_main(\(wrapperParams)) {
                float4 col = _user_fragment(\(callArgs));
                float d = _sdf_shape(in.texCoord, in.shapeAspect, in.cornerRadius);
                float aa = fwidth(d);
                col.a *= 1.0 - smoothstep(0.0, aa, d);
                return col;
            }
            """
        return code
    }

    // MARK: 2D Shader Templates

    /// Demo 2D distortion (vertex) shader — gentle wave effect.
    static let distortion2DDemo = """
    // 2D DISTORTION (VERTEX) SHADER
    // position: shape-local coords, uv: [0,1], return distorted position.
    float2 distort_main(float2 position, float2 uv, Uniforms uniforms) {
        position.x += sin(uv.y * 18.0 + uniforms.time * 3.0) * 0.015;
        position.y += cos(uv.x * 14.0 + uniforms.time * 2.0) * 0.010;
        return position;
    }
    """

    /// Identity distortion template — no-op, with documentation.
    static let distortion2DTemplate = """
    // ============================================================
    // 2D DISTORTION (VERTEX) SHADER
    // ============================================================
    // Receives each vertex in shape-local space and returns a new position.
    // The system then applies object transform + canvas camera.
    //
    //   position — vertex coord (shape-local, ~[-0.5, 0.5])
    //   uv       — texture coordinate [0,1]
    //   uniforms — .time, .resolution, .mouseX/Y
    // ============================================================
    float2 distort_main(float2 position, float2 uv, Uniforms uniforms) {
        return position;
    }
    """

    /// Demo 2D fragment shader — UI-style animated gradient button.
    static let fragment2DDemo = """
    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
        float2 uv = in.texCoord;
        float t = uniforms.time;

        float3 topCol    = float3(0.25, 0.55, 1.0);
        float3 bottomCol = float3(0.10, 0.30, 0.75);
        float3 col = mix(bottomCol, topCol, uv.y);

        float wave = sin(uv.x * 12.0 - t * 3.0) * 0.5 + 0.5;
        col += wave * 0.08;

        float2 p = uv - 0.5;
        float edgeDist = max(abs(p.x), abs(p.y));
        float innerGlow = smoothstep(0.48, 0.42, edgeDist);
        col = mix(col + 0.15, col, innerGlow);

        float specular = smoothstep(0.85, 1.0, uv.y) * 0.25;
        col += specular;

        return float4(col, 1.0);
    }
    """

    /// Educational 2D fragment shader template.
    static let fragment2DTemplate = """
    // ============================================================
    // 2D SHAPE FRAGMENT SHADER (Color Effect)
    // ============================================================
    // Defines the shape's surface colour. SDF edge clipping is automatic.
    //
    //   in.texCoord          — shape-local UV [0,1]
    //   uniforms.resolution  — viewport size (float2)
    //   uniforms.time        — elapsed seconds
    //   uniforms.mouseX/Y    — cursor [0,1] (screen-space)
    //
    // BACKGROUND SAMPLING (optional):
    //   Add "texture2d<float> bgTexture [[texture(0)]]" as a parameter
    //   to sample the canvas behind this object (grid + previous objects).
    //   Use screen-space UVs for correct sampling:
    //     float2 screenUV = float2(in.position.xy) / uniforms.resolution;
    //     float4 bg = bgTexture.sample(sampler(filter::linear), screenUV);
    // ============================================================
    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
        float2 uv = in.texCoord;
        return float4(uv, 0.5 + 0.5 * sin(uniforms.time), 1.0);
    }
    """
}
