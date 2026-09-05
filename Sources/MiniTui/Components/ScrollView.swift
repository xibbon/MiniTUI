import Foundation

/// Scrollbar visibility policy for a scroll view.
public enum ScrollViewScrollbar: Equatable {
    case hidden
    case auto
    case always
}

/// Automatic scroll-follow behavior.
public enum ScrollViewFollow: Equatable {
    case none
    case end
}

/// Configuration for a vertical scroll view.
public struct ScrollViewOptions {
    public var follow: ScrollViewFollow
    public var primary: Bool
    public var overscroll: ScrollOverscroll
    public var scrollbar: ScrollViewScrollbar
    public var scrollbarTrackStyle: (String) -> String
    public var scrollbarThumbStyle: (String) -> String
    public var scrollbarHideDelayMilliseconds: Int

    public init(
        follow: ScrollViewFollow = .none,
        primary: Bool = false,
        overscroll: ScrollOverscroll = .chain,
        scrollbar: ScrollViewScrollbar = .hidden,
        scrollbarTrackStyle: @escaping (String) -> String = { "\u{001B}[90m" + $0 + "\u{001B}[39m" },
        scrollbarThumbStyle: @escaping (String) -> String = { "\u{001B}[37m" + $0 + "\u{001B}[39m" },
        scrollbarHideDelayMilliseconds: Int = 1_000
    ) {
        self.follow = follow
        self.primary = primary
        self.overscroll = overscroll
        self.scrollbar = scrollbar
        self.scrollbarTrackStyle = scrollbarTrackStyle
        self.scrollbarThumbStyle = scrollbarThumbStyle
        self.scrollbarHideDelayMilliseconds = scrollbarHideDelayMilliseconds
    }
}

/// Options for an absolute scroll operation.
public struct ScrollViewScrollToOptions {
    public var disableFollow: Bool

    public init(disableFollow: Bool = false) {
        self.disableFollow = disableFollow
    }
}

/// A programmatically controlled vertical viewport over one child component.
public final class ScrollView: Container, LayoutComponent, ScrollLayoutState {
    private let child: Component
    public let followEnd: Bool
    public let primary: Bool
    public let overscroll: ScrollOverscroll
    public let scrollbarTrackStyle: (String) -> String
    public let scrollbarThumbStyle: (String) -> String
    private let scrollbarHideDelayMilliseconds: Int

    private var currentScrollbar: ScrollViewScrollbar
    private var currentScrollTop = 0
    private var contentHeight = 0
    private var currentViewportHeight = 0
    private var followingEnd: Bool
    private var followSuppressedAtEnd = false
    private var requestRenderCallback: (() -> Void)?
    private var transientScrollbarVisible = false
    private var scrollbarActive = false
    private var scrollbarHideTask: Task<Void, Never>?

    private var cachedWidth: Int?
    private var cachedChildLines: [String]?
    private var cachedLines: [String]?

    public init(_ component: Component, options: ScrollViewOptions = ScrollViewOptions()) {
        child = component
        followEnd = options.follow == .end
        followingEnd = options.follow == .end
        primary = options.primary
        overscroll = options.overscroll
        currentScrollbar = options.scrollbar
        scrollbarTrackStyle = options.scrollbarTrackStyle
        scrollbarThumbStyle = options.scrollbarThumbStyle
        scrollbarHideDelayMilliseconds = max(0, options.scrollbarHideDelayMilliseconds)
        super.init()
        super.addChild(component)
    }

    public var scrollTop: Int { currentScrollTop }
    public var isFollowingEnd: Bool { followingEnd }
    public var viewportHeight: Int { currentViewportHeight }
    public var scrollbar: ScrollViewScrollbar { currentScrollbar }
    public var isScrollbarActive: Bool { scrollbarActive }

    public var isScrollbarVisible: Bool {
        if currentScrollbar == .always { return currentViewportHeight > 0 }
        return currentScrollbar == .auto
            && contentHeight > currentViewportHeight
            && transientScrollbarVisible
    }

    public func setScrollbar(_ scrollbar: ScrollViewScrollbar) {
        guard scrollbar != currentScrollbar else { return }
        currentScrollbar = scrollbar
        if scrollbar != .auto {
            hideTransientScrollbar()
        } else if scrollbarActive {
            markScrollbarActivity()
        }
        invalidateCache()
        requestRenderCallback?()
    }

    public func contentWidth(forWidth width: Int) -> Int {
        currentScrollbar == .always && width > 1 ? width - 1 : width
    }

