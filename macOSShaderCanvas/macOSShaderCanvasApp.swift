//
//  macOSShaderCanvasApp.swift
//  macOSShaderCanvas
//
//  Created by Lingheng Tony Tao on 2/24/26.
//
//  APPLICATION ENTRY POINT
//  ───────────────────────
//  This file defines the app's main structure and the macOS menu bar commands.
//
//  MENU → VIEW COMMUNICATION:
//  ──────────────────────────
//  macOS menu bar items cannot directly call methods on SwiftUI views.
//  Instead, we use NotificationCenter as a decoupled message bus:
//
//    Menu Button → NotificationCenter.post() → ContentView.onReceive()
//
//  This keeps the App struct thin and the ContentView in full control of
//  all state mutations. See SharedTypes.swift for notification name definitions.
//
//  MENU STRUCTURE:
//  ───────────────
//  File
//  ├── New Canvas        (⌘N)     → .canvasNew
//  ├── Open...           (⌘O)     → .canvasOpen
//  ├── Tutorial          (⇧⌘T)    → .canvasTutorial
//  ├── Save              (⌘S)     → .canvasSave
//  └── Save As...        (⇧⌘S)    → .canvasSaveAs
//
//  AI
//  ├── AI Chat           (⌘L)     → .aiChat
//  └── AI Settings...    (⌥⌘,)    → .aiSettings
//

import SwiftUI

/// The main application entry point. Uses SwiftUI's `App` protocol (macOS 11+).
///
/// The `@main` attribute designates this struct as the app's entry point,
/// replacing the traditional AppDelegate / NSApplicationMain pattern.
@main
struct macOSShaderCanvasApp: App {
    @State private var appState = AppState()
    @State private var recentManager = RecentProjectManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.currentScreen == .hub {
                    HubView(appState: appState, recentManager: recentManager)
                } else if appState.canvasMode.isLab {
                    LabView(appState: appState, recentManager: recentManager)
                } else {
                    ContentView(appState: appState, recentManager: recentManager)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: appState.currentScreen == .hub)
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Canvas") {
                    NotificationCenter.default.post(name: .canvasNew, object: nil)
                }
                .keyboardShortcut("n")

                Divider()

                Button("Open...") {
                    NotificationCenter.default.post(name: .canvasOpen, object: nil)
                }
                .keyboardShortcut("o")

                Divider()

                Button("Back to Hub") {
                    NotificationCenter.default.post(name: .backToHub, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Tutorial") {
                    NotificationCenter.default.post(name: .canvasTutorial, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .canvasSave, object: nil)
                }
                .keyboardShortcut("s")

                Button("Save As...") {
                    NotificationCenter.default.post(name: .canvasSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("AI") {
                Button("AI Chat") {
                    NotificationCenter.default.post(name: .aiChat, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Divider()

                Button("AI Settings...") {
                    NotificationCenter.default.post(name: .aiSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
            }
        }
    }
}
