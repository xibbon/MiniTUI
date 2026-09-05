import Foundation

/// Options for terminal LaTeX rendering.
public struct RenderLatexOptions: Sendable {
    /// Stack fractions and operator limits vertically.
    public var display: Bool

    public init(display: Bool = false) {
        self.display = display
    }
}

private let latexSymbols: [String: String] = [
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ",
    "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ",
    "iota": "ι", "kappa": "κ", "varkappa": "ϰ", "lambda": "λ", "mu": "μ",
    "nu": "ν", "xi": "ξ", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ",
    "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ",
    "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ",
    "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
    "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "·", "ast": "∗",
    "star": "⋆", "circ": "∘", "bullet": "•", "oplus": "⊕", "ominus": "⊖",
    "otimes": "⊗", "oslash": "⊘", "odot": "⊙", "bigcirc": "○", "dagger": "†",
    "ddagger": "‡", "amalg": "⨿", "uplus": "⊎", "sqcap": "⊓", "sqcup": "⊔",
    "bowtie": "⋈", "Join": "⋈", "ltimes": "⋉", "rtimes": "⋊",
    "leftouterjoin": "⟕", "rightouterjoin": "⟖", "fullouterjoin": "⟗",
    "triangleleft": "◁", "triangleright": "▷", "wr": "≀", "cap": "∩", "cup": "∪",
    "bigcap": "⋂", "bigcup": "⋃", "bigwedge": "⋀", "bigvee": "⋁",
    "bigsqcup": "⨆", "biguplus": "⨄", "bigoplus": "⨁", "bigotimes": "⨂",
    "bigodot": "⨀", "setminus": "∖", "in": "∈", "notin": "∉", "ni": "∋",
    "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇",
    "sqsubset": "⊏", "sqsupset": "⊐", "sqsubseteq": "⊑", "sqsupseteq": "⊒",
    "prec": "≺", "preceq": "≼", "succ": "≻", "succeq": "≽", "ll": "≪",
    "gg": "≫", "le": "≤", "leq": "≤", "leqslant": "≤", "ge": "≥",
    "geq": "≥", "geqslant": "≥", "ne": "≠", "neq": "≠", "equiv": "≡",
    "approx": "≈", "sim": "∼", "simeq": "≃", "cong": "≅", "asymp": "≍",
    "doteq": "≐", "propto": "∝", "parallel": "∥", "perp": "⊥", "mid": "∣",
    "vdash": "⊢", "dashv": "⊣", "models": "⊨", "Vdash": "⊩", "Vvdash": "⊪",
    "nvdash": "⊬", "nvDash": "⊭", "forall": "∀", "exists": "∃", "nexists": "∄",
    "neg": "¬", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "to": "→",
    "rightarrow": "→", "longrightarrow": "→", "leftarrow": "←", "longleftarrow": "←",
    "gets": "←", "leftrightarrow": "↔", "longleftrightarrow": "↔", "hookleftarrow": "↩",
    "hookrightarrow": "↪", "twoheadleftarrow": "↞", "twoheadrightarrow": "↠",
    "leftharpoonup": "↼", "leftharpoondown": "↽", "rightharpoonup": "⇀",
    "rightharpoondown": "⇁", "rightleftharpoons": "⇌", "leftrightharpoons": "⇋",
    "nearrow": "↗", "searrow": "↘", "swarrow": "↙", "nwarrow": "↖",
    "rightsquigarrow": "⇝", "leadsto": "⇝", "Rightarrow": "⇒", "Longrightarrow": "⇒",
    "Leftarrow": "⇐", "Longleftarrow": "⇐", "Leftrightarrow": "⇔",
    "Longleftrightarrow": "⇔", "implies": "⇒", "iff": "⇔", "mapsto": "↦",
    "longmapsto": "↦", "uparrow": "↑", "downarrow": "↓", "partial": "∂",
    "nabla": "∇", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
    "sum": "∑", "prod": "∏", "coprod": "∐", "infty": "∞", "emptyset": "∅",
    "varnothing": "∅", "angle": "∠", "therefore": "∴", "because": "∵",
    "aleph": "ℵ", "beth": "ℶ", "gimel": "ℷ", "daleth": "ℸ", "top": "⊤",
    "bot": "⊥", "triangle": "△", "square": "□", "lozenge": "◊", "checkmark": "✓",
    "complement": "∁", "wp": "℘", "prime": "′", "ldots": "…", "dots": "…",
    "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "ell": "ℓ", "hbar": "ℏ",
    "Im": "ℑ", "Re": "ℜ", "langle": "⟨", "rangle": "⟩", "vert": "|",
    "lvert": "|", "rvert": "|", "Vert": "‖", "lVert": "‖", "rVert": "‖",
    "lbrace": "{", "rbrace": "}", "backslash": "\\", "lfloor": "⌊",
    "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "colon": ":",
]

