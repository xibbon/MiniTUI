import Foundation
import Darwin
import MiniTui

private enum DemoScreen: String, CaseIterable {
    case text
    case truncatedText
    case input
    case editor
    case selectList
    case settingsList
    case markdown
    case box
    case loader
    case cancellableLoader
    case image
    case spacer
    case quit

    var label: String {
        switch self {
        case .text: return "Text"
        case .truncatedText: return "TruncatedText"
        case .input: return "Input"
        case .editor: return "Editor"
        case .selectList: return "SelectList"
        case .settingsList: return "SettingsList"
        case .markdown: return "Markdown"
        case .box: return "Box"
        case .loader: return "Loader"
        case .cancellableLoader: return "CancellableLoader"
        case .image: return "Image"
        case .spacer: return "Spacer"
        case .quit: return "Quit"
        }
    }

    var description: String {
        switch self {
        case .text: return "Wrapped text with padding and background"
        case .truncatedText: return "Single-line truncation with ANSI"
        case .input: return "Single-line input with shortcuts"
        case .editor: return "Multi-line editor with autocomplete"
        case .selectList: return "Selectable list with descriptions"
        case .settingsList: return "Settings list with values and submenu"
        case .markdown: return "Markdown rendering"
        case .box: return "Padded container with background"
        case .loader: return "Spinner animation"
        case .cancellableLoader: return "Spinner that cancels on Escape"
        case .image: return "Image rendering and fallback"
        case .spacer: return "Blank line spacer"
        case .quit: return "Exit the demo"
        }
    }
}

private enum Ansi {
    static func wrap(_ codes: [String], _ text: String) -> String {
        return "\u{001B}[" + codes.joined(separator: ";") + "m" + text + "\u{001B}[0m"
    }

    static func blue(_ text: String) -> String { wrap(["34"], text) }
    static func cyan(_ text: String) -> String { wrap(["36"], text) }
    static func yellow(_ text: String) -> String { wrap(["33"], text) }
    static func green(_ text: String) -> String { wrap(["32"], text) }
    static func red(_ text: String) -> String { wrap(["31"], text) }
    static func gray(_ text: String) -> String { wrap(["90"], text) }
    static func dim(_ text: String) -> String { wrap(["2"], text) }
    static func bold(_ text: String) -> String { wrap(["1"], text) }
    static func italic(_ text: String) -> String { wrap(["3"], text) }
    static func underline(_ text: String) -> String { wrap(["4"], text) }
    static func strikethrough(_ text: String) -> String { wrap(["9"], text) }
    static func header(_ text: String) -> String { wrap(["44", "97"], text) }
    static func boxed(_ text: String) -> String { wrap(["47", "30"], text) }
}

private let selectListTheme = SelectListTheme(
    selectedPrefix: { Ansi.blue($0) },
    selectedText: { Ansi.bold($0) },
    description: { Ansi.dim($0) },
    scrollInfo: { Ansi.dim($0) },
    noMatch: { Ansi.dim($0) }
)

private let editorTheme = EditorTheme(
    borderColor: { Ansi.dim($0) },
    selectList: selectListTheme
)

private let markdownTheme = MarkdownTheme(
    heading: { Ansi.bold($0) },
    link: { Ansi.blue($0) },
    linkUrl: { Ansi.dim($0) },
    code: { Ansi.yellow($0) },
    codeBlock: { Ansi.green($0) },
    codeBlockBorder: { Ansi.dim($0) },
    quote: { Ansi.italic($0) },
    quoteBorder: { Ansi.dim($0) },
    hr: { Ansi.dim($0) },
    listBullet: { Ansi.cyan($0) },
    bold: { Ansi.bold($0) },
    italic: { Ansi.italic($0) },
    strikethrough: { Ansi.strikethrough($0) },
    underline: { Ansi.underline($0) }
)

private let settingsTheme = SettingsListTheme(
    label: { text, isSelected in
        return isSelected ? Ansi.bold(text) : text
    },
    value: { text, isSelected in
        return isSelected ? Ansi.blue(text) : Ansi.dim(text)
    },
    description: { Ansi.dim($0) },
    cursor: Ansi.blue(">"),
    hint: { Ansi.dim($0) }
)

private let imageTheme = ImageTheme(
    fallbackColor: { Ansi.dim($0) }
)

private struct ScreenState {
    let body: Component
    let footer: String
    let cleanup: (() -> Void)?
}

@MainActor
private final class MenuScreen: Component {
    private let container = Container()
    private let list: SelectList
    var onSelect: ((DemoScreen) -> Void)?
    var onCancel: (() -> Void)?