    private func markScrollbarActivity() {
        guard currentScrollbar == .auto, contentHeight > currentViewportHeight else { return }
        transientScrollbarVisible = true
        scrollbarHideTask?.cancel()
        scrollbarHideTask = nil
        if scrollbarActive { return }

        let delay = scrollbarHideDelayMilliseconds
        scrollbarHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.scrollbarHideTask = nil
            self.transientScrollbarVisible = false
            self.requestRenderCallback?()
        }
    }

    private func hideTransientScrollbar() {
        transientScrollbarVisible = false
        scrollbarHideTask?.cancel()
        scrollbarHideTask = nil
    }

    /// Keep an automatic scrollbar visible while an external interaction is active.
    public func setScrollbarActive(_ active: Bool) {
        guard active != scrollbarActive else { return }
        scrollbarActive = active
        markScrollbarActivity()
        requestRenderCallback?()
    }

    /// Set the absolute vertical scroll offset, clamped to the current content.
    public func scrollTo(_ scrollTop: Int, options: ScrollViewScrollToOptions = ScrollViewScrollToOptions()) {
        let maxScrollTop = max(0, contentHeight - currentViewportHeight)
        let next = max(0, min(maxScrollTop, scrollTop))
        let nextSuppressed = options.disableFollow && next == maxScrollTop
        let nextFollowing = !nextSuppressed && followEnd && next == maxScrollTop
        guard next != currentScrollTop || nextFollowing != followingEnd
                || nextSuppressed != followSuppressedAtEnd else { return }
        let moved = next != currentScrollTop
        currentScrollTop = next
        followingEnd = nextFollowing
        followSuppressedAtEnd = nextSuppressed
        if moved { markScrollbarActivity() }
        requestRenderCallback?()
    }

    /// Scroll by a line count and return the unconsumed amount.
    @discardableResult
    public func scrollBy(_ lines: Int) -> Int {
        guard lines != 0 else { return 0 }
        let maxScrollTop = max(0, contentHeight - currentViewportHeight)
        let start = followingEnd ? maxScrollTop : currentScrollTop
        let next = max(0, min(maxScrollTop, start + lines))
        let moved = next - start
        let wasFollowingEnd = followingEnd
        currentScrollTop = next
        followingEnd = followEnd && next == maxScrollTop
        followSuppressedAtEnd = false
        if moved != 0 { markScrollbarActivity() }
        if moved != 0 || followingEnd != wasFollowingEnd { requestRenderCallback?() }
        return lines - moved
    }

    public func scrollToStart() {
        let nextFollowingEnd = followEnd && contentHeight <= currentViewportHeight
        let changed = currentScrollTop != 0 || followingEnd != nextFollowingEnd
        currentScrollTop = 0
        followingEnd = nextFollowingEnd
        followSuppressedAtEnd = false
        if changed {
            markScrollbarActivity()
            requestRenderCallback?()
        }
    }

    public func scrollToEnd() {
        let next = max(0, contentHeight - currentViewportHeight)
        let changed = currentScrollTop != next || followingEnd != followEnd
        currentScrollTop = next
        followingEnd = followEnd
        followSuppressedAtEnd = false
        if changed {
            markScrollbarActivity()
            requestRenderCallback?()
        }
    }

    public func updateLayout(contentHeight: Int, viewportHeight: Int, requestRender: @escaping () -> Void) {
        let nextContentHeight = max(0, contentHeight)
        let nextViewportHeight = max(0, viewportHeight)

        self.contentHeight = nextContentHeight
        currentViewportHeight = nextViewportHeight
        requestRenderCallback = requestRender
        let maxScrollTop = max(0, nextContentHeight - nextViewportHeight)
        if followingEnd {
            currentScrollTop = maxScrollTop
        } else {
            currentScrollTop = max(0, min(currentScrollTop, maxScrollTop))
        }
        if currentScrollTop < maxScrollTop { followSuppressedAtEnd = false }
        if followEnd, currentScrollTop == maxScrollTop, !followSuppressedAtEnd {
            followingEnd = true
        }
        if nextContentHeight <= nextViewportHeight {
            hideTransientScrollbar()
        }
        // Upstream stores the callback here but deliberately does not invoke it: layout runs
        // *during* a render, so self-triggering would render every change twice (the perf bug
        // upstream fixed in v0.84.0) and can flip-flop when scrollbar visibility feeds back into
        // wrapped content height. Scroll actions call `requestRenderCallback` themselves.
    }

    public override func addChild(_ component: Component) {
        preconditionFailure("ScrollView has exactly one child")
    }

    public override func removeChild(_ component: Component) {
        preconditionFailure("ScrollView child cannot be removed")
    }

    public override func clear() {
        preconditionFailure("ScrollView child cannot be cleared")
    }

    public override func invalidate() {
        invalidateCache()
        child.invalidate()
    }

    public override func render(width: Int) -> [String] {
        let safeWidth = max(1, width)
        let contentWidth = contentWidth(forWidth: safeWidth)
        let childLines = child.render(width: contentWidth)
        if let cachedLines,
           cachedWidth == safeWidth,
           cachedChildLines == childLines {
            return cachedLines
        }

        let lines = contentWidth == safeWidth ? childLines : childLines.map { $0 + " " }
        cachedWidth = safeWidth
        cachedChildLines = childLines
        cachedLines = lines
        return lines
    }

    public var layoutNode: LayoutNode {
        .scroll(ScrollLayoutNode(component: child, state: self))
    }

    private func invalidateCache() {
        cachedWidth = nil
        cachedChildLines = nil
        cachedLines = nil
    }
}