private let namedOperators: Set<String> = [
    "arccos", "arcsin", "arctan", "arg", "cos", "cosh", "cot", "coth", "csc", "deg",
    "det", "dim", "exp", "gcd", "hom", "inf", "ker", "lg", "lim", "liminf",
    "limsup", "ln", "log", "max", "min", "Pr", "sec", "sin", "sinh", "sup", "tan", "tanh",
]

private let limitOperators: Set<String> = [
    "argmax", "argmin", "inf", "injlim", "lim", "liminf", "limsup", "max", "min",
    "projlim", "sup",
]

private let displayLimitSymbols: Set<String> = [
    "bigcap", "bigcup", "bigodot", "bigoplus", "bigotimes", "bigsqcup", "biguplus",
    "bigvee", "bigwedge", "coprod", "int", "iint", "iiint", "oint", "prod", "sum",
]

private let relationCommands: Set<String> = [
    "bowtie", "Join", "ltimes", "rtimes", "leftouterjoin", "rightouterjoin", "fullouterjoin",
    "Leftarrow", "Leftrightarrow", "Longleftarrow", "Longleftrightarrow", "Longrightarrow",
    "Rightarrow", "Vdash", "Vvdash", "approx", "asymp", "cong", "dashv", "doteq",
    "downarrow", "equiv", "ge", "geq", "geqslant", "gets", "gg", "hookleftarrow",
    "hookrightarrow", "iff", "implies", "in", "leadsto", "le", "leftarrow",
    "leftharpoondown", "leftharpoonup", "leftrightarrow", "leftrightharpoons", "leq",
    "leqslant", "ll", "longleftarrow", "longleftrightarrow", "longmapsto",
    "longrightarrow", "mapsto", "mid", "models", "ne", "nearrow", "neq", "ni",
    "notin", "nvdash", "nvDash", "nwarrow", "parallel", "perp", "prec", "preceq",
    "propto", "rightharpoondown", "rightharpoonup", "rightleftharpoons", "rightarrow",
    "rightsquigarrow", "searrow", "sim", "simeq", "sqsubset", "sqsubseteq", "sqsupset",
    "sqsupseteq", "subset", "subseteq", "succ", "succeq", "supset", "supseteq",
    "swarrow", "to", "triangleleft", "triangleright", "twoheadleftarrow",
    "twoheadrightarrow", "uparrow", "vdash",
]

private let negatedSymbols: [String: String] = [
    "<": "≮", ">": "≯", "=": "≠", "∈": "∉", "∋": "∌", "∣": "∤", "∥": "∦",
    "∼": "≁", "≃": "≄", "≅": "≇", "≈": "≉", "≡": "≢", "≤": "≰", "≥": "≱",
    "≺": "⊀", "≻": "⊁", "⊂": "⊄", "⊃": "⊅", "⊆": "⊈", "⊇": "⊉",
    "⊢": "⊬", "⊨": "⊭", "↔": "↮", "←": "↚", "→": "↛", "⇒": "⇏",
    "⇐": "⇍", "⇔": "⇎", "≼": "⋠", "≽": "⋡",
]

private let blackboard: [Character: String] = [
    "C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ",
]

private let superscripts: [Character: String] = [
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
    "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽",
    ")": "⁾", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ",
    "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ",
    "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
    "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
]

private let subscripts: [Character: String] = [
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
    "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍",
    ")": "₎", "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ",
    "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ",
    "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
]

private let spacingCommands: Set<String> = [
    ",", ":", ";", " ", ">", "enspace", "enskip", "medspace", "quad", "qquad",
    "thickspace", "thinspace",
]
private let negativeSpacingCommands: Set<String> = ["!", "negmedspace", "negthickspace", "negthinspace"]
private let ignoredCommands: Set<String> = [
    "displaystyle", "limits", "nolimits", "scriptstyle", "scriptscriptstyle", "textstyle",
]
private let sizeCommands: Set<String> = [
    "big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl", "bigr", "Bigr",
    "biggr", "Biggr",
]
private let plainWrappers: Set<String> = [
    "emph", "mathcal", "mathbf", "mathfrak", "mathit", "mathrm", "mathnormal", "mathscr",
    "mathsf", "mathtt", "mathup", "mbox", "overbrace", "pmb", "smash", "substack",
    "text", "textbf", "textit", "textmd", "textnormal", "textrm", "textsc", "textsf",
    "textsl", "texttt", "textup", "underbrace", "bm", "boldsymbol",
]
private let accents: [String: String] = [
    "acute": "\u{0301}", "bar": "\u{0305}", "breve": "\u{0306}", "check": "\u{030c}",
    "ddot": "\u{0308}", "dot": "\u{0307}", "grave": "\u{0300}", "hat": "\u{0302}",
    "mathring": "\u{030a}", "overleftarrow": "\u{20d6}", "overleftrightarrow": "\u{20e1}",
    "overline": "\u{0305}", "overrightarrow": "\u{20d7}", "tilde": "\u{0303}",
    "underline": "\u{0332}", "vec": "\u{20d7}", "widehat": "\u{0302}",
    "widetilde": "\u{0303}",
]

