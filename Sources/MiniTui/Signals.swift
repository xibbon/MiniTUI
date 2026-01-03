#if os(Linux)
import Glibc
#else
import Darwin
#endif

func sendSuspendSignal() {
    _ = kill(getpid(), SIGTSTP)
}