    init(theme: SelectListTheme) {
        let items = DemoScreen.allCases.map { screen in
            SelectItem(value: screen.rawValue, label: screen.label, description: screen.description)
        }
        list = SelectList(items: items, maxVisible: 12, theme: theme)

        let intro = Text("Select a component to demo.", paddingX: 1, paddingY: 0)
        container.addChild(intro)
        container.addChild(Spacer(1))
        container.addChild(list)

        list.onSelect = { [weak self] item in
            guard let screen = DemoScreen(rawValue: item.value) else { return }
            self?.onSelect?(screen)
        }
        list.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        list.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class InputDemo: Component {
    private let container = Container()
    private let input = Input()
    private let output = Text("Submitted: (none)", paddingX: 1, paddingY: 0)
    private let onExit: () -> Void

    init(onExit: @escaping () -> Void) {
        self.onExit = onExit
        let instructions = Text("Type a line and press Enter. Ctrl-D returns to menu.", paddingX: 1, paddingY: 0)
        container.addChild(instructions)
        container.addChild(Spacer(1))
        container.addChild(input)
        container.addChild(Spacer(1))
        container.addChild(output)

        input.onSubmit = { [weak self] text in
            self?.output.setText("Submitted: \(text)")
        }
        input.onEnd = { [weak self] in
            self?.onExit()
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        input.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class EditorDemo: Component {
    private let container = Container()
    private let editor: Editor
    private let output = Text("Last submit: (none)", paddingX: 1, paddingY: 0)

    init(theme: EditorTheme) {
        editor = Editor(theme: theme)
        let instructions = Text(
            "Tab triggers autocomplete. Enter submits. Shift+Enter inserts a newline.",
            paddingX: 1,
            paddingY: 0
        )
        container.addChild(instructions)
        container.addChild(Spacer(1))
        container.addChild(editor)
        container.addChild(Spacer(1))
        container.addChild(output)

        let commands = [
            SlashCommand(name: "help", description: "Show available commands"),
            SlashCommand(name: "open", description: "Open a file"),
            SlashCommand(name: "theme", description: "Change theme")
        ]
        let items = [
            AutocompleteItem(value: "@Sources/", label: "Sources/", description: "Project sources"),
            AutocompleteItem(value: "@Tests/", label: "Tests/", description: "Project tests")
        ]
        let provider = CombinedAutocompleteProvider(commands: commands, items: items)
        editor.setAutocompleteProvider(provider)

        editor.onSubmit = { [weak self] text in
            self?.editor.addToHistory(text)
            self?.output.setText("Last submit: \(text)")
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        editor.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class SelectListDemo: Component {
    private let container = Container()
    private let list: SelectList
    private let output = Text("Selected: (none)", paddingX: 1, paddingY: 0)

    init(theme: SelectListTheme, onExit: @escaping () -> Void) {
        let items = [
            SelectItem(value: "alpha", label: "Alpha", description: "First choice"),
            SelectItem(value: "beta", label: "Beta", description: "Second choice"),
            SelectItem(value: "gamma", label: "Gamma", description: "Third choice"),
            SelectItem(value: "delta", label: "Delta", description: "Fourth choice"),
            SelectItem(value: "epsilon", label: "Epsilon", description: "Fifth choice")
        ]
        list = SelectList(items: items, maxVisible: 6, theme: theme)
        let instructions = Text("Use arrows to move. Enter selects. Esc returns.", paddingX: 1, paddingY: 0)
        container.addChild(instructions)
        container.addChild(Spacer(1))
        container.addChild(list)
        container.addChild(Spacer(1))
        container.addChild(output)

        list.onSelectionChange = { [weak self] item in
            self?.output.setText("Selected: \(item.value)")
        }
        list.onSelect = { [weak self] item in
            self?.output.setText("Selected: \(item.value)")
        }
        list.onCancel = {
            onExit()
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        list.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class SimpleSelectSubmenu: Component {
    private let container = Container()
    private let list: SelectList
    private let onFinish: (String?) -> Void

    init(title: String, options: [String], selected: String, theme: SelectListTheme, onFinish: @escaping (String?) -> Void) {
        self.onFinish = onFinish
        let items = options.map { value in
            SelectItem(value: value, label: value, description: nil)
        }
        list = SelectList(items: items, maxVisible: 6, theme: theme)
        if let index = options.firstIndex(of: selected) {
            list.setSelectedIndex(index)
        }

        let header = Text(title, paddingX: 1, paddingY: 0)
        let hint = Text("Enter selects. Esc returns.", paddingX: 1, paddingY: 0)
        container.addChild(header)
        container.addChild(Spacer(1))
        container.addChild(list)
        container.addChild(Spacer(1))
        container.addChild(hint)

        list.onSelect = { [weak self] item in
            self?.onFinish(item.value)
        }
        list.onCancel = { [weak self] in
            self?.onFinish(nil)
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        list.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class SettingsListDemo: Component {
    private let container = Container()
    private let list: SettingsList
    private let output = Text("Last change: (none)", paddingX: 1, paddingY: 0)

    init(theme: SettingsListTheme, selectTheme: SelectListTheme, onExit: @escaping () -> Void) {
        let items = [
            SettingItem(
                id: "theme",
                label: "Theme",
                description: "Color mode for the UI",
                currentValue: "System",
                values: ["System", "Light", "Dark"]
            ),
            SettingItem(
                id: "density",
                label: "Density",
                description: "Row spacing for lists",
                currentValue: "Comfortable",
                values: ["Compact", "Comfortable", "Spacious"]
            ),
            SettingItem(
                id: "accent",
                label: "Accent",
                description: "Accent color selection",
                currentValue: "Blue",
                submenu: { current, onSelect in
                    return SimpleSelectSubmenu(
                        title: "Pick an accent color",
                        options: ["Blue", "Green", "Orange", "Gray"],
                        selected: current,
                        theme: selectTheme,
                        onFinish: onSelect
                    )
                }
            )
        ]

        list = SettingsList(
            items: items,
            maxVisible: 6,
            theme: theme,
            onChange: { [weak output] id, value in
                output?.setText("Last change: \(id) = \(value)")
            },
            onCancel: onExit
        )

        container.addChild(list)
        container.addChild(Spacer(1))
        container.addChild(output)
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        list.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }
}

@MainActor
private final class CancellableLoaderDemo: Component {
    private let container = Container()
    private let loader: CancellableLoader
    private let status = Text("Status: running", paddingX: 1, paddingY: 0)

    init(tui: TUI) {
        loader = CancellableLoader(
            ui: tui,
            spinnerColorFn: { Ansi.cyan($0) },
            messageColorFn: { Ansi.dim($0) },
            message: "Press Escape to cancel"
        )
        let instructions = Text("Esc cancels the loader. Ctrl-C returns to menu.", paddingX: 1, paddingY: 0)
        container.addChild(instructions)
        container.addChild(Spacer(1))
        container.addChild(loader)
        container.addChild(Spacer(1))
        container.addChild(status)

        loader.onAbort = { [weak self, weak tui] in
            self?.status.setText("Status: cancelled")
            self?.loader.dispose()
            tui?.requestRender()
        }
    }

    func render(width: Int) -> [String] {
        return container.render(width: width)
    }

    func handleInput(_ data: String) {
        loader.handleInput(data)
    }

    func invalidate() {
        container.invalidate()
    }

    func dispose() {
        loader.dispose()
    }
}

@MainActor
private final class DemoApp: Component {
    private let tui: TUI
    private let header: Text
    private let footer: Text
    private let menuScreen: MenuScreen
    private var body: Component
    private var cleanup: (() -> Void)?
    private var current: DemoScreen?

    init(tui: TUI) {
        self.tui = tui
        header = Text("MiniTui Component Demo", paddingX: 1, paddingY: 0, customBgFn: Ansi.header)
        footer = Text("Use arrows and Enter to select. Esc quits.", paddingX: 1, paddingY: 0)
        menuScreen = MenuScreen(theme: selectListTheme)
        body = menuScreen

        menuScreen.onSelect = { [weak self] screen in
            if screen == .quit {
                self?.quit()
                return
            }
            self?.showScreen(screen)
        }
        menuScreen.onCancel = { [weak self] in
            self?.quit()
        }
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: header.render(width: width))
        lines.append("")
        lines.append(contentsOf: body.render(width: width))
        lines.append("")
        lines.append(contentsOf: footer.render(width: width))
        return lines
    }

    func handleInput(_ data: String) {
        if current == nil {
            if isCtrlC(data) {
                quit()
                return
            }
            body.handleInput(data)
            return
        }

        if isCtrlC(data) {
            showMenu()
            return
        }

        body.handleInput(data)
    }

    func invalidate() {
        header.invalidate()
        footer.invalidate()
        body.invalidate()
    }

    private func showMenu() {
        cleanup?()
        cleanup = nil
        current = nil
        body = menuScreen
        header.setText("MiniTui Component Demo")
        footer.setText("Use arrows and Enter to select. Esc quits.")
        tui.requestRender()
    }

    private func showScreen(_ screen: DemoScreen) {
        cleanup?()
        cleanup = nil
        current = screen

        let state = buildScreen(for: screen)
        body = state.body
        footer.setText(state.footer)
        header.setText("MiniTui - \(screen.label)")
        cleanup = state.cleanup

        tui.requestRender()
    }

    private func buildScreen(for screen: DemoScreen) -> ScreenState {
        switch screen {
        case .text:
            let container = Container()
            let regular = Text("This is a wrapped text block with padding.", paddingX: 1, paddingY: 0)
            let highlighted = Text(
                "This text uses a background color.",
                paddingX: 1,
                paddingY: 0,
                customBgFn: { Ansi.wrap(["44", "97"], $0) }
            )
            container.addChild(regular)
            container.addChild(Spacer(1))
            container.addChild(highlighted)
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .truncatedText:
            let container = Container()
            let label = Text("Resize the terminal to see truncation.", paddingX: 1, paddingY: 0)
            let longText = "\(Ansi.red("Red")) \(Ansi.blue("blue")) \(Ansi.green("green")) text that should truncate when the width is small."
            let truncated = TruncatedText(longText, paddingX: 1, paddingY: 0)
            container.addChild(label)
            container.addChild(Spacer(1))
            container.addChild(truncated)
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .input:
            let demo = InputDemo(onExit: { [weak self] in
                self?.showMenu()
            })
            return ScreenState(
                body: demo,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .editor:
            let demo = EditorDemo(theme: editorTheme)
            return ScreenState(
                body: demo,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .selectList:
            let demo = SelectListDemo(theme: selectListTheme, onExit: { [weak self] in
                self?.showMenu()
            })
            return ScreenState(
                body: demo,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .settingsList:
            let demo = SettingsListDemo(
                theme: settingsTheme,
                selectTheme: selectListTheme,
                onExit: { [weak self] in
                    self?.showMenu()
                }
            )
            return ScreenState(
                body: demo,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .markdown:
            let markdownText = """
            # MiniTui Markdown

            This is **bold**, *italic*, and `inline code`.

            - Bullet one
            - Bullet two
            - Bullet three

            > Blockquote with a few words.

            ```
            let value = 42
            print(value)
            ```

            [MiniTui on GitHub](https://github.com/)
            """
            let markdown = Markdown(
                markdownText,
                paddingX: 1,
                paddingY: 0,
                theme: markdownTheme,
                defaultTextStyle: DefaultTextStyle(color: { Ansi.gray($0) })
            )
            return ScreenState(
                body: markdown,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .box:
            let container = Container()
            let box = Box(paddingX: 1, paddingY: 1, bgFn: Ansi.boxed)
            box.addChild(Text("Box adds padding and background.", paddingX: 1, paddingY: 0))
            box.addChild(Spacer(1))
            box.addChild(TruncatedText("Box can wrap multiple children.", paddingX: 1, paddingY: 0))
            container.addChild(box)
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .loader:
            let container = Container()
            let loader = Loader(
                ui: tui,
                spinnerColorFn: { Ansi.cyan($0) },
                messageColorFn: { Ansi.dim($0) },
                message: "Loading demo"
            )
            let instructions = Text("Spinner runs until you return to menu.", paddingX: 1, paddingY: 0)
            container.addChild(instructions)
            container.addChild(Spacer(1))
            container.addChild(loader)
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: { [weak loader] in
                    loader?.stop()
                }
            )
        case .cancellableLoader:
            let demo = CancellableLoaderDemo(tui: tui)
            return ScreenState(
                body: demo,
                footer: "Ctrl-C returns to menu.",
                cleanup: { [weak demo] in
                    demo?.dispose()
                }
            )
        case .image:
            let container = Container()
            let instructions = Text("If your terminal supports images, one will render below.", paddingX: 1, paddingY: 0)
            let base64Png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X+5e0AAAAASUVORK5CYII="
            let image = Image(
                base64Data: base64Png,
                mimeType: "image/png",
                theme: imageTheme,
                options: ImageOptions(maxWidthCells: 20, maxHeightCells: 10, filename: "demo.png")
            )
            container.addChild(instructions)
            container.addChild(Spacer(1))
            container.addChild(image)
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .spacer:
            let container = Container()
            container.addChild(Text("Above the spacer.", paddingX: 1, paddingY: 0))
            container.addChild(Spacer(3))
            container.addChild(Text("Below the spacer.", paddingX: 1, paddingY: 0))
            return ScreenState(
                body: container,
                footer: "Ctrl-C returns to menu.",
                cleanup: nil
            )
        case .quit:
            return ScreenState(body: Text("Exiting...", paddingX: 1, paddingY: 0), footer: "", cleanup: nil)
        }
    }

    private func quit() {
        cleanup?()
        tui.stop()
        Darwin.exit(0)
    }
}

@main
struct Demo {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())
        let app = DemoApp(tui: tui)
        tui.addChild(app)
        tui.setFocus(app)
        tui.start()
        RunLoop.main.run()
    }
}