private let negativeSpace = "\u{0}"
private let namedOperatorStart: Character = "\u{F0004}"
private let namedOperatorEnd: Character = "\u{F0005}"
private let layoutMarkerStart: Character = "\u{F0000}"
private let layoutMarkerEnd: Character = "\u{F0001}"
private let protectedSpace: Character = "\u{F0002}"

private func isLetterOrNumber(_ character: Character) -> Bool {
    character.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
}

private func trimWhitespace(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func replaceCharacters(_ value: String, replacements: [Character: String]) -> String? {
    var result = ""
    for character in value {
        guard let replacement = replacements[character] else { return nil }
        result += replacement
    }
    return result
}

private func compactScriptOperators(_ value: String) -> String {
    let characters = Array(value)
    var result = ""
    for index in characters.indices {
        let character = characters[index]
        if character.isWhitespace {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if previous == "=" || previous == "+" || previous == "-" ||
                next == "=" || next == "+" || next == "-" {
                continue
            }
        }
        result.append(character)
    }
    return result
}

private func formatScript(_ source: String, kind: ScriptKind) -> String {
    let value = compactScriptOperators(trimWhitespace(source))
    let replacements = kind == .sub ? subscripts : superscripts
    if let unicode = replaceCharacters(value, replacements: replacements) {
        return unicode
    }

    let prefix = kind == .sub ? "_" : "^"
    let isASCIIWord = !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isLetter }
    if value.count == 1 || (kind == .sub && isASCIIWord) {
        return prefix + value
    }
    return "\(prefix)(\(value))"
}

private enum ScriptKind {
    case sub
    case sup
}

private func isSimpleNumerator(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { isLetterOrNumber($0) || $0 == "." }
}

private func isSimpleDenominator(_ value: String) -> Bool {
    (!value.isEmpty && value.allSatisfy { $0.isNumber || $0 == "." }) || value.count == 1
}

private func formatFraction(_ numeratorSource: String, _ denominatorSource: String) -> String {
    let numerator = trimWhitespace(numeratorSource)
    let denominator = trimWhitespace(denominatorSource)
    let top = isSimpleNumerator(numerator) ? numerator : "(\(numerator))"
    let bottom = isSimpleDenominator(denominator) ? denominator : "(\(denominator))"
    return "\(top)/\(bottom)"
}

private func formatRoot(_ source: String, symbol: String = "√") -> String {
    let value = trimWhitespace(source)
    return isSimpleNumerator(value) ? symbol + value : "\(symbol)(\(value))"
}

private func normalizedOperatorMarkers(_ value: String) -> String {
    let characters = Array(value)
    var result = ""
    for index in characters.indices {
        let character = characters[index]
        if character == namedOperatorStart {
            if index > 0 {
                let previous = characters[index - 1]
                if isLetterOrNumber(previous) || [")", "]", "}", layoutMarkerEnd].contains(previous) {
                    result.append(" ")
                }
            }
            continue
        }
        if character == namedOperatorEnd {
            if index + 1 < characters.count {
                let next = characters[index + 1]
                if isLetterOrNumber(next) || next == "√" || next == layoutMarkerStart {
                    result.append(" ")
                }
            }
            continue
        }
        result.append(character)
    }
    return result
}

private func normalizeLatexOutput(_ value: String) -> String {
    let marked = normalizedOperatorMarkers(value)
    var lines = marked.components(separatedBy: "\n").map { line in
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }
    if lines.count > 1 {
        lines = lines.enumerated().filter { index, line in
            !line.isEmpty || (index > 0 && index < lines.count - 1)
        }.map(\.element)
    }
    return trimWhitespace(lines.joined(separator: "\n"))
}

private struct FractionNode {
    var numerator: String
    var denominator: String
}

private struct OperatorNode {
    var value: String
    var lower: String?
    var upper: String?
}

private struct MatrixNode {
    var lines: [String]
    var baseline: Int
}

private enum LatexLayoutNode {
    case fraction(FractionNode)
    case `operator`(OperatorNode)
    case matrix(MatrixNode)
}

private struct LatexLayout {
    var lines: [String]
    var width: Int
    var baseline: Int
}

private func padLayoutLine(_ line: String, width: Int, centered: Bool = false) -> String {
    let padding = max(0, width - visibleWidth(line))
    let left = centered ? padding / 2 : 0
    return String(repeating: " ", count: left) + line + String(repeating: " ", count: padding - left)
}

private func trimEnd(_ value: String) -> String {
    var result = value
    while result.last?.isWhitespace == true {
        result.removeLast()
    }
    return result
}

