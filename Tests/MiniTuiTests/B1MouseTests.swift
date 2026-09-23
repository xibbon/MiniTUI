import Foundation
import Testing
@testable import MiniTui

@MainActor
func b1Mouse(_ type: TuiMouseEventType, _ x: Int = 1, _ y: Int = 0, width: Int = 40, height: Int = 10, button: TuiMouseButton = .left, delta: Int? = nil) -> TuiMouseEvent {
    TuiMouseEvent(type: type, button: button, x: x, y: y, screenX: x, screenY: y, width: width, height: height, wheelDelta: delta, clickCount: type == .click ? 1 : nil)
}

@MainActor
private final class MouseProbe: Component {
    var height = 1
    var renders = 0
    var invalidations = 0
    var events: [TuiMouseEvent] = []
    var result: TuiMouseEventResult?
    func render(width: Int) -> [String] { renders += 1; return Array(repeating: "probe", count: height) }
    func invalidate() { invalidations += 1 }
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? { events.append(event); return result }
}

@MainActor
private final class MouseInputContainer: Container, MouseFocusOwner {
    let input = Input()
    override init() { super.init(); addChild(input) }
    override func handleInput(_ data: String) { input.handleInput(data) }
}

private let b1SettingsTheme = SettingsListTheme(label: { text, _ in text }, value: { text, _ in text }, description: { $0 }, cursor: "> ", hint: { $0 })

@MainActor
@Suite("B1 mouse components")
struct B1MouseTests {
    @Test("positions a single-line input cursor on press")
    func inputPress() {
        let input = Input()
        input.setValue("hello")
        _ = input.render(width: 20)
        #expect(input.handleMouse(b1Mouse(.press, 4, 0, width: 20, height: 1))?.handled == true)
        input.handleInput("X")
        #expect(input.getValue() == "heXllo")
        #expect(input.handleMouse(b1Mouse(.click)) == nil)
        #expect(input.handleMouse(b1Mouse(.press, button: .right)) == nil)
        #expect(input.handleMouse(b1Mouse(.press, 1, 1)) == nil)
    }

