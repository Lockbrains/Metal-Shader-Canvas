//
//  MSLHighlighter.swift
//  macOSShaderCanvas
//
//  Shared MSL syntax highlighting rules used by both the editable CodeEditor
//  in ContentView and the read-only Code Editor in Lab mode.
//

import AppKit

struct MSLHighlighter {

    struct Rule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options
    }

    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let defaultTextColor = NSColor(white: 0.9, alpha: 1.0)

    static let rules: [Rule] = [
        Rule(pattern: "\\b(include|using|namespace|struct|vertex|fragment|kernel|constant|device|thread|threadgroup|return|constexpr|sampler|address|filter|if|else|for|while|switch|case|break|continue|default|do|static|inline)\\b",
             color: NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1.0), options: []),
        Rule(pattern: "\\b(float|float2|float3|float4|float4x4|float3x3|half|half2|half3|half4|int|int2|int3|int4|uint|uint2|uint3|uint4|texture2d|void|bool|short|ushort|char|uchar)\\b",
             color: NSColor(red: 0.3, green: 0.7, blue: 0.8, alpha: 1.0), options: []),
        Rule(pattern: "\\b(sin|cos|tan|asin|acos|atan|atan2|max|min|clamp|dot|cross|normalize|length|distance|reflect|refract|mix|smoothstep|step|sample|abs|floor|ceil|round|fract|fmod|pow|sqrt|rsqrt|exp|exp2|log|log2|sign|saturate|fwidth|dfdx|dfdy|select|any|all|get_width|get_height)\\b",
             color: NSColor(red: 0.8, green: 0.8, blue: 0.5, alpha: 1.0), options: []),
        Rule(pattern: "\\[\\[[^\\]]+\\]\\]",
             color: NSColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0), options: []),
        Rule(pattern: "\\b\\d+(\\.\\d+)?[fh]?\\b",
             color: NSColor(red: 0.6, green: 0.8, blue: 0.6, alpha: 1.0), options: []),
        Rule(pattern: "^\\s*#.*",
             color: NSColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1.0), options: .anchorsMatchLines),
        Rule(pattern: "//.*",
             color: NSColor(red: 0.5, green: 0.6, blue: 0.5, alpha: 1.0), options: []),
    ]

    /// Clickable-variable attribute key used by MSLCodeEditorView
    static let variableAttributeKey = NSAttributedString.Key("MSLVariable")

    static let variableUnderlineColor = NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.6)

    static func apply(
        to storage: NSTextStorage,
        font: NSFont? = nil,
        variables: [MSLVariable] = []
    ) {
        let f = font ?? defaultFont
        let range = NSRange(location: 0, length: storage.length)
        let content = storage.string

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: defaultTextColor, range: range)
        storage.addAttribute(.font, value: f, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.underlineColor, range: range)
        storage.removeAttribute(variableAttributeKey, range: range)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            for match in regex.matches(in: content, range: range) {
                storage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }

        for variable in variables {
            guard variable.characterRange.location + variable.characterRange.length <= storage.length else { continue }
            storage.addAttribute(variableAttributeKey, value: variable, range: variable.characterRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: variable.characterRange)
            storage.addAttribute(.underlineColor, value: variableUnderlineColor, range: variable.characterRange)
        }

        storage.endEditing()
    }
}
