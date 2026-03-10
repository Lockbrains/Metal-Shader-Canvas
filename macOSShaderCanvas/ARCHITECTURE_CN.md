# 架构文档

**macOS Shader Canvas** — 基于 Metal 的实时着色器编辑器

---

## 目录

1. [项目概述](#1-项目概述)
2. [文件结构](#2-文件结构)
3. [双层架构](#3-双层架构)
4. [MetalView 设计](#4-metalview-设计)
5. [MetalRenderer 设计](#5-metalrenderer-设计)
6. [数据流图](#6-数据流图)
7. [菜单通信](#7-菜单通信)
8. [画布持久化](#8-画布持久化)
9. [AI 集成](#9-ai-集成)
10. [教程系统](#10-教程系统)
11. [Metal API 使用总结](#11-metal-api-使用总结)
12. [系统要求](#12-系统要求)

---

## 1. 项目概述

**macOS Shader Canvas** 是一个原生 macOS 应用程序，采用 **SwiftUI + Metal** 技术栈，允许用户在 3D 网格上实时编写、编辑和预览 Metal 着色器。

### 核心特性

- **基于图层的架构**：支持顶点着色器、片段着色器和后处理着色器
- **实时编辑**：用户修改代码后立即在画布上看到效果
- **运行时 MSL 编译**：无需预编译，直接编译 Metal Shading Language 源码字符串
- **多通道渲染**：支持后处理链（如 bloom → blur → 色彩分级）

---

## 2. 文件结构

```
macOSShaderCanvas/
├── macOSShaderCanvasApp.swift    # 应用入口点，菜单命令（NotificationCenter）
├── ContentView.swift             # 主 UI：侧边栏、编辑器、教程、画布逻辑
├── MetalView.swift               # NSViewRepresentable 桥接（SwiftUI ↔ MTKView）
├── MetalRenderer.swift           # Metal 渲染引擎（MTKViewDelegate）
├── SharedTypes.swift             # 数据模型、UTType、通知名称
├── ShaderSnippets.swift          # 着色器源码：默认、演示、模板、预设
├── TutorialData.swift            # 9 步教程内容
├── AIService.swift               # AI 聊天和教程生成（actor）
├── AIChatView.swift              # AI 聊天 UI + 发光边框
└── AISettings.swift              # AI 提供商配置（Observable，UserDefaults）
```

### 文件职责概览

| 文件 | 职责 |
|------|------|
| `macOSShaderCanvasApp.swift` | 应用入口、菜单栏命令、通过 NotificationCenter 与视图通信 |
| `ContentView.swift` | 主界面布局、侧边栏、代码编辑器、教程面板、AI 聊天、画布状态管理 |
| `MetalView.swift` | SwiftUI 与 Metal 的桥接层，将 UI 状态推送到渲染器 |
| `MetalRenderer.swift` | GPU 资源管理、着色器编译、多通道渲染管线 |
| `SharedTypes.swift` | 数据模型（ActiveShader、CanvasDocument、MeshType 等）、自定义 UTType、通知名称 |
| `ShaderSnippets.swift` | 默认着色器、演示、模板、预设代码 |
| `TutorialData.swift` | 9 步渐进式教程的步骤内容 |
| `AIService.swift` | AI 对话、教程生成，actor 确保线程安全 |
| `AIChatView.swift` | AI 聊天界面、发光边框效果 |
| `AISettings.swift` | AI 提供商配置（OpenAI、Anthropic、Gemini），UserDefaults 持久化 |

---

## 3. 双层架构

应用采用清晰的前后端分离设计：

```
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftUI 前端（UI 层）                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────┐ │
│  │   侧边栏    │ │  代码编辑器  │ │  教程面板   │ │  AI 聊天   │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    │ MetalView（桥接层）
                                    │ NSViewRepresentable
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Metal 后端（GPU 层）                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ MetalRenderer：着色器编译、管线构建、每帧绘制                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

- **SwiftUI 前端**：所有 UI 组件（侧边栏、代码编辑器、教程面板、AI 聊天）
- **Metal 后端**：所有 GPU 渲染逻辑集中在 MetalRenderer 中
- **桥接层**：MetalView（NSViewRepresentable）连接两者，负责状态传递

---

## 4. MetalView 设计

### 4.1 为什么需要桥接？

SwiftUI 无法直接托管 `MTKView`（MetalKit 视图）。Apple 的解决方案是 **NSViewRepresentable** 协议，它将 AppKit 的 `NSView` 包装起来，使 SwiftUI 能够管理其生命周期。

### 4.2 设计原则

MetalView 是一个**薄的、无状态的桥接层**：

1. 从 SwiftUI 接收渲染参数（ContentView 中的 `@State`）
2. 在创建时（`makeNSView`），实例化 MTKView 和 MetalRenderer
3. 在每次 SwiftUI 状态变化时（`updateNSView`），将新值推送到 MetalRenderer

### 4.3 输入属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `activeShaders` | `[ActiveShader]` | 着色器图层配置（顶点、片段、全屏） |
| `meshType` | `MeshType` | 要渲染的 3D 网格类型 |
| `backgroundImage` | `NSImage?` | 可选背景图 |

### 4.4 Coordinator 模式

Coordinator 持有跨 SwiftUI 视图更新而持久存在的可变状态：

```
┌──────────────────────────────────────┐
│           Coordinator                 │
├──────────────────────────────────────┤
│  renderer: MetalRenderer?             │  ← 创建一次，永久复用
│  lastBackgroundImage: NSImage?        │  ← 引用比较 (===)，避免重复 GPU 纹理上传
└──────────────────────────────────────┘
```

- **renderer**：MetalRenderer 实例，在 `makeNSView` 中创建，之后一直复用
- **lastBackgroundImage**：通过引用比较（`===`）判断图片是否变化，避免重复上传纹理到 GPU

---

## 5. MetalRenderer 设计

### 5.1 GPU 资源管理

MetalRenderer 管理四类 GPU 资源：

#### 1. 管线（MTLRenderPipelineState）

| 管线 | 用途 |
|------|------|
| `meshPipelineState` | 用户的顶点 + 片段着色器，渲染 3D 网格 |
| `fullscreenPipelineStates` | 每个后处理层一个管线，按 UUID 索引 |
| `blitPipelineState` | 最终复制到屏幕 |
| `bgBlitPipelineState` | 背景图渲染 |

#### 2. 纹理（MTLTexture）

| 纹理 | 用途 |
|------|------|
| `offscreenTextureA` / `offscreenTextureB` | 乒乓缓冲区，用于后处理链 |
| `depthTexture` | 深度缓冲（格式：.depth32Float） |
| `backgroundTexture` | 用户上传的背景图片 |

#### 3. 网格（MTKMesh + ModelIO）

- **顶点布局**：position(float3) + normal(float3) + texCoord(float2)，步长 32 字节
- **支持类型**：球体、立方体、自定义 USD/OBJ

#### 4. Uniforms 结构体

```c
struct Uniforms {
    float4x4 modelViewProjectionMatrix;  // 4x4 变换矩阵
    float time;                           // 动画时间（秒）
};
```

- 始终绑定在 **buffer index 1**
- `modelViewProjectionMatrix`：模型-视图-投影矩阵
- `time`：自应用启动以来的秒数，用于着色器动画

### 5.2 运行时着色器编译

与典型的 Metal 应用不同（预编译着色器到 .metallib），本应用在**运行时**编译 MSL 源码字符串：

```
用户输入代码
    │
    ▼
device.makeLibrary(source:)
    │
    ▼
MTLLibrary
    │
    ▼
makeFunction(name:)
    │
    ▼
MTLRenderPipelineState
```

`updateShaders()` 会对比新旧着色器数组，**仅重新编译代码发生变化的着色器**，以提升性能。

### 5.3 多通道渲染管线（draw(in:)）

```
┌──────────────────────────────────────────────────────────────────┐
│ 通道 1：基础网格 → offscreenTextureA                              │
│   • 清除为深灰色                                                  │
│   • 绘制背景图（全屏四边形）                                       │
│   • 绘制 3D 网格（MVP 变换 + 深度测试）                           │
├──────────────────────────────────────────────────────────────────┤
│ 通道 2..N：后处理（乒乓 A↔B）                                     │
│   每个全屏着色器：                                                 │
│     • 从 currentSourceTex 读取                                    │
│     • 写入 currentDestTex                                         │
│     • 交换 source ↔ dest                                          │
│   可链式叠加效果：bloom → blur → 色彩分级 等                       │
├──────────────────────────────────────────────────────────────────┤
│ 最终通道：输出到屏幕                                               │
│   • 将 currentSourceTex 复制到 view.currentDrawable               │
│   • 简单纹理采样，无额外效果                                       │
└──────────────────────────────────────────────────────────────────┘
```

### 5.4 全屏三角形技术

不使用四边形（4 顶点，2 三角形），而是用**单个超大三角形**（3 顶点）覆盖整个屏幕，GPU 自动裁剪超出部分。这种方式更高效，顶点数更少。

### 5.5 着色器入口点约定

所有着色器必须定义以下入口点：

| 入口点 | 用途 |
|--------|------|
| `vertex_main` | 顶点着色器入口 |
| `fragment_main` | 片段着色器入口 |

**绑定约定**：
- Uniforms：buffer index **1**
- 片段纹理：texture index **0**

---

## 6. 数据流图

```
                    ContentView
                    (@State)
                         │
         activeShaders, meshType, backgroundImage
                         │
                         ▼
              MetalView (NSViewRepresentable)
                         │
              updateNSView 推送状态
                         │
                         ▼
              MetalRenderer (MTKViewDelegate)
                         │
         编译着色器 → 构建管线 → 每帧绘制
                         │
                         ▼
                       GPU
```

---

## 7. 菜单通信

SwiftUI 的菜单命令无法直接引用视图状态，因此采用 **NotificationCenter** 进行解耦通信：

```
菜单栏 (macOSShaderCanvasApp)
    │
    │  NotificationCenter.post()
    │
    ▼
ContentView.onReceive()
    │
    │  响应通知，更新 @State 或执行操作
    ▼
视图更新 / 文件操作
```

### 通知名称（NSNotification.Name）

| 通知 | 用途 |
|------|------|
| `canvasNew` | 新建画布 |
| `canvasSave` | 保存画布 |
| `canvasSaveAs` | 另存为 |
| `canvasOpen` | 打开画布 |
| `canvasTutorial` | 打开教程 |
| `aiSettings` | AI 设置 |
| `aiChat` | AI 聊天 |

---

## 8. 画布持久化

### 8.1 文件格式

工作区保存为 **JSON** 文件，扩展名为 `.shadercanvas`。

### 8.2 自定义 UTType

```
com.linghent.shadercanvas
```

在 Info.plist 中声明为导出类型，实现 Finder 集成和文档关联。

### 8.3 序列化结构

通过 `Codable` 协议序列化 `CanvasDocument`：

```swift
struct CanvasDocument: Codable {
    var name: String        // 画布名称
    var meshType: MeshType  // 网格类型
    var shaders: [ActiveShader]  // 着色器图层列表
}
```

包含恢复工作区所需的全部信息：画布名称、网格类型、所有着色器图层。

---

## 9. AI 集成

### 9.1 架构

- **AIService**：使用 Swift `actor` 确保线程安全
- **AISettings**：`Observable` 对象，通过 UserDefaults 持久化配置

### 9.2 支持的提供商

| 提供商 | 说明 |
|--------|------|
| OpenAI | GPT 系列模型 |
| Anthropic | Claude 系列模型 |
| Gemini | Google Gemini 模型 |

### 9.3 功能

- **带着色器上下文的聊天**：可将当前着色器代码作为上下文发送给 AI
- **教程生成**：AI 生成结构化 JSON，解析为 `TutorialStep` 显示

---

## 10. 教程系统

### 10.1 结构

共 **9 个渐进式课程**，从基础到进阶：

| 步骤 | 主题 | 内容 |
|------|------|------|
| 1 | 纯色 | 基础片段着色器，输出固定颜色 |
| 2 | 法线 | 使用顶点法线进行简单着色 |
| 3 | Lambert | 漫反射光照模型 |
| 4 | Blinn-Phong | 高光 + 漫反射 |
| 5 | 时间动画 | 使用 `uniforms.time` 实现动画 |
| 6 | 顶点位移 | 顶点着色器中的几何变形 |
| 7 | 菲涅尔 | 边缘发光效果 |
| 8 | 后处理 | 全屏着色器、后处理链 |
| 9 | 综合挑战 | 综合运用所学知识 |

### 10.2 数据来源

教程内容定义在 `TutorialData.swift` 中，每步包含标题、说明和示例代码。

---

## 11. Metal API 使用总结

| API | 用途 |
|-----|------|
| `MTLDevice` | GPU 设备句柄，所有 Metal 资源的创建入口 |
| `MTLCommandQueue` | 命令缓冲区序列化 |
| `MTLCommandBuffer` | 每帧 GPU 命令批次 |
| `MTLRenderCommandEncoder` | 编码绘制调用 |
| `MTLRenderPipelineState` | 编译后的顶点+片段着色器对 |
| `MTLDepthStencilState` | 深度测试配置 |
| `MTLLibrary` | 编译后的 MSL 源码（运行时通过 `makeLibrary(source:)`） |
| `MTLFunction` | 命名着色器入口点 |
| `MTLTexture` | 渲染目标、背景纹理 |
| `MTKTextureLoader` | 图片 → GPU 纹理 |
| `MTKMesh` / `MDLMesh` | ModelIO 3D 几何体 |
| `MTKView` | 基于 CAMetalLayer 的可绘制视图 |

---

## 12. 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | macOS 26+ |
| 开发工具 | Xcode 26+ |
| 硬件 | 支持 Metal 的 GPU |

---

*文档版本：1.0 | macOS Shader Canvas 架构说明*