private func joinLayouts(_ layouts: [LatexLayout]) -> LatexLayout {
    guard !layouts.isEmpty else { return LatexLayout(lines: [""], width: 0, baseline: 0) }
    let baseline = layouts.map(\.baseline).max() ?? 0
    let below = layouts.map { $0.lines.count - $0.baseline - 1 }.max() ?? 0
    var lines: [String] = []
    for row in 0...(baseline + below) {
        var line = ""
        for layout in layouts {
            let sourceRow = row - baseline + layout.baseline
            if layout.lines.indices.contains(sourceRow) {
                line += padLayoutLine(layout.lines[sourceRow], width: layout.width)
            } else {
                line += String(repeating: " ", count: layout.width)
            }
        }
        lines.append(trimEnd(line))
    }
    return LatexLayout(
        lines: lines,
        width: layouts.reduce(0) { $0 + $1.width },
        baseline: baseline
    )
}

private func marker(at position: Int, in characters: [Character]) -> (index: Int, end: Int)? {
    guard characters.indices.contains(position), characters[position] == layoutMarkerStart else { return nil }
    var cursor = position + 1
    var digits = ""
    while characters.indices.contains(cursor), characters[cursor].isNumber {
        digits.append(characters[cursor])
        cursor += 1
    }
    guard !digits.isEmpty, characters.indices.contains(cursor), characters[cursor] == layoutMarkerEnd,
          let index = Int(digits) else { return nil }
    return (index, cursor + 1)
}

private func renderLatexLayout(_ source: String, nodes: [LatexLayoutNode]) -> LatexLayout {
    var renderedLines: [String] = []
    var firstBaseline = 0
    for sourceLine in source.components(separatedBy: "\n") {
        let characters = Array(sourceLine)
        var layouts: [LatexLayout] = []
        var position = 0
        var previousNode: LatexLayoutNode?
        while position < characters.count {
            guard let found = (position..<characters.count).compactMap({ cursor in
                marker(at: cursor, in: characters).map { (cursor, $0) }
            }).first else { break }
            let markerPosition = found.0
            let markerValue = found.1
            guard nodes.indices.contains(markerValue.index) else {
                position = markerValue.end
                continue
            }
            let node = nodes[markerValue.index]
            if markerPosition > position {
                let slice = String(characters[position..<markerPosition])
                let leftTrimmed = previousNode == nil ? slice : String(slice.drop(while: { $0.isWhitespace }))
                let trimmed = trimEnd(leftTrimmed)
                let previousIsMatrix: Bool
                if case .matrix? = previousNode { previousIsMatrix = true } else { previousIsMatrix = false }
                let nodeIsMatrix: Bool
                if case .matrix = node { nodeIsMatrix = true } else { nodeIsMatrix = false }
                let preserveLeading = previousIsMatrix && slice.first?.isWhitespace == true
                let preserveTrailing = nodeIsMatrix && slice.last?.isWhitespace == true
                let text: String
                if !trimmed.isEmpty {
                    text = (preserveLeading ? " " : "") + trimmed + (preserveTrailing ? " " : "")
                } else if preserveLeading || preserveTrailing {
                    text = " "
                } else {
                    text = ""
                }
                layouts.append(LatexLayout(lines: [text], width: visibleWidth(text), baseline: 0))
            }

            switch node {
            case .fraction(let fraction):
                let numerator = renderLatexLayout(fraction.numerator, nodes: nodes)
                let denominator = renderLatexLayout(fraction.denominator, nodes: nodes)
                let contentWidth = max(numerator.width, denominator.width, 1)
                let width = contentWidth + 2
                let lines = numerator.lines.map { padLayoutLine($0, width: width, centered: true) }
                    + [" " + String(repeating: "─", count: contentWidth) + " "]
                    + denominator.lines.map { padLayoutLine($0, width: width, centered: true) }
                layouts.append(LatexLayout(lines: lines, width: width, baseline: numerator.lines.count))
            case .operator(let node):
                let contentWidth = max(
                    visibleWidth(node.value),
                    node.lower.map(visibleWidth) ?? 0,
                    node.upper.map(visibleWidth) ?? 0
                )
                var lines: [String] = []
                if let upper = node.upper { lines.append(padLayoutLine(upper, width: contentWidth, centered: true) + " ") }
                lines.append(padLayoutLine(node.value, width: contentWidth, centered: true) + " ")
                if let lower = node.lower { lines.append(padLayoutLine(lower, width: contentWidth, centered: true) + " ") }
                layouts.append(LatexLayout(
                    lines: lines,
                    width: contentWidth + 1,
                    baseline: node.upper == nil ? 0 : 1
                ))
            case .matrix(let node):
                let width = node.lines.map(visibleWidth).max() ?? 0
                layouts.append(LatexLayout(
                    lines: node.lines.map { padLayoutLine($0, width: width) },
                    width: width,
                    baseline: node.baseline
                ))
            }
            position = markerValue.end
            previousNode = node
        }

        if position < characters.count {
            let slice = String(characters[position...])
            let trimmed = previousNode == nil ? slice : String(slice.drop(while: { $0.isWhitespace }))
            let previousIsMatrix: Bool
            if case .matrix? = previousNode { previousIsMatrix = true } else { previousIsMatrix = false }
            let text = previousIsMatrix && slice.first?.isWhitespace == true ? " " + trimmed : trimmed
            layouts.append(LatexLayout(lines: [text], width: visibleWidth(text), baseline: 0))
        }

        let lineLayout = joinLayouts(layouts)
        if renderedLines.isEmpty { firstBaseline = lineLayout.baseline }
        renderedLines += lineLayout.lines
    }
    return LatexLayout(
        lines: renderedLines,
        width: renderedLines.map(visibleWidth).max() ?? 0,
        baseline: firstBaseline
    )
}

