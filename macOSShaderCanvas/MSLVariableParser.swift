//
//  MSLVariableParser.swift
//  macOSShaderCanvas
//
//  Regex-based parser that extracts local variable declarations AND all
//  references from MSL source. Provides type, line number, and character
//  range for each occurrence so the Code Editor can make them all clickable.
//

import Foundation

// MARK: - MSL Value Type

enum MSLValueType: String, CaseIterable {
    case float_  = "float"
    case float2  = "float2"
    case float3  = "float3"
    case float4  = "float4"
    case half_   = "half"
    case half2   = "half2"
    case half3   = "half3"
    case half4   = "half4"
    case int_    = "int"
    case int2    = "int2"
    case int3    = "int3"
    case int4    = "int4"
    case uint_   = "uint"
    case uint2   = "uint2"
    case uint3   = "uint3"
    case uint4   = "uint4"
    case bool_   = "bool"

    var componentCount: Int {
        switch self {
        case .float_, .half_, .int_, .uint_, .bool_: return 1
        case .float2, .half2, .int2, .uint2:         return 2
        case .float3, .half3, .int3, .uint3:         return 3
        case .float4, .half4, .int4, .uint4:         return 4
        }
    }

    func debugExpression(for varName: String, channel: Int = -1) -> String {
        if channel < 0 {
            switch componentCount {
            case 1:  return "float4(float3(float(\(varName))), 1.0)"
            case 2:  return "float4(float2(\(varName)), 0.0, 1.0)"
            case 3:  return "float4(float3(\(varName)), 1.0)"
            case 4:  return "float4(\(varName))"
            default: return "float4(float3(float(\(varName))), 1.0)"
            }
        }
        let swizzle = ["x", "y", "z", "w"]
        guard channel < componentCount else {
            return debugExpression(for: varName)
        }
        if componentCount == 1 {
            return "float4(float3(float(\(varName))), 1.0)"
        }
        return "float4(float3(\(varName).\(swizzle[channel])), 1.0)"
    }

    static func from(keyword: String) -> MSLValueType? {
        allCases.first { $0.rawValue == keyword }
    }
}

// MARK: - MSL Variable

struct MSLVariable {
    let name: String
    let type: MSLValueType
    let lineNumber: Int
    let characterRange: NSRange
    let isDeclaration: Bool
}

// MARK: - Parser

struct MSLVariableParser {

    private static let typeKeywords = Set(MSLValueType.allCases.map(\.rawValue))

    private static let reservedNames: Set<String> = [
        "in", "out", "uniforms", "params", "transform", "bgTexture",
        "position", "texCoord", "vertexID", "uv", "main", "sampler",
        "true", "false", "return", "if", "else", "for", "while",
        "float2", "float3", "float4", "half2", "half3", "half4",
        "int2", "int3", "int4", "uint2", "uint3", "uint4",
        "device", "constant", "thread", "threadgroup", "s"
    ]

    static func parse(source: String) -> [MSLVariable] {
        let nsSource = source as NSString
        let lines = source.components(separatedBy: "\n")
        var declarations: [(name: String, type: MSLValueType)] = []
        var results: [MSLVariable] = []
        var braceDepth = 0
        var inStruct = false
        var charOffset = 0

        let declarationPattern = try! NSRegularExpression(
            pattern: #"(?:^|(?<=[\s(,]))(?:const\s+|thread\s+)?(\w+)\s+(\w+)\s*[=;,)]"#
        )

        // Pass 1: find declarations
        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNS = line as NSString
            let lineLen = lineNS.length

            if trimmed.hasPrefix("struct ") { inStruct = true }
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                else if ch == "}" {
                    braceDepth -= 1
                    if inStruct && braceDepth <= 1 { inStruct = false }
                }
            }

            let skipLine = inStruct
                || trimmed.hasPrefix("//")
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix("struct ")
                || trimmed.contains("[[")
                || braceDepth < 1

            if !skipLine {
                let lineRange = NSRange(location: 0, length: lineLen)
                let matches = declarationPattern.matches(in: line, range: lineRange)
                for match in matches {
                    guard match.numberOfRanges >= 3 else { continue }
                    let typeStr = lineNS.substring(with: match.range(at: 1))
                    let nameStr = lineNS.substring(with: match.range(at: 2))

                    guard typeKeywords.contains(typeStr),
                          let valType = MSLValueType.from(keyword: typeStr),
                          !reservedNames.contains(nameStr) else { continue }

                    let nameRange = match.range(at: 2)
                    let globalRange = NSRange(
                        location: charOffset + nameRange.location,
                        length: nameRange.length
                    )
                    declarations.append((nameStr, valType))
                    results.append(MSLVariable(
                        name: nameStr, type: valType,
                        lineNumber: lineIdx, characterRange: globalRange,
                        isDeclaration: true
                    ))
                }
            }
            charOffset += lineLen + 1
        }

        // Pass 2: find all references to declared variables
        guard !declarations.isEmpty else { return results }
        let varNames = Set(declarations.map(\.name))
        let varTypeMap = Dictionary(declarations.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        let identPattern = try! NSRegularExpression(pattern: #"\b(\w+)\b"#)

        charOffset = 0
        braceDepth = 0
        inStruct = false

        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNS = line as NSString
            let lineLen = lineNS.length

            if trimmed.hasPrefix("struct ") { inStruct = true }
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                else if ch == "}" {
                    braceDepth -= 1
                    if inStruct && braceDepth <= 1 { inStruct = false }
                }
            }

            let skipLine = inStruct
                || trimmed.hasPrefix("//")
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix("struct ")
                || braceDepth < 1

            if !skipLine {
                let lineRange = NSRange(location: 0, length: lineLen)
                let matches = identPattern.matches(in: line, range: lineRange)
                for match in matches {
                    let word = lineNS.substring(with: match.range)
                    guard varNames.contains(word), let vtype = varTypeMap[word] else { continue }

                    let globalRange = NSRange(
                        location: charOffset + match.range.location,
                        length: match.range.length
                    )

                    let alreadyDecl = results.contains {
                        $0.characterRange.location == globalRange.location
                        && $0.characterRange.length == globalRange.length
                    }
                    if !alreadyDecl {
                        results.append(MSLVariable(
                            name: word, type: vtype,
                            lineNumber: lineIdx, characterRange: globalRange,
                            isDeclaration: false
                        ))
                    }
                }
            }
            charOffset += lineLen + 1
        }

        return results.sorted { $0.characterRange.location < $1.characterRange.location }
    }
}
