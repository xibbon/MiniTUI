# Building a Settings Panel

Create a configuration interface with value cycling, submenus, and search.

@Metadata {
    @PageKind(article)
    @PageColor(purple)
}

## Overview

This tutorial shows how to build a settings panel using ``SettingsList``. You'll implement settings with cycling values, submenus for complex options, and optional search functionality.

## What You'll Build

A settings panel with:
- Grouped settings categories
- Value cycling (light/dark theme, etc.)
- Submenus for complex choices
- Search filtering
- Persistence to file

## Step 1: Project Setup

```bash
mkdir SettingsDemo && cd SettingsDemo
swift package init --type executable
```

Update `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SettingsDemo",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MiniTui")
    ],
    targets: [
        .executableTarget(name: "SettingsDemo", dependencies: ["MiniTui"])
    ]
)
```

## Step 2: Define Settings Model

Create `Sources/SettingsDemo/Settings.swift`:

```swift
import Foundation

struct AppSettings: Codable {
    var theme: String = "system"
    var fontSize: Int = 14
    var model: String = "gpt-4"
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
    var streamResponses: Bool = true
    var saveHistory: Bool = true
    var historyLimit: Int = 100

    static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".settings-demo.json")

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: defaultPath),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.defaultPath)
        }
    }
}
```

## Step 3: Create the Theme

Create `Sources/SettingsDemo/Theme.swift`:

```swift
import MiniTui

struct PanelTheme {
    static let settings = SettingsListTheme(
        label: { text, isSelected in
            isSelected ? "\u{001B}[1m\(text)\u{001B}[0m" : text
        },
        value: { text, isSelected in
            let color = isSelected ? "36" : "90"  // Cyan when selected, gray otherwise
            return "\u{001B}[\(color)m\(text)\u{001B}[0m"
        },
        description: { "\u{001B}[90m\($0)\u{001B}[0m" },
        cursor: "\u{001B}[33m▸\u{001B}[0m ",  // Yellow arrow
        hint: { "\u{001B}[90m\($0)\u{001B}[0m" }
    )

    static let selectList = SelectListTheme(
        selectedPrefix: { "\u{001B}[32m● \u{001B}[0m" + $0 },
        selectedText: { "\u{001B}[1m\($0)\u{001B}[0m" },
        description: { "\u{001B}[90m\($0)\u{001B}[0m" },
        scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
        noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }
    )

    static func header(_ text: String) -> String {
        "\u{001B}[1;34m\(text)\u{001B}[0m"
    }

    static func hint(_ text: String) -> String {
        "\u{001B}[90m\(text)\u{001B}[0m"
    }
}
```

## Step 4: Build the Settings Panel

Create `Sources/SettingsDemo/SettingsPanel.swift`:

