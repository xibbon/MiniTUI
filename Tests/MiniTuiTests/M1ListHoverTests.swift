import Testing
@testable import MiniTui

@MainActor
private func listMouse(_ type: TuiMouseEventType, y: Int, button: TuiMouseButton = .left, wheelDelta: Int? = nil) -> TuiMouseEvent {
    TuiMouseEvent(type: type, button: button, x: 1, y: y, screenX: 1, screenY: y,
                  width: 80, height: 10, wheelDelta: wheelDelta)
}

private let listSettingsTheme = SettingsListTheme(label: { text, _ in text }, value: { text, _ in text },
                                                  description: { $0 }, cursor: "> ", hint: { $0 })

@MainActor
@Suite("M1 list hover stability")
struct M1ListHoverTests {
    @Test("SelectList hover leaves selection and visible rows stable, then click commits the pressed row")
    func selectListHover() {
        for row in [0, 4] {
            let items = (0..<12).map { SelectItem(value: "item-\($0)", label: "Item \($0)") }
            let list = SelectList(items: items, maxVisible: 5, theme: defaultSelectListTheme)
            var changes: [String] = []
            var selected: String?
            list.onSelectionChange = { changes.append($0.value) }
            list.onSelect = { selected = $0.value }
            list.setSelectedIndex(5)
            #expect(list.handleMouse(listMouse(.wheel, y: row, wheelDelta: 1))?.handled == true)
            #expect(list.getSelectedItem()?.value == "item-6")
            let before = list.render(width: 80)
            #expect(before[row].contains("Item \(4 + row)"))

            for y in [0, 1, 2, 3, 4, row] {
                #expect(list.handleMouse(listMouse(.move, y: y, button: .none)) == nil)
                #expect(list.render(width: 80) == before)
            }
            #expect(list.getSelectedItem()?.value == "item-6")
            #expect(changes == ["item-6"])
            #expect(selected == nil)

            #expect(list.handleMouse(listMouse(.press, y: row))?.focus == true)
            _ = list.render(width: 80)
            #expect(list.handleMouse(listMouse(.click, y: row))?.handled == true)
            #expect(selected == "item-\(4 + row)")
            #expect(changes == ["item-6", "item-\(4 + row)"])
        }
    }

    @Test("SettingsList excludes search rows, ignores hover, and commits the pressed item")
    func settingsListHover() {
        for row in [0, 4] {
            let items = (0..<12).map {
                SettingItem(id: "item-\($0)", label: "Item \($0)", description: "Description \($0)",
                            currentValue: "off", values: ["off", "on"])
            }
            var changes: [String] = []
            let list = SettingsList(items: items, maxVisible: 5, theme: listSettingsTheme,
                                    onChange: { changes.append("\($0):\($1)") }, onCancel: {},
                                    options: SettingsListOptions(enableSearch: true))
            list.selectItem(id: "item-5")
            #expect(list.handleMouse(listMouse(.wheel, y: row + 2, wheelDelta: 1))?.handled == true)
            let before = list.render(width: 80)
            #expect(before[4].hasPrefix("> Item 6"))
            #expect(before[row + 2].contains("Item \(4 + row)"))
            #expect(list.handleMouse(listMouse(.press, y: 1)) == nil)

            for y in [0, 1, 2, 3, 4] {
                #expect(list.handleMouse(listMouse(.move, y: y + 2, button: .none)) == nil)
                #expect(list.render(width: 80) == before)
            }
            #expect(changes.isEmpty)

            #expect(list.handleMouse(listMouse(.press, y: row + 2))?.focus == true)
            _ = list.render(width: 80)
            #expect(list.handleMouse(listMouse(.click, y: row + 2))?.handled == true)
            #expect(changes == ["item-\(4 + row):on"])
        }
    }
}
