import Foundation

/// A single settings entry displayed in a settings list.
public struct SettingItem {
    /// Stable identifier for the setting.
    public let id: String
    /// Label shown in the list.
    public let label: String
    /// Optional description shown below the list.
    public let description: String?
    /// Current value displayed in the list.
    public var currentValue: String
    /// Optional list of fixed values.
    public let values: [String]?
    /// Optional submenu component factory.
    public let submenu: ((String, @escaping (String?) -> Void) -> Component)?

    /// Create a settings item.
    public init(
        id: String,
        label: String,
        description: String? = nil,
        currentValue: String,
        values: [String]? = nil,
        submenu: ((String, @escaping (String?) -> Void) -> Component)? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.currentValue = currentValue
        self.values = values
        self.submenu = submenu
    }
}

/// Theme configuration for settings lists.
public struct SettingsListTheme: Sendable {
    /// Style for labels.
    public let label: @Sendable (String, Bool) -> String
    /// Style for values.
    public let value: @Sendable (String, Bool) -> String
    /// Style for descriptions.
    public let description: @Sendable (String) -> String
    /// Prefix used to indicate the selected item.
    public let cursor: String
    /// Style for hints and footer text.
    public let hint: @Sendable (String) -> String

    /// Create a settings list theme.
    public init(
        label: @escaping @Sendable (String, Bool) -> String,
        value: @escaping @Sendable (String, Bool) -> String,
        description: @escaping @Sendable (String) -> String,
        cursor: String,
        hint: @escaping @Sendable (String) -> String
    ) {
        self.label = label
        self.value = value
        self.description = description
        self.cursor = cursor
        self.hint = hint
    }
}

/// Options to configure SettingsList behavior.
public struct SettingsListOptions: Sendable {
    public var enableSearch: Bool

    public init(enableSearch: Bool = false) {
        self.enableSearch = enableSearch
    }
}

/// List UI for editing and selecting setting values.
public final class SettingsList: SystemCursorAware {
    private var items: [SettingItem]
    private var filteredItems: [SettingItem]
    private let theme: SettingsListTheme
    private var selectedIndex = 0
    private let maxVisible: Int
    private let onChange: (String, String) -> Void
    private let onCancel: () -> Void
    public var usesSystemCursor = false

    private var submenuComponent: Component?
    private var submenuItemIndex: Int?
    private var searchInput: Input?
    private var searchEnabled: Bool

    /// Create a settings list.
    public init(
        items: [SettingItem],
        maxVisible: Int,
        theme: SettingsListTheme,
        onChange: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void,
        options: SettingsListOptions = SettingsListOptions()
    ) {
        self.items = items
        self.filteredItems = items
        self.maxVisible = maxVisible
        self.theme = theme
        self.onChange = onChange
        self.onCancel = onCancel
        self.searchEnabled = options.enableSearch
        if self.searchEnabled {
            self.searchInput = Input()
        }
    }

