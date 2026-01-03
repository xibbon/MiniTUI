import MiniTui

let defaultSelectListTheme = SelectListTheme(
    selectedPrefix: { Ansi.blue($0) },
    selectedText: { Ansi.bold($0) },
    description: { Ansi.dim($0) },
    scrollInfo: { Ansi.dim($0) },
    noMatch: { Ansi.dim($0) }
)

let defaultMarkdownTheme = MarkdownTheme(
    heading: { Ansi.wrap(["1", "36"], $0) },
    link: { Ansi.blue($0) },
    linkUrl: { Ansi.dim($0) },
    code: { Ansi.yellow($0) },
    codeBlock: { Ansi.green($0) },
    codeBlockBorder: { Ansi.dim($0) },
    quote: { Ansi.italic($0) },
    quoteBorder: { Ansi.dim($0) },
    hr: { Ansi.dim($0) },
    listBullet: { Ansi.cyan($0) },
    bold: { Ansi.bold($0) },
    italic: { Ansi.italic($0) },
    strikethrough: { Ansi.strikethrough($0) },
    underline: { Ansi.underline($0) }
)

let defaultEditorTheme = EditorTheme(
    borderColor: { Ansi.dim($0) },
    selectList: defaultSelectListTheme
)
