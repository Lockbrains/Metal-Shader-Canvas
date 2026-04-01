import Testing
import SwiftUI
@testable import macOSShaderCanvas

// MARK: - ParseBlocks Tests

struct ParseBlocksTests {

    @Test func emptyStringProducesNoBlocks() {
        let blocks = MarkdownTextView.parseBlocks("")
        #expect(blocks.isEmpty)
    }

    @Test func whitespaceOnlyProducesNoBlocks() {
        let blocks = MarkdownTextView.parseBlocks("   \n  \n   ")
        #expect(blocks.isEmpty)
    }

    @Test func singleParagraph() {
        let blocks = MarkdownTextView.parseBlocks("Hello world")
        #expect(blocks == [.paragraph("Hello world")])
    }

    @Test func multiLineParagraph() {
        let blocks = MarkdownTextView.parseBlocks("Line one\nLine two\nLine three")
        #expect(blocks == [.paragraph("Line one\nLine two\nLine three")])
    }

    @Test func headingLevels1Through6() {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let blocks = MarkdownTextView.parseBlocks("\(prefix) Title")
            #expect(blocks == [.heading(level, "Title")])
        }
    }

    @Test func sevenHashesFallsToParagraph() {
        let blocks = MarkdownTextView.parseBlocks("####### Not a heading")
        #expect(blocks.count == 1)
        guard case .paragraph = blocks[0] else {
            Issue.record("Expected paragraph for 7-hash line")
            return
        }
    }

    @Test func hashWithoutSpaceIsParagraph() {
        let blocks = MarkdownTextView.parseBlocks("#NoSpace")
        #expect(blocks.count == 1)
        guard case .paragraph = blocks[0] else {
            Issue.record("Expected paragraph for '#NoSpace'")
            return
        }
    }

    @Test func bareHashesAreParagraph() {
        let blocks = MarkdownTextView.parseBlocks("###")
        #expect(blocks.count == 1)
        guard case .paragraph(let text) = blocks[0] else {
            Issue.record("Expected paragraph for bare '###'")
            return
        }
        #expect(text == "###")
    }

    @Test func codeBlockWithLanguage() {
        let input = "```swift\nlet x = 1\nlet y = 2\n```"
        let blocks = MarkdownTextView.parseBlocks(input)
        #expect(blocks == [.codeBlock("swift", "let x = 1\nlet y = 2")])
    }

    @Test func codeBlockWithoutLanguage() {
        let input = "```\nsome code\n```"
        let blocks = MarkdownTextView.parseBlocks(input)
        #expect(blocks == [.codeBlock(nil, "some code")])
    }

    @Test func unclosedCodeBlockConsumesRest() {
        let input = "```metal\nfloat4 color = float4(1.0);\nno closing fence"
        let blocks = MarkdownTextView.parseBlocks(input)
        #expect(blocks.count == 1)
        guard case .codeBlock(let lang, let code) = blocks[0] else {
            Issue.record("Expected codeBlock")
            return
        }
        #expect(lang == "metal")
        #expect(code.contains("float4 color"))
        #expect(code.contains("no closing fence"))
    }

    @Test func unorderedListDash() {
        let blocks = MarkdownTextView.parseBlocks("- Alpha\n- Beta\n- Gamma")
        #expect(blocks == [.unorderedList(["Alpha", "Beta", "Gamma"])])
    }

    @Test func unorderedListAsterisk() {
        let blocks = MarkdownTextView.parseBlocks("* One\n* Two")
        #expect(blocks == [.unorderedList(["One", "Two"])])
    }

    @Test func unorderedListBullet() {
        let blocks = MarkdownTextView.parseBlocks("• First\n• Second")
        #expect(blocks == [.unorderedList(["First", "Second"])])
    }

    @Test func unorderedListMixedMarkers() {
        let blocks = MarkdownTextView.parseBlocks("- One\n* Two\n• Three")
        #expect(blocks == [.unorderedList(["One", "Two", "Three"])])
    }

    @Test func orderedListDotFormat() {
        let blocks = MarkdownTextView.parseBlocks("1. First\n2. Second\n3. Third")
        #expect(blocks == [.orderedList(["First", "Second", "Third"])])
    }

    @Test func orderedListParenFormat() {
        let blocks = MarkdownTextView.parseBlocks("1) Alpha\n2) Beta")
        #expect(blocks == [.orderedList(["Alpha", "Beta"])])
    }

    @Test func mixedBlockTypes() {
        let input = "# Title\n\nSome paragraph text.\n\n- Item A\n- Item B\n\n```\ncode here\n```\n\n1. Step one\n2. Step two"
        let blocks = MarkdownTextView.parseBlocks(input)
        #expect(blocks.count == 5)
        #expect(blocks[0] == .heading(1, "Title"))
        #expect(blocks[1] == .paragraph("Some paragraph text."))
        #expect(blocks[2] == .unorderedList(["Item A", "Item B"]))
        #expect(blocks[3] == .codeBlock(nil, "code here"))
        #expect(blocks[4] == .orderedList(["Step one", "Step two"]))
    }

    @Test func paragraphBreaksBeforeHeading() {
        let blocks = MarkdownTextView.parseBlocks("Normal text\n# Heading")
        #expect(blocks.count == 2)
        #expect(blocks[0] == .paragraph("Normal text"))
        #expect(blocks[1] == .heading(1, "Heading"))
    }

    @Test func paragraphBreaksBeforeCodeFence() {
        let blocks = MarkdownTextView.parseBlocks("Some text\n```\ncode\n```")
        #expect(blocks.count == 2)
        #expect(blocks[0] == .paragraph("Some text"))
        #expect(blocks[1] == .codeBlock(nil, "code"))
    }

    @Test func paragraphBreaksBeforeList() {
        let blocks = MarkdownTextView.parseBlocks("Some text\n- item")
        #expect(blocks.count == 2)
        #expect(blocks[0] == .paragraph("Some text"))
        #expect(blocks[1] == .unorderedList(["item"]))
    }
}