private final class LatexParser {
    private let source: [Character]
    private var layoutNodes: [LatexLayoutNode]
    private let display: Bool
    private var position = 0
    private var supported = true
    private var stackFractions = true

    init(source: String, layoutNodes: [LatexLayoutNode] = [], display: Bool) {
        self.source = Array(source)
        self.layoutNodes = layoutNodes
        self.display = display
    }

    func render() -> (text: String, nodes: [LatexLayoutNode])? {
        let rendered = parseSequence()
        guard supported, position == source.count else { return nil }
        return (normalizeLatexOutput(rendered), layoutNodes)
    }

    private func parseSequence(endCharacter: Character? = nil) -> String {
        var result = ""
        while position < source.count {
            let character = source[position]
            if let endCharacter, character == endCharacter {
                position += 1
                return result
            }
            if character == "}" {
                supported = false
                return result
            }
            if character == "{" {
                position += 1
                result += parseSequence(endCharacter: "}")
                continue
            }
            if character == "\\" {
                let command = parseCommand()
                if command == negativeSpace {
                    result = trimEnd(result)
                    if result.last == namedOperatorEnd { result.removeLast() }
                } else {
                    result += command
                }
                continue
            }
            if character == "^" || character == "_" {
                position += 1
                result = trimEnd(result)
                let script = formatScript(parseRequiredArgument(stackFractions: false), kind: character == "_" ? .sub : .sup)
                if result.last == namedOperatorEnd {
                    result.removeLast()
                    result += script
                    result.append(namedOperatorEnd)
                } else {
                    result += script
                }
                continue
            }
            if character.isWhitespace {
                result += parseWhitespace()
                continue
            }
            if character == "=" || character == "<" || character == ">" {
                result = trimEnd(result) + " \(character) "
                position += 1
                continue
            }
            if character == "&" {
                position += 1
                continue
            }
            if character == "~" {
                position += 1
                result += " "
                continue
            }
            if character == ".", let index = trailingLayoutIndex(in: result),
               layoutNodes.indices.contains(index), case .matrix(var node) = layoutNodes[index] {
                let lastLine = node.lines.count - 1
                if node.lines.indices.contains(lastLine) { node.lines[lastLine].append(character) }
                layoutNodes[index] = .matrix(node)
                position += 1
                continue
            }
            result.append(character)
            position += 1
        }
        if endCharacter != nil { supported = false }
        return result
    }

    private func trailingLayoutIndex(in value: String) -> Int? {
        let characters = Array(value)
        guard let start = characters.lastIndex(of: layoutMarkerStart),
              let parsed = marker(at: start, in: characters), parsed.end == characters.count else { return nil }
        return parsed.index
    }

    private func parseWhitespace() -> String {
        while position < source.count, source[position].isWhitespace { position += 1 }
        return " "
    }

