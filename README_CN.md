# macOS Shader Canvas

一个轻量级的 macOS Metal 着色器工作台 —— 在 3D 网格上实时构建、编辑和叠加着色器。

[English](README.md) | **中文**

**文档**: [架构说明](ARCHITECTURE_CN.md) | [Architecture (English)](ARCHITECTURE.md)

## 概述

macOS Shader Canvas 是一个原生 macOS 应用，让你可以可视化地编写 Metal 着色器。你可以把它看作一个迷你图形引擎：添加顶点、片段和后处理着色器作为可叠加的图层，通过语法高亮实时编辑，并在 3D 网格上即时看到结果。

### 核心功能

- **实时着色器编辑** — Metal 语法高亮、自动缩进、代码片段插入
- **基于图层的架构** — 任意叠加顶点、片段和全屏着色器
- **多通道渲染管线** — 乒乓后处理
- **10 种片段着色器预设**（Lambert、Phong、Blinn-Phong、Fresnel、卡通/Toon、Gooch 等）
- **5 种后处理预设**（Bloom、高斯模糊、HSV 调节、色调映射、边缘检测）
- **网格切换** — 球体、立方体，或上传自定义 USD/OBJ 模型
- **背景图片** — 加载任意图片作为场景背景
- **画布持久化** — 保存/加载整个工作区为 `.shadercanvas` 文件
- **交互式教程** — 9 步引导课程，从零学习 Metal 着色器
- **AI 聊天** — 从 OpenAI、Anthropic 或 Gemini 获取着色器帮助
- **AI 教程生成** — 关于任何主题生成自定义着色器教程
- **多语言支持** — 英语、简体中文、日语

## 快速开始

### 系统要求
- macOS 26+（Tahoe）
- Xcode 26+
- 支持 Metal 的 GPU

### 构建与运行
1. 克隆仓库
   ```bash
   git clone https://github.com/your-username/macOSShaderCanvas.git
   cd macOSShaderCanvas
   ```
2. 在 Xcode 中打开 `macOSShaderCanvas.xcodeproj`
3. 选择 macOSShaderCanvas scheme
4. 按 ⌘R 运行

### 基本使用
1. 点击底部的 **VS**（顶点）、**FS**（片段）或 **PP**（后处理）按钮添加着色器层
2. 点击层列表中的铅笔图标打开代码编辑器
3. 编辑 Metal 着色器代码，实时预览效果
4. 使用预设按钮快速应用经典着色模型
5. 使用 ⌘S 保存工作区

## AI 功能

### AI 聊天（⌘L）
内置 AI 助手理解你的着色器代码上下文，可以：
- 解释 Metal 着色器概念
- 帮助调试编译错误
- 建议优化方案
- 生成新的着色器代码

支持三大 AI 提供商：OpenAI、Anthropic（Claude）、Google Gemini。在 AI → AI Settings 中配置 API 密钥。

### AI 教程生成
输入任何着色器主题（如"构建 PBR 金属着色器"），AI 会生成 3-6 步的渐进式教程，包含初始代码（带 TODO 标记）和完整解决方案。

## 项目结构

| 文件 | 说明 |
|------|------|
| `macOSShaderCanvasApp.swift` | 应用入口点，菜单命令 |
| `ContentView.swift` | 主 UI：侧边栏、编辑器、教程、画布管理 |
| `MetalView.swift` | NSViewRepresentable 桥接（SwiftUI ↔ MTKView）|
| `MetalRenderer.swift` | Metal 渲染引擎（多通道管线）|
| `SharedTypes.swift` | 共享数据模型和类型定义 |
| `ShaderSnippets.swift` | 所有着色器源码（默认、演示、模板、预设）|
| `TutorialData.swift` | 内置 9 步教程数据 |
| `AIService.swift` | AI API 集成（OpenAI、Anthropic、Gemini）|
| `AIChatView.swift` | AI 聊天界面和发光边框效果 |
| `AISettings.swift` | AI 设置和提供商配置 |

## 架构概览

应用采用清晰的双层架构：**SwiftUI 前端**负责所有用户交互，**Metal 后端**负责 GPU 渲染。

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI 前端                               │
│                                                             │
│  macOSShaderCanvasApp ──(NotificationCenter)──► ContentView │
│                                                    │        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │        │
│  │ 图层侧边栏   │  │ 着色器编辑器 │  │ 教程面板 │ │        │
│  │ (增/删)      │  │ (代码 + UI)  │  │          │ │        │
│  └──────────────┘  └──────────────┘  └──────────┘ │        │
│                                                    │        │
│  @State activeShaders, meshType, backgroundImage   │        │
│                         │                                   │
│                         ▼                                   │
│               MetalView (NSViewRepresentable)               │
│            ┌────────────┴────────────┐                      │
│            │  将 SwiftUI 属性桥接    │                      │
│            │  到 MetalRenderer       │                      │
│            └────────────┬────────────┘                      │
└─────────────────────────┼───────────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────────┐
│                    Metal 后端                                │
│                          ▼                                   │
│               MetalRenderer (MTKViewDelegate)                │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              多通道 draw(in:)                        │    │
│  │                                                     │    │
│  │  通道 1 ─► 背景 + 网格 ─► offscreenTextureA        │    │
│  │  通道 2..N ─► 后处理（乒乓 A↔B）                    │    │
│  │  最终通道 ─► 输出到屏幕 drawable                    │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

详细架构文档请参阅 [ARCHITECTURE_CN.md](ARCHITECTURE_CN.md)。

## 教程系统

内置 9 步渐进式教程：

| # | 主题 | 着色器类型 |
|---|------|-----------|
| 1 | 纯色输出 | 片段 |
| 2 | 法线可视化 | 片段 |
| 3 | Lambert 漫反射 | 片段 |
| 4 | Blinn-Phong 高光 | 片段 |
| 5 | 时间动画 | 片段 |
| 6 | 顶点位移 | 顶点 |
| 7 | 菲涅尔边缘光 | 片段 |
| 8 | 后处理暗角 | 全屏 |
| 9 | 综合挑战 | 片段 |

通过 **File → Tutorial** (⇧⌘T) 开始教程。

## 贡献

欢迎贡献！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

### 贡献方向
- 新的着色器预设
- 更多后处理效果
- UI/UX 改进
- 额外语言的本地化
- 性能优化
- Bug 修复

## 免责声明

> **AI 辅助开发**：本代码库的部分内容（包括代码、注释和文档）由 AI 工具辅助生成或优化。虽然代码已经过审查和测试，但 AI 生成的内容可能包含不准确之处、次优模式或细微错误。**请在用于生产环境或作为学习参考前仔细审查。** 如果发现任何问题，欢迎贡献和修正。

## 许可证

本项目用于教育目的。