    /// Update a setting value by id.
    public func updateValue(id: String, newValue: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].currentValue = newValue
        }
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            filteredItems[index].currentValue = newValue
        }
    }

    /// Invalidate the active submenu, if present.
    public func invalidate() {
        submenuComponent?.invalidate()
        searchInput?.invalidate()
    }

    /// Render the list or the active submenu.
    public func render(width: Int) -> [String] {
        if let submenuComponent {
            if let submenuAware = submenuComponent as? SystemCursorAware {
                submenuAware.usesSystemCursor = usesSystemCursor
            }
            return submenuComponent.render(width: width)
        }
        return renderMainList(width: width)
    }

    /// Handle navigation, selection, and submenu input.
    public func handleInput(_ data: String) {
        if let submenuComponent {
            submenuComponent.handleInput(data)
            return
        }

        let kb = getEditorKeybindings()
        let displayItems = searchEnabled ? filteredItems : items
        if kb.matches(data, .selectUp) {
            guard !displayItems.isEmpty else { return }
            selectedIndex = selectedIndex == 0 ? max(displayItems.count - 1, 0) : selectedIndex - 1
        } else if kb.matches(data, .selectDown) {
            guard !displayItems.isEmpty else { return }
            selectedIndex = selectedIndex == max(displayItems.count - 1, 0) ? 0 : selectedIndex + 1
        } else if kb.matches(data, .selectConfirm) || data == " " {
            activateItem()
        } else if kb.matches(data, .selectCancel) {
            onCancel()
        } else if searchEnabled, let searchInput {
            let sanitized = data.replacingOccurrences(of: " ", with: "")
            guard !sanitized.isEmpty else { return }
            searchInput.handleInput(sanitized)
            applyFilter(query: searchInput.getValue())
        }
    }

    private func renderMainList(width: Int) -> [String] {
        var lines: [String] = []

        if searchEnabled, let searchInput {
            searchInput.usesSystemCursor = usesSystemCursor
            lines.append(contentsOf: searchInput.render(width: width))
            lines.append("")
        }

        guard !items.isEmpty else {
            lines.append(theme.hint("  No settings available"))
            if searchEnabled {
                addHintLine(into: &lines)
            }
            return lines
        }

        let displayItems = searchEnabled ? filteredItems : items
        if displayItems.isEmpty {
            lines.append(theme.hint("  No matching settings"))
            addHintLine(into: &lines)
            return lines
        }

        let startIndex = max(0, min(selectedIndex - maxVisible / 2, displayItems.count - maxVisible))
        let endIndex = min(startIndex + maxVisible, displayItems.count)
        let maxLabelWidth = min(30, items.map { visibleWidth($0.label) }.max() ?? 0)

        for i in startIndex..<endIndex {
            let item = displayItems[i]
            let isSelected = i == selectedIndex
            let basePrefix = isSelected ? theme.cursor : "  "
            let prefix = isSelected && usesSystemCursor ? basePrefix + systemCursorMarker : basePrefix
            let prefixWidth = visibleWidth(basePrefix)

            let labelPadded = item.label + String(repeating: " ", count: max(0, maxLabelWidth - visibleWidth(item.label)))
            let labelText = theme.label(labelPadded, isSelected)

            let separator = "  "
            let usedWidth = prefixWidth + maxLabelWidth + visibleWidth(separator)
            let valueMaxWidth = width - usedWidth - 2
            let valueText = theme.value(truncateToWidth(item.currentValue, maxWidth: valueMaxWidth, ellipsis: ""), isSelected)

            lines.append(prefix + labelText + separator + valueText)
        }

        if startIndex > 0 || endIndex < displayItems.count {
            let scrollText = "  (\(selectedIndex + 1)/\(displayItems.count))"
            lines.append(theme.hint(truncateToWidth(scrollText, maxWidth: width - 2, ellipsis: "")))
        }

        if let description = displayItems[safe: selectedIndex]?.description {
            lines.append("")
            let wrappedDesc = wrapTextWithAnsi(description, width: width - 4)
            for line in wrappedDesc {
                lines.append(theme.description("  \(line)"))
            }
        }

        addHintLine(into: &lines)

        return lines
    }

    private func activateItem() {
        let displayItems = searchEnabled ? filteredItems : items
        guard let item = displayItems[safe: selectedIndex] else { return }

        if let submenu = item.submenu {
            submenuItemIndex = selectedIndex
            submenuComponent = submenu(item.currentValue) { [weak self] selectedValue in
                guard let self else { return }
                if let selectedValue {
                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[index].currentValue = selectedValue
                    }
                    if let index = self.filteredItems.firstIndex(where: { $0.id == item.id }) {
                        self.filteredItems[index].currentValue = selectedValue
                    }
                    self.onChange(item.id, selectedValue)
                }
                self.closeSubmenu()
            }
            if let submenuAware = submenuComponent as? SystemCursorAware {
                submenuAware.usesSystemCursor = usesSystemCursor
            }
        } else if let values = item.values, !values.isEmpty {
            let currentIndex = values.firstIndex(of: item.currentValue) ?? 0
            let nextIndex = (currentIndex + 1) % values.count
            let newValue = values[nextIndex]
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].currentValue = newValue
            }
            if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
                filteredItems[index].currentValue = newValue
            }
            onChange(item.id, newValue)
        }
    }

    private func closeSubmenu() {
        submenuComponent = nil
        if let submenuItemIndex {
            selectedIndex = submenuItemIndex
            self.submenuItemIndex = nil
        }
    }

    private func applyFilter(query: String) {
        filteredItems = fuzzyFilter(items, query: query) { $0.label }
        selectedIndex = 0
    }

    private func addHintLine(into lines: inout [String]) {
        lines.append("")
        let hint = searchEnabled
            ? "  Type to search · Enter/Space to change · Esc to cancel"
            : "  Enter/Space to change · Esc to cancel"
        lines.append(theme.hint(hint))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