    private func parseCommand() -> String {
        position += 1
        guard position < source.count else {
            supported = false
            return ""
        }
        let first = source[position]
        if first == "\n" || first == "\r" || first == "\r\n" {
            position += 1
            if first == "\r", position < source.count, source[position] == "\n" { position += 1 }
            return " "
        }
        let command: String
        if first.isASCII && first.isLetter {
            let start = position
            while position < source.count, source[position].isASCII, source[position].isLetter { position += 1 }
            command = String(source[start..<position])
        } else {
            command = String(first)
            position += 1
        }

        if command == "\\" { return "\n" }
        if spacingCommands.contains(command) { return " " }
        if negativeSpacingCommands.contains(command) { return negativeSpace }
        if ignoredCommands.contains(command) { return "" }
        if ["{", "}", "$", "%", "#", "_", "&"].contains(command) { return command }
        if command == "|" { return "‖" }
        if command == "not" {
            let value = trimWhitespace(parseRequiredArgument(stackFractions: false))
            if let negated = negatedSymbols[value] { return " \(negated) " }
            let characters = Array(value)
            guard let first = characters.first else {
                supported = false
                return ""
            }
            return " \(first)\u{0338}\(String(characters.dropFirst())) "
        }
        if limitOperators.contains(command) {
            return parseOperator(command, inlineLowerStyle: .bracket, displayLimits: true, spaced: true)
        }
        if let symbol = latexSymbols[command] {
            if displayLimitSymbols.contains(command) {
                return parseOperator(symbol, inlineLowerStyle: .script, displayLimits: true)
            }
            return command == "cdot" || command == "times" || relationCommands.contains(command)
                ? " \(symbol) " : symbol
        }
        if namedOperators.contains(command) {
            return String(namedOperatorStart) + command + String(namedOperatorEnd)
        }
        if sizeCommands.contains(command) { return "" }
        if command == "left" || command == "middle" || command == "right" {
            if position < source.count, source[position] == "." { position += 1 }
            return ""
        }
        if command == "frac" || command == "dfrac" || command == "tfrac" {
            let shouldStack = display && stackFractions && command != "tfrac"
            let numerator = parseRequiredArgument(stackFractions: !shouldStack)
            let denominator = parseRequiredArgument(stackFractions: !shouldStack)
            if shouldStack {
                layoutNodes.append(.fraction(FractionNode(
                    numerator: normalizeLatexOutput(numerator),
                    denominator: normalizeLatexOutput(denominator)
                )))
                return layoutMarker(layoutNodes.count - 1)
            }
            return formatFraction(numerator, denominator)
        }
        if command == "sqrt" {
            let degree = parseOptionalArgument().map(trimWhitespace)
            let value = parseRequiredArgument()
            switch degree {
            case nil, "2": return formatRoot(value)
            case "3": return formatRoot(value, symbol: "∛")
            case "4": return formatRoot(value, symbol: "∜")
            default: return formatScript(degree ?? "", kind: .sup) + formatRoot(value)
            }
        }
        if command == "boxed" || command == "fbox" {
            return "[\(trimWhitespace(parseRequiredArgument()))]"
        }
        if command == "binom" || command == "dbinom" || command == "tbinom" {
            return "(\(parseRequiredArgument()) choose \(parseRequiredArgument()))"
        }
        if let accent = accents[command] {
            let value = parseRequiredArgument()
            return value.count == 1 ? value + accent : "\(command)(\(value))"
        }
        if command == "mathbb" {
            return parseRequiredArgument().map { blackboard[$0] ?? String($0) }.joined()
        }
        if command == "operatorname" {
            let starred = position < source.count && source[position] == "*"
            if starred { position += 1 }
            let value = trimWhitespace(normalizeLatexOutput(parseRequiredArgument()))
            return parseOperator(value, inlineLowerStyle: .bracket, displayLimits: starred, spaced: true)
        }
        if command == "mod" || command == "bmod" { return " mod " }
        if command == "pmod" || command == "pod" {
            let value = trimWhitespace(parseRequiredArgument())
            return command == "pmod" ? " (mod \(value))" : " (\(value))"
        }
        if command == "overset" || command == "stackrel" {
            let upper = parseRequiredArgument()
            let value = trimWhitespace(parseRequiredArgument())
            return value + formatScript(upper, kind: .sup)
        }
        if command == "underset" {
            let lower = parseRequiredArgument()
            let value = trimWhitespace(parseRequiredArgument())
            return value + formatScript(lower, kind: .sub)
        }
        if plainWrappers.contains(command) {
            let value = parseRequiredArgument()
            return command.hasPrefix("text") || command == "mbox" ? value : trimWhitespace(value)
        }
        if command == "begin" { return parseEnvironment() }
        if command == "end" {
            supported = false
            return ""
        }

        supported = false
        return "\\" + command
    }

    private enum InlineLowerStyle {
        case bracket
        case script
    }

    private func parseOperator(
        _ value: String,
        inlineLowerStyle: InlineLowerStyle,
        displayLimits: Bool,
        spaced: Bool = false
    ) -> String {
        var useDisplayLimits = displayLimits
        var modifierPosition = position
        while modifierPosition < source.count, source[modifierPosition] == " " || source[modifierPosition] == "\t" {
            modifierPosition += 1
        }
        for modifier in ["limits", "nolimits"] {
            let token = Array("\\" + modifier)
            if source.matches(token, at: modifierPosition) {
                let after = modifierPosition + token.count
                if after >= source.count || !(source[after].isASCII && source[after].isLetter) {
                    useDisplayLimits = modifier == "limits"
                    position = after
                    break
                }
            }
        }

        var lower: String?
        var upper: String?
        while true {
            var scriptPosition = position
            while scriptPosition < source.count, source[scriptPosition] == " " || source[scriptPosition] == "\t" {
                scriptPosition += 1
            }
            guard scriptPosition < source.count,
                  source[scriptPosition] == "_" || source[scriptPosition] == "^" else { break }
            let kind = source[scriptPosition]
            position = scriptPosition + 1
            let scriptValue = normalizeLatexOutput(parseRequiredArgument(stackFractions: false))
                .filter { !$0.isWhitespace }
            if kind == "_" {
                if lower != nil { supported = false }
                lower = scriptValue
            } else {
                if upper != nil { supported = false }
                upper = scriptValue
            }
        }

        if display && useDisplayLimits && (lower != nil || upper != nil) {
            layoutNodes.append(.operator(OperatorNode(value: value, lower: lower, upper: upper)))
            return layoutMarker(layoutNodes.count - 1)
        }
        var rendered = value
        if let lower {
            rendered += inlineLowerStyle == .bracket ? "[\(lower)]" : formatScript(lower, kind: .sub)
        }
        if let upper { rendered += formatScript(upper, kind: .sup) }
        return spaced ? " \(rendered) " : rendered
    }

