import Foundation

/// Item displayed in a selection list.
public struct SelectItem: Equatable {
    /// Value used when selected.
    public let value: String
    /// Display label shown in the list.
    public let label: String
    /// Optional description shown alongside the label.
    public let description: String?

    /// Create a select item.
    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

/// Theme configuration for a select list.
public struct SelectListTheme: Sendable {
    /// Style for the selected prefix marker.
    public let selectedPrefix: @Sendable (String) -> String
    /// Style for selected item text.
    public let selectedText: @Sendable (String) -> String
    /// Optional style for the selected line background.
    public let selectedBackground: (@Sendable (String) -> String)?
    /// Style for item descriptions.
    public let description: @Sendable (String) -> String
    /// Style for scroll info text.
    public let scrollInfo: @Sendable (String) -> String
    /// Style for the "no matches" message.
    public let noMatch: @Sendable (String) -> String

    /// Create a select list theme.
    public init(
        selectedPrefix: @escaping @Sendable (String) -> String,
        selectedText: @escaping @Sendable (String) -> String,
        description: @escaping @Sendable (String) -> String,
        scrollInfo: @escaping @Sendable (String) -> String,
        noMatch: @escaping @Sendable (String) -> String,
        selectedBackground: (@Sendable (String) -> String)? = nil
    ) {
        self.selectedPrefix = selectedPrefix
        self.selectedText = selectedText
        self.description = description
        self.scrollInfo = scrollInfo
        self.noMatch = noMatch
        self.selectedBackground = selectedBackground
    }
}

/// Layout options for controlling select list column sizing.
public struct SelectListLayoutOptions: Sendable {
    /// Minimum width for the primary (label/value) column.
    public var minPrimaryColumnWidth: Int?
    /// Maximum width for the primary (label/value) column.
    public var maxPrimaryColumnWidth: Int?
    /// Optional custom truncation function for the primary column.
    /// Receives (text, maxWidth) and returns truncated text.
    public var truncatePrimary: (@Sendable (String, Int) -> String)?

    public init(
        minPrimaryColumnWidth: Int? = nil,
        maxPrimaryColumnWidth: Int? = nil,
        truncatePrimary: (@Sendable (String, Int) -> String)? = nil
    ) {
        self.minPrimaryColumnWidth = minPrimaryColumnWidth
        self.maxPrimaryColumnWidth = maxPrimaryColumnWidth
        self.truncatePrimary = truncatePrimary
    }
}

private let DEFAULT_PRIMARY_COLUMN_WIDTH = 32
private let PRIMARY_COLUMN_GAP = 2
private let MIN_DESCRIPTION_WIDTH = 10

/// Scrollable list of selectable items.
public final class SelectList: SystemCursorAware {
    private var items: [SelectItem]
    private var filteredItems: [SelectItem]
    private var selectedIndex: Int = 0
    private let maxVisible: Int
    private let theme: SelectListTheme
    public var usesSystemCursor = false

    /// Layout options for controlling column sizing.
    public var layoutOptions: SelectListLayoutOptions?

    /// Called when an item is selected with Enter.
    public var onSelect: ((SelectItem) -> Void)?
    /// Called when the list is canceled (Escape or Ctrl+C).
    public var onCancel: (() -> Void)?
    /// Called when the selection changes.
    public var onSelectionChange: ((SelectItem) -> Void)?

    /// Create a list with items, max visible rows, and theme.
    public init(items: [SelectItem], maxVisible: Int, theme: SelectListTheme, layoutOptions: SelectListLayoutOptions? = nil) {
        self.items = items
        self.filteredItems = items
        self.maxVisible = maxVisible
        self.theme = theme
        self.layoutOptions = layoutOptions
    }

    /// Calculate the primary column width based on filtered items and layout options.
    private func getPrimaryColumnWidth(availableWidth: Int) -> Int {
        let layout = layoutOptions

        let minBound = layout?.minPrimaryColumnWidth ?? 1
        let maxBound = layout?.maxPrimaryColumnWidth ?? DEFAULT_PRIMARY_COLUMN_WIDTH

        // Find widest item label
        var widest = 0
        for item in filteredItems {
            let display = item.label.isEmpty ? item.value : item.label
            let w = visibleWidth(display) + PRIMARY_COLUMN_GAP
            if w > widest { widest = w }
        }

        // Clamp to bounds
        var columnWidth = max(minBound, min(widest, maxBound))

        // Ensure description has at least MIN_DESCRIPTION_WIDTH
        let descSpace = availableWidth - columnWidth - 4 // prefix + margin
        if descSpace < MIN_DESCRIPTION_WIDTH {
            columnWidth = max(minBound, availableWidth - MIN_DESCRIPTION_WIDTH - 4)
        }

        return max(1, columnWidth)
    }

    /// Update the filter text and reset selection.
    public func setFilter(_ filter: String) {
        filteredItems = items.filter { $0.value.lowercased().hasPrefix(filter.lowercased()) }
        selectedIndex = 0
    }

    /// Set the selected index in the filtered list.
    public func setSelectedIndex(_ index: Int) {
        selectedIndex = max(0, min(index, filteredItems.count - 1))
    }

