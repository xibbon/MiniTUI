# MiniTui

Terminal UI components for Swift.

## Origin

MiniTui is a machine Swift port of `pi-mono/packages/tui` by Mario Zechner.

## Build

```sh
swift build
```

## Run

```sh
swift run MiniTuiDemo
```

Press Ctrl-D on empty input to exit.

## Test

```sh
swift test
```

## Usage

```swift
import Foundation
import Darwin
import MiniTui

@main
struct Demo {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())
        let header = Text("MiniTui demo", paddingX: 1, paddingY: 0)
        let output = Text("Type something and press Enter. Ctrl-D exits on empty input.", paddingX: 1, paddingY: 0)
        let input = Input()

        input.onSubmit = { @MainActor [weak tui, weak output] text in
            output?.setText("You typed: \(text)")
            tui?.requestRender()
        }
        input.onEnd = { [weak tui] in
            tui?.stop()
            exit(0)
        }

        tui.addChild(header)
        tui.addChild(Spacer(1))
        tui.addChild(output)
        tui.addChild(Spacer(1))
        tui.addChild(input)

        tui.setFocus(input)
        tui.start()

        RunLoop.main.run()
    }
}
```