    private func parseRequiredArgument(stackFractions: Bool = true) -> String {
        let previous = self.stackFractions
        self.stackFractions = previous && stackFractions
        let value = parseRequiredArgumentValue()
        self.stackFractions = previous
        return value
    }

    private func parseRequiredArgumentValue() -> String {
        while position < source.count, source[position].isWhitespace { position += 1 }
        guard position < source.count else {
            supported = false
            return ""
        }
        if source[position] == "{" {
            position += 1
            return parseSequence(endCharacter: "}")
        }
        if source[position] == "\\" { return parseCommand() }
        let value = source[position]
        position += 1
        return String(value)
    }

    private func parseOptionalArgument() -> String? {
        while position < source.count, source[position] == " " || source[position] == "\t" { position += 1 }
        guard position < source.count, source[position] == "[" else { return nil }
        guard let end = source[(position + 1)...].firstIndex(of: "]") else {
            supported = false
            return nil
        }
        let value = String(source[(position + 1)..<end])
        position = end + 1
        return renderNested(value)
    }

    private func readRawGroup() -> String? {
        while position < source.count, source[position] == " " || source[position] == "\t" { position += 1 }
        guard position < source.count, source[position] == "{" else {
            supported = false
            return nil
        }
        position += 1
        let start = position
        var depth = 1
        while position < source.count {
            let character = source[position]
            if character == "\\" {
                position = min(source.count, position + 2)
                continue
            }
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if depth == 0 {
                let value = String(source[start..<position])
                position += 1
                return value
            }
            position += 1
        }
        supported = false
        return nil
    }

    private func splitEnvironmentRows(_ body: String) -> [String] {
        let characters = Array(body)
        var rows: [String] = []
        var start = 0
        var cursor = 0
        while cursor + 1 < characters.count {
            if characters[cursor] == "\\", characters[cursor + 1] == "\\" {
                rows.append(String(characters[start..<cursor]))
                cursor += 2
                if cursor < characters.count, characters[cursor] == "[",
                   let close = characters[cursor...].firstIndex(of: "]"),
                   !characters[cursor..<close].contains("\n") {
                    cursor = close + 1
                }
                start = cursor
            } else {
                cursor += 1
            }
        }
        rows.append(String(characters[start...]))
        return rows
    }

    private func parseEnvironment() -> String {
        guard let environment = readRawGroup(), !environment.isEmpty else { return "" }
        let endMarker = Array("\\end{\(environment)}")
        guard let end = source.firstMatch(of: endMarker, from: position) else {
            supported = false
            return ""
        }
        let body = String(source[position..<end])
        position = end + endMarker.count

        if ["equation", "equation*", "displaymath"].contains(environment) {
            return trimWhitespace(renderNested(body))
        }
        let alignedEnvironments = [
            "aligned", "align", "align*", "alignedat", "alignat", "alignat*", "gather",
            "gathered", "multline", "multline*", "split",
        ]
        if alignedEnvironments.contains(environment) {
            let alignedAt = ["alignedat", "alignat", "alignat*"].contains(environment)
            let alignedBody = alignedAt ? droppingInitialGroup(body) : body
            return splitEnvironmentRows(alignedBody).compactMap { row in
                let cells = row.components(separatedBy: "&")
                let value: String
                if alignedAt {
                    value = stride(from: 0, to: cells.count, by: 2).map { index in
                        cells[index..<min(index + 2, cells.count)].joined()
                    }.joined(separator: " ")
                } else {
                    value = cells.joined()
                }
                let rendered = trimWhitespace(renderNested(value))
                return rendered.isEmpty ? nil : rendered
            }.joined(separator: "\n")
        }
        if environment == "cases" || environment == "cases*" {
            let rows = splitEnvironmentRows(body).map { row in
                row.components(separatedBy: "&").map { trimWhitespace(renderNested($0, stackFractions: false)) }
            }.filter { $0.contains(where: { !$0.isEmpty }) }
            return rows.enumerated().map { index, row in
                let rawValue = row.first ?? ""
                let value = rawValue.replacingTrailingComma()
                let condition = row.count > 1 ? row[1] : ""
                let delimiter = index == 0 ? "⎧" : index == rows.count - 1 ? "⎩" : "⎨"
                let lower = condition.lowercased()
                let hasPrefix = ["if", "when", "for", "otherwise"].contains { keyword in
                    lower == keyword || lower.hasPrefix(keyword + " ")
                }
                let conditionPrefix = hasPrefix ? " " : " if "
                return "\(delimiter) \(value)\(condition.isEmpty ? "" : conditionPrefix + condition)"
            }.joined(separator: "\n")
        }
        let matrixEnvironments = ["array", "matrix", "smallmatrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix"]
        if matrixEnvironments.contains(environment) {
            return renderMatrix(environment, body: environment == "array" ? droppingInitialGroup(body) : body)
        }

        supported = false
        return body
    }