```swift
import MiniTui
import Foundation

@MainActor
final class SettingsPanel {
    private let tui: TUI
    private var settings: AppSettings
    private var settingsList: SettingsList!
    private let statusText: Text

    init() {
        tui = TUI(terminal: ProcessTerminal())
        settings = AppSettings.load()
        statusText = Text("", paddingX: 1, paddingY: 0)

        setupUI()
    }

    private func setupUI() {
        // Header
        let header = Text(PanelTheme.header("⚙️  Application Settings"), paddingX: 1, paddingY: 1)
        tui.addChild(header)

        // Settings list
        settingsList = createSettingsList()
        tui.addChild(settingsList)

        // Status
        tui.addChild(Spacer(1))
        tui.addChild(statusText)

        // Help
        let help = Text(
            PanelTheme.hint("[↑↓] Navigate  [Enter/Space] Change  [/] Search  [Esc] Close"),
            paddingX: 1,
            paddingY: 1
        )
        tui.addChild(help)

        tui.setFocus(settingsList)

        // Global input
        tui.onGlobalInput = { [weak self] input in
            if matchesKey(input, Key.ctrl("c")) {
                self?.quit()
                return true
            }
            if matchesKey(input, Key.ctrl("s")) {
                self?.saveSettings()
                return true
            }
            return false
        }
    }

    private func createSettingsList() -> SettingsList {
        let items = [
            // Appearance section
            SettingItem(
                id: "section-appearance",
                label: "── Appearance ──",
                currentValue: "",
                values: nil
            ),
            SettingItem(
                id: "theme",
                label: "Theme",
                currentValue: settings.theme,
                values: ["system", "light", "dark"],
                description: "Application color theme"
            ),
            SettingItem(
                id: "fontSize",
                label: "Font Size",
                currentValue: String(settings.fontSize),
                values: ["12", "14", "16", "18", "20"],
                description: "Editor font size in points"
            ),

            // AI section
            SettingItem(
                id: "section-ai",
                label: "── AI Configuration ──",
                currentValue: "",
                values: nil
            ),
            SettingItem(
                id: "model",
                label: "Model",
                currentValue: settings.model,
                submenu: { [weak self] list, item in
                    self?.createModelSubmenu(list: list, item: item)
                },
                description: "AI model for responses"
            ),
            SettingItem(
                id: "temperature",
                label: "Temperature",
                currentValue: String(format: "%.1f", settings.temperature),
                values: ["0.0", "0.3", "0.5", "0.7", "0.9", "1.0"],
                description: "Response randomness (0=focused, 1=creative)"
            ),
            SettingItem(
                id: "maxTokens",
                label: "Max Tokens",
                currentValue: String(settings.maxTokens),
                values: ["1024", "2048", "4096", "8192", "16384"],
                description: "Maximum response length"
            ),

            // Behavior section
            SettingItem(
                id: "section-behavior",
                label: "── Behavior ──",
                currentValue: "",
                values: nil
            ),
            SettingItem(
                id: "streamResponses",
                label: "Stream Responses",
                currentValue: settings.streamResponses ? "On" : "Off",
                values: ["On", "Off"],
                description: "Show responses as they generate"
            ),
            SettingItem(
                id: "saveHistory",
                label: "Save History",
                currentValue: settings.saveHistory ? "On" : "Off",
                values: ["On", "Off"],
                description: "Persist conversation history"
            ),
            SettingItem(
                id: "historyLimit",
                label: "History Limit",
                currentValue: String(settings.historyLimit),
                values: ["50", "100", "200", "500", "1000"],
                description: "Maximum saved conversations"
            ),

            // Actions section
            SettingItem(
                id: "section-actions",
                label: "── Actions ──",
                currentValue: "",
                values: nil
            ),
            SettingItem(
                id: "resetDefaults",
                label: "Reset to Defaults",
                currentValue: "→",
                submenu: { [weak self] list, item in
                    self?.createResetConfirmation(list: list, item: item)
                },
                description: "Restore all default settings"
            ),
            SettingItem(
                id: "exportSettings",
                label: "Export Settings",
                currentValue: "→",
                submenu: { [weak self] list, item in
                    self?.showExportInfo()
                },
                description: "Show settings file location"
            )
        ]

        return SettingsList(
            items: items,
            maxVisible: min(15, tui.terminal.rows - 8),
            theme: PanelTheme.settings,
            onChange: { [weak self] id, newValue in
                self?.handleSettingChange(id: id, value: newValue)
            },
            onCancel: { [weak self] in
                self?.quit()
            },
            options: SettingsListOptions(enableSearch: true)
        )
    }

    private func createModelSubmenu(list: SettingsList, item: SettingItem) -> Component {
        let models = [
            SelectItem(value: "gpt-4", label: "GPT-4", description: "Most capable, slower"),
            SelectItem(value: "gpt-4-turbo", label: "GPT-4 Turbo", description: "Fast and capable"),
            SelectItem(value: "gpt-3.5-turbo", label: "GPT-3.5 Turbo", description: "Fast, less capable"),
            SelectItem(value: "claude-3-opus", label: "Claude 3 Opus", description: "Anthropic's best"),
            SelectItem(value: "claude-3-sonnet", label: "Claude 3 Sonnet", description: "Balanced performance")
        ]

        let selectList = SelectList(items: models, maxVisible: 5, theme: PanelTheme.selectList)

        selectList.onSelect = { [weak self] selected in
            list.updateValue(id: item.id, newValue: selected.value)
            self?.tui.hideOverlay()
            self?.handleSettingChange(id: "model", value: selected.value)
        }

        selectList.onCancel = { [weak self] in
            self?.tui.hideOverlay()
        }

        let box = Box(paddingX: 1, paddingY: 1)
        box.addChild(Text("Select Model:", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(selectList)

        tui.showOverlay(box, options: OverlayOptions(
            width: .absolute(45),
            anchor: .center
        ))
        tui.setFocus(selectList)

        return selectList
    }

    private func createResetConfirmation(list: SettingsList, item: SettingItem) -> Component {
        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text("Reset all settings to defaults?", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(Text(PanelTheme.hint("[Enter] Yes  [Escape] No"), paddingX: 0, paddingY: 0))

        let handle = tui.showOverlay(box, options: OverlayOptions(
            width: .absolute(40),
            anchor: .center
        ))

        let handler = ConfirmHandler(
            onConfirm: { [weak self] in
                handle.hide()
                self?.resetToDefaults()
            },
            onCancel: { handle.hide() }
        )
        tui.setFocus(handler)

        return handler
    }

    private func showExportInfo() -> Component {
        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text("Settings Location:", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(Text(AppSettings.defaultPath.path, paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(Text(PanelTheme.hint("[Enter] Close"), paddingX: 0, paddingY: 0))

        let handle = tui.showOverlay(box, options: OverlayOptions(
            width: .percent(60),
            anchor: .center
        ))

        let handler = DialogHandler { handle.hide() }
        tui.setFocus(handler)

        return handler
    }

    private func handleSettingChange(id: String, value: String) {
        switch id {
        case "theme":
            settings.theme = value
        case "fontSize":
            settings.fontSize = Int(value) ?? 14
        case "model":
            settings.model = value
        case "temperature":
            settings.temperature = Double(value) ?? 0.7
        case "maxTokens":
            settings.maxTokens = Int(value) ?? 4096
        case "streamResponses":
            settings.streamResponses = value == "On"
        case "saveHistory":
            settings.saveHistory = value == "On"
        case "historyLimit":
            settings.historyLimit = Int(value) ?? 100
        default:
            break
        }

        updateStatus("Changed: \(id) = \(value)")
        settings.save()
    }

    private func resetToDefaults() {
        settings = AppSettings()
        settings.save()

        // Recreate settings list with new values
        tui.removeChild(settingsList)
        settingsList = createSettingsList()

        // Find insertion point (after header)
        tui.clear()
        setupUI()

        updateStatus("Settings reset to defaults")
    }

    private func saveSettings() {
        settings.save()
        updateStatus("Settings saved to \(AppSettings.defaultPath.lastPathComponent)")
    }

    private func updateStatus(_ message: String) {
        statusText.setText(PanelTheme.hint(message))
        tui.requestRender()

        // Clear status after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                statusText.setText("")
                tui.requestRender()
            }
        }
    }

    private func quit() {
        settings.save()
        tui.stop()
        exit(0)
    }

    func run() {
        tui.start()
        RunLoop.main.run()
    }
}

// Helper components
@MainActor
final class DialogHandler: Component {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.enter) || matchesKey(data, Key.escape) {
            onDismiss()
        }
    }
}

@MainActor
final class ConfirmHandler: Component {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.enter) {
            onConfirm()
        } else if matchesKey(data, Key.escape) {
            onCancel()
        }
    }
}
```

