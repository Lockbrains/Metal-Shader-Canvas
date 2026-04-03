//
//  MSLDebugShaderGenerator.swift
//  macOSShaderCanvas
//
//  Generates a debug-instrumented version of a fragment shader source.
//  Finds the target variable in the full compiled source by matching
//  the line text from the display source, then inserts an early-return
//  that outputs the variable's value as a visible color.
//

import Foundation

struct MSLDebugShaderGenerator {

    /// Takes the full compiled fragment MSL source and a parsed variable
    /// (from the display source), finds the matching line in the full source,
    /// and inserts an early-return visualizing the variable.
    /// - channel: -1 = all channels, 0 = R/X, 1 = G/Y, 2 = B/Z, 3 = A/W
    static func generateDebugFragmentSource(
        originalFragmentSource: String,
        variable: MSLVariable,
        displaySource: String,
        channel: Int = -1
    ) -> String {
        let displayLines = displaySource.components(separatedBy: "\n")
        guard variable.lineNumber >= 0,
              variable.lineNumber < displayLines.count else {
            return originalFragmentSource
        }

        let targetLineText = displayLines[variable.lineNumber]
            .trimmingCharacters(in: .whitespaces)
        guard !targetLineText.isEmpty else { return originalFragmentSource }

        var fullLines = originalFragmentSource.components(separatedBy: "\n")
        let debugReturn = "    return \(variable.type.debugExpression(for: variable.name, channel: channel)); /* DEBUG */"

        for (i, line) in fullLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == targetLineText {
                fullLines.insert(debugReturn, at: i + 1)
                return fullLines.joined(separator: "\n")
            }
        }

        // Fallback: partial match (for lines that may have been slightly modified)
        for (i, line) in fullLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(variable.name) && trimmed.contains(variable.type.rawValue) {
                fullLines.insert(debugReturn, at: i + 1)
                return fullLines.joined(separator: "\n")
            }
        }

        // Last resort: search for the variable name assignment
        for (i, line) in fullLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(variable.name) && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("#") {
                fullLines.insert(debugReturn, at: i + 1)
                return fullLines.joined(separator: "\n")
            }
        }

        return originalFragmentSource
    }
}