// MARK: - InlineText Safety Tests

struct InlineTextTests {

    let color = Color.white

    @Test func plainTextNoMarkers() {
        _ = MarkdownTextView.inlineText("Hello world 123", color: color)
    }

    @Test func boldSpan() {
        _ = MarkdownTextView.inlineText("This is **bold** text", color: color)
    }

    @Test func codeSpan() {
        _ = MarkdownTextView.inlineText("Use `normalize()` here", color: color)
    }

    @Test func unmatchedDoubleStar() {
        _ = MarkdownTextView.inlineText("Open ** never closed", color: color)
    }

    @Test func unmatchedBacktick() {
        _ = MarkdownTextView.inlineText("Broken ` backtick", color: color)
    }

    @Test func emptyBold() {
        _ = MarkdownTextView.inlineText("Empty **** bold", color: color)
    }

    @Test func emptyCodeBackticks() {
        _ = MarkdownTextView.inlineText("Empty `` backticks", color: color)
    }

    @Test func mixedBoldAndCode() {
        _ = MarkdownTextView.inlineText("**bold** then `code` then **more**", color: color)
    }

    @Test func consecutiveBoldSpans() {
        _ = MarkdownTextView.inlineText("**a****b****c**", color: color)
    }

    @Test func onlyDoubleStar() {
        _ = MarkdownTextView.inlineText("**", color: color)
    }

    @Test func onlyBacktick() {
        _ = MarkdownTextView.inlineText("`", color: color)
    }

    @Test func emptyString() {
        _ = MarkdownTextView.inlineText("", color: color)
    }

    @Test func trailingDoubleStarAfterBold() {
        _ = MarkdownTextView.inlineText("**a** leftover **", color: color)
    }

    @Test func codeInsideBoldContext() {
        _ = MarkdownTextView.inlineText("**Use `func` here**", color: color)
    }
}

// MARK: - Hang / Performance Tests

struct MarkdownHangTests {

    let color = Color.white

    // Each test uses .timeLimit(.minutes(1)) as a hard kill and
    // ContinuousClock to assert sub-2-second completion.

