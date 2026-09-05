import Foundation
import Testing
import os
@testable import MiniTui

@Suite("B1 terminal input", .serialized)
struct B1TerminalTests {
    @Test("resolves configured, invalid, SSH, and local Escape delays")
    func timeouts() {
        #expect(resolveEscapeTimeoutMs(env: ["PI_TUI_ESC_TIMEOUT": "80"]) == 80)
        #expect(resolveEscapeTimeoutMs(env: ["PI_TUI_ESC_TIMEOUT": "80", "SSH_TTY": "/dev/pts/1"]) == 80)
        for invalid in ["abc", "0", "-5", "", "nan", "inf"] { #expect(resolveEscapeTimeoutMs(env: ["PI_TUI_ESC_TIMEOUT": invalid]) == 10) }
        #expect(resolveEscapeTimeoutMs(env: ["SSH_CONNECTION": "10.0.0.1 22"]) == 100)
        #expect(resolveEscapeTimeoutMs(env: ["SSH_TTY": "/dev/pts/1"]) == 100)
        #expect(resolveEscapeTimeoutMs(env: [:]) == 10)
    }

    @Test("dimension refresh ignores EACCES and EPERM and skips Windows")
    func refresh() {
        for code in [EACCES, EPERM, ESRCH] {
            var called = false
            refreshTerminalDimensions(pid: 123, isWindows: false) { pid, signal in
                #expect(pid == 123 && signal == SIGWINCH)
                called = true; errno = code; return -1
            }
            #expect(called)
        }
        for (pid, windows) in [(Int32(123), true), (Int32(0), false)] {
            var called = false
            refreshTerminalDimensions(pid: pid, isWindows: windows) { _, _ in called = true; return 0 }
            #expect(!called)
        }
    }

    @Test("lone ESC and delayed CR remain separate after the Escape timeout")
    func delayedCR() async throws {
        let values = OSAllocatedUnfairLock(initialState: [String]())
        let buffer = StdinBuffer()
        _ = buffer.on(.data) { value in values.withLock { $0.append(value) } }
        defer { buffer.destroy() }
        buffer.process("\u{1b}")
        try await Task.sleep(for: .milliseconds(20))
        buffer.process("\r")
        #expect(values.withLock { $0 } == ["\u{1b}", "\r"])
    }

    @Test("merges ESC and CR within a larger Escape timeout")
    func mergedCR() async throws {
        let values = OSAllocatedUnfairLock(initialState: [String]())
        let buffer = StdinBuffer(options: StdinBufferOptions(escapeTimeout: 0.1))
        _ = buffer.on(.data) { value in values.withLock { $0.append(value) } }
        defer { buffer.destroy() }
        buffer.process("\u{1b}")
        try await Task.sleep(for: .milliseconds(20))
        buffer.process("\r")
        #expect(values.withLock { $0 } == ["\u{1b}\r"])
        #expect(matchesKey(values.withLock { $0.first ?? "" }, Key.alt(Key.enter)))
    }

    @Test("sequence timeout does not delay a lone ESC")
    func separateTimeout() async throws {
        let values = OSAllocatedUnfairLock(initialState: [String]())
        let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.1))
        _ = buffer.on(.data) { value in values.withLock { $0.append(value) } }
        defer { buffer.destroy() }
        buffer.process("\u{1b}")
        try await Task.sleep(for: .milliseconds(20))
        buffer.process("\r")
        #expect(values.withLock { $0 } == ["\u{1b}", "\r"])
    }

    @Test("default timeout keeps delayed mouse chunks together")
    func delayedMouse() async throws {
        let values = OSAllocatedUnfairLock(initialState: [String]())
        let buffer = StdinBuffer()
        _ = buffer.on(.data) { value in values.withLock { $0.append(value) } }
        defer { buffer.destroy() }
        buffer.process("\u{1b}[")
        try await Task.sleep(for: .milliseconds(20))
        #expect(values.withLock { $0.isEmpty })
        buffer.process("<65;48;39M")
        #expect(values.withLock { $0 } == ["\u{1b}[<65;48;39M"])
    }

    @Test("default lone Escape is emitted promptly")
    func promptEscape() async throws {
        let values = OSAllocatedUnfairLock(initialState: [String]())
        let buffer = StdinBuffer()
        _ = buffer.on(.data) { value in values.withLock { $0.append(value) } }
        defer { buffer.destroy() }
        buffer.process("\u{1b}")
        try await Task.sleep(for: .milliseconds(20))
        #expect(values.withLock { $0 } == ["\u{1b}"])
    }
}

@MainActor
@Suite("B1 capabilities and renderer configuration")
struct B1CapabilityTests {
    @Test("environment capability overrides and auto values")
    func environment() {
        let on = detectCapabilities(environment: ["PI_HYPERLINKS": "1", "PI_IMAGE_PROTOCOL": "kitty", "PI_TRUE_COLOR": "1"])
        #expect(on.images == .kitty && on.hyperlinks && on.trueColor)
        let off = detectCapabilities(environment: ["TERM_PROGRAM": "iterm.app", "PI_HYPERLINKS": "0", "PI_IMAGE_PROTOCOL": "none", "PI_TRUE_COLOR": "0"])
        #expect(off.images == nil && !off.hyperlinks && !off.trueColor)
        let auto = detectCapabilities(environment: ["TERM_PROGRAM": "ghostty", "PI_HYPERLINKS": "auto", "PI_IMAGE_PROTOCOL": "auto", "PI_TRUE_COLOR": "auto"])
        #expect(auto.images == .kitty && auto.hyperlinks && auto.trueColor)
        #expect(detectCapabilities(environment: ["PI_IMAGE_PROTOCOL": "ITERM2"]).images == .iterm2)
        #expect(detectCapabilities(environment: ["TERM_PROGRAM": "kitty", "PI_IMAGE_PROTOCOL": "0"]).images == nil)
    }