    private func droppingInitialGroup(_ value: String) -> String {
        let characters = Array(value)
        var cursor = 0
        while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
        guard cursor < characters.count, characters[cursor] == "{",
              let close = characters[cursor...].firstIndex(of: "}") else { return value }
        return String(characters[(close + 1)...])
    }

    private func renderMatrix(_ environment: String, body: String) -> String {
        let matrix = splitEnvironmentRows(body).map { row in
            row.components(separatedBy: "&").map { trimWhitespace(renderNested($0, stackFractions: false)) }
        }.filter { $0.contains(where: { !$0.isEmpty }) }
        let columnCount = matrix.map(\.count).max() ?? 0
        let columnWidths = (0..<columnCount).map { column in
            matrix.map { row in row.indices.contains(column) ? visibleWidth(row[column]) : 0 }.max() ?? 0
        }
        let rows = matrix.map { row in
            (0..<columnCount).map { column in
                let cell = row.indices.contains(column) ? row[column] : ""
                return cell + String(repeating: String(protectedSpace), count: max(0, columnWidths[column] - visibleWidth(cell)))
            }.joined(separator: " │ ")
        }

        let lines: [String]
        if ["array", "matrix", "smallmatrix"].contains(environment) {
            lines = rows
        } else {
            let delimiters: [String: [String]] = [
                "pmatrix": ["⎛", "⎞", "⎜", "⎟", "⎝", "⎠"],
                "bmatrix": ["⎡", "⎤", "⎢", "⎥", "⎣", "⎦"],
                "Bmatrix": ["⎧", "⎫", "⎨", "⎬", "⎩", "⎭"],
                "vmatrix": ["│", "│", "│", "│", "│", "│"],
                "Vmatrix": ["║", "║", "║", "║", "║", "║"],
            ]
            guard let delimiter = delimiters[environment] else {
                supported = false
                return rows.joined(separator: "\n")
            }
            lines = rows.enumerated().map { index, row in
                let left = index == 0 ? delimiter[0] : index == rows.count - 1 ? delimiter[4] : delimiter[2]
                let right = index == 0 ? delimiter[1] : index == rows.count - 1 ? delimiter[5] : delimiter[3]
                return "\(left) \(row) \(right)"
            }
        }
        guard lines.count > 1 else { return lines.first ?? "" }
        layoutNodes.append(.matrix(MatrixNode(lines: lines, baseline: 0)))
        return layoutMarker(layoutNodes.count - 1)
    }

    private func renderNested(_ source: String, stackFractions: Bool = true) -> String {
        let parser = LatexParser(source: source, layoutNodes: layoutNodes, display: display && stackFractions)
        guard let rendered = parser.render() else {
            supported = false
            return source
        }
        layoutNodes = rendered.nodes
        return rendered.text
    }

    private func layoutMarker(_ index: Int) -> String {
        String(layoutMarkerStart) + String(index) + String(layoutMarkerEnd)
    }
}

private extension Array where Element == Character {
    func matches(_ token: [Character], at position: Int) -> Bool {
        guard position >= 0, position + token.count <= count else { return false }
        return Array(self[position..<(position + token.count)]) == token
    }

    func firstMatch(of token: [Character], from start: Int) -> Int? {
        guard !token.isEmpty, start <= count - token.count else { return nil }
        return (start...(count - token.count)).first { matches(token, at: $0) }
    }
}

private extension String {
    func replacingTrailingComma() -> String {
        let trimmed = trimEnd(self)
        guard trimmed.last == "," else { return self }
        return trimEnd(String(trimmed.dropLast()))
    }
}

/// Render supported LaTeX math as terminal-friendly Unicode text.
///
/// The function returns `nil` for unsupported or malformed input.
public func renderLatex(
    _ source: String,
    options: RenderLatexOptions = RenderLatexOptions()
) -> String? {
    let parser = LatexParser(source: source, display: options.display)
    guard let rendered = parser.render() else { return nil }
    guard !rendered.nodes.isEmpty else {
        return rendered.text.replacingOccurrences(of: String(protectedSpace), with: " ")
    }

    let lines = renderLatexLayout(rendered.text, nodes: rendered.nodes).lines
    let nonblank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let indentation = nonblank.map { line in
        line.prefix(while: { $0.isWhitespace }).count
    }.min() ?? 0
    let result = lines.map { line in
        let dropped = String(line.dropFirst(min(indentation, line.count)))
        return trimEnd(dropped)
    }.joined(separator: "\n")
    return trimEnd(result).replacingOccurrences(of: String(protectedSpace), with: " ")
}
