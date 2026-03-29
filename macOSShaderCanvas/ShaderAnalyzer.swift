//
//  ShaderAnalyzer.swift
//  macOSShaderCanvas
//
//  Static analysis engine that extracts semantic meaning from MSL shader code.
//
//  This gives the AI Agent "engineering touch" — instead of seeing raw code text,
//  it receives structured understanding of what a shader *does*: which effects it
//  implements, which uniforms it depends on, and how complex it is.
//
//  All analysis is pure regex/string scanning — no compiler integration needed.
//  The output (ShaderSemantics) is injected into the AI context alongside the
//  raw code so the LLM can reason about intent, not just syntax.
//

import Foundation

struct ShaderAnalyzer {

    // MARK: - Public API

    /// Analyze a shader's MSL source and produce a structured semantic summary.
    static func analyze(code: String, category: ShaderCategory) -> ShaderSemantics {
        let lines = code.components(separatedBy: .newlines)
        let lc = lines.count
        let lower = code.lowercased()

        let tags = detectEffectTags(code: lower, category: category)
        let uniforms = detectUsedUniforms(code: code)
        let sources = detectSampledSources(code: code)
        let complexity = classifyComplexity(lineCount: lc, tagCount: tags.count)
        let temporal = analyzeTemporalBehavior(code: code)
        let summary = buildSummary(tags: tags, category: category, uniforms: uniforms, sources: sources)

        return ShaderSemantics(
            effectTags: tags, summary: summary, usedUniforms: Array(uniforms),
            sampledSources: sources, complexity: complexity, lineCount: lc,
            temporalBehavior: temporal
        )
    }

    // MARK: - Effect Tag Detection

    private static let effectPatterns: [(tag: String, patterns: [String])] = [
        // Noise
        ("perlin_noise",      ["perlin", "pnoise", "simplex"]),
        ("fbm_noise",         ["fbm", "fractal_brownian", "octave"]),
        ("value_noise",       ["value_noise", "hash(", "hash2(", "hash3("]),
        ("voronoi",           ["voronoi", "worley", "cellular"]),

        // Lighting models
        ("lambert",           ["dot(n", "dot(normal", "n_dot_l", "ndotl", "lambert"]),
        ("phong",             ["phong", "specular", "pow(", "shininess"]),
        ("blinn_phong",       ["blinn", "half_dir", "halfdir", "halfway"]),
        ("toon_shading",      ["step(", "smoothstep(", "ceil(", "floor(", "toon", "cel"]),
        ("pbr",               ["metallic", "roughness", "brdf", "fresnel", "f0", "ggx", "cook_torrance", "schlick"]),
        ("gooch",             ["gooch", "warm", "cool"]),
        ("fresnel",           ["fresnel", "pow(1.0 - ", "pow(1. - ", "rim_light", "rimlight"]),

        // SDF operations
        ("sdf",               ["sdsphere", "sdbox", "sdcircle", "sdroundedbox", "sdrect"]),
        ("sdf_boolean",       ["opunion", "opintersect", "opsubtract", "opsmoothunion", "min(d1", "min(d2", "max(d1"]),
        ("sdf_transform",     ["oprepeat", "optwist", "opbend"]),
        ("raymarching",       ["raymarch", "ray_march", "sphere_trace", "sdscene"]),

        // Color operations
        ("gradient",          ["mix(", "lerp(", "gradient", "ramp"]),
        ("color_grading",     ["contrast", "saturation", "brightness", "gamma", "tonemap", "aces"]),
        ("hue_shift",         ["hue", "hsv", "hsl", "rgb2hsv", "hsv2rgb"]),

        // Vertex deformation
        ("displacement",      ["displace", "displacement", "offset", "deform"]),
        ("wave",              ["sin(", "cos(", "wave"]),
        ("twist",             ["twist", "rotate", "atan2("]),
        ("morph",             ["morph", "blend", "interpolat"]),

        // Post-processing
        ("blur",              ["blur", "gaussian", "kernel", "convol"]),
        ("bloom",             ["bloom", "glow", "bright_pass", "brightpass", "threshold"]),
        ("vignette",          ["vignette", "vignette_strength"]),
        ("edge_detection",    ["sobel", "laplacian", "edge_detect", "edgedetect", "outline"]),
        ("distortion",        ["distort", "warp", "ripple", "refract"]),
        ("chromatic_aberration", ["chromatic", "aberration", "rgb_split"]),
        ("crt_effect",        ["scanline", "crt", "retro", "curvature"]),
        ("glitch",            ["glitch", "artifact", "corruption", "datamosh"]),

        // Animation
        ("animation",         ["time", "uniforms.time", ".time"]),
        ("mouse_interactive", ["mousex", "mousey", "mouse.x", "mouse.y", ".mousex", ".mousey"]),

        // Texture sampling
        ("texture_sample",    ["intexture", "bgtexture", ".sample("]),

        // UV manipulation
        ("uv_scroll",         ["uv +", "uv -", "texcoord +", "texcoord -"]),
        ("uv_polar",          ["atan2(", "length(", "polar"]),
        ("uv_tile",           ["fract(", "fmod(", "repeat", "tile"]),
    ]