    @Test("capability override bypasses a tmux probe and detects Zed")
    func probe() {
        var probed = false
        let caps = detectCapabilities(environment: ["TMUX": "session", "PI_HYPERLINKS": "1", "PI_IMAGE_PROTOCOL": "kitty"], tmuxForwardsHyperlink: { probed = true; return false })
        #expect(!probed && caps.hyperlinks && caps.images == .kitty)
        let zed = detectCapabilities(environment: ["TERM_PROGRAM": "zed"])
        #expect(zed.images == nil && zed.trueColor && zed.hyperlinks)
    }

    @Test("programmatic overrides replace the set and unchanged sets retain cached values")
    func overrides() {
        defer { setCapabilityOverrides(TerminalCapabilityOverrides()); resetCapabilitiesCache() }
        let original = detectCapabilities()
        let overrides = TerminalCapabilityOverrides(images: .some(nil), trueColor: false, hyperlinks: false)
        setCapabilityOverrides(overrides)
        let off = getCapabilities()
        #expect(off.images == nil && !off.trueColor && !off.hyperlinks)
        setCapabilities(TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true))
        setCapabilityOverrides(overrides)
        #expect(getCapabilities().images == .iterm2)
        resetCapabilitiesCache()
        #expect(getCapabilities().images == nil)
        setCapabilityOverrides(TerminalCapabilityOverrides())
        let restored = getCapabilities()
        #expect(restored.images == original.images && restored.trueColor == original.trueColor && restored.hyperlinks == original.hyperlinks)
    }

    @Test("new keybindings and prompt navigation defaults")
    func bindings() {
        let kb = TUIKeybindingsManager()
        #expect(kb.getKeys(TUIKeybinding.altScreenLineUp) == [])
        #expect(kb.getKeys(TUIKeybinding.altScreenLineDown) == [])
        #expect(kb.getKeys(TUIKeybinding.altScreenPreviousPrompt) == ["ctrl+shift+up", "ctrl+up"])
        #expect(kb.getKeys(TUIKeybinding.altScreenNextPrompt) == ["ctrl+shift+down", "ctrl+down"])
        #expect(kb.getKeys(TUIKeybinding.altScreenSearch) == ["ctrl+shift+f"])
        #expect(kb.getKeys(TUIKeybinding.altScreenSearchNext) == ["enter", "ctrl+g"])
        #expect(kb.getKeys(TUIKeybinding.altScreenSearchPrevious) == ["shift+enter", "ctrl+shift+g"])
        #expect(kb.getKeys(TUIKeybinding.altScreenSearchClose) == ["escape"])
    }

    @Test("cursor and shrink defaults ignore old environment settings")
    func defaults() {
        let names = ["PI_HARDWARE_CURSOR", "PI_CLEAR_ON_SHRINK"]
        let saved = names.map { ProcessInfo.processInfo.environment[$0] }
        for name in names { setenv(name, "1", 1) }
        defer { for (name, value) in zip(names, saved) { if let value { setenv(name, value, 1) } else { unsetenv(name) } } }
        let ui = TUI(terminal: VirtualTerminal())
        #expect(!ui.useSystemCursor && !ui.getClearOnShrink())
        ui.setClearOnShrink(true); #expect(ui.getClearOnShrink())
        #expect(TUI(terminal: VirtualTerminal(), showHardwareCursor: true).useSystemCursor)
    }

    @Test("redraw logs use the configured directory and crash dumps default to OS temp")
    func logs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("b1-log-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = ProcessInfo.processInfo.environment["PI_TUI_DEBUG_REDRAW"]
        setenv("PI_TUI_DEBUG_REDRAW", "1", 1)
        defer { if let saved { setenv("PI_TUI_DEBUG_REDRAW", saved, 1) } else { unsetenv("PI_TUI_DEBUG_REDRAW") } }
        let terminal = VirtualTerminal(columns: 40, rows: 10)
        let renderer = MainScreenRenderer(terminal: terminal, logDirectory: directory.path)
        let frame = TuiRenderFrame(lines: ["ok"], cursor: nil, width: 40, height: 10, clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false)
        renderer.present(frame)
        let log = try String(contentsOf: directory.appendingPathComponent("pi-tui-debug.log"), encoding: .utf8)
        #expect(log.contains("fullRender:"))
        #expect(renderer.writeCrashDump("overflow", index: 0, lines: ["overflow"], frame: frame) == directory.appendingPathComponent("pi-tui-crash.log"))
        let dump = try String(contentsOf: directory.appendingPathComponent("pi-tui-crash.log"), encoding: .utf8)
        #expect(dump.contains("Terminal width: 40"))
        let unconfigured = MainScreenRenderer(terminal: terminal)
        #expect(unconfigured.crashLogURL == FileManager.default.temporaryDirectory.appendingPathComponent("pi-tui-crash.log"))
    }
}
