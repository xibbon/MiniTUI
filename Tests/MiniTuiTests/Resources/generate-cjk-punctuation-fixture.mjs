// Generate the Swift predicate and the independent test fixture from the tagged upstream regex.
// Run from the MiniTui root with Node 22:
// node Tests/MiniTuiTests/Resources/generate-cjk-punctuation-fixture.mjs
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const upstream = "/Users/miguel/cvs/pi/pi-mono";
const source = execFileSync("git", ["-C", upstream, "show", "v1.5.2:packages/tui/src/utils.ts"], { encoding: "utf8" });
const start = source.indexOf("export const cjkBreakRegex =");
const end = source.indexOf("export const autocompleteSeparatorRegex =", start);
if (start < 0 || end < 0) throw new Error("Tagged CJK punctuation source was not found");
const declarations = source.slice(start, end).replaceAll("export const ", "const ");
const upstreamRegex = new Function(`${declarations}\nreturn cjkPunctuationRegex;`)();
const ranges = [];
let first = -1;
let last = -1;
for (let value = 0; value <= 0x10ffff; value++) {
  const matches = upstreamRegex.test(String.fromCodePoint(value));
  if (matches) {
    if (first < 0) first = value;
    last = value;
  } else if (first >= 0) {
    ranges.push([first, last]);
    first = -1;
  }
}
if (first >= 0) ranges.push([first, last]);
const fixture = {
  source: "pi-mono v1.5.2 packages/tui/src/utils.ts cjkPunctuationRegex",
  node: process.versions.node,
  icu: process.versions.icu,
  unicode: process.versions.unicode,
  ranges,
};
writeFileSync("Tests/MiniTuiTests/Resources/cjk-punctuation-v1.5.2.json", JSON.stringify(fixture) + "\n");
const swiftRanges = ranges.map(([from, through]) => `    (0x${from.toString(16).toUpperCase()}, 0x${through.toString(16).toUpperCase()}),`).join("\n");
writeFileSync("Sources/MiniTui/CJKPunctuation.swift", `import Foundation\n\n// Generated from pi-mono v1.5.2 cjkPunctuationRegex by the test resource generator.\n// Node ${process.versions.node}, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}.\nprivate let cjkPunctuationRanges: [(UInt32, UInt32)] = [\n${swiftRanges}\n]\n\n/// Match the punctuation boundary used by the tagged TUI for CJK text.\nfunc isCJKPunctuation(_ scalar: Unicode.Scalar) -> Bool {\n    let value = scalar.value\n    var lower = 0\n    var upper = cjkPunctuationRanges.count\n    while lower < upper {\n        let middle = lower + (upper - lower) / 2\n        let range = cjkPunctuationRanges[middle]\n        if value < range.0 {\n            upper = middle\n        } else if value > range.1 {\n            lower = middle + 1\n        } else {\n            return true\n        }\n    }\n    return false\n}\n\nfunc isCJKPunctuation(_ character: Character) -> Bool {\n    character.unicodeScalars.contains(where: isCJKPunctuation)\n}\n`);
console.log(`Generated ${ranges.length} ranges from ${fixture.source}; Node ${fixture.node}, ICU ${fixture.icu}, Unicode ${fixture.unicode}`);