    private static func detectEffectTags(code lower: String, category: ShaderCategory) -> [String] {
        var tags = Set<String>()
        for (tag, patterns) in effectPatterns {
            for p in patterns {
                if lower.contains(p) { tags.insert(tag); break }
            }
        }
        switch category {
        case .vertex:    tags.insert("vertex_shader")
        case .fragment:  tags.insert("fragment_shader")
        case .fullscreen: tags.insert("fullscreen_post")
        }
        return tags.sorted()
    }

    // MARK: - Uniform Detection

    private static let uniformNames = [
        "time", "mouseX", "mouseY", "resolution",
        "mvpMatrix", "modelMatrix", "normalMatrix", "cameraPosition",
    ]

    private static func detectUsedUniforms(code: String) -> Set<String> {
        var found = Set<String>()
        for name in uniformNames {
            if code.contains(name) || code.contains(".\(name)") {
                found.insert(name)
            }
        }
        // @param user parameters
        let paramRegex = try? NSRegularExpression(pattern: #"//\s*@param\s+(_\w+)\s+(\w+)"#)
        let range = NSRange(code.startIndex..., in: code)
        if let matches = paramRegex?.matches(in: code, range: range) {
            for m in matches {
                if let r = Range(m.range(at: 1), in: code) {
                    found.insert("param:" + String(code[r]))
                }
            }
        }
        return found
    }

    // MARK: - Sampled Source Detection

    private static func detectSampledSources(code: String) -> [String] {
        var sources = [String]()
        if code.contains("inTexture") || code.contains("intexture") { sources.append("inTexture") }
        if code.contains("bgTexture") || code.contains("bgtexture") { sources.append("bgTexture") }
        return sources
    }

    // MARK: - Complexity Classification

    private static func classifyComplexity(lineCount: Int, tagCount: Int) -> ShaderComplexity {
        if lineCount > 80 || tagCount > 6 { return .complex }
        if lineCount > 30 || tagCount > 3 { return .moderate }
        return .simple
    }

    // MARK: - Temporal Behavior Analysis

    /// Analyzes time-dependent expressions to describe the shader's dynamic behavior.
    ///
    /// Instead of capturing multiple frames (expensive in tokens), we extract precise
    /// mathematical descriptions of *how* the shader changes over time. This gives the
    /// AI a much denser understanding than "4 slightly different screenshots".
    private static func analyzeTemporalBehavior(code: String) -> String? {
        // Quick check: does the shader use time at all?
        let usesTime = code.contains(".time") || code.contains("uniforms.time") ||
                        code.range(of: #"\btime\b"#, options: .regularExpression) != nil
        guard usesTime else { return nil }

        var behaviors = [String]()

        // Detect sin/cos oscillations with time: sin(time * N), cos(time * N + offset)
        let oscRegex = try? NSRegularExpression(pattern: #"(sin|cos)\s*\(\s*(?:uniforms\.)?time\s*\*\s*([\d.]+)"#)
        let range = NSRange(code.startIndex..., in: code)
        var frequencies = Set<String>()
        if let matches = oscRegex?.matches(in: code, range: range) {
            for m in matches {
                let func_ = m.range(at: 1).location != NSNotFound ? String(code[Range(m.range(at: 1), in: code)!]) : "sin"
                let freq = m.range(at: 2).location != NSNotFound ? String(code[Range(m.range(at: 2), in: code)!]) : "1"
                frequencies.insert(freq)
                if let f = Float(freq) {
                    let hz = f / (2 * .pi)
                    behaviors.append("\(func_)(time×\(freq)) oscillation, ~\(String(format: "%.2f", hz))Hz")
                }
            }
        }

        // Detect simple sin(time)/cos(time) without multiplier
        let simpleOscRegex = try? NSRegularExpression(pattern: #"(sin|cos)\s*\(\s*(?:uniforms\.)?time\s*[+\-\)]"#)
        if let matches = simpleOscRegex?.matches(in: code, range: range), !matches.isEmpty, frequencies.isEmpty {
            behaviors.append("oscillation at base frequency (~0.16Hz)")
        }

        // Detect time as UV offset (scrolling): uv + time * vec, texCoord + time
        let scrollPatterns = [
            #"uv\s*[\+\-]\s*(?:float2\s*\()?\s*(?:uniforms\.)?time"#,
            #"texcoord\s*[\+\-]\s*(?:uniforms\.)?time"#,
            #"(?:uniforms\.)?time\s*\*\s*(?:float2|vec2)"#,
        ]
        for pattern in scrollPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: code, range: range) != nil {
                behaviors.append("continuous UV scrolling")
                break
            }
        }

        // Detect fract(time) - repeating sawtooth
        if code.contains("fract(") && usesTime {
            let fractTimeRegex = try? NSRegularExpression(pattern: #"fract\s*\(\s*(?:uniforms\.)?time"#)
            if let m = fractTimeRegex, m.firstMatch(in: code, range: range) != nil {
                behaviors.append("repeating sawtooth cycle via fract(time)")
            }
        }

        // Detect time-modulated color (color changing over time)
        let colorTimePatterns = [
            #"float[34]\s*\(.*(?:sin|cos)\s*\(\s*(?:uniforms\.)?time"#,
            #"color.*(?:sin|cos)\s*\(\s*(?:uniforms\.)?time"#,
            #"(?:sin|cos)\s*\(\s*(?:uniforms\.)?time.*\*.*color"#,
        ]
        for pattern in colorTimePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: code, range: range) != nil {
                behaviors.append("time-varying color/hue")
                break
            }
        }

        // Detect rotation over time: angle = time, rotation matrix with time
        let rotPatterns = [
            #"(?:angle|rot|theta)\s*=\s*(?:uniforms\.)?time"#,
            #"(?:angle|rot|theta)\s*=.*(?:uniforms\.)?time\s*\*"#,
            #"float2x2\s*\(.*(?:sin|cos)\s*\(\s*(?:uniforms\.)?time"#,
        ]
        for pattern in rotPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: code, range: range) != nil {
                behaviors.append("continuous rotation")
                break
            }
        }

