import Foundation
import Testing
#if os(Linux)
import Glibc
#else
import Darwin
#endif
@testable import MiniTui

private func suspendDispositionIsDefault() -> Bool {
    var action = sigaction()
    _ = sigaction(SIGTSTP, nil, &action)
    #if os(Linux)
    return action.__sigaction_handler.sa_handler == nil
    #else
    return action.__sigaction_u.__sa_handler == nil
    #endif
}

@MainActor
private func withRestoredSuspendDisposition(_ body: () async -> Void) async {
    var original = sigaction()
    _ = sigaction(SIGTSTP, nil, &original)
    await body()
    _ = sigaction(SIGTSTP, &original, nil)
}

@Suite("MT4 suspend signal handler", .serialized)
@MainActor
struct MT4SuspendSignalTests {
    @Test("calls the handler on SIGTSTP only while started")
    func callsHandlerOnlyWhileStarted() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            var calls = 0
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            tui.setSuspendSignalHandler {
                MainActor.assertIsolated()
                calls += 1
                continuation.yield()
            }
            #expect(tui.suspendSignalSource == nil)
            tui.start()
            #expect(tui.suspendSignalSource != nil)
            #expect(!suspendDispositionIsDefault())
            let timeout = Task {
                try? await Task.sleep(for: .seconds(2))
                continuation.finish()
            }
            _ = kill(getpid(), SIGTSTP)
            var iterator = stream.makeAsyncIterator()
            let delivered = await iterator.next() != nil
            timeout.cancel()
            #expect(delivered)
            #expect(calls == 1)
            tui.stop()
            #expect(tui.suspendSignalSource == nil)
            #expect(suspendDispositionIsDefault())
            tui.start()
            #expect(tui.suspendSignalSource != nil)
            tui.stop()
            #expect(suspendDispositionIsDefault())
        }
    }

    @Test("does not register a listener before the first start()")
    func deferredUntilFirstStart() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            tui.setSuspendSignalHandler {}
            #expect(tui.suspendSignalSource == nil)
            #expect(suspendDispositionIsDefault())
            tui.start()
            #expect(tui.suspendSignalSource != nil)
            tui.stop()
        }
    }

    @Test("keeps the listener until stop() has restored the terminal")
    func listenerIsLastInStop() async {
        await withRestoredSuspendDisposition {
            let terminal = VirtualTerminal()
            let tui = TUI(terminal: terminal)
            var listenerPresentDuringStop = false
            terminal.stopObserver = {
                listenerPresentDuringStop = tui.suspendSignalSource != nil && !suspendDispositionIsDefault()
            }
            tui.setSuspendSignalHandler {}
            tui.start()
            tui.stop()
            #expect(listenerPresentDuringStop)
            #expect(suspendDispositionIsDefault())
        }
    }

    @Test("does not remove the listener while it stays needed")
    func stableListener() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            tui.setSuspendSignalHandler {}
            tui.start()
            let first = tui.suspendSignalSource.map { ObjectIdentifier($0 as AnyObject) }
            tui.setSuspendSignalHandler {}
            tui.start()
            let second = tui.suspendSignalSource.map { ObjectIdentifier($0 as AnyObject) }
            #expect(first != nil && first == second)
            #expect(!suspendDispositionIsDefault())
            tui.stop()
        }
    }

    @Test("does not register a listener twice when start() runs again")
    func repeatedStartKeepsOneListener() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            tui.setSuspendSignalHandler {}
            tui.start()
            let first = tui.suspendSignalSource.map { ObjectIdentifier($0 as AnyObject) }
            tui.start()
            #expect(tui.suspendSignalSource.map { ObjectIdentifier($0 as AnyObject) } == first)
            tui.stop()
        }
    }

    @Test("applies a handler set or cleared while started immediately")
    func immediateSetAndClear() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            tui.start()
            #expect(tui.suspendSignalSource == nil)
            #expect(suspendDispositionIsDefault())
            tui.setSuspendSignalHandler {}
            #expect(tui.suspendSignalSource != nil)
            #expect(!suspendDispositionIsDefault())
            tui.setSuspendSignalHandler(nil)
            #expect(tui.suspendSignalSource == nil)
            #expect(suspendDispositionIsDefault())
            tui.stop()
        }
    }

    @Test("does not register a listener when a handler is set while stopped")
    func settingWhileStoppedDoesNotListen() async {
        await withRestoredSuspendDisposition {
            let tui = TUI(terminal: VirtualTerminal())
            tui.start()
            tui.stop()
            tui.setSuspendSignalHandler {}
            #expect(tui.suspendSignalSource == nil)
            #expect(suspendDispositionIsDefault())
        }
    }
}