    @Test(.timeLimit(.minutes(1)))
    func thousandUnpairedStars() {
        let input = String(repeating: "*", count: 1000)
        let start = ContinuousClock.now
        _ = MarkdownTextView.inlineText(input, color: color)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "inlineText on 1000 '*' took \(elapsed)")
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedEmphasisMarkers() {
        let input = (0..<200).map { "***a\($0)*b**c***d**" }.joined()
        let start = ContinuousClock.now
        _ = MarkdownTextView.inlineText(input, color: color)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "Nested emphasis took \(elapsed)")
    }

    @Test(.timeLimit(.minutes(1)))
    func longShaderDiscussionText() {
        var lines: [String] = []
        for i in 0..<100 {
            lines.append("Step \(i): 使用 `normalize(vec3(ddx, ddy, thickness))` 计算法线，然后通过 **SDF** 融合 smoothMin。")
            lines.append("公式: `d = length(p - center) * scale` 其中 p 范围 `[-1, 1]`。")
            lines.append("注意 `*` 运算符优先级，以及 `**` 不是幂运算。float4 c = float4(r * 0.5 + 0.5, g * 0.3, b, 1.0);")
        }
        let input = lines.joined(separator: "\n")
        let start = ContinuousClock.now
        _ = MarkdownTextView.inlineText(input, color: color)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "Shader discussion inlineText took \(elapsed)")
    }

    @Test(.timeLimit(.minutes(1)))
    func fiveHundredOrderedListItems() {
        let input = (1...500).map { "\($0). Item number \($0)" }.joined(separator: "\n")
        let start = ContinuousClock.now
        let blocks = MarkdownTextView.parseBlocks(input)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "500-item list parseBlocks took \(elapsed)")
        #expect(blocks.count == 1)
        guard case .orderedList(let items) = blocks[0] else {
            Issue.record("Expected orderedList")
            return
        }
        #expect(items.count == 500)
    }

    @Test(.timeLimit(.minutes(1)))
    func largeRepeatingMixedBlocks() {
        var input = ""
        for i in 0..<100 {
            input += "# Section \(i)\n\n"
            input += "This is paragraph \(i) with **bold** and `code`.\n\n"
            input += "```metal\nfloat4 color\(i) = float4(1.0);\n```\n\n"
            input += "- Point A\(i)\n- Point B\(i)\n- Point C\(i)\n\n"
            input += "1. Step \(i).1\n2. Step \(i).2\n\n"
        }
        let start = ContinuousClock.now
        let blocks = MarkdownTextView.parseBlocks(input)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "100-section parseBlocks took \(elapsed)")
        #expect(blocks.count == 500)
    }

    @Test(.timeLimit(.minutes(1)))
    func fullPipelineRealAIResponse() {
        let aiResponse = """
        # 初步的技术方案 (Initial Technical Approach)

        我们可以分几个步骤来构建这个 Shader：

        ## Step 1: 构建背景 (Background)

        先写一个函数 `getBackground(uv)`，画出底部的浅灰色网格和几个彩色的渐变数量体，作为被折射的纹理。

        ## Step 2: 玻璃 SDF 与流体融合 (SDF & smin)

        定义各个玻璃状的 SDF，并用经典的多项式平滑最小值 (Polynomial Smooth Min) 将它们组合起来。这会给出每个像素到玻璃体边缘的最短距离 `d`。

        - **SDF 基本形状**: `sdCircle`, `sdBox`, `sdEllipse`
        - **Smooth Min**: `smin(a, b, k) = -log(exp(-k*a) + exp(-k*b)) / k`
        - **距离场采样**: `float d = sceneSDF(uv);`

        ## Step 3: 升级！2D 转 3D 法线 (Pseudo-3D Normals)

        这是最奇妙的一步。我们通过对 SDF 求导（在当前像素点附近进行微小的偏移采样），计算出 X 和 Y 方向的梯度，结合我们假定的玻璃 "厚度" Z，构建出一个完整的 3D 法线向量 `N = normalize(vec3(ddx, ddy, thickness))`。

        ```metal
        float eps = 0.001;
        float dx = sceneSDF(uv + float2(eps, 0)) - sceneSDF(uv - float2(eps, 0));
        float dy = sceneSDF(uv + float2(0, eps)) - sceneSDF(uv - float2(0, eps));
        float3 N = normalize(float3(dx, dy, thickness * 2.0));
        ```

        ## Step 4: 光学渲染 (Refraction & Lighting)

        1. **折射**: 当处于玻璃内部 (`d < 0`) 时，使用 `uv_distorted = uv + N.xy * refraction_strength` 去重新采样 `getBackground`
        2. **高光**: 给定一个虚拟光源 L，计算 `dot(N, L)` 和环境反射向量，叠加高光
        3. **边缘光**: `float rim = pow(1.0 - abs(dot(N, viewDir)), rimPower);`

        你觉得这个拆解思路怎样？如果你对上面的几个问题（特别是背景生成方式和交互动画）有具体的想法，请告诉我！
        """

        let start = ContinuousClock.now
        let blocks = MarkdownTextView.parseBlocks(aiResponse)
        for block in blocks {
            switch block {
            case .heading(_, let content), .paragraph(let content):
                _ = MarkdownTextView.inlineText(content, color: color)
            case .unorderedList(let items), .orderedList(let items):
                for item in items {
                    _ = MarkdownTextView.inlineText(item, color: color)
                }
            case .codeBlock:
                break
            }
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "Full AI response pipeline took \(elapsed)")
        #expect(!blocks.isEmpty)
    }
}