        // Detect pulsing (scale/size changes with time)
        let pulsePatterns = [
            #"(?:scale|size|radius|amplitude)\s*[=\*\+].*(?:sin|cos)\s*\(\s*(?:uniforms\.)?time"#,
            #"(?:sin|cos)\s*\(\s*(?:uniforms\.)?time.*(?:scale|size|radius|amplitude)"#,
        ]
        for pattern in pulsePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: code, range: range) != nil {
                behaviors.append("pulsing/breathing scale")
                break
            }
        }

        // Detect noise with time seed (evolving procedural patterns)
        let noiseTimePatterns = [
            #"(?:noise|hash|random|fbm)\s*\(.*(?:uniforms\.)?time"#,
            #"(?:uniforms\.)?time.*(?:noise|hash|random|fbm)"#,
        ]
        for pattern in noiseTimePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: code, range: range) != nil {
                behaviors.append("evolving procedural noise (time-seeded)")
                break
            }
        }

        // Detect step/smoothstep with time (animated thresholds, wipes)
        if code.contains("smoothstep") || code.contains("step(") {
            let stepTimeRegex = try? NSRegularExpression(pattern: #"(?:smooth)?step\s*\(.*(?:uniforms\.)?time"#)
            if let m = stepTimeRegex, m.firstMatch(in: code, range: range) != nil {
                behaviors.append("animated threshold/wipe via step(time)")
            }
        }

        if behaviors.isEmpty && usesTime {
            return "Uses time (dynamic), but animation pattern is non-standard/complex"
        }
        guard !behaviors.isEmpty else { return nil }

        return "DYNAMIC: " + behaviors.joined(separator: "; ")
    }

    // MARK: - Natural Language Summary

    private static func buildSummary(tags: [String], category: ShaderCategory, uniforms: Set<String>, sources: [String]) -> String {
        var parts = [String]()

        let lightingTags = tags.filter { ["lambert", "phong", "blinn_phong", "toon_shading", "pbr", "gooch", "fresnel"].contains($0) }
        let noiseTags = tags.filter { ["perlin_noise", "fbm_noise", "value_noise", "voronoi"].contains($0) }
        let ppTags = tags.filter { ["blur", "bloom", "vignette", "edge_detection", "distortion", "chromatic_aberration", "crt_effect", "glitch"].contains($0) }
        let deformTags = tags.filter { ["displacement", "wave", "twist", "morph"].contains($0) }
        let sdfTags = tags.filter { $0.hasPrefix("sdf") || $0 == "raymarching" }

        if !lightingTags.isEmpty { parts.append(lightingTags.joined(separator: "+") + " lighting") }
        if !noiseTags.isEmpty { parts.append(noiseTags.joined(separator: "+") + " noise") }
        if !ppTags.isEmpty { parts.append(ppTags.joined(separator: "+") + " post-processing") }
        if !deformTags.isEmpty { parts.append(deformTags.joined(separator: "+") + " deformation") }
        if !sdfTags.isEmpty { parts.append(sdfTags.joined(separator: "+") + " SDF") }

        if tags.contains("animation") { parts.append("animated") }
        if tags.contains("mouse_interactive") { parts.append("mouse-interactive") }
        if !sources.isEmpty { parts.append("samples " + sources.joined(separator: ",")) }

        if parts.isEmpty {
            return "\(category.rawValue) shader with custom logic"
        }

        let prefix: String
        switch category {
        case .vertex:    prefix = "Vertex shader:"
        case .fragment:  prefix = "Fragment shader:"
        case .fullscreen: prefix = "Fullscreen effect:"
        }
        return "\(prefix) \(parts.joined(separator: ", "))"
    }
}
