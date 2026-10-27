import Foundation
import MiniTui
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private func writeExitBytes(_ text: String) {
    let bytes = Array(text.utf8)
    bytes.withUnsafeBytes { buffer in
        if let base = buffer.baseAddress { _ = write(STDOUT_FILENO, base, buffer.count) }
    }
}

private final class CustomExitTerminal: Terminal {
    let exitDuringStart: Bool
    let exitDuringAltStart: Bool
    init(exitDuringStart: Bool, exitDuringAltStart: Bool) {
        self.exitDuringStart = exitDuringStart
        self.exitDuringAltStart = exitDuringAltStart
    }
    var restoreOnExit: TerminalExitRestoreHandler {
        { before, after in writeExitBytes("MT1-CUSTOM:" + before + "|" + after) }
    }
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        if exitDuringStart { exit(0) }
    }
    func stop() {}
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) {
        if exitDuringAltStart, data.contains("\u{001B}[?1049h") { exit(0) }
    }
    var columns: Int { 80 }
    var rows: Int { 24 }
    var kittyProtocolActive: Bool { false }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
}

@main
struct ExitRestoreFixture {
    @MainActor
    static func main() async {
        let mode = CommandLine.arguments.dropFirst().first ?? "exit-alt"
        if mode.hasPrefix("custom") {
            let tui = TUI(terminal: CustomExitTerminal(exitDuringStart: mode == "custom-start",
                                                      exitDuringAltStart: mode == "custom-alt-start"))
            if mode == "custom-alt-start" {
                tui.enableAltScreen(options: AltScreenRendererOptions(mouse: true))
                _ = tui.switchRenderer(to: .altScreen)
            }
            tui.setTerminalColorSchemeNotifications(true)
            tui.start()
            exit(0)
        }
        let terminal = ProcessTerminal()
        let tui = TUI(terminal: terminal)
        if mode.contains("alt") || mode == "loss" {
            tui.enableAltScreen(options: AltScreenRendererOptions(mouse: !mode.contains("no-mouse")))
            _ = tui.switchRenderer(to: .altScreen)
        }
        tui.setTerminalColorSchemeNotifications(!mode.contains("minimal") && !mode.contains("color-late"))
        if mode == "loss" {
            tui.setIOErrorHandler { error in
                if error.isTerminalLoss { exit(129) }
            }
        }
        tui.start()
        if mode.contains("color-off") { tui.setTerminalColorSchemeNotifications(false) }
        if mode.contains("color-late") { tui.setTerminalColorSchemeNotifications(true) }
        func enableModes() {
            terminal.write("\u{001B}[>3u\u{001B}[>4;2m")
            tui.setProgress(true)
        }
        if !mode.contains("minimal") { enableModes() }
        if mode.contains("restart") {
            tui.stop()
            terminal.write("MT1-RESTART\n")
            tui.start()
            enableModes()
        }
        if mode.contains("stop") { tui.stop() }
        if mode.contains("switch") { _ = tui.switchRenderer(to: .mainScreen) }
        if mode == "loss" {
            terminal.write("MT1-READY\n")
            while true { try? await Task.sleep(for: .milliseconds(50)) }
        }
        terminal.write("MT1-EXIT\n")
        exit(0)
    }
}