    @Test("selects and activates list rows")
    func listRows() {
        let list = SelectList(items: ["a", "b", "c", "d", "e"].map { SelectItem(value: $0, label: $0.uppercased()) }, maxVisible: 3, theme: defaultSelectListTheme)
        var selected: String?
        var changes: [String] = []
        list.onSelect = { selected = $0.value }
        list.onSelectionChange = { changes.append($0.value) }
        #expect(list.handleMouse(b1Mouse(.press, 1, 2))?.focus == true)
        #expect(list.getSelectedItem()?.value == "c")
        #expect(list.handleMouse(b1Mouse(.click, 1, 2))?.handled == true)
        #expect(selected == "c")
        #expect(changes == ["c"])
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.handleMouse(b1Mouse(.move, 1, 0, button: .none)) == nil)
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.getSelectedItem()?.value == "c")
        #expect(list.handleMouse(b1Mouse(.wheel, delta: -10))?.render == true)
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.getSelectedItem()?.value == "b")
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.handleMouse(b1Mouse(.wheel, delta: -10))?.render == true)
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.getSelectedItem()?.value == "a")
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.handleMouse(b1Mouse(.wheel, delta: -10))?.render == false)
        #expect(list.handleMouse(b1Mouse(.press, button: .right)) == nil)
    }

    @Test("activates settings rows")
    func settingsRows() {
        var changes: [String] = []
        let list = SettingsList(items: [
            SettingItem(id: "mode", label: "Mode", currentValue: "one", values: ["one", "two"]),
            SettingItem(id: "other", label: "Other", currentValue: "off", values: ["off", "on"]),
            SettingItem(id: "third", label: "Third", currentValue: "low", values: ["low", "high"]),
            SettingItem(id: "fourth", label: "Fourth", currentValue: "x", values: ["x", "y"]),
        ], maxVisible: 3, theme: b1SettingsTheme, onChange: { changes.append("\($0):\($1)") }, onCancel: {})
        _ = list.handleMouse(b1Mouse(.press, 1, 2))
        _ = list.handleMouse(b1Mouse(.click, 1, 2))
        #expect(changes == ["third:high"])
        list.selectItem(id: "other")
        list.handleInput("\r")
        #expect(changes.last == "other:on")
        list.selectItem(id: "missing")
        list.handleInput("\r")
        #expect(changes.last == "other:off")
    }

    @Test("settings search rows and submenu navigation")
    func settingsNavigation() {
        var done: SettingsSubmenuDone?
        var opened = false
        let child = Input()
        let list = SettingsList(items: [
            SettingItem(id: "first", label: "First", currentValue: "a", submenuWithNavigation: { _, callback in done = callback; return child }),
            SettingItem(id: "next", label: "Next", currentValue: "b", submenuWithNavigation: { _, _ in opened = true; return Text("next submenu") }),
        ], maxVisible: 5, theme: b1SettingsTheme, onChange: { _, _ in }, onCancel: {}, options: SettingsListOptions(enableSearch: true))
        #expect(list.handleMouse(b1Mouse(.press, 2, 0))?.focus == true)
        #expect(list.handleMouse(b1Mouse(.wheel, 1, 1, delta: 1)) == nil)
        // Upstream v0.85.1: hover no longer changes selection (#select-list hover stability).
        #expect(list.handleMouse(b1Mouse(.move, 1, 2, button: .none)) == nil)
        _ = list.handleMouse(b1Mouse(.click, 1, 2))
        #expect(list.handleMouse(b1Mouse(.press, 2, 0))?.focus == true)
        done?("updated", options: SettingsSubmenuOptions(navigateTo: "next"))
        #expect(opened)
        #expect(list.render(width: 40).joined().contains("next submenu"))
    }

    @Test("dispatch preserves target, coordinates, flags, and default render behavior")
    func dispatchFlags() throws {
        let child = MouseProbe()
        var event = b1Mouse(.press, 2, 1, width: 12, height: 3)
        event.screenX = 20; event.screenY = 30; event.shift = true; event.ctrl = true
        #expect(dispatchMouseEvent(child, event) == nil)
        child.result = TuiMouseEventResult(render: true)
        #expect(dispatchMouseEvent(child, event) == nil)
        child.result = TuiMouseEventResult(capture: true, focus: true)
        let result = try #require(dispatchMouseEvent(child, event))
        #expect(result.handled == true && result.capture == true)
        #expect(result.focusTarget === child)
        #expect(result.target.originX == 18 && result.target.originY == 29)
        var next = event; next.screenX = 24; next.screenY = 31
        let local = retargetMouseEvent(next, result.target)
        #expect(local.x == 6 && local.y == 2 && local.width == 12 && local.height == 3)
        #expect(local.shift && local.ctrl)
        for type in [TuiMouseEventType.press, .click, .drag, .wheel] { #expect(result.shouldRender(for: type)) }
        for type in [TuiMouseEventType.move, .release] { #expect(!result.shouldRender(for: type)) }
        result.render = false
        #expect(!result.shouldRender(for: .press))
        #expect(dispatchMouseEvent(Text("plain"), event) == nil)
    }

    @Test("container and padded box use last rendered child heights")
    func containerGeometry() throws {
        let root = Container()
        let spacer = MouseProbe(); spacer.height = 2
        let box = Box(paddingX: 2, paddingY: 1)
        let child = MouseProbe(); child.result = TuiMouseEventResult(focus: true)
        box.addChild(child); root.addChild(spacer); root.addChild(box)
        _ = root.render(width: 20)
        spacer.height = 5
        let result = try #require(dispatchMouseEvent(root, b1Mouse(.press, 4, 3, width: 20, height: 5)))
        #expect(result.target.component === child)
        #expect(result.focusTarget === child)
        #expect(result.target.originX == 2 && result.target.originY == 3)
        #expect(child.events.last?.x == 2 && child.events.last?.y == 0)
        #expect(child.renders == 1 && spacer.renders == 1)
        #expect(dispatchMouseEvent(root, b1Mouse(.press, 1, 3, width: 20, height: 5)) == nil)
        _ = dispatchMouseEvent(root, b1Mouse(.press, 4, 6, width: 21, height: 10))
        #expect(child.renders == 2 && spacer.renders == 2)
        #expect(dispatchMouseEvent(root, b1Mouse(.press, 1, -1)) == nil)
        let owner = MouseInputContainer()
        _ = owner.render(width: 20)
        #expect(dispatchMouseEvent(owner, b1Mouse(.press, 2, 0, width: 20))?.focusTarget === owner)
    }

    @Test("MouseRegion dispatches to its child first and forwards invalidation")
    func region() throws {
        let child = MouseProbe()
        var calls = 0
        let region = MouseRegion(child: child) { _ in calls += 1; return TuiMouseEventResult(handled: true) }
        #expect(region.render(width: 20) == ["probe"])
        region.invalidate(); #expect(child.invalidations == 1)
        #expect(dispatchMouseEvent(region, b1Mouse(.click))?.target.component === region)
        child.result = TuiMouseEventResult(capture: true)
        let result = try #require(dispatchMouseEvent(region, b1Mouse(.press)))
        #expect(result.target.component === child && calls == 1)
    }

    @Test("overlay bounds and dispatch use the visible topmost rendered rectangle")
    func overlayBounds() async throws {
        let terminal = VirtualTerminal(columns: 30, rows: 10)
        let tui = TUI(terminal: terminal)
        let owner = MouseInputContainer()
        let handle = tui.showOverlay(owner, options: OverlayOptions(width: 10, row: 2, col: 3))
        #expect(handle.getBounds() == nil)
        tui.start(); await tui.waitForRender()
        defer { tui.stop() }
        #expect(handle.getBounds() == OverlayBounds(row: 2, col: 3, width: 10, height: 1))
        #expect(tui.isOverlayFocused())
        #expect(tui.resolveMouseFocusTarget(owner.input) === owner)
        let hit = tui.dispatchMouseToOverlay(b1Mouse(.press, 7, 2))
        #expect(hit.hit && hit.result?.focusTarget === owner)
        #expect(hit.result?.target.component === owner.input)
        let top = tui.showOverlay(Text("top", paddingX: 0, paddingY: 0), options: OverlayOptions(width: 10, row: 2, col: 3))
        await tui.waitForRender()
        let blocked = tui.dispatchMouseToOverlay(b1Mouse(.press, 7, 2))
        #expect(blocked.hit && blocked.result == nil)
        #expect(!tui.dispatchMouseToOverlay(b1Mouse(.press, 25, 9)).hit)
        top.setHidden(true); #expect(top.getBounds() == nil)
        await tui.waitForRender()
        #expect(tui.dispatchMouseToOverlay(b1Mouse(.press, 7, 2)).result?.focusTarget === owner)
        handle.hide(); #expect(handle.getBounds() == nil)
        await tui.waitForRender()
        #expect(!tui.dispatchMouseToOverlay(b1Mouse(.press, 7, 2)).hit)
    }

    @Test("settings label alignment uses a 36-column limit")
    func settingLabels() {
        let list = SettingsList(items: [
            SettingItem(id: "long", label: String(repeating: "a", count: 40), currentValue: "long"),
            SettingItem(id: "short", label: "x", currentValue: "VALUE")
        ], maxVisible: 5, theme: b1SettingsTheme, onChange: { _, _ in }, onCancel: {})
        let line = list.render(width: 80)[1]
        #expect(line.hasPrefix("  x" + String(repeating: " ", count: 37) + "VALUE"))
    }

    @Test("focus forwarding does not change a reusable child result")
    func resultCopy() {
        let probe = MouseProbe()
        probe.result = TuiMouseEventResult(handled: true, focus: false)
        let list = SettingsList(items: [SettingItem(id: "a", label: "a", currentValue: "a", submenu: { _, _ in probe })],
                                maxVisible: 5, theme: b1SettingsTheme, onChange: { _, _ in }, onCancel: {})
        list.handleInput("\r")
        #expect(list.handleMouse(b1Mouse(.press))?.focus == true)
        #expect(probe.result?.focus == false)
    }

    @Test("TUI updates opt-in focus state without enabling the hardware cursor")
    func focusState() {
        let tui = TUI(terminal: VirtualTerminal())
        let input = Input(options: InputOptions(placeholder: "Find"))
        tui.setFocus(input)
        #expect(input.focused && !input.usesSystemCursor)
        #expect(input.render(width: 20)[0].contains(systemCursorMarker))
        tui.setFocus(nil)
        #expect(!input.focused)
        #expect(!input.render(width: 20)[0].contains(systemCursorMarker))
    }

    @Test("editor click moves the cursor but selection gestures remain unhandled")
    func editorMouse() {
        let editor = Editor(theme: defaultEditorTheme)
        editor.setText("hello")
        _ = editor.render(width: 20)
        for type in [TuiMouseEventType.press, .drag, .release] { #expect(editor.handleMouse(b1Mouse(type, 2, 1)) == nil) }
        #expect(editor.handleMouse(b1Mouse(.click, 2, 1))?.focus == true)
        editor.handleInput("X"); #expect(editor.getText() == "heXllo")
        #expect(editor.handleMouse(b1Mouse(.click, 0, 0))?.focus == true)
        editor.setText("abcdef")
        _ = editor.render(width: 5)
        _ = editor.handleMouse(b1Mouse(.click, 10, 1, width: 5))
        editor.handleInput("X"); #expect(editor.getText() == "abcXdef")
        editor.setText("a界e\u{301}z")
        _ = editor.render(width: 20)
        _ = editor.handleMouse(b1Mouse(.click, 2, 1, width: 20))
        editor.handleInput("X"); #expect(editor.getText() == "aX界e\u{301}z")
    }
}
