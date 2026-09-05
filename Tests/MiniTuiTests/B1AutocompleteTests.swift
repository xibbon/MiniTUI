import Foundation
import Testing
@testable import MiniTui

@MainActor
@Suite("B1 autocomplete ranking")
struct B1AutocompleteTests {
    @Test("same-score path ties use depth, length, then locale order")
    func tieOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("b1-fd-ties-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = root.appendingPathComponent("fd")
        let script = "#!/bin/sh\nprintf '%s\\n' 'z/project/' 'prob/' 'project/' 'proa/' 'a/project/'\n"
        try script.write(to: fd, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fd.path)
        let provider = CombinedAutocompleteProvider(basePath: root.path, fdPath: fd.path)
        let values = provider.getSuggestions(lines: ["@pro"], cursorLine: 0, cursorCol: 4)?.items.map(\.value)
        #expect(values == ["@proa/", "@prob/", "@project/", "@a/project/", "@z/project/"])
    }

    @Test("ranks shallow same-score paths first and keeps direct children under flood", arguments: [false, true])
    func depthRanking(flooded: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("b1-fd-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scope/projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let count = flooded ? 250 : 1
        for index in 0..<count {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("scope/a\(String(format: "%03d", index))/venv/lib/python3.12/site-packages/pkg/core/profile"), withIntermediateDirectories: true)
        }
        let fd = root.appendingPathComponent("fd")
        // Deterministic fd test double. The recursive pass is deliberately flooded.
        let script = #"""
        #!/usr/bin/env python3
        import os, sys
        args=sys.argv[1:]
        base=args[args.index('--base-directory')+1]
        limit=int(args[args.index('--max-results')+1])
        shallow='--max-depth' in args
        with open(os.path.join(base, '..', 'calls'), 'a') as log:
            log.write(('base' if shallow else 'recursive')+'\n')
        paths=[]
        for directory, dirs, files in os.walk(base):
            dirs.sort()
            for name in dirs:
                if 'pro' in name:
                    paths.append(os.path.relpath(os.path.join(directory,name),base)+'/')
            if shallow:
                dirs[:]=[]
        for path in paths[:limit]: print(path)
        """#
        try script.write(to: fd, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fd.path)
        let provider = CombinedAutocompleteProvider(basePath: root.path, fdPath: fd.path)
        let line = "@scope/pro"
        let values = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)?.items.map(\.value) ?? []
        #expect(values.first == "@scope/projects/")
        #expect(values.contains { $0.contains("/profile/") })
        #expect(values.filter { $0 == "@scope/projects/" }.count == 1)
        #expect(try String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8) == "base\nrecursive\n")
    }
}