    /// Render the list contents.
    public func render(width: Int) -> [String] {
        var lines: [String] = []

        if filteredItems.isEmpty {
            lines.append(theme.noMatch("  No matching commands"))
            return lines
        }

        let startIndex = max(0, min(selectedIndex - maxVisible / 2, filteredItems.count - maxVisible))
        let endIndex = min(startIndex + maxVisible, filteredItems.count)

        let columnWidth = getPrimaryColumnWidth(availableWidth: width)

        for i in startIndex..<endIndex {
            let item = filteredItems[i]
            let isSelected = i == selectedIndex

            let line: String
            let displayValue = item.label.isEmpty ? item.value : item.label

            if isSelected {
                let prefix = "→ " + (usesSystemCursor ? systemCursorMarker : "")
                let prefixWidth = visibleWidth("→ ")
                let styledPrefix = theme.selectedPrefix(prefix)
                if let description = item.description, width > 40 {
                    let maxValueWidth = min(columnWidth, width - prefixWidth - 4)
                    let truncatedValue: String
                    if let customTruncate = layoutOptions?.truncatePrimary {
                        truncatedValue = customTruncate(displayValue, maxValueWidth)
                    } else {
                        truncatedValue = truncateToWidth(displayValue, maxWidth: maxValueWidth, ellipsis: "")
                    }
                    let truncatedWidth = visibleWidth(truncatedValue)
                    let spacing = String(repeating: " ", count: max(1, columnWidth - truncatedWidth))
                    let descriptionStart = prefixWidth + truncatedWidth + spacing.count
                    let remainingWidth = width - descriptionStart - 2
                    if remainingWidth > MIN_DESCRIPTION_WIDTH {
                        let truncatedDesc = truncateToWidth(description, maxWidth: remainingWidth, ellipsis: "")
                        line = styledPrefix + theme.selectedText("\(truncatedValue)\(spacing)\(truncatedDesc)")
                    } else {
                        let maxWidth = width - prefixWidth - 2
                        line = styledPrefix + theme.selectedText("\(truncateToWidth(displayValue, maxWidth: maxWidth, ellipsis: ""))")
                    }
                } else {
                    let maxWidth = width - prefixWidth - 2
                    line = styledPrefix + theme.selectedText("\(truncateToWidth(displayValue, maxWidth: maxWidth, ellipsis: ""))")
                }
            } else {
                let prefix = "  "

                if let description = item.description, width > 40 {
                    let maxValueWidth = min(columnWidth, width - prefix.count - 4)
                    let truncatedValue: String
                    if let customTruncate = layoutOptions?.truncatePrimary {
                        truncatedValue = customTruncate(displayValue, maxValueWidth)
                    } else {
                        truncatedValue = truncateToWidth(displayValue, maxWidth: maxValueWidth, ellipsis: "")
                    }
                    let truncatedWidth = visibleWidth(truncatedValue)
                    let spacing = String(repeating: " ", count: max(1, columnWidth - truncatedWidth))
                    let descriptionStart = prefix.count + truncatedWidth + spacing.count
                    let remainingWidth = width - descriptionStart - 2
                    if remainingWidth > MIN_DESCRIPTION_WIDTH {
                        let truncatedDesc = truncateToWidth(description, maxWidth: remainingWidth, ellipsis: "")
                        let descText = theme.description(spacing + truncatedDesc)
                        line = prefix + truncatedValue + descText
                    } else {
                        let maxWidth = width - prefix.count - 2
                        line = prefix + truncateToWidth(displayValue, maxWidth: maxWidth, ellipsis: "")
                    }
                } else {
                    let maxWidth = width - prefix.count - 2
                    line = prefix + truncateToWidth(displayValue, maxWidth: maxWidth, ellipsis: "")
                }
            }

            if isSelected, let selectedBackground = theme.selectedBackground {
                lines.append(applyBackgroundToLine(line, width: width, bgFn: selectedBackground))
            } else {
                lines.append(line)
            }
        }

        if startIndex > 0 || endIndex < filteredItems.count {
            let scrollText = "  (\(selectedIndex + 1)/\(filteredItems.count))"
            let scrollMaxWidth = max(1, width < 40 ? width : width - 2)
            lines.append(theme.scrollInfo(truncateToWidth(scrollText, maxWidth: scrollMaxWidth, ellipsis: "")))
        }

        return lines
    }

    /// Handle navigation and selection input.
    public func handleInput(_ data: String) {
        let kb = getKeybindings()
        if kb.matches(data, TUIKeybinding.selectUp) {
            selectedIndex = selectedIndex == 0 ? max(filteredItems.count - 1, 0) : selectedIndex - 1
            notifySelectionChange()
        } else if kb.matches(data, TUIKeybinding.selectDown) {
            selectedIndex = selectedIndex == max(filteredItems.count - 1, 0) ? 0 : selectedIndex + 1
            notifySelectionChange()
        } else if kb.matches(data, TUIKeybinding.selectPageUp) {
            guard !filteredItems.isEmpty else { return }
            selectedIndex = max(0, selectedIndex - maxVisible)
            notifySelectionChange()
        } else if kb.matches(data, TUIKeybinding.selectPageDown) {
            guard !filteredItems.isEmpty else { return }
            selectedIndex = min(max(filteredItems.count - 1, 0), selectedIndex + maxVisible)
            notifySelectionChange()
        } else if kb.matches(data, TUIKeybinding.selectConfirm) {
            if let selected = filteredItems[safe: selectedIndex] {
                onSelect?(selected)
            }
        } else if kb.matches(data, TUIKeybinding.selectCancel) {
            onCancel?()
        }
    }

    /// Return the currently selected item, if any.
    public func getSelectedItem() -> SelectItem? {
        return filteredItems[safe: selectedIndex]
    }

    private func notifySelectionChange() {
        if let selected = filteredItems[safe: selectedIndex] {
            onSelectionChange?(selected)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