## Step 5: Create Entry Point

Create `Sources/SettingsDemo/main.swift`:

```swift
@main
struct Main {
    @MainActor
    static func main() {
        let panel = SettingsPanel()
        panel.run()
    }
}
```

## Step 6: Build and Run

```bash
swift build
swift run SettingsDemo
```

## Key Concepts

### Section Headers

Use settings with empty `values` as section headers:

```swift
SettingItem(
    id: "section-header",
    label: "── Section Name ──",
    currentValue: "",
    values: nil
)
```

### Value Cycling

For simple choices, provide a `values` array:

```swift
SettingItem(
    id: "theme",
    label: "Theme",
    currentValue: "dark",
    values: ["light", "dark", "system"]
)
```

### Submenus

For complex selections, use a `submenu` closure:

```swift
SettingItem(
    id: "model",
    label: "Model",
    currentValue: "gpt-4",
    submenu: { list, item in
        // Return a component (usually SelectList)
    }
)
```

### Search

Enable search with `SettingsListOptions`:

```swift
SettingsListOptions(enableSearch: true)
```

## Summary

You've built a full-featured settings panel with:
- ``SettingsList`` for the main interface
- Value cycling for simple options
- ``SelectList`` submenus for complex choices
- Search filtering
- Persistent storage

## Topics

### Related Components

- ``SettingsList``
- ``SettingItem``
- ``SelectList``
- ``SettingsListTheme``
